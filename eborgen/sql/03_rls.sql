-- ============================================================
-- E-BORGEN: 03_rls.sql
-- Run AFTER 02_indexes.sql.
-- Row-level security policies.
-- ============================================================

-- ----- HELPER FUNCTIONS -----

-- True if current user is mod, admin, or og
create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public as $$
  select coalesce(
    (select role in ('mod','admin','og') from public.profiles where id = auth.uid()),
    false
  );
$$;

-- True only for og admin
create or replace function public.is_og()
returns boolean language sql stable security definer
set search_path = public as $$
  select coalesce(
    (select role = 'og' from public.profiles where id = auth.uid()),
    false
  );
$$;

-- Verified + not banned + not under_review
create or replace function public.can_act()
returns boolean language sql stable security definer
set search_path = public as $$
  select coalesce(
    (select verified_at is not null
            and is_banned = false
            and not exists (
              select 1 from public.reports r
              where r.reported_user_id = profiles.id
                and r.status = 'under_review'
            )
     from public.profiles where id = auth.uid()),
    false
  );
$$;

-- 5-minute flower cooldown check (per giver→receiver pair)
create or replace function public.flower_cooldown_ok(receiver uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select not exists (
    select 1 from public.flowers
    where giver_user_id = auth.uid()
      and receiver_user_id = receiver
      and given_at > now() - interval '5 minutes'
  );
$$;

-- ----- ENABLE RLS ON ALL TABLES -----
alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.listings enable row level security;
alter table public.listing_items enable row level security;
alter table public.interests enable row level security;
alter table public.interest_items enable row level security;
alter table public.trades enable row level security;
alter table public.trade_items enable row level security;
alter table public.flowers enable row level security;
alter table public.badges enable row level security;
alter table public.reports enable row level security;
alter table public.trouts enable row level security;
alter table public.verification_attempts enable row level security;
alter table public.charity_listings enable row level security;
alter table public.charity_interests enable row level security;
alter table public.borgen_cut enable row level security;

-- ============================================================
-- profiles
-- ============================================================
create policy "profiles_select_all" on public.profiles
  for select using (true);

create policy "profiles_insert_own" on public.profiles
  for insert with check (id = auth.uid());

create policy "profiles_update_own_or_admin" on public.profiles
  for update
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());
-- Column-level protection enforced by trigger in 04_triggers.sql

-- ============================================================
-- items (admin-managed catalog)
-- ============================================================
create policy "items_select_all" on public.items
  for select using (true);

create policy "items_admin_write" on public.items
  for all using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- listings
-- ============================================================
create policy "listings_select_all" on public.listings
  for select using (true);

create policy "listings_insert_self" on public.listings
  for insert with check (seller_user_id = auth.uid() and public.can_act());

create policy "listings_update_own_or_admin" on public.listings
  for update
  using (seller_user_id = auth.uid() or public.is_admin())
  with check (seller_user_id = auth.uid() or public.is_admin());

create policy "listings_delete_own_or_admin" on public.listings
  for delete using (seller_user_id = auth.uid() or public.is_admin());

-- ============================================================
-- listing_items (mirror parent listing's permissions)
-- ============================================================
create policy "listing_items_select_all" on public.listing_items
  for select using (true);

create policy "listing_items_owner_write" on public.listing_items
  for all
  using (exists (
    select 1 from public.listings l
    where l.id = listing_id and (l.seller_user_id = auth.uid() or public.is_admin())
  ))
  with check (exists (
    select 1 from public.listings l
    where l.id = listing_id and (l.seller_user_id = auth.uid() or public.is_admin())
  ));

-- ============================================================
-- interests (queue privacy: only seller + interested user can see)
-- ============================================================
create policy "interests_select_relevant" on public.interests
  for select using (
    interested_user_id = auth.uid()
    or exists (
      select 1 from public.listings l
      where l.id = listing_id and l.seller_user_id = auth.uid()
    )
    or public.is_admin()
  );

create policy "interests_insert_self" on public.interests
  for insert with check (interested_user_id = auth.uid() and public.can_act());

create policy "interests_update_relevant" on public.interests
  for update
  using (
    interested_user_id = auth.uid()
    or exists (
      select 1 from public.listings l
      where l.id = listing_id and l.seller_user_id = auth.uid()
    )
    or public.is_admin()
  )
  with check (
    interested_user_id = auth.uid()
    or exists (
      select 1 from public.listings l
      where l.id = listing_id and l.seller_user_id = auth.uid()
    )
    or public.is_admin()
  );

create policy "interests_delete_own_or_admin" on public.interests
  for delete using (interested_user_id = auth.uid() or public.is_admin());

-- ============================================================
-- interest_items
-- ============================================================
create policy "interest_items_select_relevant" on public.interest_items
  for select using (
    exists (
      select 1 from public.interests i
      where i.id = interest_id
        and (
          i.interested_user_id = auth.uid()
          or exists (
            select 1 from public.listings l
            where l.id = i.listing_id and l.seller_user_id = auth.uid()
          )
          or public.is_admin()
        )
    )
  );

create policy "interest_items_owner_write" on public.interest_items
  for all
  using (exists (
    select 1 from public.interests i
    where i.id = interest_id and (i.interested_user_id = auth.uid() or public.is_admin())
  ))
  with check (exists (
    select 1 from public.interests i
    where i.id = interest_id and (i.interested_user_id = auth.uid() or public.is_admin())
  ));

-- ============================================================
-- trades (immutable record)
-- ============================================================
create policy "trades_select_all" on public.trades
  for select using (true);

create policy "trades_insert_seller" on public.trades
  for insert with check (seller_user_id = auth.uid() and public.can_act());

create policy "trades_update_party" on public.trades
  for update
  using (seller_user_id = auth.uid() or buyer_user_id = auth.uid() or public.is_admin())
  with check (seller_user_id = auth.uid() or buyer_user_id = auth.uid() or public.is_admin());
-- No deletes — trades are permanent

-- ============================================================
-- trade_items
-- ============================================================
create policy "trade_items_select_all" on public.trade_items
  for select using (true);

create policy "trade_items_party_write" on public.trade_items
  for all
  using (exists (
    select 1 from public.trades t
    where t.id = trade_id
      and (t.seller_user_id = auth.uid() or t.buyer_user_id = auth.uid() or public.is_admin())
  ))
  with check (exists (
    select 1 from public.trades t
    where t.id = trade_id
      and (t.seller_user_id = auth.uid() or t.buyer_user_id = auth.uid() or public.is_admin())
  ));

-- ============================================================
-- flowers (public read, cooldown-gated insert, no edits)
-- ============================================================
create policy "flowers_select_all" on public.flowers
  for select using (true);

create policy "flowers_insert_with_cooldown" on public.flowers
  for insert with check (
    giver_user_id = auth.uid()
    and public.can_act()
    and public.flower_cooldown_ok(receiver_user_id)
  );

-- ============================================================
-- badges (public read, admin/system writes only)
-- ============================================================
create policy "badges_select_all" on public.badges
  for select using (true);

create policy "badges_admin_write" on public.badges
  for all using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- reports
-- ============================================================
create policy "reports_select_own_or_admin" on public.reports
  for select using (reporter_user_id = auth.uid() or public.is_admin());

create policy "reports_insert_self" on public.reports
  for insert with check (reporter_user_id = auth.uid() and public.can_act());

create policy "reports_admin_update" on public.reports
  for update using (public.is_admin()) with check (public.is_admin());

create policy "reports_admin_delete" on public.reports
  for delete using (public.is_admin());

-- ============================================================
-- trouts (admin-only visibility)
-- ============================================================
create policy "trouts_admin_only" on public.trouts
  for all using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- verification_attempts
-- ============================================================
create policy "verification_select_own" on public.verification_attempts
  for select using (user_id = auth.uid() or public.is_admin());

create policy "verification_insert_own" on public.verification_attempts
  for insert with check (user_id = auth.uid());

create policy "verification_admin_update" on public.verification_attempts
  for update using (public.is_admin()) with check (public.is_admin());
-- Edge Function uses service_role and bypasses RLS — that's intentional

-- ============================================================
-- charity_listings + charity_interests
-- ============================================================
create policy "charity_select_all" on public.charity_listings
  for select using (true);

create policy "charity_insert_self" on public.charity_listings
  for insert with check (user_id = auth.uid() and public.can_act());

create policy "charity_update_own_or_admin" on public.charity_listings
  for update using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

create policy "charity_delete_own_or_admin" on public.charity_listings
  for delete using (user_id = auth.uid() or public.is_admin());

create policy "charity_interests_select_relevant" on public.charity_interests
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.charity_listings c
      where c.id = charity_id and c.user_id = auth.uid()
    )
    or public.is_admin()
  );

create policy "charity_interests_insert_self" on public.charity_interests
  for insert with check (user_id = auth.uid() and public.can_act());

create policy "charity_interests_update_relevant" on public.charity_interests
  for update
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

create policy "charity_interests_delete_own" on public.charity_interests
  for delete using (user_id = auth.uid() or public.is_admin());

-- ============================================================
-- borgen_cut (public read, system writes only)
-- ============================================================
create policy "borgen_cut_select_all" on public.borgen_cut
  for select using (true);

create policy "borgen_cut_admin_write" on public.borgen_cut
  for all using (public.is_admin()) with check (public.is_admin());
-- Trigger in 04_triggers.sql increments this on confirmed trades
