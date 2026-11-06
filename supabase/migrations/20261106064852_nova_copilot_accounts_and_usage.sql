create schema if not exists nova_copilot_private;
revoke all on schema nova_copilot_private from public, anon, authenticated;

create table nova_copilot_private.nova_copilot_owners (
    email text primary key check (email = lower(btrim(email)))
);

create table nova_copilot_private.nova_copilot_usage (
    user_id uuid primary key references auth.users(id) on delete cascade,
    usage_date date not null,
    daily_count integer not null default 0 check (daily_count >= 0),
    minute_window_started_at timestamptz not null,
    minute_count integer not null default 0 check (minute_count >= 0),
    updated_at timestamptz not null default now()
);

alter table nova_copilot_private.nova_copilot_owners enable row level security;
alter table nova_copilot_private.nova_copilot_usage enable row level security;
revoke all on table nova_copilot_private.nova_copilot_owners from public, anon, authenticated;
revoke all on table nova_copilot_private.nova_copilot_usage from public, anon, authenticated;

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
    if v_user_id is null or v_email = '' then
        return jsonb_build_object('allowed', false, 'reason', 'unauthorized');
    end if;

    select exists (
        select 1 from nova_copilot_private.nova_copilot_owners as owner
        where owner.email = v_email
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
