// ============================================================
// E-BORGEN Edge Function: verify-bio
// Deno runtime. Deploy with:
//   supabase functions deploy verify-bio
//
// Flow:
//   1. Frontend POSTs { username } -> we generate code, store
//      pending verification_attempts row, return code to display
//      to user
//   2. Frontend (after user pastes in bio) POSTs { username, mode: "check" }
//   3. We fetch farmrpg.com/profile.php?user_name=USERNAME
//   4. If page contains the code AND it matches our pending row,
//      we mark profile.verified_at = now() and farmrpg_username = X
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Code generation: 🌻 + 5 chars (no O/0/I/1 confusion)
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function generateCode() {
  let s = '🌻';
  for (let i = 0; i < 5; i++) s += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  return s;
}

const FARM_PROFILE_URL = (username: string) =>
  `https://farmrpg.com/profile.php?user_name=${encodeURIComponent(username)}`;

Deno.serve(async (req) => {
  // CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
      }
    });
  }

  const supa = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  // Authenticate caller
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'no auth' }, 401);
  const { data: { user }, error: userErr } = await supa.auth.getUser(authHeader.replace('Bearer ', ''));
  if (userErr || !user) return json({ error: 'invalid auth' }, 401);

  const body = await req.json().catch(() => ({}));
  const { username, mode } = body;
  if (!username || typeof username !== 'string') {
    return json({ error: 'username required' }, 400);
  }
  // Sanitize: FarmRPG usernames are alphanumeric/limited
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(username)) {
    return json({ error: 'invalid username format' }, 400);
  }

  // ----- MODE A: start verification (generate code) -----
  if (mode === 'start' || !mode) {
    const code = generateCode();
    // Invalidate any prior pending attempts for this user
    await supa.from('verification_attempts')
      .update({ status: 'expired' })
      .eq('user_id', user.id)
      .eq('status', 'pending');
    // Insert new pending attempt
    const { error: insErr } = await supa.from('verification_attempts').insert({
      user_id: user.id,
      claimed_username: username,
      code,
      status: 'pending'
    });
    if (insErr) return json({ error: 'db_error', detail: insErr.message }, 500);
    return json({ ok: true, code, username, expires_in_seconds: 300 });
  }

  // ----- MODE B: check (after user pasted code in bio) -----
  if (mode === 'check') {
    // Get latest pending attempt
    const { data: att, error: attErr } = await supa
      .from('verification_attempts')
      .select('*')
      .eq('user_id', user.id)
      .eq('claimed_username', username)
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(1)
      .single();
    if (attErr || !att) return json({ error: 'no pending attempt — start first' }, 400);
    if (new Date(att.expires_at).getTime() < Date.now()) {
      await supa.from('verification_attempts').update({ status: 'expired' }).eq('id', att.id);
      return json({ error: 'expired — start over' }, 410);
    }

    // Increment attempts counter
    await supa.from('verification_attempts').update({ attempts: (att.attempts || 0) + 1 }).eq('id', att.id);

    // Fetch the FarmRPG profile page
    let pageText = '';
    try {
      const resp = await fetch(FARM_PROFILE_URL(username), {
        headers: { 'User-Agent': 'E-Borgen-Verify/1.0 (fan project)' }
      });
      if (!resp.ok) return json({ error: 'profile fetch failed', status: resp.status }, 502);
      pageText = await resp.text();
    } catch (err) {
      return json({ error: 'profile unreachable', detail: String(err) }, 502);
    }

    // Look for the code on the page
    if (!pageText.includes(att.code)) {
      return json({ ok: false, found: false, message: 'Code not found in your bio yet' });
    }

    // Confirm username uniqueness — no other verified profile has it
    const { data: clash } = await supa
      .from('profiles')
      .select('id')
      .eq('farmrpg_username', username)
      .not('verified_at', 'is', null)
      .neq('id', user.id)
      .maybeSingle();
    if (clash) {
      return json({ error: 'username already claimed by another user' }, 409);
    }

    // Success — mark verified
    const now = new Date().toISOString();
    const { error: updErr } = await supa.from('profiles').update({
      farmrpg_username: username,
      verified_at: now
    }).eq('id', user.id);
    if (updErr) return json({ error: 'db_error', detail: updErr.message }, 500);

    await supa.from('verification_attempts').update({
      status: 'success',
      completed_at: now
    }).eq('id', att.id);

    return json({ ok: true, found: true, username, verified_at: now });
  }

  return json({ error: 'unknown mode' }, 400);
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}
