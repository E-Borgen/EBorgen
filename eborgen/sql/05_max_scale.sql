-- ============================================================
-- E-BORGEN: 05_max_scale.sql
-- Run AFTER 04_triggers.sql.
-- Adds infrastructure for long-term scaling:
--   1. Storage bucket for report screenshots
--   2. Audit log for admin actions
--   3. In-app notifications
--   4. Site-wide announcements
--   5. Soft-delete pattern (deleted_at columns + filtered views)
-- ============================================================

-- ============================================================
-- 1) STORAGE BUCKET — report screenshots
-- ============================================================
-- Note: bucket creation in Supabase Storage UI is also fine.
-- This is the SQL equivalent for repeatability.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-screenshots',
  'report-screenshots',
  false,                                -- private bucket; URLs are signed
  5242880,                              -- 5 MB max per file
  array['image/png','image/jpeg','image/webp','image/gif']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Storage policies: only authenticated users can upload, only admins
-- and the original reporter can read.
create policy "screenshots_insert_self" on storage.objects
  for insert
  with check (
    bucket_id = 'report-screenshots'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.can_act()
  );

create policy "screenshots_select_relevant" on storage.objects
  for select
  using (
    bucket_id = 'report-screenshots'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

create policy "screenshots_admin_delete" on storage.objects
  for delete using (bucket_id = 'report-screenshots' and public.is_admin());

-- File path convention: {user_id}/{report_id}/{filename}.png

-- ============================================================
-- 2) AUDIT LOG — every admin action writes here
-- ============================================================
create type audit_action as enum (
  'ban','unban','promote','demote',
  'role_change','verify_user','unverify_user',
  'award_badge','revoke_badge','award_trout',
  'resolve_report','dismiss_report',
  'force_cancel_listing','force_close_stall',
  'edit_item_catalog','adjust_borgen_cut',
  'announcement_post','announcement_clear',
  'other'
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id),
  action audit_action not null,
  target_user_id uuid references public.profiles(id),
  target_table text,                    -- e.g. 'listings', 'reports'
  target_id text,                       -- the row id (uuid or text)
  before_state jsonb,                   -- snapshot before change
  after_state jsonb,                    -- snapshot after change
  reason text,                          -- admin's note
  ip_address inet,                      -- best-effort, may be null
  created_at timestamptz default now()
);

create index idx_audit_actor on public.audit_log(actor_user_id, created_at desc);
create index idx_audit_target_user on public.audit_log(target_user_id, created_at desc);
create index idx_audit_action on public.audit_log(action, created_at desc);
create index idx_audit_recent on public.audit_log(created_at desc);

alter table public.audit_log enable row level security;

create policy "audit_admin_select" on public.audit_log
  for select using (public.is_admin());

create policy "audit_admin_insert" on public.audit_log
  for insert with check (public.is_admin() and actor_user_id = auth.uid());

-- No updates, no deletes. Audit log is immutable.

-- Helper to write an audit entry (call from app code or other triggers)
create or replace function public.write_audit(
  p_action audit_action,
  p_target_user_id uuid,
  p_target_table text,
  p_target_id text,
  p_before jsonb,
  p_after jsonb,
  p_reason text
)
returns uuid language plpgsql security definer
set search_path = public as $$
declare
  new_id uuid;
begin
  insert into public.audit_log (
    actor_user_id, action, target_user_id, target_table, target_id,
    before_state, after_state, reason
  ) values (
    auth.uid(), p_action, p_target_user_id, p_target_table, p_target_id,
    p_before, p_after, p_reason
  ) returning id into new_id;
  return new_id;
end;
$$;

-- ============================================================
-- 3) NOTIFICATIONS — in-app inbox (🔔 badge)
-- ============================================================
create type notification_type as enum (
  'interest_received',                  -- someone clicked interested on your listing
  'listing_locked',                     -- seller locked you in for trade
  'listing_unlocked',                   -- seller unlocked you (rejected/flake)
  'trade_confirmed_other',              -- other party confirmed trade
  'trade_completed',                    -- both parties confirmed
  'flower_received',                    -- someone gave you a flower
  'badge_awarded',                      -- you earned a leaderboard badge
  'cicada_warning',                     -- you've been reported (1st time)
  'under_review',                       -- account moved to under review
  'ban_notice',                         -- you were banned
  'unban_notice',                       -- you were unbanned
  'announcement',                       -- site-wide announcement
  'verify_reminder',                    -- still haven't linked account
  'charity_request_filled',             -- someone offered to fulfill your request
  'other'
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type notification_type not null,
  title text not null,
  body text,                            -- optional longer text
  link_url text,                        -- where clicking the notif sends them
  related_user_id uuid references public.profiles(id),
  related_listing_id uuid references public.listings(id) on delete set null,
  related_trade_id uuid references public.trades(id) on delete set null,
  read_at timestamptz,
  created_at timestamptz default now()
);

create index idx_notif_user_unread on public.notifications(user_id, created_at desc) where read_at is null;
create index idx_notif_user_recent on public.notifications(user_id, created_at desc);

alter table public.notifications enable row level security;

create policy "notif_select_own" on public.notifications
  for select using (user_id = auth.uid() or public.is_admin());

create policy "notif_update_own" on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
-- only thing user can update is read_at; we'll trigger-protect that

create policy "notif_insert_admin_or_system" on public.notifications
  for insert with check (public.is_admin());
-- App-level inserts go through Edge Functions or admin endpoints

create policy "notif_delete_own_or_admin" on public.notifications
  for delete using (user_id = auth.uid() or public.is_admin());

-- Restrict user updates to only read_at column
create or replace function public.protect_notification_fields()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if public.is_admin() then return new; end if;

  if new.user_id is distinct from old.user_id
    or new.type is distinct from old.type
    or new.title is distinct from old.title
    or new.body is distinct from old.body
    or new.link_url is distinct from old.link_url
    or new.related_user_id is distinct from old.related_user_id
    or new.related_listing_id is distinct from old.related_listing_id
    or new.related_trade_id is distinct from old.related_trade_id
    or new.created_at is distinct from old.created_at
  then
    raise exception 'Only read_at can be modified by users';
  end if;

  return new;
end;
$$;

create trigger trg_protect_notification_fields
  before update on public.notifications
  for each row execute function public.protect_notification_fields();

-- ============================================================
-- 3b) AUTO-NOTIFICATION TRIGGERS
-- ============================================================
-- When someone clicks "interested" on a listing, notify the seller
create or replace function public.notify_interest_received()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  seller_id uuid;
begin
  select seller_user_id into seller_id from public.listings where id = new.listing_id;
  if seller_id is null or seller_id = new.interested_user_id then
    return new;
  end if;
  insert into public.notifications (
    user_id, type, title, body, link_url,
    related_user_id, related_listing_id
  ) values (
    seller_id, 'interest_received',
    'New interest on your listing',
    'Someone wants to trade with you.',
    '/index.html#listing-' || new.listing_id::text,
    new.interested_user_id, new.listing_id
  );
  return new;
end;
$$;

create trigger trg_notify_interest_received
  after insert on public.interests
  for each row execute function public.notify_interest_received();

-- When a listing is locked, notify the locked-with user
create or replace function public.notify_listing_locked()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.status = 'locked' and (old.status is null or old.status <> 'locked')
     and new.locked_with_user_id is not null
  then
    insert into public.notifications (
      user_id, type, title, body, link_url, related_listing_id, related_user_id
    ) values (
      new.locked_with_user_id, 'listing_locked',
      'You are locked in for a trade!',
      'Open the app and complete the trade in-game, then mark complete.',
      '/index.html#listing-' || new.id::text,
      new.id, new.seller_user_id
    );
  end if;
  return new;
end;
$$;

create trigger trg_notify_listing_locked
  after update on public.listings
  for each row execute function public.notify_listing_locked();

-- When a flower is given, notify the receiver
create or replace function public.notify_flower_received()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.notifications (
    user_id, type, title, body, related_user_id
  ) values (
    new.receiver_user_id, 'flower_received',
    'You received a flower 🌸',
    'Someone appreciated you.',
    new.giver_user_id
  );
  return new;
end;
$$;

create trigger trg_notify_flower_received
  after insert on public.flowers
  for each row execute function public.notify_flower_received();

-- ============================================================
-- 4) ANNOUNCEMENTS — site-wide banner messages
-- ============================================================
create type announcement_severity as enum ('info','warn','critical');

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  severity announcement_severity not null default 'info',
  posted_by uuid references public.profiles(id),
  posted_at timestamptz default now(),
  expires_at timestamptz,                  -- auto-hide after this; null = until cleared
  cleared_at timestamptz                   -- explicit dismissal by admin
);

create index idx_announce_active on public.announcements(posted_at desc)
  where cleared_at is null;

alter table public.announcements enable row level security;

create policy "announce_select_all" on public.announcements
  for select using (true);

create policy "announce_admin_write" on public.announcements
  for all using (public.is_admin()) with check (public.is_admin());

-- Convenience view: only currently-active announcements
create or replace view public.active_announcements as
select * from public.announcements
where cleared_at is null
  and (expires_at is null or expires_at > now())
order by
  case severity
    when 'critical' then 1
    when 'warn' then 2
    else 3
  end,
  posted_at desc;

-- ============================================================
-- 5) SOFT-DELETE PATTERN
-- ============================================================
-- Add deleted_at to user-content tables. Cascade deletes from auth.users
-- still fire on hard-delete; soft-delete is for user-initiated "delete account"
-- that needs to preserve trade history.

alter table public.profiles       add column deleted_at timestamptz;
alter table public.listings       add column deleted_at timestamptz;
alter table public.charity_listings add column deleted_at timestamptz;

create index idx_profiles_active on public.profiles(id) where deleted_at is null;
create index idx_listings_active on public.listings(seller_user_id, status) where deleted_at is null;
create index idx_charity_active on public.charity_listings(user_id, status) where deleted_at is null;

-- "Active" views that hide soft-deleted rows. Use these in the app.
create or replace view public.active_profiles as
  select * from public.profiles where deleted_at is null;

create or replace view public.active_listings as
  select * from public.listings where deleted_at is null;

create or replace view public.active_charity_listings as
  select * from public.charity_listings where deleted_at is null;

-- Soft-delete function (app calls this; trigger writes audit log)
create or replace function public.soft_delete_account(reason text default null)
returns void language plpgsql security definer
set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;

  update public.profiles
  set deleted_at = now(),
      farmrpg_username = null,             -- free up the username
      verified_at = null,
      presence_status = 'away'
  where id = uid;

  -- Cancel all active listings (don't delete — trade history preserved)
  update public.listings
  set status = 'cancelled', cancelled_at = now()
  where seller_user_id = uid
    and status in ('open','locked');

  -- Close charity
  update public.charity_listings
  set status = 'closed', closed_at = now()
  where user_id = uid and status = 'open';

  -- Audit
  perform public.write_audit(
    'other'::audit_action, uid, 'profiles', uid::text,
    null, jsonb_build_object('action','self_delete'), reason
  );
end;
$$;

-- Admin soft-delete (used by ban-with-cleanup flow)
create or replace function public.admin_soft_delete(target uuid, reason text)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;

  update public.profiles
  set deleted_at = now(),
      is_banned = true
  where id = target;

  update public.listings
  set status = 'cancelled', cancelled_at = now()
  where seller_user_id = target and status in ('open','locked');

  update public.charity_listings
  set status = 'closed', closed_at = now()
  where user_id = target and status = 'open';

  perform public.write_audit(
    'ban'::audit_action, target, 'profiles', target::text,
    null, jsonb_build_object('action','admin_soft_delete'), reason
  );
end;
$$;

-- ============================================================
-- DONE. Schema is now fully production-grade.
-- ============================================================
