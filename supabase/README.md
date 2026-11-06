# NOVA Copilot account limits

Apply the migration in `migrations/` to create the private owner and usage tables and the quota-check RPC. The owner table is intentionally empty in the public source repository.

To grant unlimited daily use to the owner, add the verified account email directly in the Supabase SQL editor, replacing the placeholder below with the account email:

```sql
insert into nova_copilot_private.nova_copilot_owners (email)
values (lower(btrim('OWNER_EMAIL_CONFIGURED_PRIVATELY')))
on conflict (email) do nothing;
```

Do not commit the real owner email to the public repository. The database schema and RLS keep this table inaccessible to client accounts; the gateway's authenticated quota RPC reads it server-side.
