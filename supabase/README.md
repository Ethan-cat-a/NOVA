# NOVA Copilot account limits and owner access

The migrations create private owner and usage tables, guest authorization, and one-time owner-code redemption. The code table stores only a SHA-256 hash; the plaintext code is provisioned privately and must never be committed to the public repository.

For guest profiles, enable **Allow anonymous sign-ins** in the Supabase dashboard under **Authentication → Sign In / Providers**. Supabase guest users receive the `authenticated` role and an `is_anonymous` claim. A guest profile is not recoverable after its local session data is cleared, so the 25-message daily allowance is per profile rather than per person. See [Supabase Anonymous Sign-Ins](https://supabase.com/docs/guides/auth/auth-anonymous).

The regular daily allowance is 25 chat requests per UTC day, with a 10-per-minute rate limit. Owner profiles keep unlimited daily use with a 30-per-minute rate limit. These limits are checked by the gateway through `nova_copilot_authorize_chat()`.

The older verified-email owner allowlist remains supported. Its table is intentionally empty in the public source repository.

To grant an existing verified account unlimited daily use by email, add the address directly in the Supabase SQL editor, replacing the placeholder below with the account email:

```sql
insert into nova_copilot_private.nova_copilot_owners (email)
values (lower(btrim('OWNER_EMAIL_CONFIGURED_PRIVATELY')))
on conflict (email) do nothing;
```

Do not commit the real owner email to the public repository. The database schema and RLS keep this table inaccessible to client accounts; the gateway's authenticated quota RPC reads it server-side.
