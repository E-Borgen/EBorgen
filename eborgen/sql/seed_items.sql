-- ============================================================
-- E-BORGEN: seed_items.sql
-- A tiny placeholder so the app has SOMETHING to work with
-- before we build the buddy.farm sync function.
-- Run AFTER the schema files. Safe to re-run (uses ON CONFLICT).
--
-- Real catalog will be synced from buddy.farm via Edge Function.
-- ============================================================

insert into public.items (id, name, type, is_tradeable, is_currency_like, buddy_url) values
  -- Currency-like items
  ('silver',        'Silver',         'currency', true,  true,  'https://buddy.farm/i/silver/'),
  ('gold',          'Gold',           'currency', true,  true,  'https://buddy.farm/i/gold/'),
  ('apple-cider',   'Apple Cider',    'drink',    true,  true,  'https://buddy.farm/i/apple-cider/'),
  ('orange-juice',  'Orange Juice',   'drink',    true,  true,  'https://buddy.farm/i/orange-juice/'),
  ('arnold-palmer', 'Arnold Palmer',  'drink',    true,  true,  'https://buddy.farm/i/arnold-palmer/'),

  -- Crops
  ('apple',         'Apple',          'crop',     true,  false, 'https://buddy.farm/i/apple/'),
  ('orange',        'Orange',         'crop',     true,  false, 'https://buddy.farm/i/orange/'),
  ('lemon',         'Lemon',          'crop',     true,  false, 'https://buddy.farm/i/lemon/'),
  ('carrot',        'Carrot',         'crop',     true,  false, 'https://buddy.farm/i/carrot/'),
  ('corn',          'Corn',           'crop',     true,  false, 'https://buddy.farm/i/corn/'),
  ('eggplant',      'Eggplant',       'crop',     true,  false, 'https://buddy.farm/i/eggplant/'),
  ('cucumber',      'Cucumber',       'crop',     true,  false, 'https://buddy.farm/i/cucumber/'),
  ('blueberry',     'Blueberry',      'crop',     true,  false, 'https://buddy.farm/i/blueberry/'),
  ('strawberry',    'Strawberry',     'crop',     true,  false, 'https://buddy.farm/i/strawberry/'),
  ('tomato',        'Tomato',         'crop',     true,  false, 'https://buddy.farm/i/tomato/'),

  -- Universal Likes
  ('bouquet',       'Bouquet of Flowers', 'gift', true, false, 'https://buddy.farm/i/bouquet/'),
  ('heart-container','Heart Container',  'gift', true, false, 'https://buddy.farm/i/heart-container/')
on conflict (id) do update set
  name = excluded.name,
  type = excluded.type,
  is_tradeable = excluded.is_tradeable,
  is_currency_like = excluded.is_currency_like,
  buddy_url = excluded.buddy_url,
  last_synced_at = now();
