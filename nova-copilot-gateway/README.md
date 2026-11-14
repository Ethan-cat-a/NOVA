# NOVA Copilot Gateway

Private server-side gateway for NOVA Copilot. It validates Supabase sessions, enforces the existing NOVA usage limits, routes each chat mode to an OpenRouter free model, and streams only the final answer text to the Mac app.

## Model routing

The gateway reads the active mode from the first conversation instruction sent by the app:

| NOVA mode | OpenRouter model | Settings |
| --- | --- | --- |
| Fast | `nvidia/nemotron-3.5-lightning:free` | Default inference settings |
| Hard Thinker | `nvidia/nemotron-3-ultra-550b-a55b:free` | High reasoning; reasoning text is excluded from the user-visible stream |
| CS Agent | `nvidia/nemotron-3-ultra-550b-a55b:free` | High reasoning with allowlisted server tools; local app context is opt-in |

The first app instruction is converted to a `system` message for OpenRouter. Older app builds that omit a recognizable mode use Fast mode.

## Agent plugins

CS Agent is the only mode that receives server tool definitions. The server-side plugin registry is in `agent/plugins.js`; each plugin declares OpenRouter function schemas and an executor. The current allowlist contains:

- `calculate`: evaluates bounded arithmetic without using `eval` or executing code.
- `search_selected_documents`: searches excerpts from files attached or selected for the current chat. It cannot enumerate or read other files or folders.

The gateway runs at most two tool rounds and four tool executions per chat request, then asks the model for a final answer without tools. Tool results are treated as source material. To add another server-deployed plugin, add a validated schema and executor to the registry and document the data it can access. Plugins are not dynamically downloaded or installed by users. The Mac app provides separate opt-in local integrations for a selected project folder, read-only Git summary, reviewed Chrome page text and app handoffs to Xcode and Microsoft Word. Those local integrations do not run through this gateway.

## Deployment

In Vercel, set the project Root Directory to `nova-copilot-gateway` so `api/chat.js` is exposed at `/api/chat`.

Set these server-side environment variables in Vercel:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `OPENROUTER_API_KEY`

Keep the OpenRouter key only in Vercel. Never put it in the Mac app or commit it to this repository. The gateway checks the key at `/api/v1/key` for the app’s connection status. `UPSTREAM_CHAT_URL` and `VERCEL_AUTOMATION_BYPASS_SECRET` are not used by this gateway version.

The gateway streams OpenRouter Chat Completions events as plain UTF-8 text for the current app client. CS Agent now combines coding, Word drafting and tool-enabled support. It uses available error metadata to distinguish upstream provider rate limits from OpenRouter free-tier limits.

## Free-tier limits and data handling

OpenRouter's free model limit is 50 requests per day and 20 per minute for the key/account. NOVA's per-user quota does not increase that shared OpenRouter allowance, so everyone using this deployment shares it. Failed requests can count toward the daily limit.

Free model providers have their own data terms. The Fast, Hard Thinker and CS Agent routes use NVIDIA's free Nemotron endpoints, whose notice says not to send personal or confidential information. Avoid using free routes for sensitive documents or personal information. CS Agent tools search only text already supplied with that chat request; the provider receives the supplied excerpts, including any project or Chrome text the user reviewed and submitted.

The gateway uses one module-scoped HTTPS agent with keep-alive sockets and cached TLS sessions for Supabase and OpenRouter while a Vercel function instance is warm. Fluid Compute is enabled in `vercel.json`. `Server-Timing` reports Supabase auth, quota, and upstream-header durations; recycled instances may still need new connections.
