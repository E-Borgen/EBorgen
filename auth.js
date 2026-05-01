// ============================================================
// E-BORGEN: auth.js
// Sign in / sign up / sign out + profile loading.
// ============================================================

import { supabase, getSession, invalidate, reportError, toast } from './supabase-client.js';

// ---------- SIGN UP ----------
export async function signUp(email, password) {
  try {
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) throw error;
    toast('Check your email to confirm 📬');
    return data;
  } catch (err) {
    reportError('Sign up failed', err);
    return null;
  }
}

// ---------- SIGN IN ----------
export async function signIn(email, password) {
  try {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    toast('Welcome back 🌻');
    return data;
  } catch (err) {
    reportError('Sign in failed', err);
    return null;
  }
}

// ---------- SIGN OUT ----------
export async function signOut() {
  try {
    invalidate();
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    location.reload();
  } catch (err) {
    reportError('Sign out failed', err);
  }
}

// ---------- LOAD PROFILE ----------
// Reads public.profiles for the logged-in user. Caches in session.
export async function loadProfile(forceRefresh = false) {
  const sess = getSession();
  if (sess.profile && !forceRefresh) return sess.profile;
  if (!sess.user) return null;

  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', sess.user.id)
      .single();
    if (error) throw error;

    // Defense-in-depth: confirm IDs still match (Chicken Zone lesson)
    if (data && data.id !== sess.user.id) {
      console.warn('[E-Borgen] profile/user mismatch — invalidating');
      invalidate();
      return null;
    }

    sess.profile = data;
    return data;
  } catch (err) {
    reportError('Could not load profile', err);
    return null;
  }
}

// ---------- AUTH STATUS HELPERS ----------
export function isLoggedIn() { return !!getSession().user; }
export function isVerified() {
  const p = getSession().profile;
  return !!(p && p.verified_at && !p.is_banned);
}
export function isAdmin() {
  const p = getSession().profile;
  return !!(p && ['mod','admin','og'].includes(p.role));
}
export function isOG() {
  const p = getSession().profile;
  return !!(p && p.role === 'og');
}

// Initial profile bootstrap on auth events
window.addEventListener('eborgen:auth', async (e) => {
  if (e.detail.sess?.user) {
    await loadProfile(true);
    window.dispatchEvent(new CustomEvent('eborgen:profileReady'));
  } else {
    window.dispatchEvent(new CustomEvent('eborgen:profileReady'));
  }
});
