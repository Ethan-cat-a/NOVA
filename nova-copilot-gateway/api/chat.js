const https = require("node:https");
const { performance } = require("node:perf_hooks");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
const UPSTREAM_CHAT_URL = process.env.UPSTREAM_CHAT_URL;
const VERCEL_AUTOMATION_BYPASS_SECRET = process.env.VERCEL_AUTOMATION_BYPASS_SECRET;

// Module-scoped so warm Vercel instances reuse HTTPS sockets and cached TLS
// sessions for Supabase and the NOVA V8 upstream across requests.
const httpsAgent = new https.Agent({
  keepAlive: true,
  keepAliveMsecs: 1_000,
  maxSockets: 8,
  maxFreeSockets: 4,
  maxTotalSockets: 16,
  maxCachedSessions: 100,
  scheduling: "lifo",
});
const connectionReuse = new WeakMap();

function requestHTTPS(url, options = {}) {
  let target;
  try {
    target = new URL(url);
    if (target.protocol !== "https:") throw new Error("NOVA backend URLs must use HTTPS.");
  } catch (error) {
    return Promise.reject(error);
  }

  return new Promise((resolve, reject) => {
    const headers = { ...options.headers };
    if (options.body !== undefined && !Object.keys(headers).some((name) => name.toLowerCase() === "content-length")) {
      headers["Content-Length"] = Buffer.byteLength(options.body);
    }
    const request = https.request(target, {
      method: options.method || "GET",
      headers,
      agent: httpsAgent,
      signal: options.signal,
    }, (response) => {
      connectionReuse.set(response, {
        socketReused: request.reusedSocket === true,
        tlsSessionReused: typeof response.socket?.isSessionReused === "function" && response.socket.isSessionReused(),
      });
      resolve(response);
    });
    request.once("error", reject);
    if (options.body !== undefined) request.write(options.body);
    request.end();
  });
}

async function readResponseText(response) {
  const chunks = [];
  for await (const chunk of response) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks).toString("utf8");
}

function setServerTiming(res, timings) {
  const value = Object.entries(timings)
    .filter(([, metric]) => Number.isFinite(typeof metric === "number" ? metric : metric?.duration))
    .map(([name, metric]) => {
      const duration = typeof metric === "number" ? metric : metric.duration;
      const connection = typeof metric === "number"
        ? ""
        : metric.socketReused
          ? ';desc="socket reused"'
          : metric.tlsSessionReused
            ? ';desc="TLS session resumed"'
            : ';desc="new connection"';
      return `${name};dur=${Math.max(0, duration).toFixed(1)}${connection}`;
    })
    .join(", ");
  if (value) res.setHeader("Server-Timing", value);
}

function responseHeader(response, name) {
  const value = response.headers[name.toLowerCase()];
  return Array.isArray(value) ? value.join(", ") : value;
}

function sendJSON(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

async function readJSON(req, maxBytes = 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) throw Object.assign(new Error("Request is too large."), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw Object.assign(new Error("Request body must be valid JSON."), { status: 400 });
  }
}

async function authenticatedUser(token) {
  const response = await requestHTTPS(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
    },
  });
  const body = await readResponseText(response);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    return { user: null, connection: connectionReuse.get(response) };
  }
  const user = JSON.parse(body);
  if (!user.id || (user.is_anonymous !== true && (!user.email || !user.email_confirmed_at))) {
    return { user: null, connection: connectionReuse.get(response) };
  }
  return { user, connection: connectionReuse.get(response) };
}

function validateMessages(payload) {
  if (!payload || !Array.isArray(payload.messages) || payload.messages.length < 1 || payload.messages.length > 30) {
    return "Include between 1 and 30 chat messages.";
  }
  let totalCharacters = 0;
  for (const message of payload.messages) {
    if (!message || !["system", "user", "assistant"].includes(message.role) || typeof message.content !== "string") {
      return "Each message needs a supported role and text content.";
    }
    totalCharacters += message.content.length;
    if (message.content.length > 100_000 || totalCharacters > 250_000) return "The chat context is too large.";
  }
  return null;
}

module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY || !UPSTREAM_CHAT_URL || !VERCEL_AUTOMATION_BYPASS_SECRET) {
    return sendJSON(res, 503, { error: "NOVA Copilot is not configured yet." });
  }

  if (req.method === "GET") {
    try {
      const startedAt = performance.now();
      const upstream = await requestHTTPS(UPSTREAM_CHAT_URL, {
        headers: {
          Accept: "application/json",
          "x-vercel-protection-bypass": VERCEL_AUTOMATION_BYPASS_SECRET,
        },
      });
      setServerTiming(res, {
        upstream_headers: {
          duration: performance.now() - startedAt,
          ...connectionReuse.get(upstream),
        },
      });
      const text = await readResponseText(upstream);
      res.statusCode = upstream.statusCode || 502;
      res.setHeader("Content-Type", responseHeader(upstream, "content-type") || "application/json; charset=utf-8");
      return res.end(text);
    } catch {
      return sendJSON(res, 502, { ok: false, error: "NOVA V8 is unavailable." });
    }
  }
  if (req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return sendJSON(res, 405, { error: "Method not allowed." });
  }

  const authorization = req.headers.authorization || "";
  const match = /^Bearer\s+([A-Za-z0-9._~-]+)$/i.exec(authorization);
  if (!match) return sendJSON(res, 401, { error: "Continue as a guest or sign in to chat." });

  try {
    const timings = {};
    let stageStartedAt = performance.now();
    const authResult = await authenticatedUser(match[1]);
    const user = authResult.user;
    timings.auth = { duration: performance.now() - stageStartedAt, ...authResult.connection };
    if (!user) return sendJSON(res, 401, { error: "Your session is invalid or your email is not verified. Continue as a guest or sign in again." });

    const payload = await readJSON(req);
    const validationError = validateMessages(payload);
    if (validationError) return sendJSON(res, 400, { error: validationError });

    stageStartedAt = performance.now();
    const quotaResponse = await requestHTTPS(`${SUPABASE_URL}/rest/v1/rpc/nova_copilot_authorize_chat`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${match[1]}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    const quotaBody = await readResponseText(quotaResponse);
    timings.quota = {
      duration: performance.now() - stageStartedAt,
      ...connectionReuse.get(quotaResponse),
    };
    if (quotaResponse.statusCode < 200 || quotaResponse.statusCode >= 300) {
      console.error("NOVA Copilot quota check failed", quotaResponse.statusCode);
      return sendJSON(res, 503, { error: "Usage limits could not be checked. Please try again shortly." });
    }
    const quota = JSON.parse(quotaBody);
    if (!quota || quota.allowed !== true) {
      if (quota && quota.reason === "daily_limit") {
        return sendJSON(res, 429, { error: "You’ve reached today’s 25-message limit. Try again after the daily reset." });
      }
      if (quota && quota.reason === "rate_limit") {
        const retryAfter = Math.max(1, Number(quota.retry_after_seconds) || 60);
        res.setHeader("Retry-After", String(retryAfter));
        return sendJSON(res, 429, { error: `You’re sending messages too quickly. Try again in ${retryAfter} seconds.` });
      }
      return sendJSON(res, 401, { error: "This profile cannot start a chat. Continue as a guest or sign in again." });
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 180_000);
    let upstream;
    try {
      stageStartedAt = performance.now();
      upstream = await requestHTTPS(UPSTREAM_CHAT_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/plain, */*",
          "x-vercel-protection-bypass": VERCEL_AUTOMATION_BYPASS_SECRET,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      timings.upstream_headers = {
        duration: performance.now() - stageStartedAt,
        ...connectionReuse.get(upstream),
      };
      setServerTiming(res, timings);
      res.statusCode = upstream.statusCode || 502;
      res.setHeader("Content-Type", responseHeader(upstream, "content-type") || "text/plain; charset=utf-8");
      res.setHeader("X-NOVA-Plan", quota.is_owner ? "owner-unlimited" : "daily-limit");
      if (Number.isFinite(Number(quota.remaining))) res.setHeader("X-NOVA-Remaining", String(quota.remaining));
      for await (const chunk of upstream) {
        if (!res.write(chunk)) await new Promise((resolve) => res.once("drain", resolve));
      }
      return res.end();
    } finally {
      clearTimeout(timeout);
      if (upstream && !upstream.complete) upstream.destroy();
    }
  } catch (error) {
    if (res.headersSent) return res.end();
    return sendJSON(res, error.status || 502, { error: error.message || "NOVA V8 could not complete the request." });
  }
};
