const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
const UPSTREAM_CHAT_URL = process.env.UPSTREAM_CHAT_URL;
const VERCEL_AUTOMATION_BYPASS_SECRET = process.env.VERCEL_AUTOMATION_BYPASS_SECRET;

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
  const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) return null;
  const user = await response.json();
  if (!user.id) return null;
  if (user.is_anonymous !== true && (!user.email || !user.email_confirmed_at)) return null;
  return user;
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
      const upstream = await fetch(UPSTREAM_CHAT_URL, {
        headers: {
          Accept: "application/json",
          "x-vercel-protection-bypass": VERCEL_AUTOMATION_BYPASS_SECRET,
        },
      });
      const text = await upstream.text();
      res.statusCode = upstream.status;
      res.setHeader("Content-Type", upstream.headers.get("content-type") || "application/json; charset=utf-8");
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
    const user = await authenticatedUser(match[1]);
    if (!user) return sendJSON(res, 401, { error: "Your session is invalid or your email is not verified. Continue as a guest or sign in again." });

    const payload = await readJSON(req);
    const validationError = validateMessages(payload);
    if (validationError) return sendJSON(res, 400, { error: validationError });

    const quotaResponse = await fetch(`${SUPABASE_URL}/rest/v1/rpc/nova_copilot_authorize_chat`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${match[1]}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    if (!quotaResponse.ok) {
      console.error("NOVA Copilot quota check failed", quotaResponse.status);
      return sendJSON(res, 503, { error: "Usage limits could not be checked. Please try again shortly." });
    }
    const quota = await quotaResponse.json();
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
      upstream = await fetch(UPSTREAM_CHAT_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/plain, */*",
          "x-vercel-protection-bypass": VERCEL_AUTOMATION_BYPASS_SECRET,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      res.statusCode = upstream.status;
      res.setHeader("Content-Type", upstream.headers.get("content-type") || "text/plain; charset=utf-8");
      res.setHeader("X-NOVA-Plan", quota.is_owner ? "owner-unlimited" : "daily-limit");
      if (Number.isFinite(Number(quota.remaining))) res.setHeader("X-NOVA-Remaining", String(quota.remaining));
      if (upstream.body) {
        for await (const chunk of upstream.body) {
          if (!res.write(chunk)) await new Promise((resolve) => res.once("drain", resolve));
        }
      }
      return res.end();
    } finally {
      clearTimeout(timeout);
      if (upstream && upstream.body && !upstream.body.locked) {
        try { await upstream.body.cancel(); } catch {}
      }
    }
  } catch (error) {
    if (res.headersSent) return res.end();
    return sendJSON(res, error.status || 502, { error: error.message || "NOVA V8 could not complete the request." });
  }
};
