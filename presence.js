// ============================================================
// E-BORGEN: presence.js
// Active Trading / Away toggle.
// - Persistent across tabs (DB-backed)
// - 12h "still there?" nudge
// - 7-day stale auto-flip handled by SQL view
// - Heartbeat updates last_seen_at on page load
// ============================================================

import { supabase, getSession, reportError, toast } from './supabase-client.js';
import { loadProfile, isLoggedIn } from './auth.js';

const STALE_HOURS = 12;
const NUDGE_DISMISSED_KEY = 'eborgen_nudge_dismissed_at';

// ---------- HEARTBEAT ----------
// Touch last_seen_at on every page load (silent, no UI feedback)
export async function heartbeat() {
  if (!isLoggedIn()) return;
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('id', getSession().user.id);
    if (error) console.warn('heartbeat failed', error);
  } catch (err) {
    console.warn('heartbeat error', err);
  }
}

// ---------- TOGGLE ----------
export async function setPresence(newStatus) {
  if (!['active','away'].includes(newStatus)) return;
  if (!isLoggedIn()) return;
  try {
    const { error } = await supabase
      .from('profiles')
      .update({
        presence_status: newStatus,
        presence_changed_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString()
      })
      .eq('id', getSession().user.id);
    if (error) throw error;
    await loadProfile(true);
    window.dispatchEvent(new CustomEvent('eborgen:presenceChanged'));
    toast(newStatus === 'active' ? 'Stall is open 🌻' : 'Stall closed 🚪');
  } catch (err) {
    reportError('Could not update presence', err);
  }
}

// ---------- 12h NUDGE ----------
// Called periodically; shows modal if user has been "active" for 12+ hours
// AND hasn't dismissed the nudge in the last 6 hours.
export function checkStalePresence() {
  const p = getSession().profile;
  if (!p || p.presence_status !== 'active') return;

  const changedAt = new Date(p.presence_changed_at);
  const hoursActive = (Date.now() - changedAt.getTime()) / (1000 * 60 * 60);
  if (hoursActive < STALE_HOURS) return;

  // Don't nudge again if user dismissed within last 6h
  const lastDismissed = parseInt(localStorage.getItem(NUDGE_DISMISSED_KEY) || '0', 10);
  if (Date.now() - lastDismissed < 6 * 60 * 60 * 1000) return;

  showStaleNudge(hoursActive);
}

function showStaleNudge(hoursActive) {
  const mount = document.getElementById('modalMount');
  if (!mount || mount.querySelector('.modal-bg')) return; // already showing

  mount.innerHTML = `
    <div class="modal-bg">
      <div class="modal" style="position: relative;">
        <button class="modal-close" id="nudgeClose" title="Close">✕</button>
        <h2>Still trading? 🌻</h2>
        <p>You've been Active Trading for <strong>${Math.floor(hoursActive)} hours</strong>. Did you forget to close up?</p>
        <div class="button-row">
          <button class="btn" id="nudgeStay">I'm still here</button>
          <button class="btn btn-secondary" id="nudgeAway">Set me Away</button>
        </div>
      </div>
    </div>
  `;
  const close = () => {
    localStorage.setItem(NUDGE_DISMISSED_KEY, String(Date.now()));
    mount.innerHTML = '';
  };
  document.getElementById('nudgeClose').onclick = close;
  document.getElementById('nudgeStay').onclick = async () => {
    // Reset presence_changed_at by toggling away->active
    await setPresence('active'); // updates timestamp
    close();
  };
  document.getElementById('nudgeAway').onclick = async () => {
    await setPresence('away');
    close();
  };
}

// ---------- BOOTSTRAP ----------
window.addEventListener('eborgen:profileReady', () => {
  heartbeat();
  checkStalePresence();
});

// Periodic recheck every 10 minutes
setInterval(checkStalePresence, 10 * 60 * 1000);
