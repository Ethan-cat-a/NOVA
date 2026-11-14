const MAX_EXPRESSION_LENGTH = 256;
const MAX_SEARCH_QUERY_LENGTH = 200;
const MAX_SOURCE_COUNT = 20;
const MAX_SOURCE_CHARACTERS = 200_000;

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

const plugins = Object.freeze([calculatorPlugin, documentSearchPlugin]);
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
