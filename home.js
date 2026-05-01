// ============================================================
// E-BORGEN: home.js
// Renders the homepage: hero (chalkboard + Borgen's cut),
// chat-text generator, user's active listings.
// ============================================================

import { supabase, getSession, reportError } from './supabase-client.js';
import { isLoggedIn, isVerified } from './auth.js';

// ============================================================
// HERO: chalkboard + Borgen's cut counter
// ============================================================
async function renderHero() {
  const hero = document.getElementById('hero');
  if (!hero) return;

  // Fetch Borgen's cut
  let totalAc = 0, tradeCount = 0;
  try {
    const { data, error } = await supabase
      .from('borgen_cut')
      .select('total_ac, trade_count')
      .eq('id', 1)
      .single();
    if (error) throw error;
    totalAc = data.total_ac;
    tradeCount = data.trade_count;
  } catch (err) {
    console.warn('Could not load Borgen\'s cut', err);
  }

  hero.innerHTML = `
    <div class="chalkboard">
      <div class="chalk-pre">welcome to</div>
      <h1 class="chalk-title">E-Borgen<span class="accent">.</span></h1>
      <div class="chalk-sub">Borgen heard about the internet. This is what happened.</div>
      <div class="chalk-divider"></div>
      <p class="chalk-body">
        One Wednesday at his Camp, Borgen casually asked if I'd heard of something called <em>"the internet."</em>
        After a long, awkward pause, I admitted I had. His eyes lit up. He asked if I'd help him set up an
        online store. So I did. For every confirmed trade — Borgen gets his cut of <em>100 Ancient Coins</em>.
      </p>
    </div>
    <div class="cut-counter">
      <div class="cut-label">Borgen has earned a fortune of</div>
      <div class="cut-amount">
        <span class="cut-coin">🪙</span>
        <span>${totalAc.toLocaleString()}</span>
      </div>
      <div class="cut-unit">Ancient Coins</div>
      <div class="cut-foot">From <strong>${tradeCount.toLocaleString()} confirmed trades.</strong> He's never been happier.</div>
    </div>
  `;
}

// ============================================================
// CHAT TEXT GENERATOR (works for everyone, no account needed)
// ============================================================

const GEN_STATE = {
  mode: 'sell', // 'buy' | 'sell' | 'trade'
  fromQty: 50,
  fromItem: 'carrot',
  toQty: 500,
  toItem: 'silver'
};

function generateText(s, items) {
  const lookup = (id) => (items.find(i => i.id === id) || { name: id }).name;
  const fromName = lookup(s.fromItem);
  const toName = lookup(s.toItem);
  const verb = { buy: 'buy', sell: 'sell', trade: 'trade' }[s.mode];
  return `Looking to ${verb} ${s.fromQty}x ((${fromName})) for ${s.toQty}x ((${toName}))`;
}

function generateHTML(s, items) {
  const lookup = (id) => (items.find(i => i.id === id) || { name: id }).name;
  const fromName = lookup(s.fromItem);
  const toName = lookup(s.toItem);
  const verb = { buy: 'buy', sell: 'sell', trade: 'trade' }[s.mode];
  return `Looking to ${verb} <code>${s.fromQty}x ((${fromName}))</code> for <code>${s.toQty}x ((${toName}))</code>`;
}

async function loadItems() {
  const sess = getSession();
  if (sess.items) return sess.items;
  try {
    const { data, error } = await supabase
      .from('items')
      .select('id, name, type, is_tradeable, is_currency_like')
      .eq('is_tradeable', true)
      .order('name');
    if (error) throw error;
    sess.items = data || [];
    return sess.items;
  } catch (err) {
    console.warn('Could not load items', err);
    return [];
  }
}

async function renderChatGen() {
  const card = document.getElementById('chatGen');
  if (!card) return;
  const items = await loadItems();
  const currency = items.filter(i => i.is_currency_like);
  const goods    = items.filter(i => !i.is_currency_like);

  // Default selections (in case seed differs)
  if (!items.find(i => i.id === GEN_STATE.fromItem)) GEN_STATE.fromItem = goods[0]?.id || 'carrot';
  if (!items.find(i => i.id === GEN_STATE.toItem))   GEN_STATE.toItem   = currency[0]?.id || 'silver';

  function renderInner() {
    const optList = (list, sel) =>
      list.map(i => `<option value="${i.id}"${i.id===sel?' selected':''}>${i.name}</option>`).join('');

    // For "Trade" mode, both sides offer goods (no currency)
    const fromOpts = optList(GEN_STATE.mode === 'buy' ? currency : goods, GEN_STATE.fromItem);
    const toOpts   = optList(GEN_STATE.mode === 'sell' ? currency : (GEN_STATE.mode==='buy' ? goods : goods), GEN_STATE.toItem);

    card.innerHTML = `
      <div class="gen-awning"></div>
      <div class="gen-body">
        <div class="gen-eyebrow">stop typing it out by hand</div>
        <div class="gen-title">Write a clean trade chat post in 5 seconds.</div>
        <p class="gen-sub">
          Pick what you're after, hit copy, paste it in trade chat. Item names auto-format as
          <strong>((double-parens))</strong> just like the game.
        </p>
        <div class="tab-row" id="genTabs">
          <button class="tab${GEN_STATE.mode==='buy'?' active':''}" data-mode="buy">Buy</button>
          <button class="tab${GEN_STATE.mode==='sell'?' active':''}" data-mode="sell">Sell</button>
          <button class="tab${GEN_STATE.mode==='trade'?' active':''}" data-mode="trade">Trade</button>
        </div>
        <div class="form-row">
          <div class="field">
            <label class="field-label">${GEN_STATE.mode === 'buy' ? 'Paying with' : 'Offering'}</label>
            <div class="field-row">
              <input type="number" id="fromQty" value="${GEN_STATE.fromQty}" class="input qty" min="1">
              <select class="select" id="fromItem">${fromOpts}</select>
            </div>
          </div>
          <div class="field-arrow">→</div>
          <div class="field">
            <label class="field-label">${GEN_STATE.mode === 'buy' ? 'For' : 'Asking for'}</label>
            <div class="field-row">
              <input type="number" id="toQty" value="${GEN_STATE.toQty}" class="input qty" min="1">
              <select class="select" id="toItem">${toOpts}</select>
            </div>
          </div>
        </div>
        <div class="preview-box" id="genPreview">${generateHTML(GEN_STATE, items)}</div>
        <div class="button-row">
          <button class="btn" id="genCopy">📋 Copy to Clipboard</button>
          <button class="btn btn-secondary" id="genSwap">🔄 Swap sides</button>
        </div>
      </div>
    `;
    wireUp();
  }

  function wireUp() {
    document.getElementById('genTabs').onclick = (e) => {
      const t = e.target.closest('.tab');
      if (!t) return;
      GEN_STATE.mode = t.dataset.mode;
      renderInner();
    };
    const updPreview = () => {
      document.getElementById('genPreview').innerHTML = generateHTML(GEN_STATE, items);
    };
    document.getElementById('fromQty').oninput = (e) => { GEN_STATE.fromQty = Math.max(1, +e.target.value || 1); updPreview(); };
    document.getElementById('toQty').oninput   = (e) => { GEN_STATE.toQty   = Math.max(1, +e.target.value || 1); updPreview(); };
    document.getElementById('fromItem').onchange = (e) => { GEN_STATE.fromItem = e.target.value; updPreview(); };
    document.getElementById('toItem').onchange   = (e) => { GEN_STATE.toItem   = e.target.value; updPreview(); };

    document.getElementById('genCopy').onclick = async () => {
      const text = generateText(GEN_STATE, items);
      try {
        await navigator.clipboard.writeText(text);
        const btn = document.getElementById('genCopy');
        const orig = btn.textContent;
        btn.textContent = '✓ Copied!';
        setTimeout(() => btn.textContent = orig, 1800);
      } catch (err) {
        alert('Could not copy — text:\n\n' + text);
      }
    };
    document.getElementById('genSwap').onclick = () => {
      [GEN_STATE.fromItem, GEN_STATE.toItem] = [GEN_STATE.toItem, GEN_STATE.fromItem];
      [GEN_STATE.fromQty, GEN_STATE.toQty] = [GEN_STATE.toQty, GEN_STATE.fromQty];
      renderInner();
    };
  }

  renderInner();
}

// ============================================================
// MY ACTIVE LISTINGS
// ============================================================
async function renderMyListings() {
  const grid = document.getElementById('myListings');
  const head = document.getElementById('listingsHead');
  const count = document.getElementById('listingsCount');
  if (!grid || !head) return;

  if (!isLoggedIn() || !isVerified()) {
    grid.innerHTML = '';
    head.hidden = true;
    return;
  }

  try {
    const { data, error } = await supabase
      .from('listings')
      .select(`
        id, type, status, expires_at, created_at,
        listing_items(id, item_id, side, qty, remaining_qty,
          items(id, name, icon_url))
      `)
      .eq('seller_user_id', getSession().user.id)
      .in('status', ['open','locked'])
      .order('created_at', { ascending: false });
    if (error) throw error;

    const list = data || [];
    head.hidden = list.length === 0;
    if (count) count.textContent = list.length === 1 ? '1 in flight' : `${list.length} in flight`;
    grid.innerHTML = list.map(renderListingCard).join('');
  } catch (err) {
    reportError('Could not load your listings', err);
  }
}

function timeLeft(iso) {
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return 'expired';
  const m = Math.floor(ms / 60000);
  if (m < 60) return `${m}m left`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m left`;
}

function renderListingCard(l) {
  const offers   = (l.listing_items || []).filter(li => li.side === 'offer');
  const requests = (l.listing_items || []).filter(li => li.side === 'request');
  const tagText = {
    sell:  'Sell · Express',
    buy:   'Buy · Restock',
    trade: 'Trade · Black Market',
    stall: 'Stall · BoregnMart'
  }[l.type] || l.type;

  const lineHTML = (li) => `
    <div class="listing-line">
      <div class="item-icon">${li.items?.icon_url ? `<img src="${li.items.icon_url}" alt="">` : '🔹'}</div>
      <div class="item-info">
        <div class="item-name"><a href="https://buddy.farm/i/${li.item_id}/" target="_blank" rel="noopener">${li.items?.name || li.item_id}</a></div>
      </div>
      <div class="item-qty">×${li.qty}</div>
    </div>
  `;

  return `
    <article class="listing-card" data-type="${l.type}" data-id="${l.id}">
      <div class="listing-head">
        <span class="listing-tag">${tagText}</span>
        <span class="listing-queue">${l.status === 'locked' ? '🔒 locked' : ''}</span>
      </div>
      ${offers.map(lineHTML).join('')}
      ${requests.length > 0 ? '<div class="swap-arrow">↓ for ↓</div>' : ''}
      ${requests.map(lineHTML).join('')}
      <div class="listing-foot">
        <div class="listing-time"><span class="clock">⏱</span> ${timeLeft(l.expires_at)}</div>
        <div style="display: flex; gap: 6px;">
          <button class="icon-btn edit" title="Edit" data-act="edit" data-id="${l.id}">✏️</button>
          <button class="icon-btn" title="Cancel" data-act="cancel" data-id="${l.id}">✕</button>
        </div>
      </div>
    </article>
  `;
}

// ============================================================
// LINK PROMPT (for logged-in but unverified users)
// ============================================================
function renderLinkPrompt() {
  const el = document.getElementById('linkPrompt');
  if (!el) return;
  if (!isLoggedIn()) { el.hidden = true; return; }
  if (isVerified())  { el.hidden = true; return; }

  el.hidden = false;
  el.innerHTML = `
    <h3>One last step 🌻</h3>
    <p>Link your FarmRPG account to post listings, send flowers, and join queues. It takes about 30 seconds and uses a one-time bio code.</p>
    <a href="/pages/settings.html" class="btn">Link my account</a>
  `;
}

// ============================================================
// BOOT
// ============================================================
async function boot() {
  await renderHero();
  await renderChatGen();
  await renderMyListings();
  renderLinkPrompt();
}

window.addEventListener('eborgen:profileReady', boot);
window.addEventListener('DOMContentLoaded', () => {
  // First paint even before profile loads — hero + generator work for everyone
  renderHero();
  renderChatGen();
});
