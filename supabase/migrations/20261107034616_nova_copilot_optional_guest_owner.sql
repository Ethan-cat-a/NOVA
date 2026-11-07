-- NOVA Copilot 1.5.2: guest authorization and one-time owner-code redemption.

create table nova_copilot_private.nova_copilot_owner_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    claimed_at timestamptz not null default now()
);

create table nova_copilot_private.nova_copilot_owner_codes (
    code_hash text primary key check (code_hash ~ '^[0-9a-f]{64}$'),
    redeemed_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    redeemed_at timestamptz,
    check ((redeemed_by is null) = (redeemed_at is null))
);

alter table nova_copilot_private.nova_copilot_owner_profiles enable row level security;
alter table nova_copilot_private.nova_copilot_owner_codes enable row level security;
revoke all on table nova_copilot_private.nova_copilot_owner_profiles from public, anon, authenticated;
revoke all on table nova_copilot_private.nova_copilot_owner_codes from public, anon, authenticated;

create or replace function public.nova_copilot_owner_status()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
begin
    if v_user_id is null then
        return false;
    end if;

    return exists (
        select 1
        from nova_copilot_private.nova_copilot_owner_profiles as profile
        where profile.user_id = v_user_id
    ) or (
        v_email <> '' and exists (
            select 1
            from nova_copilot_private.nova_copilot_owners as owner
            where owner.email = v_email
        )
    );
end;
$function$;

revoke all on function public.nova_copilot_owner_status() from public, anon;
grant execute on function public.nova_copilot_owner_status() to authenticated;

create or replace function public.nova_copilot_redeem_owner_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user_id uuid := auth.uid();
    v_code text := upper(btrim(coalesce(p_code, '')));
    v_hash text;
    v_claimed integer := 0;
begin
    if v_user_id is null or v_code = '' or length(v_code) > 128 then
        return jsonb_build_object('is_owner', false);
    end if;

    if exists (
        select 1
        from nova_copilot_private.nova_copilot_owner_profiles as profile
        where profile.user_id = v_user_id
    ) then
        return jsonb_build_object('is_owner', true);
    end if;

    v_hash := encode(extensions.digest(convert_to(v_code, 'UTF8'), 'sha256'), 'hex');

    update nova_copilot_private.nova_copilot_owner_codes as owner_code
    set redeemed_by = v_user_id,
        redeemed_at = clock_timestamp()
    where owner_code.code_hash = v_hash
      and (owner_code.redeemed_by is null or owner_code.redeemed_by = v_user_id);

    get diagnostics v_claimed = row_count;
    if v_claimed = 0 then
        return jsonb_build_object('is_owner', false);
    end if;

    insert into nova_copilot_private.nova_copilot_owner_profiles(user_id)
    values (v_user_id)
    on conflict (user_id) do nothing;

    return jsonb_build_object('is_owner', true);
end;
$function$;

revoke all on function public.nova_copilot_redeem_owner_code(text) from public, anon;
grant execute on function public.nova_copilot_redeem_owner_code(text) to authenticated;

create or replace function public.nova_copilot_authorize_chat()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
    v_now timestamptz := clock_timestamp();
    v_today date := (clock_timestamp() at time zone 'UTC')::date;
    v_is_owner boolean;
    v_daily_limit integer;
    v_minute_limit integer;
    v_usage nova_copilot_private.nova_copilot_usage%rowtype;
    v_retry_seconds integer;
begin
    if v_user_id is null then
        return jsonb_build_object('allowed', false, 'reason', 'unauthorized');
    end if;

    select exists (
        select 1
        from nova_copilot_private.nova_copilot_owner_profiles as profile
        where profile.user_id = v_user_id
    ) or (
        v_email <> '' and exists (
            select 1
            from nova_copilot_private.nova_copilot_owners as owner
            where owner.email = v_email
        )
    ) into v_is_owner;

    v_daily_limit := case when v_is_owner then null else 25 end;
    v_minute_limit := case when v_is_owner then 30 else 10 end;

    insert into nova_copilot_private.nova_copilot_usage(
        user_id, usage_date, daily_count, minute_window_started_at, minute_count
    ) values (v_user_id, v_today, 0, v_now, 0)
    on conflict (user_id) do nothing;

    select usage.* into v_usage
    from nova_copilot_private.nova_copilot_usage as usage
    where usage.user_id = v_user_id
    for update;

    if v_usage.usage_date <> v_today then
        v_usage.daily_count := 0;
        v_usage.usage_date := v_today;
    end if;
    if v_now >= v_usage.minute_window_started_at + interval '1 minute' then
        v_usage.minute_window_started_at := v_now;
        v_usage.minute_count := 0;
    end if;

    if v_usage.minute_count >= v_minute_limit then
        v_retry_seconds := greatest(1, ceil(extract(epoch from
            (v_usage.minute_window_started_at + interval '1 minute' - v_now)
        ))::integer);
        update nova_copilot_private.nova_copilot_usage as usage
        set usage_date = v_usage.usage_date,
            daily_count = v_usage.daily_count,
            minute_window_started_at = v_usage.minute_window_started_at,
            minute_count = v_usage.minute_count,
            updated_at = v_now
        where usage.user_id = v_user_id;
        return jsonb_build_object(
            'allowed', false,
            'reason', 'rate_limit',
            'is_owner', v_is_owner,
            'retry_after_seconds', v_retry_seconds
        );
    end if;

    if not v_is_owner and v_usage.daily_count >= v_daily_limit then
        update nova_copilot_private.nova_copilot_usage as usage
        set usage_date = v_usage.usage_date,
            daily_count = v_usage.daily_count,
            minute_window_started_at = v_usage.minute_window_started_at,
            minute_count = v_usage.minute_count,
            updated_at = v_now
        where usage.user_id = v_user_id;
        return jsonb_build_object(
            'allowed', false,
            'reason', 'daily_limit',
            'is_owner', false,
            'remaining', 0,
            'resets_at', ((v_today + 1)::timestamp at time zone 'UTC')
        );
    end if;

    v_usage.daily_count := v_usage.daily_count + 1;
    v_usage.minute_count := v_usage.minute_count + 1;
    update nova_copilot_private.nova_copilot_usage as usage
    set usage_date = v_usage.usage_date,
        daily_count = v_usage.daily_count,
        minute_window_started_at = v_usage.minute_window_started_at,
        minute_count = v_usage.minute_count,
        updated_at = v_now
    where usage.user_id = v_user_id;

    return jsonb_build_object(
        'allowed', true,
        'is_owner', v_is_owner,
        'remaining', case when v_is_owner then null else greatest(0, v_daily_limit - v_usage.daily_count) end,
        'daily_limit', v_daily_limit,
        'resets_at', ((v_today + 1)::timestamp at time zone 'UTC'),
        'retry_after_seconds', 0
    );
end;
$function$;

revoke all on function public.nova_copilot_authorize_chat() from public, anon;
grant execute on function public.nova_copilot_authorize_chat() to authenticated;
