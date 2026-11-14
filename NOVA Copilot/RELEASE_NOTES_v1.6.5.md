# NOVA Copilot for macOS 1.6.5

## Agent mode

Choose **Agent** when you want NOVA to use a small set of tools while working through a request. The current tools can calculate arithmetic and search text from files you attached or explicitly selected for that chat. NOVA can use up to two tool rounds and four tool calls per reply.

The plugin registry is server-side and allowlisted. It cannot open other files or folders, change documents, run shell commands, or control other apps. Treat free-model providers as untrusted with sensitive data; do not send confidential documents through the free OpenRouter routes.

## Model routing

- Hard Thinker and Agent use `nvidia/nemotron-3-ultra-550b-a55b:free`.
- Fast uses `nvidia/nemotron-3.5-lightning:free`.
- Coding uses `cohere/north-mini-code:free`.
- Word Doc remains on `google/gemma-4-26b-a4b-it:free`.
