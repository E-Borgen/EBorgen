// ============================================================
// E-BORGEN: topbar.js
// Renders the top bar: presence toggle + user pill or sign-in.
// ============================================================

import { getSession } from './supabase-client.js';
import { isLoggedIn, isVerified } from './auth.js';
import { setPresence } from './presence.js';

function formatDuration(fromIso) {
  if (!fromIso) return '';
  const ms = Date.now() - new Date(fromIso).getTime();
  const m = Math.floor(ms / 60000);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ${m % 60}m`;
  const d = Math.floor(h / 24);
  return `${d}d ${h % 24}h`;
}

function renderTopbar() {
  const bar = document.getElementById('topbar');
  if (!bar) return;
  const { user, profile } = getSession();

  var html = '';

  // ---- LEFT: presence toggle (logged-in only) ----
  if (user && profile) {
    const status = profile.presence_status || 'away';
    const dur = formatDuration(profile.presence_changed_at);
    const meta = status === 'active' ? `open · ${dur}` : `closed · ${dur}`;
    const label = status === 'active' ? 'Active Trading' : 'Away';
    html += `
      <button class="toggle-shop" data-state="${status}" id="presenceToggle">
        <span class="toggle-light"></span>
        <span>
          <div class="toggle-status">${label}</div>
          <div class="toggle-meta">${meta}</div>
        </span>
      </button>
    `;
  } else {
    html += `<div></div>`; // spacer
  }

  // ---- RIGHT: user pill or sign-in button ----
  if (user && profile) {
    const initial = (profile.farmrpg_username || user.email || '?')[0].toUpperCase();
    const name = profile.farmrpg_username || user.email.split('@')[0];
    const flowerCount = profile.flower_count || 0;
    const mailbox = profile.mailbox_capacity ? `${profile.mailbox_capacity}` : '?';
    html += `
      <a href="/pages/settings.html" class="user-pill" title="Settings">
        <div class="avatar">${initial}</div>
        <div class="user-meta">
          <div class="user-name">${name}${isVerified() ? '' : ' <span style="opacity:0.5">⚠</span>'}</div>
          <div class="user-stats">
            <span class="flower">🌸 ${flowerCount}</span>
            <span>·</span>
            <span class="mailbox">📬 ${mailbox}</span>
          </div>
        </div>
      </a>
    `;
  } else {
    html += `<button class="signin-btn" id="signInBtn">Sign In</button>`;
  }

  bar.innerHTML = html;

  // Wire up presence toggle
  const tog = document.getElementById('presenceToggle');
  if (tog) tog.onclick = async () => {
    const cur = tog.dataset.state;
    await setPresence(cur === 'active' ? 'away' : 'active');
  };

  // Wire up sign-in (placeholder for now)
  const sib = document.getElementById('signInBtn');
  if (sib) sib.onclick = () => {
    // TODO: open sign-in modal in next session
    alert('Sign-in modal coming next session — for now use Supabase email magic link');
  };
}

window.addEventListener('eborgen:profileReady', renderTopbar);
window.addEventListener('eborgen:presenceChanged', renderTopbar);
window.addEventListener('DOMContentLoaded', renderTopbar);
