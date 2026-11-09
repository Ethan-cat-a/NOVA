# NOVA Copilot for macOS 1.5.5

- Reuses a persistent app-wide HTTPS session for chat and account requests, reducing fresh connections and TLS handshakes when the server keeps a connection open.
- Adds privacy-safe DNS, TCP, TLS and first-byte timing logs to help identify slow network phases.
- Reuses pooled HTTPS sockets and cached TLS sessions for Supabase and the NOVA V8 upstream on warm Vercel gateway instances.
- Enables Vercel Fluid Compute and reports gateway auth, quota and upstream-header timings with `Server-Timing`.
- Increments the Mac build number to 22.

Connections may still be reopened after an idle timeout, a network change, or a serverless instance recycle. Those cases reconnect automatically and use TLS session resumption when available.
