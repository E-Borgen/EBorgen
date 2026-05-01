-- ============================================================
-- E-BORGEN: 02_indexes.sql
-- Run AFTER 01_schema.sql.
-- Performance indexes for common query patterns.
-- ============================================================

-- profiles
create index idx_profiles_username on public.profiles(farmrpg_username);
create index idx_profiles_admin on public.profiles(role) where role <> 'user';
create index idx_profiles_presence on public.profiles(presence_status, last_seen_at);

-- listings
create index idx_listings_seller on public.listings(seller_user_id);
create index idx_listings_status_expires on public.listings(status, expires_at);
create index idx_listings_open_recent on public.listings(created_at desc) where status = 'open';
create index idx_listings_locked_with on public.listings(locked_with_user_id) where locked_with_user_id is not null;
create index idx_listings_type_status on public.listings(type, status);

-- listing_items
create index idx_listing_items_listing on public.listing_items(listing_id);
create index idx_listing_items_item_side on public.listing_items(item_id, side);

-- interests
create index idx_interests_listing on public.interests(listing_id);
create index idx_interests_user on public.interests(interested_user_id);
create index idx_interests_pending on public.interests(listing_id, created_at) where status = 'pending';

-- interest_items
create index idx_interest_items_interest on public.interest_items(interest_id);

-- trades
create index idx_trades_seller on public.trades(seller_user_id, completed_at desc);
create index idx_trades_buyer on public.trades(buyer_user_id, completed_at desc);
create index idx_trades_listing on public.trades(listing_id);
create index idx_trades_completed on public.trades(completed_at desc) where completed_at is not null;

-- trade_items
create index idx_trade_items_trade on public.trade_items(trade_id);
create index idx_trade_items_item on public.trade_items(item_id);

-- flowers
create index idx_flowers_receiver on public.flowers(receiver_user_id);
create index idx_flowers_cooldown on public.flowers(giver_user_id, receiver_user_id, given_at desc);
create index idx_flowers_recent on public.flowers(given_at desc);

-- badges
create index idx_badges_user on public.badges(user_id);
create index idx_badges_type on public.badges(type);

-- reports
create index idx_reports_pending on public.reports(created_at desc) where status = 'pending';
create index idx_reports_under_review on public.reports(created_at desc) where status in ('under_review','cicada_warning');
create index idx_reports_reporter on public.reports(reporter_user_id);
create index idx_reports_reported on public.reports(reported_user_id);

-- trouts
create index idx_trouts_user on public.trouts(user_id);

-- verification_attempts
create index idx_verification_user on public.verification_attempts(user_id, created_at desc);
create index idx_verification_active on public.verification_attempts(expires_at) where status = 'pending';

-- charity
create index idx_charity_kind_status on public.charity_listings(kind, status);
create index idx_charity_user on public.charity_listings(user_id);
create index idx_charity_expires on public.charity_listings(expires_at) where status = 'open';
create index idx_charity_interests_charity on public.charity_interests(charity_id);
create index idx_charity_interests_user on public.charity_interests(user_id);
