import type { Model, Pick } from '../engine';
import { positionsOf } from '../engine';
import { portrait } from './picker';

const fmt = (v: number) => `${v >= 0 ? '+' : '−'}${Math.abs(v).toFixed(1)}`;
const LOW_DATA = 1500; // total head-to-head games under this → flag as low confidence

export interface ResultHandlers {
  onLock(id: number): void;
  onHide(id: number): void;
}

function bar(v: number, max: number) {
  const w = Math.min(Math.abs(v) / max, 1) * 50;
  const color = v >= 0 ? 'var(--ally)' : 'var(--enemy)';
  return `<span class="bar"><i style="${v >= 0 ? `left:50%` : `right:50%`};width:${w}%;background:${color}"></i></span>`;
}

function card(m: Model, p: Pick, i: number, h: ResultHandlers, opts: { actions: boolean }) {
  const li = document.createElement('li');
  li.className = 'pick';
  li.dataset.id = String(p.hero.id);
  const name = (id: number) => m.byId.get(id)!;
  const vsSorted = [...p.vs].sort((a, b) => b.value - a.value);
  const good = vsSorted.filter((l) => l.value >= 0.8).slice(0, 3);
  const bad = vsSorted.filter((l) => l.value <= -0.8).reverse().slice(0, 2);
  const games = p.vs.reduce((s, l) => s + l.games, 0);
  const low = p.vs.length > 0 && games / p.vs.length < LOW_DATA / 5;
  const chip = (id: number, v: number, cls: string) =>
    `<span class="chip ${cls}" title="${name(id).name} ${fmt(v)}%"><img alt="" src="${portrait(name(id))}">${fmt(v)}</span>`;

  const why = [
    ...good.map((l) => chip(l.hero, l.value, 'good')),
    ...bad.map((l) => chip(l.hero, l.value, 'bad')),
    ...(p.synergy >= 0.8 ? [`<span class="chip note">synergy ${fmt(p.synergy)}</span>`] : []),
    ...p.roleNotes.map((n) => `<span class="chip note">${n}</span>`),
  ].join('');

  const max = Math.max(4, ...p.vs.map((l) => Math.abs(l.value)), ...p.with.map((l) => Math.abs(l.value)));
  const rows = [
    `<tr><td>Hero win rate (${(m.winRate(p.hero.id) * 100).toFixed(1)}%)</td><td>${bar(p.base, max)}</td><td>${fmt(p.base)}</td></tr>`,
    ...p.vs.map((l) => `<tr><td>vs ${name(l.hero).name} <small>(${l.games.toLocaleString()} games)</small></td><td>${bar(l.value, max)}</td><td>${fmt(l.value)}</td></tr>`),
    ...p.with.map((l) => `<tr><td>with ${name(l.hero).name} <small>(×0.6)</small></td><td>${bar(l.value * 0.6, max)}</td><td>${fmt(l.value * 0.6)}</td></tr>`),
    ...(p.roles ? [`<tr><td>Fills a missing role</td><td>${bar(p.roles, max)}</td><td>${fmt(p.roles)}</td></tr>`] : []),
  ].join('');

  li.innerHTML = `
    <span class="rank">${i + 1}</span>
    <img class="pic" alt="" src="${portrait(p.hero)}" width="128" height="72">
    <div class="pmain">
      <div class="pname">${p.hero.name}${positionsOf(p.hero.id).map((x) => `<span class="pos">P${x}</span>`).join('')}${low ? '<span class="lowdata" title="Few recent games for these matchups">low data</span>' : ''}</div>
      <div class="why">${why || '<span>No standout matchups — pick on comfort.</span>'}</div>
    </div>
    <div class="score"><b class="${p.total >= 0 ? 'pos-v' : 'neg-v'}">${fmt(p.total)}</b><small>draft score</small></div>
    ${opts.actions ? `<div class="pick-actions">
      <button class="mini" data-act="detail" type="button">Why?</button>
      <button class="mini" data-act="hide" type="button" title="Hide — not in my hero pool">Hide</button>
      <button class="mini lock" data-act="lock" type="button">Lock in</button>
    </div>` : ''}
    <div class="detail"><table>${rows}</table></div>`;
  li.addEventListener('click', (e) => {
    const act = (e.target as HTMLElement).closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'lock') h.onLock(p.hero.id);
    else if (act === 'hide') h.onHide(p.hero.id);
    else li.classList.toggle('expand-open');
  });
  return li;
}

export function renderPicks(el: HTMLElement, m: Model, picks: Pick[], h: ResultHandlers, opts = { actions: true }) {
  el.innerHTML = '';
  picks.forEach((p, i) => el.appendChild(card(m, p, i, h, opts)));
}
