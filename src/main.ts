import './style.css';
import { gsap } from 'gsap';
import { Model, banThreats, predictEnemy, type Bracket, type Data, type Draft, type Hero, type Pick } from './engine';
import { POS_LABEL } from './positions';
import { ATTR_COLOR, filterGrid, portrait, renderGrid } from './ui/picker';
import { renderPicks } from './ui/results';

type Team = 'ally' | 'enemy' | 'ban';
const SIZE: Record<Team, number> = { ally: 4, enemy: 5, ban: 10 };
const HIDDEN_KEY = 'lastpick.hidden';

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;

interface State {
  ally: (number | null)[];
  enemy: (number | null)[];
  ban: (number | null)[];
  you: number | null;
  pos: number;
  bracket: Bracket;
  active: { team: Team; i: number } | null;
  attr: string | null;
}

const state: State = {
  ally: Array(4).fill(null),
  enemy: Array(5).fill(null),
  ban: Array(10).fill(null),
  you: null,
  pos: 0,
  bracket: 'all',
  active: { team: 'enemy', i: 0 },
  attr: null,
};

let data: Data;
let model: Model;
let hidden = new Set<number>();
try { hidden = new Set(JSON.parse(localStorage.getItem(HIDDEN_KEY) || '[]')); } catch { /* storage blocked */ }
const saveHidden = () => { try { localStorage.setItem(HIDDEN_KEY, JSON.stringify([...hidden])); } catch { /* ignore */ } };

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---------- URL state ----------
function writeHash() {
  const ids = (a: (number | null)[]) => a.filter((x): x is number => x != null).join('.');
  const p = new URLSearchParams();
  if (ids(state.ally)) p.set('a', ids(state.ally));
  if (ids(state.enemy)) p.set('e', ids(state.enemy));
  if (ids(state.ban)) p.set('b', ids(state.ban));
  if (state.you) p.set('y', String(state.you));
  if (state.pos) p.set('p', String(state.pos));
  if (state.bracket !== 'all') p.set('r', String(state.bracket));
  history.replaceState(null, '', p.toString() ? `#${p}` : location.pathname);
}

function readHash() {
  const p = new URLSearchParams(location.hash.slice(1));
  const valid = (x: number) => model.byId.has(x);
  const seen = new Set<number>();
  const fill = (team: Team, key: string) => {
    const ids = (p.get(key) || '').split('.').map(Number).filter((x) => valid(x) && !seen.has(x));
    ids.slice(0, SIZE[team]).forEach((id, i) => { state[team][i] = id; seen.add(id); });
  };
  fill('ally', 'a');
  fill('enemy', 'e');
  fill('ban', 'b');
  const y = Number(p.get('y'));
  if (valid(y) && !seen.has(y)) state.you = y;
  const pos = Number(p.get('p'));
  if (pos >= 1 && pos <= 5) state.pos = pos;
  const r = p.get('r');
  if (r === '0' || r === '1' || r === '2') state.bracket = Number(r) as Bracket;
}

// ---------- helpers ----------
const taken = () => new Set([...state.ally, ...state.enemy, ...state.ban, state.you].filter((x): x is number => x != null));
const draft = (): Draft => ({
  allies: state.ally.filter((x): x is number => x != null),
  enemies: state.enemy.filter((x): x is number => x != null),
  bans: state.ban.filter((x): x is number => x != null),
});

function nextEmpty(): { team: Team; i: number } | null {
  const cur = state.active ?? { team: 'enemy' as Team, i: 0 };
  const order: Team[] = cur.team === 'ban' ? ['ban', 'enemy', 'ally'] : cur.team === 'ally' ? ['ally', 'enemy'] : ['enemy', 'ally'];
  for (const t of order) {
    const start = t === cur.team ? cur.i : 0;
    for (let k = 0; k < SIZE[t]; k++) {
      const i = (start + k) % SIZE[t];
      if (state[t][i] == null) return { team: t, i };
    }
  }
  return null; // both teams full
}

function toast(msg: string) {
  const t = $('toast');
  t.textContent = msg;
  gsap.killTweensOf(t);
  gsap.timeline()
    .to(t, { opacity: 1, y: 0, duration: 0.25, ease: 'power2.out' })
    .to(t, { opacity: 0, y: 20, duration: 0.3, delay: 1.6 });
}

// ---------- rendering ----------
function slotEl(team: Team, i: number, id: number | null) {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'slot';
  const isActive = state.active?.team === team && state.active?.i === i;
  if (isActive) b.classList.add('active');
  if (id != null) {
    const h = model.byId.get(id)!;
    b.classList.add('filled');
    b.innerHTML = `<img alt="" src="${portrait(h)}"><span class="x" aria-hidden="true">✕</span>`;
    b.setAttribute('aria-label', `${h.name} — click to remove`);
    b.title = `${h.name} — click to remove`;
  } else {
    b.innerHTML = '<span class="plus">+</span>';
    b.setAttribute('aria-label', `Empty ${team} slot ${i + 1}`);
  }
  b.addEventListener('click', () => {
    if (state[team][i] != null) state[team][i] = null;
    state.active = { team, i };
    update();
    $('q').focus({ preventScroll: true });
  });
  return b;
}

function youSlot() {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'slot you';
  if (state.you != null) {
    const h = model.byId.get(state.you)!;
    b.classList.add('filled');
    b.innerHTML = `<img alt="" src="${portrait(h)}"><span class="x" aria-hidden="true">✕</span>`;
    b.title = `Your pick: ${h.name} — click to clear`;
    b.setAttribute('aria-label', b.title);
  } else {
    b.innerHTML = '<span class="plus">YOU</span>';
    b.title = 'Your last pick — lock one in from the results';
    b.setAttribute('aria-label', b.title);
  }
  b.addEventListener('click', () => { state.you = null; update(); });
  return b;
}

function renderBoard(popped?: { team: Team; i: number }) {
  for (const team of ['ally', 'enemy', 'ban'] as Team[]) {
    const el = $(`${team}Slots`);
    el.innerHTML = '';
    state[team].forEach((id, i) => el.appendChild(slotEl(team, i, id)));
    if (team === 'ally') el.appendChild(youSlot());
  }
  const bans = state.ban.filter((x) => x != null).length;
  $('banCount').textContent = bans ? `(${bans})` : '';
  if (popped && !reduced) {
    const host = $(`${popped.team}Slots`).children[popped.i];
    if (host) gsap.fromTo(host, { scale: 0.7, opacity: 0.2 }, { scale: 1, opacity: 1, duration: 0.45, ease: 'back.out(2.2)' });
  }
  const a = state.active;
  if (!a) {
    $('target').innerHTML = 'Draft complete — lock in your pick from the list, or click a slot to change it';
    return;
  }
  const label = a.team === 'ally' ? `<b class="ally">your team</b> slot ${a.i + 1}` : a.team === 'enemy' ? `<b class="enemy">enemy</b> slot ${a.i + 1}` : `<b class="ban">ban</b> slot ${a.i + 1}`;
  $('target').innerHTML = `Adding to ${label} · click a slot to change`;
}

let lastResultKey = '';
function renderResults() {
  const d = draft();
  const all = model.rank(d, { position: state.pos || undefined, exclude: hidden });
  const handlers = {
    onLock: (id: number) => { state.you = id; update(); toast(`Locked in ${model.byId.get(id)!.name}`); },
    onHide: (id: number) => {
      hidden.add(id); saveHidden(); update();
      toast(`${model.byId.get(id)!.name} hidden from suggestions`);
    },
  };
  const top = all.slice(0, 10);
  const worst = all.slice(-5).reverse();
  renderPicks($('picks'), model, top, handlers);
  renderPicks($('avoid'), model, worst, handlers, { actions: false });

  $('resTitle').textContent = d.enemies.length ? 'Best last picks' : 'Strongest picks right now';
  $('resHint').textContent = d.enemies.length
    ? `vs ${d.enemies.length} enem${d.enemies.length === 1 ? 'y' : 'ies'}${d.allies.length ? ` · with ${d.allies.length} all${d.allies.length === 1 ? 'y' : 'ies'}` : ''}`
    : 'add enemy heroes to counter-pick';
  if (!top.length) $('picks').innerHTML = '<li class="empty">No heroes left for this filter.</li>';

  const note = $('hiddenNote');
  note.innerHTML = hidden.size ? `${hidden.size} hero${hidden.size > 1 ? 'es' : ''} hidden from your pool · <button type="button" id="unhide">show all</button>` : '';
  note.querySelector('#unhide')?.addEventListener('click', () => { hidden.clear(); saveHidden(); update(); });

  const key = top.map((p) => p.hero.id).join(',');
  if (key !== lastResultKey && !reduced) {
    gsap.fromTo('#picks .pick', { y: 14, opacity: 0 }, { y: 0, opacity: 1, duration: 0.4, stagger: 0.035, ease: 'power3.out', clearProps: 'transform,opacity' });
  }
  lastResultKey = key;
}

// Enemy reads: only while the enemy still has picks left. Our team includes the locked-in pick.
function renderReads() {
  const d = draft();
  const box = $('reads');
  box.hidden = d.enemies.length >= 5;
  if (box.hidden) return;
  const team: Draft = { ...d, allies: state.you != null ? [...d.allies, state.you] : d.allies };
  const beats = (p: Pick) => p.vs.filter((l) => l.value >= 0.8).sort((a, b) => b.value - a.value).slice(0, 3)
    .map((l) => { const h = model.byId.get(l.hero)!; return `<span class="chip bad" title="beats ${h.name}"><img alt="" src="${portrait(h)}">+${l.value.toFixed(1)}</span>`; }).join('');
  const row = (p: Pick, right: string, cap: string) => `<li><img class="pic" alt="" src="${portrait(p.hero)}" width="128" height="72">
    <div class="pmain"><div class="pname">${p.hero.name}</div><div class="why">${beats(p)}</div></div>
    <div class="score"><b>${right}</b><small>${cap}</small></div></li>`;
  $('preds').innerHTML = predictEnemy(model, team).map((x) => row(x.pick, `${Math.round(x.chance * 100)}%`, 'chance')).join('');
  $('bans').innerHTML = banThreats(model, team).map((x) => row(x.pick, `${x.value >= 0 ? '+' : '−'}${Math.abs(x.value).toFixed(1)}`, 'threat')).join('');
  $('predHint').textContent = team.allies.length || team.enemies.length ? 'popularity + fit vs your team' : 'most likely in this bracket';
  $('banHint').textContent = team.allies.length ? 'would hurt your draft most' : 'strongest heroes in this bracket';
}

function refreshGrid() {
  const best = filterGrid($('heroGrid'), model.byId, ($('q') as HTMLInputElement).value, state.attr, taken());
  const any = $('heroGrid').querySelector('.hero:not(.dim)');
  $('heroGrid').dataset.empty = any ? '' : '1';
  return best;
}

function update(popped?: { team: Team; i: number }) {
  model = model.bracket === state.bracket ? model : new Model(data, state.bracket);
  renderBoard(popped);
  renderResults();
  renderReads();
  refreshGrid();
  writeHash();
}

function pick(id: number) {
  if (taken().has(id)) return;
  const slot = state.active;
  if (!slot) return toast('Both teams are full — click a slot to change it');
  state[slot.team][slot.i] = id;
  state.active = nextEmpty();
  ($('q') as HTMLInputElement).value = '';
  update(slot);
}

// ---------- controls ----------
function buildControls() {
  const seg = $('posSeg');
  POS_LABEL.forEach((label, i) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.setAttribute('role', 'radio');
    b.textContent = i === 0 ? 'Any' : `${i}`;
    b.title = label;
    b.setAttribute('aria-label', i === 0 ? 'Any position' : `Position ${i}: ${label}`);
    b.addEventListener('click', () => { state.pos = i; syncControls(); update(); });
    seg.appendChild(b);
  });
  const sel = $<HTMLSelectElement>('bracket');
  sel.innerHTML = `<option value="all">All ranks</option>` + data.brackets.map((b, i) => `<option value="${i}">${b}</option>`).join('');
  sel.addEventListener('change', () => { state.bracket = sel.value === 'all' ? 'all' : (Number(sel.value) as Bracket); update(); });

  const attrs = $('attrSeg');
  for (const a of ['str', 'agi', 'int', 'all']) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = a === 'all' ? 'uni' : a;
    b.title = { str: 'Strength', agi: 'Agility', int: 'Intelligence', all: 'Universal' }[a]!;
    b.style.setProperty('--c', ATTR_COLOR[a]);
    b.setAttribute('aria-pressed', 'false');
    b.addEventListener('click', () => { state.attr = state.attr === a ? null : a; syncControls(); refreshGrid(); });
    attrs.appendChild(b);
  }
  syncControls();
}

function syncControls() {
  [...$('posSeg').children].forEach((b, i) => b.setAttribute('aria-checked', String(i === state.pos)));
  $<HTMLSelectElement>('bracket').value = String(state.bracket);
  [...$('attrSeg').children].forEach((b, i) => b.setAttribute('aria-pressed', String(['str', 'agi', 'int', 'all'][i] === state.attr)));
}

function wireSearch() {
  const q = $<HTMLInputElement>('q');
  q.addEventListener('input', () => refreshGrid());
  q.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const best = refreshGrid();
      if (best != null) pick(best);
    } else if (e.key === 'Escape') {
      q.value = '';
      refreshGrid();
    } else if (e.key === 'Backspace' && !q.value) {
      // empty search + backspace = undo the last filled slot
      const order: Team[] = ['enemy', 'ally', 'ban'];
      for (const t of [state.active?.team ?? 'enemy', ...order]) {
        const i = state[t].map((x) => x != null).lastIndexOf(true);
        if (i >= 0) { state[t][i] = null; state.active = { team: t, i }; update(); break; }
      }
    }
  });
  // start typing anywhere → search box
  addEventListener('keydown', (e) => {
    const tag = (e.target as HTMLElement).tagName;
    if (tag === 'INPUT' || tag === 'SELECT' || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key.length === 1 && /[a-z0-9']/i.test(e.key)) q.focus({ preventScroll: true });
  });
}

function footer() {
  const d = new Date(data.updated);
  $('foot').innerHTML = `
    Based on <b>${data.matches.toLocaleString()}</b> ranked public matches from the ${data.days} days up to
    ${d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })} (via <a href="https://www.opendota.com" target="_blank" rel="noopener">OpenDota</a>).
    Draft score = hero's win rate edge + matchup advantage vs each enemy (vs. what their win rates predict) + 0.6 × synergy with allies + a small bonus for missing roles.
    All in win-rate points; matchups are additive estimates, not a guarantee. Dota 2 is a trademark of Valve.`;
}

async function init() {
  // three.js is ~450 kB — load it after first paint so the picker is usable immediately
  const loadBg = () => import('./bg').then((m) => m.startBackground($<HTMLCanvasElement>('bg')));
  if ('requestIdleCallback' in window) requestIdleCallback(loadBg, { timeout: 1500 });
  else setTimeout(loadBg, 300);
  try {
    data = await (await fetch('/data.json')).json();
  } catch {
    $('picks').innerHTML = '<li class="empty">Couldn’t load hero data. Refresh to try again.</li>';
    return;
  }
  model = new Model(data, 'all');
  readHash();
  model = new Model(data, state.bracket);
  state.active = nextEmpty();
  renderGrid($('heroGrid'), [...data.heroes] as Hero[], pick);
  buildControls();
  wireSearch();
  footer();

  $('reset').addEventListener('click', () => {
    state.ally.fill(null); state.enemy.fill(null); state.ban.fill(null); state.you = null;
    state.active = { team: 'enemy', i: 0 };
    update();
    toast('Draft cleared');
  });
  $('share').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(location.href); toast('Link copied'); }
    catch { toast('Copy the address bar to share'); }
  });

  update();
  if (!reduced) {
    gsap.from('.panel', { y: 18, opacity: 0, duration: 0.6, stagger: 0.07, ease: 'power3.out', clearProps: 'transform,opacity' });
    gsap.from('.brand', { x: -12, opacity: 0, duration: 0.6, ease: 'power3.out', clearProps: 'transform,opacity' });
  }
}

init();
