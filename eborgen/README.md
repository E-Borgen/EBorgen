# 🌻 E-Borgen

> Borgen heard about the internet. This is what happened.

A community-built trade board and farmers market for [FarmRPG](https://farmrpg.com) players. Independent fan project, not affiliated with Magic & Wires LLC.

---

## What this is

E-Borgen replaces the chaos of FarmRPG trade chat with a structured marketplace:

- **Stalls (BoregnMart)** — long-form patient listings with full inventory and prices
- **Buy/Sell/Trade (BorgenExpress + Black Market)** — short-form active deals (15min – 4hr)
- **Charity** — beg/donate freebies
- **Leaderboard** — flower-based reputation, badge rewards
- **Chat Text Generator** — formats trade posts for in-game chat (no account needed!)

Every confirmed trade nets Borgen 100 Ancient Coins. He's never been happier.

---

## Stack

| Layer       | Tech                               |
|-------------|------------------------------------|
| Frontend    | Vanilla JS + HTML + CSS            |
| Hosting     | GitHub Pages (free)                |
| Backend     | Supabase (Auth + Postgres + RLS)   |
| Functions   | Supabase Edge Functions (Deno)     |
| Domain      | TBD                                |

Cost target: **$0/month** for v1 beta (~100 users).

---

## Repo structure

```
eborgen/
├── index.html              # homepage
├── style.css               # global styles + design tokens
├── pages/                  # additional pages
│   ├── stalls.html
│   ├── buy.html
│   ├── charity.html
│   ├── leaderboard.html
│   └── settings.html
├── js/
│   ├── supabase-client.js  # config (REQUIRES YOUR KEYS)
│   ├── auth.js             # auth + session helpers
│   ├── verify.js           # bio-code claim flow
│   ├── listings.js         # post/edit/cancel/browse
│   ├── interests.js        # queue + locking
│   ├── flowers.js          # flower send + cooldown
│   ├── presence.js         # online/offline toggle
│   └── home.js             # homepage logic + chat generator
├── assets/                 # static files (logo, fonts if self-hosted)
├── sql/
│   ├── 01_schema.sql       # core tables + types
│   ├── 02_indexes.sql      # performance indexes
│   ├── 03_rls.sql          # row-level security policies
│   ├── 04_triggers.sql     # protective triggers + counters
│   ├── 05_max_scale.sql    # storage, audit log, notifications, announcements, soft-delete
│   └── seed_items.sql      # initial item catalog (placeholder)
├── supabase/
│   └── functions/
│       └── verify-bio/     # bio-code verification edge function
└── README.md
```

---

## Setup checklist

Before code does anything useful, you need:

- [ ] Email address (for support@ + Supabase signup)
- [ ] GitHub repo (this one!)
- [ ] Supabase project — save URL, `anon` key, `service_role` key
- [ ] Discord server with permanent invite link
- [ ] (Optional) custom domain

Once Supabase is live:

1. Open Supabase SQL editor
2. Paste each file from `sql/` in order: `01_schema.sql` → `02_indexes.sql` → `03_rls.sql` → `04_triggers.sql`
3. Run `seed_items.sql` (placeholder — full sync via Edge Function later)
4. Open `js/supabase-client.js` and fill in your project URL + anon key
5. Push to GitHub, enable Pages
6. Deploy the verify-bio Edge Function: `supabase functions deploy verify-bio`

---

## Development workflow

Same as Chicken Zone:

```bash
cd /mnt/c/Users/Jessi/Documents/eborgen
git pull
# ...edit files...
git add . && git commit -m "..." && git push
# in PowerShell:
wsl --shutdown
```

Bump version in `index.html` `?v=X` query strings AND in `js/supabase-client.js`'s `LS_CACHE_KEY` for any meaningful push.

---

## Anti-bug checklist (paste at start of coding sessions)

1. Never use `JSON.stringify` inside `onclick` attributes
2. Every html-building function must declare `var html` first
3. Async tab renderers must be awaited
4. Don't redeclare foundation variables
5. Apostrophes need HTML encoding
6. Always V8-validate after edits
7. Check that `var html` moves with functions when splitting files
8. **NEW**: Never expose `service_role` key in frontend code — Edge Functions only
9. **NEW**: Test RLS policies as a real non-admin user, not as service_role

---

## Disclaimer

E-Borgen is an independent fan project. Not affiliated with or endorsed by Magic & Wires LLC or FarmRPG. All FarmRPG game content, names, and item icons are property of their respective owners. For game issues, contact FarmRPG. For trade site issues, contact us.
