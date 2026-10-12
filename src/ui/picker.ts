import type { Hero } from '../engine';
import { ALIASES } from '../aliases';

export const portrait = (h: Hero) => `https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/${h.slug}.png`;

export const ATTR_COLOR: Record<string, string> = { str: 'var(--str)', agi: 'var(--agi)', int: 'var(--int)', all: 'var(--all)' };

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

/** Match quality for a query (higher is better, 0 = no match). Handles aliases, prefixes, word starts and initials. */
export function matchScore(h: Hero, raw: string): number {
  const q = norm(raw);
  if (!q) return 1;
  const name = norm(h.name);
  const words = h.name.toLowerCase().split(/[\s'-]+/).filter(Boolean);
  const initials = words.map((w) => w[0]).join('');
  if (ALIASES[q] === h.id) return 100;
  if (name === q) return 95;
  if (name.startsWith(q)) return 80;
  if (initials === q) return 75;
  if (words.some((w) => norm(w).startsWith(q))) return 60;
  if (norm(h.slug).includes(q)) return 40;
  if (name.includes(q)) return 30;
  return 0;
}

export function renderGrid(el: HTMLElement, heroes: Hero[], onPick: (id: number) => void) {
  el.innerHTML = '';
  const frag = document.createDocumentFragment();
  for (const h of heroes) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'hero';
    b.dataset.id = String(h.id);
    b.setAttribute('role', 'option');
    b.setAttribute('aria-label', h.name);
    b.style.setProperty('--c', ATTR_COLOR[h.attr]);
    b.innerHTML = `<img loading="lazy" decoding="async" alt="" src="${portrait(h)}" width="128" height="72"><span>${h.name}</span>`;
    b.addEventListener('click', () => onPick(h.id));
    frag.appendChild(b);
  }
  el.appendChild(frag);
}

/** Filter/sort the grid in place; returns the best match id (for Enter). */
export function filterGrid(el: HTMLElement, heroes: Map<number, Hero>, q: string, attr: string | null, taken: Set<number>) {
  const items = [...el.querySelectorAll<HTMLButtonElement>('.hero')];
  const scored = items.map((b) => {
    const h = heroes.get(Number(b.dataset.id))!;
    const s = (!attr || h.attr === attr) ? matchScore(h, q) : 0;
    return { b, h, s };
  });
  // with a query, best matches float to the top; otherwise keep the alphabetical order
  if (q.trim()) scored.sort((x, y) => y.s - x.s || x.h.name.localeCompare(y.h.name));
  else scored.sort((x, y) => x.h.name.localeCompare(y.h.name));
  let best: number | null = null;
  for (const { b, h, s } of scored) {
    const isTaken = taken.has(h.id);
    b.classList.toggle('dim', s === 0);
    b.classList.toggle('taken', isTaken);
    b.classList.remove('first');
    b.tabIndex = isTaken ? -1 : 0;
    if (best === null && s > 0 && !isTaken && q.trim()) {
      best = h.id;
      b.classList.add('first');
    }
    el.appendChild(b);
  }
  return best;
}
