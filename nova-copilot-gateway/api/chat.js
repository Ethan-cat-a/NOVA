const https = require("node:https");
const { performance } = require("node:perf_hooks");
const { StringDecoder } = require("node:string_decoder");
const { listAgentTools, executeAgentTool } = require("../agent/plugins");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions";
const OPENROUTER_KEY_URL = "https://openrouter.ai/api/v1/key";

const MODEL_ROUTES = Object.freeze({
  fast: { model: "nvidia/nemotron-3.5-lightning:free" },
  thinker: {
    model: "nvidia/nemotron-3-ultra-550b-a55b:free",
    reasoning: { effort: "high", exclude: true },
  },
  agent: {
    model: "nvidia/nemotron-3-ultra-550b-a55b:free",
    reasoning: { effort: "high", exclude: true },
  },
  coding: { model: "cohere/north-mini-code:free" },
  worddocument: {
    model: "google/gemma-4-26b-a4b-it:free",
    reasoning: { enabled: true, exclude: true },
  },
});

const MAX_AGENT_TOOL_ROUNDS = 2;
const MAX_AGENT_TOOL_CALLS = 4;
const MAX_AGENT_TOOL_CALLS_PER_TURN = 12;

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

function routeForPayload(payload) {
  const modeInstruction = payload.messages.find((message) =>
    ["assistant", "system"].includes(message.role) && typeof message.content === "string"
  )?.content || "";
  const modeMatch = /^Active response mode\s*\(([^)]+)\)\s*:/im.exec(modeInstruction);
  const mode = (modeMatch?.[1] || "fast").replace(/[\s_-]/g, "").toLowerCase();
  if (mode === "thinker" || mode === "hardthinker") return { mode: "thinker", ...MODEL_ROUTES.thinker };
  if (mode === "agent" || mode === "agentic" || mode === "csagent") return { mode: "agent", ...MODEL_ROUTES.agent };
  if (mode === "coding") return { mode: "coding", ...MODEL_ROUTES.coding };
  if (mode === "worddocument" || mode === "worddoc") return { mode: "wordDocument", ...MODEL_ROUTES.worddocument };
  return { mode: "fast", ...MODEL_ROUTES.fast };
}

function openRouterMessages(messages) {
  return messages.map((message, index) => ({
    role: index === 0 && message.role === "assistant" ? "system" : message.role,
    content: message.content,
  }));
}

function textContent(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((part) => {
    if (typeof part === "string") return part;
    return typeof part?.text === "string" ? part.text : "";
  }).join("");
}

async function streamOpenRouterText(upstream, res) {
  const decoder = new StringDecoder("utf8");
  let pending = "";

  const writeDelta = async (line) => {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) return;
    const data = trimmed.slice("data:".length).trim();
    if (!data || data === "[DONE]") return;

    let event;
    try {
      event = JSON.parse(data);
    } catch {
      return;
    }
    const text = textContent(event.choices?.[0]?.delta?.content);
    if (text && !res.write(text)) {
      await new Promise((resolve) => res.once("drain", resolve));
    }
  };

  for await (const chunk of upstream) {
    pending += decoder.write(chunk);
    const lines = pending.split(/\r?\n/);
    pending = lines.pop() || "";
    for (const line of lines) await writeDelta(line);
  }
  pending += decoder.end();
  if (pending) await writeDelta(pending);
}

function openRouterErrorMessage(error, statusCode) {
  const metadata = error?.metadata || {};
  const provider = typeof metadata.provider_name === "string" ? metadata.provider_name : "The model provider";
  const limitSource = typeof metadata.limit_source === "string" ? metadata.limit_source : "";
  const raw = typeof metadata.raw === "string" ? metadata.raw : "";
  if (limitSource === "upstream_provider_shared_pool" || /temporarily rate-limited upstream/i.test(raw)) {
    return `${provider} is temporarily rate-limited. Try again shortly.`;
  }
  if (limitSource.startsWith("openrouter_free_tier")) {
    return "OpenRouter’s shared free-model limit was reached. Wait for its reset, then try again.";
  }
  if (statusCode === 429) {
    return "OpenRouter or the selected model provider rate-limited this request. Try again shortly; check OpenRouter Activity if it continues.";
  }
  if (error?.message === "Provider returned error") return `${provider} could not complete this request. Try again shortly.`;
  if (typeof error?.message === "string" && error.message.trim()) return error.message.trim().slice(0, 500);
  return "OpenRouter could not complete the request.";
}

async function readOpenRouterCompletion(upstream) {
  const decoder = new StringDecoder("utf8");
  let pending = "";
  let content = "";
  let finishReason = null;
  const toolCalls = new Map();

  const readLine = (line) => {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) return;
    const data = trimmed.slice("data:".length).trim();
    if (!data || data === "[DONE]") return;
    let event;
    try {
      event = JSON.parse(data);
    } catch {
      return;
    }
    if (event.error) {
      const statusCode = Number(event.error.code) || 502;
      throw Object.assign(new Error(openRouterErrorMessage(event.error, statusCode)), { status: statusCode });
    }
    const choice = event.choices?.[0];
    if (!choice) return;
    content += textContent(choice.delta?.content);
    if (choice.finish_reason) finishReason = choice.finish_reason;
    for (const delta of choice.delta?.tool_calls || []) {
      const index = Number.isInteger(delta.index) ? delta.index : toolCalls.size;
      let call = toolCalls.get(index);
      if (!call) {
        call = { id: "", type: "function", function: { name: "", arguments: "" } };
        toolCalls.set(index, call);
      }
      if (typeof delta.id === "string") call.id += delta.id;
      if (typeof delta.type === "string") call.type = delta.type;
      if (typeof delta.function?.name === "string") call.function.name += delta.function.name;
      if (typeof delta.function?.arguments === "string") call.function.arguments += delta.function.arguments;
    }
  };

  for await (const chunk of upstream) {
    pending += decoder.write(chunk);
    const lines = pending.split(/\r?\n/);
    pending = lines.pop() || "";
    for (const line of lines) readLine(line);
  }
  pending += decoder.end();
  if (pending) readLine(pending);

  return {
    content,
    finishReason,
    toolCalls: [...toolCalls.entries()]
      .sort(([left], [right]) => left - right)
      .slice(0, MAX_AGENT_TOOL_CALLS_PER_TURN)
      .map(([, call], index) => ({
        ...call,
        id: call.id || `nova-tool-${index + 1}`,
      })),
  };
}

async function requestOpenRouterCompletion(payload, signal, onResponse) {
  const startedAt = performance.now();
  const upstream = await requestHTTPS(OPENROUTER_CHAT_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "text/event-stream",
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
      "HTTP-Referer": "https://github.com/Ethan-cat-a/NOVA",
      "X-Title": "NOVA Copilot",
    },
    body: JSON.stringify(payload),
    signal,
  });
  if (onResponse) onResponse(upstream, performance.now() - startedAt);
  if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
    const body = await readResponseText(upstream);
    let parsed = {};
    try { parsed = JSON.parse(body); } catch {}
    const error = parsed.error || parsed;
    throw Object.assign(new Error(openRouterErrorMessage(error, upstream.statusCode)), { status: upstream.statusCode || 502 });
  }
  return { upstream, ...(await readOpenRouterCompletion(upstream)) };
}

async function runAgentLoop(basePayload, sourceMessages, signal, onResponse) {
  const messages = [...basePayload.messages];
  const tools = listAgentTools();
  let toolsExecuted = 0;
  let lastUpstream = null;

  for (let round = 0; round < MAX_AGENT_TOOL_ROUNDS; round += 1) {
    const completion = await requestOpenRouterCompletion({
      ...basePayload,
      messages,
      tools,
      tool_choice: "auto",
    }, signal, onResponse);
    lastUpstream = completion.upstream;
    if (!completion.toolCalls.length) return { content: completion.content, upstream: lastUpstream };

    messages.push({
      role: "assistant",
      content: completion.content || null,
      tool_calls: completion.toolCalls.map((call) => ({
        id: call.id,
        type: "function",
        function: call.function,
      })),
    });

    for (const call of completion.toolCalls) {
      let result;
      if (toolsExecuted >= MAX_AGENT_TOOL_CALLS) {
        result = "NOVA’s safe tool-use limit for this request was reached. Finish using the results already provided.";
      } else {
        toolsExecuted += 1;
        let args;
        try {
          if (call.function.arguments.length > 4_096) throw new Error("Tool arguments are too large.");
          args = JSON.parse(call.function.arguments || "{}");
          result = await executeAgentTool(call.function.name, args, { messages: sourceMessages });
        } catch (error) {
          result = `Tool error: ${error.message || "Invalid tool arguments."}`.slice(0, 500);
        }
      }
      messages.push({
        role: "tool",
        tool_call_id: call.id,
        name: call.function.name || "unknown",
        content: String(result).slice(0, 6_000),
      });
    }

    if (toolsExecuted >= MAX_AGENT_TOOL_CALLS || round + 1 === MAX_AGENT_TOOL_ROUNDS) break;
  }

  const finalPayload = { ...basePayload, messages };
  const final = await requestOpenRouterCompletion(finalPayload, signal, onResponse);
  return { content: final.content, upstream: final.upstream || lastUpstream };
}

async function writeAgentAnswer(content, res) {
  const characters = Array.from(content || "");
  if (!characters.length) {
    res.write("I couldn’t complete the agent steps. Please try again.");
    return;
  }
  for (let index = 0; index < characters.length; index += 64) {
    if (!res.write(characters.slice(index, index + 64).join(""))) {
      await new Promise((resolve) => res.once("drain", resolve));
    }
    await new Promise((resolve) => setImmediate(resolve));
  }
}

module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY || !OPENROUTER_API_KEY) {
    return sendJSON(res, 503, { error: "NOVA Copilot is not configured yet." });
  }

  if (req.method === "GET") {
    try {
      const startedAt = performance.now();
      const upstream = await requestHTTPS(OPENROUTER_KEY_URL, {
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${OPENROUTER_API_KEY}`,
        },
      });
      const text = await readResponseText(upstream);
      const validKey = upstream.statusCode >= 200 && upstream.statusCode < 300;
      setServerTiming(res, {
        openrouter_key: {
          duration: performance.now() - startedAt,
          ...connectionReuse.get(upstream),
        },
      });
      if (!validKey) {
        return sendJSON(res, 503, { ok: false, keyConfigured: false, error: "OpenRouter API key is unavailable." });
      }
      return sendJSON(res, 200, {
        ok: true,
        keyConfigured: true,
        model: "OpenRouter mode-based free models",
        upstream: "OpenRouter",
      });
    } catch {
      return sendJSON(res, 502, { ok: false, keyConfigured: false, error: "OpenRouter is unavailable." });
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

    const route = routeForPayload(payload);
    const openRouterPayload = {
      model: route.model,
      messages: openRouterMessages(payload.messages),
      stream: true,
      ...(route.reasoning ? { reasoning: route.reasoning } : {}),
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 180_000);
    let upstream;
    const upstreamResponses = [];
    let aggregateHeaderDuration = 0;
    const onUpstreamResponse = (response, duration) => {
      upstreamResponses.push(response);
      aggregateHeaderDuration += duration;
      timings.upstream_headers = {
        duration: aggregateHeaderDuration,
        ...connectionReuse.get(response),
      };
      setServerTiming(res, timings);
    };
    const onClientDisconnect = () => {
      if (!res.writableEnded) controller.abort();
    };
    res.once("close", onClientDisconnect);
    try {
      if (route.mode === "agent") {
        const agentResult = await runAgentLoop(
          openRouterPayload,
          payload.messages,
          controller.signal,
          onUpstreamResponse,
        );
        upstream = agentResult.upstream;
        res.statusCode = 200;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.setHeader("X-NOVA-Model", route.model);
        res.setHeader("X-NOVA-Plan", quota.is_owner ? "owner-unlimited" : "daily-limit");
        if (Number.isFinite(Number(quota.remaining))) res.setHeader("X-NOVA-Remaining", String(quota.remaining));
        res.flushHeaders();
        await writeAgentAnswer(agentResult.content, res);
        return res.end();
      }

      stageStartedAt = performance.now();
      upstream = await requestHTTPS(OPENROUTER_CHAT_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/plain, */*",
          Authorization: `Bearer ${OPENROUTER_API_KEY}`,
          "HTTP-Referer": "https://github.com/Ethan-cat-a/NOVA",
          "X-Title": "NOVA Copilot",
        },
        body: JSON.stringify(openRouterPayload),
        signal: controller.signal,
      });
      onUpstreamResponse(upstream, performance.now() - stageStartedAt);
      if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
        const errorBody = await readResponseText(upstream);
        let detail = "OpenRouter could not complete the request.";
        try {
          const parsed = JSON.parse(errorBody);
          detail = openRouterErrorMessage(parsed.error || parsed, upstream.statusCode);
        } catch {
          if (errorBody.trim()) detail = errorBody.trim().slice(0, 500);
        }
        if (upstream.statusCode === 401 || upstream.statusCode === 403) {
          detail = "OpenRouter rejected the server API key. Check OPENROUTER_API_KEY in the Vercel environment.";
        }
        return sendJSON(res, upstream.statusCode || 502, { error: detail });
      }

      res.statusCode = 200;
      res.setHeader("Content-Type", "text/plain; charset=utf-8");
      res.setHeader("X-NOVA-Model", route.model);
      res.setHeader("X-NOVA-Plan", quota.is_owner ? "owner-unlimited" : "daily-limit");
      if (Number.isFinite(Number(quota.remaining))) res.setHeader("X-NOVA-Remaining", String(quota.remaining));
      res.flushHeaders();
      await streamOpenRouterText(upstream, res);
      return res.end();
    } finally {
      clearTimeout(timeout);
      res.off("close", onClientDisconnect);
      for (const response of upstreamResponses) {
        if (!response.complete) response.destroy();
      }
      if (upstream && !upstream.complete) upstream.destroy();
    }
  } catch (error) {
    if (res.headersSent) return res.end();
    return sendJSON(res, error.status || 502, { error: error.message || "NOVA V8 could not complete the request." });
  }
};
