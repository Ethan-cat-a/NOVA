# NOVA Copilot Gateway

Private server-side gateway for NOVA Copilot chat. It validates Supabase sessions, enforces atomic daily and burst limits, and streams the existing NOVA V8 response through without changing the model backend.

Required Vercel environment variables:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `UPSTREAM_CHAT_URL` (the pinned NOVA V8 deployment's `/api/chat` URL)
- `VERCEL_AUTOMATION_BYPASS_SECRET` (server-only access to the pinned upstream deployment)
The owner has no daily message cap and a 30-message-per-minute burst cap. Other verified accounts have a 25-message-per-UTC-day quota and a 10-message-per-minute burst cap. Quota enforcement lives in the Supabase RPC, not in the client.

The Supabase built-in email sender may be limited to project team members. Configure a custom SMTP sender before inviting general users. Cloudflare Turnstile is not enabled until the owner provides site and secret keys; email confirmation, Supabase Auth protections, and the server-side chat limits are enabled in this first version.
