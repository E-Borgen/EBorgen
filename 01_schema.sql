-- ============================================================
-- E-BORGEN: 01_schema.sql
-- Run this FIRST in the Supabase SQL editor.
-- Creates all tables, enums, and basic columns.
-- Subsequent files add indexes, RLS, and triggers.
-- ============================================================

-- ----- ENUMS -----
create type listing_type    as enum ('sell','buy','trade','stall');
create type listing_status  as enum ('open','locked','completed','cancelled','expired');
create type listing_side    as enum ('offer','request');
create type interest_status as enum ('pending','withdrawn','rejected','completed');
create type interest_side   as enum ('taking','giving');

-- ============================================================
-- 1) PROFILES — extends auth.users
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  farmrpg_username text unique,
  verified_at timestamptz,
  reputation_score numeric default 0,
  completed_trades_count int default 0,
  ghosted_count int default 0,
  flower_count int default 0,
  is_banned boolean default false,
  role text not null default 'user',           -- 'user' | 'mod' | 'admin' | 'og'
  presence_status text not null default 'away',-- 'active' | 'away'
  presence_changed_at timestamptz default now(),
  last_seen_at timestamptz default now(),
  mailbox_capacity int,                        -- self-reported, displayed by name
  inventory_capacity int,                      -- self-reported
  super_love_item_id text,                     -- admin-only "favorite item" badge
  created_at timestamptz default now()
);

-- ============================================================
-- 2) ITEMS — synced from buddy.farm; admin-only writes
-- ============================================================
create table public.items (
  id text primary key,                         -- buddy.farm slug
  name text not null,
  icon_url text,
  type text,                                   -- meal / fish / crop / etc.
  is_tradeable boolean default true,
  is_currency_like boolean default false,      -- exempts from "1 active per item" cap
  trade_level_required int,                    -- some items need account level
  buddy_url text,                              -- link to buddy.farm/i/<slug>
  last_synced_at timestamptz default now()
);

-- ============================================================
-- 3) LISTINGS
-- ============================================================
create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_user_id uuid not null references public.profiles(id) on delete cascade,
  type listing_type not null,
  status listing_status not null default 'open',
  locked_with_user_id uuid references public.profiles(id),
  locked_at timestamptz,
  expires_at timestamptz not null,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz default now()
);

-- ============================================================
-- 4) LISTING_ITEMS — supports bundles + stalls
-- ============================================================
create table public.listing_items (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  item_id text not null references public.items(id),
  side listing_side not null,
  qty int not null check (qty > 0),
  remaining_qty int not null,
  unit_value numeric,                          -- stalls only
  value_currency_id text references public.items(id) -- stalls only
);

-- ============================================================
-- 5) INTERESTS — the queue
-- ============================================================
create table public.interests (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  interested_user_id uuid not null references public.profiles(id) on delete cascade,
  status interest_status not null default 'pending',
  created_at timestamptz default now(),
  withdrawn_at timestamptz,
  unique (listing_id, interested_user_id)
);

-- ============================================================
-- 6) INTEREST_ITEMS — stall proposals (what they're picking & giving)
-- ============================================================
create table public.interest_items (
  id uuid primary key default gen_random_uuid(),
  interest_id uuid not null references public.interests(id) on delete cascade,
  item_id text not null references public.items(id),
  side interest_side not null,
  qty int not null check (qty > 0)
);

-- ============================================================
-- 7) TRADES — immutable record; powers reputation + data export
-- ============================================================
create table public.trades (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings(id),
  seller_user_id uuid not null references public.profiles(id),
  buyer_user_id uuid not null references public.profiles(id),
  seller_confirmed_at timestamptz,
  buyer_confirmed_at timestamptz,
  completed_at timestamptz,
  is_data_shareable boolean default true,      -- opt-out for price-checker export
  created_at timestamptz default now()
);

create table public.trade_items (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.trades(id) on delete cascade,
  item_id text not null references public.items(id),
  from_seller boolean not null,
  qty int not null check (qty > 0)
);

-- ============================================================
-- 8) FLOWERS — wholesome reputation
-- ============================================================
create table public.flowers (
  id uuid primary key default gen_random_uuid(),
  giver_user_id uuid not null references public.profiles(id) on delete cascade,
  receiver_user_id uuid not null references public.profiles(id) on delete cascade,
  given_at timestamptz default now(),
  check (giver_user_id <> receiver_user_id)
);

-- ============================================================
-- 9) BADGES — leaderboard rewards & misc achievements
-- Display-only items shown next to username (NOT in-game items)
-- ============================================================
create type badge_type as enum (
  'daily_1st','daily_2nd','daily_3rd',
  'weekly_1st','weekly_2nd','weekly_3rd',
  'alltime_1st','alltime_2nd','alltime_3rd',
  'heart_container',                            -- earned from 1000 bouquets conversion
  'apology'                                     -- given to wrongly-banned users
);

create table public.badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type badge_type not null,
  awarded_at timestamptz default now(),
  awarded_for text                             -- e.g. "weekly leaderboard 2026-W18"
);

-- ============================================================
-- 10) REPORTS — moderation: Trout / Cicada / Under Review
-- ============================================================
create type report_severity as enum ('annoying','scammer');
create type report_status as enum (
  'pending',           -- needs admin review
  'cicada_warning',    -- 1st scammer accusation w/o requirements met
  'under_review',      -- 2nd cicada OR met requirements; account restricted
  'resolved_dismissed',
  'resolved_trout',    -- loser gets invisible trout
  'resolved_banned'
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references public.profiles(id),
  reported_user_id uuid references public.profiles(id),
  reported_listing_id uuid references public.listings(id),
  severity report_severity not null,
  title text,                                  -- short, optional
  description text,                            -- long form
  ideal_outcome text,                          -- what they want
  screenshot_urls text[],                      -- supabase storage URLs
  -- scammer-specific fields:
  lost_items boolean,
  lost_items_detail text,
  reported_in_game boolean,
  hours_since_report int,
  status report_status not null default 'pending',
  moderator_notes text,                        -- visible to complainant
  moderator_internal_notes text,               -- NOT visible to complainant
  resolved_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  resolved_at timestamptz,
  check (reported_user_id is not null or reported_listing_id is not null)
);

-- Trout assignments (invisible to non-admins)
create table public.trouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  report_id uuid references public.reports(id),
  awarded_by uuid references public.profiles(id),
  awarded_at timestamptz default now(),
  reason text
);

-- ============================================================
-- 11) VERIFICATION_ATTEMPTS — bio-code flow
-- ============================================================
create table public.verification_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  claimed_username text not null,
  code text not null,                          -- e.g. "🌻7K3F9"
  status text not null default 'pending',      -- pending | success | failed | expired
  attempts int default 0,
  created_at timestamptz default now(),
  expires_at timestamptz default now() + interval '5 minutes',
  completed_at timestamptz
);

-- ============================================================
-- 12) CHARITY — Request/Donate (freebies)
-- ============================================================
create type charity_kind as enum ('request','offer');

create table public.charity_listings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind charity_kind not null,
  item_id text not null references public.items(id),
  qty int not null check (qty > 0),
  delivery_method text,                        -- 'mb' (mailbox) | 'cmb' (camp mailbox) | null
  max_recipients int,                          -- offers can cap how many can claim
  status text not null default 'open',
  created_at timestamptz default now(),
  expires_at timestamptz not null,
  closed_at timestamptz
);

create table public.charity_interests (
  id uuid primary key default gen_random_uuid(),
  charity_id uuid not null references public.charity_listings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending',      -- pending | fulfilled | withdrawn
  created_at timestamptz default now(),
  unique (charity_id, user_id)
);

-- ============================================================
-- 13) BORGEN'S CUT — single-row counter table
-- ============================================================
create table public.borgen_cut (
  id int primary key default 1,
  total_ac bigint not null default 0,
  trade_count int not null default 0,
  updated_at timestamptz default now(),
  check (id = 1)
);
insert into public.borgen_cut (id) values (1);

-- ============================================================
-- DONE. Next: run 02_indexes.sql, then 03_rls.sql, then 04_triggers.sql
-- ============================================================
