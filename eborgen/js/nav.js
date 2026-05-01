// ============================================================
// E-BORGEN: nav.js
// Renders the sidebar navigation (wooden sign stack).
// ============================================================

import { isAdmin } from './auth.js';

const NAV_ITEMS = [
  { href: '/',                 icon: '🏡', label: 'Home',        sub: 'E-Borgen' },
  { href: '/pages/stalls.html',icon: '🍅', label: 'Stalls',      sub: 'BoregnMart' },
  { href: '/pages/buy.html',   icon: '📦', label: 'Buy',         sub: 'Express' },
  { href: '/pages/charity.html',icon:'🪴', label: 'Charity',     sub: 'give & ask' },
  { href: '/pages/leaderboard.html',icon:'💐',label:'Leaderboard',sub: 'flowers' },
  { href: '/pages/settings.html',icon:'⚙️',label:'Settings',    sub: '& FAQ' }
];
const ADMIN_ITEM =
  { href: '/pages/admin.html', icon: '⭐', label: 'Admin',       sub: 'modtools' };

function renderSidebar() {
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;

  // Determine active link based on current path
  const path = location.pathname.replace(/\/$/, '') || '/';
  const items = [...NAV_ITEMS];
  if (isAdmin()) items.push(ADMIN_ITEM);

  var html = '';
  html += `
    <div class="sidebar-logo">
      <div class="logo-mark"><span class="e">E</span>-Borgen</div>
      <div class="logo-tag">Borgen's online storefront</div>
    </div>
    <nav class="nav-stack">
  `;
  for (const item of items) {
    const isActive =
      (item.href === '/' && (path === '/' || path === '/index.html')) ||
      (item.href !== '/' && path.endsWith(item.href.replace(/^\//, '')));
    html += `
      <a href="${item.href}" class="nav-link${isActive ? ' active' : ''}">
        <span class="nav-icon">${item.icon}</span>
        <span class="nav-label">${item.label}</span>
        <span class="nav-sub">${item.sub}</span>
      </a>
    `;
  }
  html += `
    </nav>
    <div class="sidebar-footer">
      <strong>Independent fan project.</strong><br>
      Not affiliated with FarmRPG or Magic &amp; Wires LLC.
    </div>
  `;
  sidebar.innerHTML = html;
}

window.addEventListener('eborgen:profileReady', renderSidebar);
window.addEventListener('DOMContentLoaded', renderSidebar);
