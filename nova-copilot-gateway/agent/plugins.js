const https = require("node:https");

const MAX_EXPRESSION_LENGTH = 256;
const MAX_SEARCH_QUERY_LENGTH = 200;
const MAX_SOURCE_COUNT = 20;
const MAX_SOURCE_CHARACTERS = 200_000;
const MAX_GITHUB_RESPONSE_BYTES = 1_000_000;
const MAX_GITHUB_FILE_CHARACTERS = 12_000;
const githubAgent = new https.Agent({ keepAlive: true, maxSockets: 4, maxFreeSockets: 2 });
const githubCache = new Map();

const commonWords = new Set([
  "about", "after", "again", "also", "and", "are", "can", "could", "did", "does", "for",
  "from", "have", "how", "into", "make", "more", "most", "need", "please", "that", "the",
  "their", "them", "there", "this", "what", "when", "where", "which", "with", "would", "your",
]);

function tokenizeExpression(expression) {
  if (typeof expression !== "string" || expression.length > MAX_EXPRESSION_LENGTH) {
    throw new Error("Use an arithmetic expression under 256 characters.");
  }

  const tokens = [];
  let offset = 0;
  while (offset < expression.length) {
    const remaining = expression.slice(offset);
    const whitespace = /^\s+/.exec(remaining);
    if (whitespace) {
      offset += whitespace[0].length;
      continue;
    }
    const number = /^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i.exec(remaining);
    if (number) {
      tokens.push({ type: "number", value: Number(number[0]) });
      offset += number[0].length;
      continue;
    }
    if ("+-*/%^()".includes(remaining[0])) {
      tokens.push({ type: remaining[0], value: remaining[0] });
      offset += 1;
      continue;
    }
    throw new Error("Only numbers, parentheses, and +, −, ×, ÷, %, and ^ are allowed.");
  }
  if (!tokens.length || tokens.length > 128) throw new Error("The expression is empty or too complex.");
  return tokens;
}

function calculate(expression) {
  const tokens = tokenizeExpression(expression);
  let cursor = 0;

  const peek = () => tokens[cursor];
  const consume = (type) => {
    if (peek()?.type !== type) throw new Error("The arithmetic expression is incomplete.");
    return tokens[cursor++];
  };

  function primary() {
    if (peek()?.type === "number") return consume("number").value;
    if (peek()?.type === "(") {
      consume("(");
      const value = additive();
      consume(")");
      return value;
    }
    throw new Error("Expected a number or a parenthesized expression.");
  }

  function power() {
    const left = primary();
    return peek()?.type === "^" ? (consume("^"), left ** unary()) : left;
  }

  function unary() {
    if (peek()?.type === "+") {
      consume("+");
      return unary();
    }
    if (peek()?.type === "-") {
      consume("-");
      return -unary();
    }
    return power();
  }

  function multiplicative() {
    let value = unary();
    while (["*", "/", "%"].includes(peek()?.type)) {
      const operator = tokens[cursor++].type;
      const right = unary();
      if ((operator === "/" || operator === "%") && right === 0) throw new Error("Division by zero is undefined.");
      if (operator === "*") value *= right;
      else if (operator === "/") value /= right;
      else value %= right;
    }
    return value;
  }

  function additive() {
    let value = multiplicative();
    while (["+", "-"].includes(peek()?.type)) {
      const operator = tokens[cursor++].type;
      const right = multiplicative();
      value = operator === "+" ? value + right : value - right;
    }
    return value;
  }

  const result = additive();
  if (cursor !== tokens.length) throw new Error("The arithmetic expression has extra characters.");
  if (!Number.isFinite(result) || Math.abs(result) > 1e100) throw new Error("The result is outside the supported range.");
  return Number.isInteger(result) && Math.abs(result) < 1e15 ? String(result) : String(Number(result.toPrecision(12)));
}

function suppliedDocumentSources(messages) {
  const sources = [];
  for (const message of messages) {
    if (message?.role !== "user" || typeof message.content !== "string") continue;
    const expression = /FILE \d+ — ([^\n]+)\n[\s\S]*?--- BEGIN EXTRACTED TEXT ---\n([\s\S]*?)\n--- END EXTRACTED TEXT ---/g;
    let match;
    while ((match = expression.exec(message.content)) && sources.length < MAX_SOURCE_COUNT) {
      const text = match[2].slice(0, MAX_SOURCE_CHARACTERS);
      sources.push({ name: match[1].trim().slice(0, 140), text });
    }
  }
  return sources;
}

function searchSuppliedDocuments(query, messages) {
  if (typeof query !== "string" || query.length > MAX_SEARCH_QUERY_LENGTH) {
    throw new Error("Use a search query under 200 characters.");
  }
  const terms = [...new Set(query.toLowerCase().match(/[\p{L}\p{N}]{2,}/gu) || [])]
    .filter((term) => !commonWords.has(term));
  if (!terms.length) return "Add a more specific search phrase.";

  const matches = [];
  for (const source of suppliedDocumentSources(messages)) {
    const lower = source.text.toLowerCase();
    const name = source.name.toLowerCase();
    const score = terms.reduce((sum, term) => {
      let count = 0;
      let offset = 0;
      while ((offset = lower.indexOf(term, offset)) !== -1 && count < 8) {
        count += 1;
        offset += term.length;
      }
      return sum + count + (name.includes(term) ? 3 : 0);
    }, 0);
    if (score < 1) continue;

    const firstMatch = terms
      .map((term) => lower.indexOf(term))
      .filter((index) => index >= 0)
      .sort((a, b) => a - b)[0];
    const start = Math.max(0, firstMatch - 450);
    const end = Math.min(source.text.length, start + 1_200);
    let excerpt = source.text.slice(start, end).trim();
    if (start > 0) excerpt = `…${excerpt}`;
    if (end < source.text.length) excerpt += "…";
    matches.push({ name: source.name, score, excerpt });
  }

  if (!matches.length) return "No matching text was found in the documents attached or selected for this chat.";
  return matches
    .sort((a, b) => b.score - a.score)
    .slice(0, 4)
    .map((match, index) => `Result ${index + 1} — ${match.name}\n${match.excerpt}`)
    .join("\n\n");
}

const calculatorPlugin = Object.freeze({
  id: "calculator",
  tools: [{
    type: "function",
    function: {
      name: "calculate",
      description: "Calculate a numeric arithmetic expression. Supports parentheses, +, -, *, /, %, and exponentiation (^). Do not use it for programming code.",
      parameters: {
        type: "object",
        properties: { expression: { type: "string", description: "A plain arithmetic expression, such as (18 * 4) / 3." } },
        required: ["expression"],
        additionalProperties: false,
      },
    },
  }],
  async execute(name, args) {
    if (name !== "calculate" || typeof args?.expression !== "string") throw new Error("Invalid calculator request.");
    return calculate(args.expression);
  },
});

const documentSearchPlugin = Object.freeze({
  id: "selected-document-search",
  tools: [{
    type: "function",
    function: {
      name: "search_selected_documents",
      description: "Search text from files the user attached to or explicitly selected for this chat. This tool cannot access other folders or files.",
      parameters: {
        type: "object",
        properties: { query: { type: "string", description: "A short phrase or set of terms to find in the supplied documents." } },
        required: ["query"],
        additionalProperties: false,
      },
    },
  }],
  async execute(name, args, context) {
    if (name !== "search_selected_documents" || typeof args?.query !== "string") throw new Error("Invalid document search request.");
    return searchSuppliedDocuments(args.query, context.messages);
  },
});

function githubPathComponent(value, label) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_.-]{1,100}$/.test(value) || value === "." || value === "..") {
    throw new Error(`Provide a valid public GitHub ${label}.`);
  }
  return encodeURIComponent(value);
}

function githubAPI(path) {
  const cached = githubCache.get(path);
  if (cached && cached.expiresAt > Date.now()) return Promise.resolve(cached.value);
  if (cached) githubCache.delete(path);

  return new Promise((resolve, reject) => {
    const request = https.request(`https://api.github.com${path}`, {
      method: "GET",
      agent: githubAgent,
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "NOVA-Copilot/1.6.8",
      },
    }, (response) => {
      const chunks = [];
      let size = 0;
      response.on("data", (chunk) => {
        size += chunk.length;
        if (size > MAX_GITHUB_RESPONSE_BYTES) {
          request.destroy(new Error("GitHub returned too much data. Narrow the repository or search."));
          return;
        }
        chunks.push(Buffer.from(chunk));
      });
      response.on("end", () => {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (response.statusCode === 404) return reject(new Error("That public GitHub repository or item was not found."));
          if (response.statusCode === 403 || response.statusCode === 429) {
            return reject(new Error("GitHub’s public API rate limit was reached. Try again later."));
          }
          return reject(new Error(`GitHub returned HTTP ${response.statusCode || 502}.`));
        }
        try {
          const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          githubCache.set(path, { value, expiresAt: Date.now() + 30_000 });
          while (githubCache.size > 64) githubCache.delete(githubCache.keys().next().value);
          resolve(value);
        } catch {
          reject(new Error("GitHub returned an invalid response."));
        }
      });
      response.on("error", reject);
    });
    request.setTimeout(8_000, () => request.destroy(new Error("GitHub took too long to respond.")));
    request.once("error", reject);
    request.end();
  });
}

function githubQuery(path, params) {
  const query = new URLSearchParams(params).toString();
  return `${path}?${query}`;
}

async function lookupPublicGitHub(args) {
  const action = args?.action;
  if (action === "search_repositories") {
    const query = typeof args.query === "string" ? args.query.trim().slice(0, 120) : "";
    if (!query) throw new Error("Add a short repository search query.");
    const result = await githubAPI(githubQuery("/search/repositories", { q: query, sort: "updated", order: "desc", per_page: "5" }));
    return (result.items || []).map((repo) => [
      `${repo.full_name} — ${repo.description || "No description"}`,
      `URL: ${repo.html_url}`,
      `Stars: ${repo.stargazers_count} · Language: ${repo.language || "not specified"} · Updated: ${repo.updated_at}`,
    ].join("\n")).join("\n\n") || "No public repositories matched that search.";
  }

  const owner = githubPathComponent(args?.owner, "owner");
  const repo = githubPathComponent(args?.repo, "repository name");
  const basePath = `/repos/${owner}/${repo}`;

  if (action === "get_repository") {
    const data = await githubAPI(basePath);
    return [
      `${data.full_name}: ${data.description || "No description"}`,
      `URL: ${data.html_url}`,
      `Default branch: ${data.default_branch} · Language: ${data.language || "not specified"}`,
      `Stars: ${data.stargazers_count} · Forks: ${data.forks_count} · Open issues: ${data.open_issues_count}`,
      `Updated: ${data.updated_at}`,
    ].join("\n");
  }

  if (action === "read_file") {
    if (typeof args.path !== "string" || !args.path.trim() || args.path.length > 300 || args.path.startsWith("/") || args.path.split("/").some((part) => part === ".." || !part)) {
      throw new Error("Provide a repository-relative file path without '..'.");
    }
    const filePath = args.path.split("/").map((part) => encodeURIComponent(part)).join("/");
    const ref = typeof args.ref === "string" && args.ref.trim() ? args.ref.trim().slice(0, 120) : undefined;
    const path = ref
      ? githubQuery(`${basePath}/contents/${filePath}`, { ref })
      : `${basePath}/contents/${filePath}`;
    const data = await githubAPI(path);
    if (!data || data.type !== "file" || typeof data.content !== "string" || data.encoding !== "base64") {
      throw new Error("That path is not a readable file in the public repository.");
    }
    const content = Buffer.from(data.content.replace(/\s+/g, ""), "base64").toString("utf8");
    return [
      `${data.path} — ${data.html_url}`,
      content.slice(0, MAX_GITHUB_FILE_CHARACTERS),
      content.length > MAX_GITHUB_FILE_CHARACTERS ? "[File excerpt truncated.]" : "",
    ].filter(Boolean).join("\n\n");
  }

  if (action === "search_issues") {
    const query = typeof args.query === "string" ? args.query.trim().slice(0, 120) : "";
    if (!query) throw new Error("Add a short issue or pull request search query.");
    const result = await githubAPI(githubQuery("/search/issues", {
      q: `repo:${args.owner}/${args.repo} ${query}`,
      sort: "updated",
      order: "desc",
      per_page: "5",
    }));
    return (result.items || []).map((item) => [
      `#${item.number} ${item.title} (${item.state})`,
      `URL: ${item.html_url}`,
      item.body ? String(item.body).slice(0, 700) : "",
    ].filter(Boolean).join("\n")).join("\n\n") || "No matching public issues or pull requests were found.";
  }

  if (action === "list_pull_requests") {
    const state = ["open", "closed", "all"].includes(args.state) ? args.state : "open";
    const result = await githubAPI(githubQuery(`${basePath}/pulls`, { state, sort: "updated", direction: "desc", per_page: "5" }));
    return result.map((item) => [
      `#${item.number} ${item.title} (${item.state}${item.draft ? ", draft" : ""})`,
      `URL: ${item.html_url}`,
      `Updated: ${item.updated_at}`,
    ].join("\n")).join("\n\n") || "No public pull requests matched that state.";
  }

  throw new Error("Choose a supported public GitHub read action.");
}

const githubPlugin = Object.freeze({
  id: "public-github-read",
  tools: [{
    type: "function",
    function: {
      name: "github_public_read",
      description: "Read public GitHub repositories only. Search public repositories, inspect public repo metadata/issues/pull requests, or read a file in a public repo. This tool cannot access private repositories or write to GitHub.",
      parameters: {
        type: "object",
        properties: {
          action: { type: "string", enum: ["search_repositories", "get_repository", "read_file", "search_issues", "list_pull_requests"] },
          query: { type: "string", description: "Search phrase for public repositories, issues, or pull requests." },
          owner: { type: "string", description: "Public repository owner." },
          repo: { type: "string", description: "Public repository name." },
          path: { type: "string", description: "Repository-relative file path for read_file." },
          ref: { type: "string", description: "Optional branch, tag, or commit for read_file." },
          state: { type: "string", enum: ["open", "closed", "all"], description: "Pull-request state for list_pull_requests." },
        },
        required: ["action"],
        additionalProperties: false,
      },
    },
  }],
  async execute(name, args) {
    if (name !== "github_public_read") throw new Error("Invalid GitHub request.");
    return lookupPublicGitHub(args);
  },
});

const plugins = Object.freeze([calculatorPlugin, documentSearchPlugin, githubPlugin]);
const toolOwners = new Map(plugins.flatMap((plugin) => plugin.tools.map((tool) => [tool.function.name, plugin])));

function listAgentTools() {
  return plugins.flatMap((plugin) => plugin.tools);
}

async function executeAgentTool(name, args, context) {
  const plugin = toolOwners.get(name);
  if (!plugin) return "This tool is not available in NOVA Agent mode.";
  try {
    const result = await plugin.execute(name, args, context);
    return String(result).slice(0, 6_000);
  } catch (error) {
    return `Tool error: ${error.message || "The tool could not complete that request."}`.slice(0, 500);
  }
}

module.exports = { listAgentTools, executeAgentTool };
