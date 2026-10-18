import { POSITIONS } from './positions';

// Last-pick scoring: hero's own win rate + summed matchup advantage vs each enemy + weighted synergy with allies
// + a small bonus for filling roles the team is missing. All terms are in win-rate percentage points.

export interface Hero {
  id: number;
  name: string;
  slug: string;
  attr: 'str' | 'agi' | 'int' | 'all';
  melee: boolean;
  roles: string[];
}

export interface Data {
  updated: string;
  days: number;
  matches: number;
  brackets: string[];
  heroes: Hero[];
  vs: Record<string, number[]>; // "a-b", a<b → [g,wA] × 3 brackets
  with: Record<string, number[]>; // "a-b", a<b → [g,w] × 3 brackets
}

export type Bracket = 'all' | 0 | 1 | 2;

export interface Draft {
  allies: number[];
  enemies: number[];
  bans: number[];
}

export interface Line {
  hero: number;
  value: number; // percentage points
  games: number;
}

export interface Pick {
  hero: Hero;
  total: number;
  base: number;
  counter: number;
  synergy: number;
  roles: number;
  vs: Line[];
  with: Line[];
  roleNotes: string[];
}

export const K = 150; // shrinkage prior: pairs with few games pull toward "no effect"
export const SYNERGY_WEIGHT = 0.6;

const pair = (a: number, b: number) => (a < b ? `${a}-${b}` : `${b}-${a}`);

function sumBr(arr: number[] | undefined, br: Bracket): [number, number] {
  if (!arr) return [0, 0];
  if (br === 'all') return [arr[0] + arr[2] + arr[4], arr[1] + arr[3] + arr[5]];
  return [arr[br * 2], arr[br * 2 + 1]];
}

export class Model {
  readonly byId = new Map<number, Hero>();
  private base = new Map<number, { g: number; wr: number }>();

  constructor(readonly data: Data, readonly bracket: Bracket = 'all') {
    for (const h of data.heroes) this.byId.set(h.id, h);
    // Each match yields 5 vs-pairs per hero, so pair totals / 5 = hero games/wins.
    const acc = new Map<number, [number, number]>();
    for (const [k, arr] of Object.entries(data.vs)) {
      const [a, b] = k.split('-').map(Number);
      const [g, w] = sumBr(arr, bracket);
      const A = acc.get(a) || [0, 0];
      const B = acc.get(b) || [0, 0];
      acc.set(a, [A[0] + g, A[1] + w]);
      acc.set(b, [B[0] + g, B[1] + (g - w)]);
    }
    for (const h of data.heroes) {
      const [g, w] = acc.get(h.id) || [0, 0];
      this.base.set(h.id, { g: g / 5, wr: g ? w / g : 0.5 });
    }
  }

  winRate(id: number) {
    return this.base.get(id)?.wr ?? 0.5;
  }

  games(id: number) {
    return this.base.get(id)?.g ?? 0;
  }

  /** Advantage of hero a vs hero b beyond what their base win rates predict (fraction, not %). */
  vs(a: number, b: number): Line {
    const [g, wLow] = sumBr(this.data.vs[pair(a, b)], this.bracket);
    const w = a < b ? wLow : g - wLow;
    const expected = 0.5 + this.winRate(a) - this.winRate(b);
    return { hero: b, value: (w - g * expected) / (g + K), games: g };
  }

  /** Extra win rate when a and b are on the same team, beyond their base win rates. */
  with(a: number, b: number): Line {
    const [g, w] = sumBr(this.data.with[pair(a, b)], this.bracket);
    const expected = this.winRate(a) + this.winRate(b) - 0.5;
    return { hero: b, value: (w - g * expected) / (g + K), games: g };
  }

  score(id: number, draft: Draft): Pick {
    const hero = this.byId.get(id)!;
    const vs = draft.enemies.map((e) => this.vs(id, e));
    const wi = draft.allies.map((a) => this.with(id, a));
    const { bonus, notes } = roleFit(hero, draft.allies.map((a) => this.byId.get(a)!).filter(Boolean));
    const base = (this.winRate(id) - 0.5) * 100;
    const counter = vs.reduce((s, l) => s + l.value, 0) * 100;
    const synergy = wi.reduce((s, l) => s + l.value, 0) * 100 * SYNERGY_WEIGHT;
    for (const l of [...vs, ...wi]) l.value *= 100;
    return {
      hero, base, counter, synergy, roles: bonus, vs, with: wi, roleNotes: notes,
      total: base + counter + synergy + bonus,
    };
  }

  rank(draft: Draft, opts: { position?: number; exclude?: Set<number> } = {}): Pick[] {
    const taken = new Set([...draft.allies, ...draft.enemies, ...draft.bans]);
    return this.data.heroes
      .filter((h) => !taken.has(h.id) && !opts.exclude?.has(h.id))
      .filter((h) => !opts.position || positionsOf(h.id).includes(opts.position))
      .map((h) => this.score(h.id, draft))
      .sort((a, b) => b.total - a.total);
  }
}

export const positionsOf = (id: number) => POSITIONS[id] ?? [1, 2, 3, 4, 5];

const NEEDS: { role: string; label: string; bonus: number; ifHeroPos?: (p: number[]) => boolean }[] = [
  { role: 'Disabler', label: 'adds the lockdown your team lacks', bonus: 0.5 },
  { role: 'Initiator', label: 'gives your team an initiator', bonus: 0.5 },
  { role: 'Durable', label: 'adds a frontliner', bonus: 0.4 },
  { role: 'Carry', label: 'gives your team a late-game carry', bonus: 0.6, ifHeroPos: (p) => p[0] <= 2 },
  { role: 'Support', label: 'your team has no support yet', bonus: 0.5, ifHeroPos: (p) => p[0] >= 4 },
];

/** Small bonus when the candidate fills a role none of the allies cover (only once 3+ allies are known). */
export function roleFit(hero: Hero, allies: Hero[]) {
  const notes: string[] = [];
  let bonus = 0;
  if (allies.length < 3) return { bonus, notes };
  const have = new Set(allies.flatMap((a) => a.roles));
  for (const n of NEEDS) {
    if (have.has(n.role) || !hero.roles.includes(n.role)) continue;
    if (n.ifHeroPos && !n.ifHeroPos(positionsOf(hero.id))) continue;
    bonus += n.bonus;
    notes.push(n.label);
  }
  return { bonus: Math.min(bonus, 1.5), notes };
}

export interface Prediction { pick: Pick; chance: number }
export interface Threat { pick: Pick; value: number }

const flip = (d: Draft): Draft => ({ allies: d.enemies, enemies: d.allies, bans: d.bans });

/** Total matches in this bracket (each match has 10 heroes). */
function matchesOf(m: Model) {
  return m.data.heroes.reduce((s, h) => s + m.games(h.id), 0) / 10;
}

export const pickRate = (m: Model, id: number) => {
  const total = matchesOf(m);
  return total ? m.games(id) / total : 0;
};

/** Enemy's likely next pick: log pick rate + 0.45 × how well the hero fits their draft vs yours, softmaxed over ALL available
 * heroes. `chance` is each hero's share of that whole field, so the returned top `limit` intentionally sums to less than 1. */
export function predictEnemy(m: Model, draft: Draft, limit = 6): Prediction[] {
  const theirs = flip(draft);
  const taken = new Set([...draft.allies, ...draft.enemies, ...draft.bans]);
  const total = matchesOf(m);
  const scored = m.data.heroes.filter((h) => !taken.has(h.id)).map((h) => {
    const p = m.score(h.id, theirs);
    return { p, logit: Math.log(Math.max(total ? m.games(h.id) / total : 0, 0.002)) + 0.45 * p.total };
  });
  if (!scored.length) return [];
  const top = Math.max(...scored.map((s) => s.logit));
  const z = scored.reduce((s, x) => s + Math.exp(x.logit - top), 0);
  return scored.sort((a, b) => b.logit - a.logit).slice(0, limit).map((s) => ({ pick: s.p, chance: Math.exp(s.logit - top) / z }));
}

/** Ban suggestions: own win-rate edge + matchups vs your heroes, nudged toward heroes people actually play. */
export function banThreats(m: Model, draft: Draft, limit = 5): Threat[] {
  const theirs = flip(draft);
  const taken = new Set([...draft.allies, ...draft.enemies, ...draft.bans]);
  const total = matchesOf(m);
  const mean = 10 / Math.max(m.data.heroes.length, 1);
  return m.data.heroes.filter((h) => !taken.has(h.id)).map((h) => {
    const p = m.score(h.id, theirs);
    const pop = Math.min(Math.max(Math.log(Math.max(total ? m.games(h.id) / total : 0, 0.002) / mean), -2), 2);
    return { pick: p, value: p.base + p.counter + 0.8 * pop };
  }).sort((a, b) => b.value - a.value).slice(0, limit);
}
