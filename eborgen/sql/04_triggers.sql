-- ============================================================
-- E-BORGEN: 04_triggers.sql
-- Run AFTER 03_rls.sql.
-- Protective triggers + auto-increment counters.
-- ============================================================

-- ============================================================
-- 1) Protect sensitive profile fields
-- RLS allows row updates but does NOT do column-level enforcement.
-- This trigger blocks non-admins from modifying privileged columns.
-- ============================================================
create or replace function public.protect_profile_fields()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if public.is_admin() then return new; end if;

  if new.role is distinct from old.role
    then raise exception 'Cannot modify role'; end if;
  if new.is_banned is distinct from old.is_banned
    then raise exception 'Cannot modify is_banned'; end if;
  if new.verified_at is distinct from old.verified_at
    then raise exception 'Cannot modify verified_at'; end if;
  if new.reputation_score is distinct from old.reputation_score
    then raise exception 'Cannot modify reputation_score'; end if;
  if new.completed_trades_count is distinct from old.completed_trades_count
    then raise exception 'Cannot modify completed_trades_count'; end if;
  if new.ghosted_count is distinct from old.ghosted_count
    then raise exception 'Cannot modify ghosted_count'; end if;
  if new.flower_count is distinct from old.flower_count
    then raise exception 'Cannot modify flower_count'; end if;

  return new;
end;
$$;

create trigger trg_protect_profile_fields
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- ============================================================
-- 2) Auto-create profile when user signs up
-- ============================================================
create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_create_profile_for_new_user
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

-- ============================================================
-- 3) Auto-increment flower_count on profiles when flower given
-- ============================================================
create or replace function public.bump_flower_count()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  update public.profiles
  set flower_count = flower_count + 1
  where id = new.receiver_user_id;
  return new;
end;
$$;

create trigger trg_bump_flower_count
  after insert on public.flowers
  for each row execute function public.bump_flower_count();

-- ============================================================
-- 4) Initialize listing_items.remaining_qty = qty on insert
-- ============================================================
create or replace function public.init_remaining_qty()
returns trigger language plpgsql as $$
begin
  if new.remaining_qty is null then
    new.remaining_qty := new.qty;
  end if;
  return new;
end;
$$;

create trigger trg_init_remaining_qty
  before insert on public.listing_items
  for each row execute function public.init_remaining_qty();

-- ============================================================
-- 5) When a trade completes, increment Borgen's Cut + counters
-- "Completed" = both seller_confirmed_at AND buyer_confirmed_at non-null
-- ============================================================
create or replace function public.on_trade_completion()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  -- Only fire when transitioning to "both confirmed"
  if (old.seller_confirmed_at is null or old.buyer_confirmed_at is null)
     and new.seller_confirmed_at is not null
     and new.buyer_confirmed_at is not null
  then
    -- Set completed_at if not already
    if new.completed_at is null then
      new.completed_at := now();
    end if;

    -- Borgen's Cut: 100 AC per confirmed trade
    update public.borgen_cut
    set total_ac = total_ac + 100,
        trade_count = trade_count + 1,
        updated_at = now()
    where id = 1;

    -- Bump completed_trades_count for both parties
    update public.profiles
    set completed_trades_count = completed_trades_count + 1
    where id in (new.seller_user_id, new.buyer_user_id);
  end if;

  return new;
end;
$$;

create trigger trg_on_trade_completion
  before update on public.trades
  for each row execute function public.on_trade_completion();

-- ============================================================
-- 6) Update last_seen_at on profile updates
-- (App should call an upsert/touch on every page load to keep this fresh)
-- ============================================================
create or replace function public.touch_last_seen()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  -- If presence_status changed, update presence_changed_at too
  if new.presence_status is distinct from old.presence_status then
    new.presence_changed_at := now();
  end if;
  return new;
end;
$$;

create trigger trg_touch_last_seen
  before update on public.profiles
  for each row
  when (new.last_seen_at is distinct from old.last_seen_at
        or new.presence_status is distinct from old.presence_status)
  execute function public.touch_last_seen();

-- ============================================================
-- 7) Auto-expire stale "active" presence (stale = >7d since last_seen)
-- Pure SQL view; app reads computed status to display
-- ============================================================
create or replace view public.profiles_with_effective_presence as
select
  p.*,
  case
    when p.presence_status = 'active'
         and p.last_seen_at < now() - interval '7 days'
      then 'away'
    else p.presence_status
  end as effective_presence
from public.profiles p;

-- ============================================================
-- DONE. Schema is now fully wired.
-- Next: seed_items.sql for catalog placeholder, then connect from frontend.
-- ============================================================
