// ============================================================
// E-BORGEN: supabase-client.js
// Initializes the Supabase client + global state.
//
// >>> FILL IN YOUR PROJECT URL AND ANON KEY BELOW <<<
//
// The anon key is SAFE to ship in frontend code — RLS policies
// gate every operation. The service_role key is NEVER in this file.
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------- CONFIG ----------
const SUPABASE_URL = 'https://ivxtixnwzzrtmqihpjgh.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml2eHRpeG53enpydG1xaWhwamdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc2MDY2MzksImV4cCI6MjA5MzE4MjYzOX0.ncEml6RltV-kBU3HWPAervh3Dq7UXYcg6TeyYVQFKW0';

// localStorage cache key — bump on meaningful pushes
export const LS_CACHE_KEY = 'eborgen_v0_0_1';

// ---------- CLIENT ----------
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});

// ---------- SESSION CACHE ----------
// Per-tab, in-memory only. Cleared on auth changes.
const session = {
  user: null,         // auth.users row
  profile: null,      // public.profiles row
  items: null,        // [items] (catalog)
  myListings: null,   // [listings]
};
export function getSession() { return session; }
export function invalidate(key) {
  if (key) session[key] = null;
  else for (const k of Object.keys(session)) session[k] = null;
}

// ---------- AUTH STATE LISTENER ----------
supabase.auth.onAuthStateChange((event, sess) => {
  // Cross-account contamination guard (lesson from Chicken Zone)
  const newId = sess?.user?.id || null;
  const oldId = session.user?.id || null;
  if (newId !== oldId) invalidate();
  session.user = sess?.user || null;
  // Tell the rest of the app to re-render
  window.dispatchEvent(new CustomEvent('eborgen:auth', { detail: { event, sess } }));
});

// ---------- TOAST HELPER ----------
export function toast(msg, kind = 'ok', durationMs = 3500) {
  const mount = document.getElementById('toastMount');
  if (!mount) return;
  let stack = mount.querySelector('.toast-stack');
  if (!stack) {
    stack = document.createElement('div');
    stack.className = 'toast-stack';
    mount.appendChild(stack);
  }
  const el = document.createElement('div');
  el.className = 'toast' + (kind === 'error' ? ' error' : kind === 'warn' ? ' warn' : '');
  el.textContent = msg;
  stack.appendChild(el);
  setTimeout(() => el.remove(), durationMs);
}

// ---------- ERROR HELPER ----------
export function reportError(label, err) {
  console.error(`[E-Borgen] ${label}:`, err);
  toast(`${label} — try again`, 'error');
}
