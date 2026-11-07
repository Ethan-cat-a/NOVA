-- Preserve the one-time redemption even if the Supabase user is deleted.
alter table nova_copilot_private.nova_copilot_owner_codes
    drop constraint if exists nova_copilot_owner_codes_redeemed_by_fkey;
