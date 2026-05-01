# 🌻 E-Borgen — Setup Guide

Step-by-step from zero. Reasonable time estimate: ~1 hour for someone who's done Chicken Zone.

---

## 1. Get an email address

Pick one you'll keep. Suggestions:
- `eborgen.support@gmail.com` (or any free Gmail)
- A subdomain forwarder if you ever buy a custom domain

This becomes:
- Your Supabase login
- The "contact us" address shown to users
- The destination for ban appeals

---

## 2. Create the Supabase project

1. Go to https://supabase.com
2. Sign up with the email above
3. Click "New Project"
4. Settings:
   - **Name**: `e-borgen` (or whatever)
   - **Database password**: generate a strong one and save it in your password manager
   - **Region**: `West US (Oregon)` for Seattle proximity
   - **Plan**: Free
5. Wait ~2 minutes for it to provision

Once provisioned, go to **Project Settings → API**. Save these three values:
- **URL** (e.g. `https://abcdefgh.supabase.co`)
- **anon public** key (long JWT string — safe to put in frontend code)
- **service_role** key (long JWT string — **NEVER** put in frontend code; Edge Functions only)

---

## 3. Run the SQL files

In Supabase, go to the **SQL editor** (left sidebar, looks like a database icon).

Click "New query," then paste and run **in order**:
1. `sql/01_schema.sql` — creates all tables
2. `sql/02_indexes.sql` — adds performance indexes
3. `sql/03_rls.sql` — enables row-level security
4. `sql/04_triggers.sql` — adds protective triggers
5. `sql/05_max_scale.sql` — storage, audit log, notifications, announcements, soft-delete
6. `sql/seed_items.sql` — adds ~17 placeholder items (full sync later)

After each, you should see "Success. No rows returned" or similar. If you see a red error, stop and ping me.

---

## 4. Make yourself the OG admin

Sign up via the app once (we'll do this together when running locally), then in the Supabase SQL editor run:

```sql
update public.profiles
set role = 'og', verified_at = now(), farmrpg_username = 'marbles'
where id = (select id from auth.users where email = 'YOUR-LOGIN-EMAIL@example.com');
```

This makes you the OG admin AND skips the bio-code verification (since you're testing).

---

## 5. Wire the frontend to Supabase

Open `js/supabase-client.js` and replace the two placeholders:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY-HERE';
```

with the URL and anon key from step 2.

**Do not commit your service_role key anywhere.** It only goes into Supabase's Edge Function secrets (step 7).

---

## 6. Set up the GitHub repo

1. Go to https://github.com/Marblesbby (your existing account)
2. Create a new repo: `e-borgen`
3. **Private** for now (flip public when ready to launch)
4. Initialize empty (no README, since we have one)
5. Clone locally:
   ```bash
   cd /mnt/c/Users/Jessi/Documents
   git clone https://github.com/Marblesbby/e-borgen.git
   ```
6. Copy all files from this scaffolding into `/mnt/c/Users/Jessi/Documents/e-borgen/`
7. First commit:
   ```bash
   cd /mnt/c/Users/Jessi/Documents/e-borgen
   git add .
   git commit -m "Initial scaffold"
   git push
   ```

---

## 7. Deploy the verify-bio Edge Function

Install Supabase CLI if you haven't:
- Windows (in PowerShell): `scoop install supabase` — or grab from https://supabase.com/docs/guides/cli

Then in WSL:
```bash
cd /mnt/c/Users/Jessi/Documents/e-borgen
supabase login            # one-time
supabase link --project-ref YOUR-PROJECT-REF   # one-time
supabase functions deploy verify-bio
```

The function URL will be something like:
`https://YOUR-PROJECT-REF.supabase.co/functions/v1/verify-bio`

(Service role key is automatically available inside Edge Functions — no manual config needed.)

---

## 8. Enable GitHub Pages

1. Repo → Settings → Pages
2. Source: `main` branch, root folder
3. Save
4. URL will be `https://marblesbby.github.io/e-borgen/`

It takes ~1 minute for the first deploy.

---

## 9. Set up Discord

1. Open Discord (use the switch-accounts feature for separation)
2. Create a new server: "E-Borgen"
3. Channels:
   - `#announcements`
   - `#general`
   - `#bug-reports`
   - `#suggestions`
   - `#trade-help`
4. Server settings → Invites → Create invite → Set "Never expire" + unlimited uses
5. Copy invite link, paste into the footer of `index.html` (search for `id="discordLink"`)

---

## 10. Test the local flow

Open https://marblesbby.github.io/e-borgen/ — you should see:
- The homepage with chalkboard hero
- Borgen's cut counter at 0 AC
- Chat text generator working (try copy)
- "Sign In" button (top right)

Click Sign In → use the magic-link or email/password flow. Confirm via your email.

After signing in, you should see your "M" avatar, presence toggle, and a "Link my account" prompt. From the SQL update in step 4, your verified_at is already set, so you should immediately have full access.

---

## What's working in this scaffold

- ✅ Homepage layout & visual design
- ✅ Borgen's Cut counter (live from DB)
- ✅ Chat text generator (no account required)
- ✅ Sidebar nav + responsive layout
- ✅ Presence toggle (Active / Away)
- ✅ My Listings query (will show empty until we build the post flow)
- ✅ All schema, RLS, triggers, indexes
- ✅ Edge Function for bio-code verification

## What's NOT yet wired

- ❌ Full sign-in/sign-up modal (placeholder alert for now)
- ❌ Post-listing modal (FAB button doesn't do anything yet)
- ❌ Stall management
- ❌ Browse pages (Stalls, Buy, Charity, Leaderboard)
- ❌ Bio-code claim UI in Settings
- ❌ Flower-giving from profiles
- ❌ Reports / admin panel
- ❌ Full buddy.farm items sync

These are next-session work. The scaffolding is structured so each piece is an isolated module.
