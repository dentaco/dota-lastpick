import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { Model, type Data, K } from './engine';

const data: Data = JSON.parse(readFileSync(new URL('../public/data.json', import.meta.url), 'utf8'));
const m = new Model(data);
const id = (name: string) => data.heroes.find((h) => h.name === name)!.id;

describe('engine', () => {
  it('base win rates are sane', () => {
    for (const h of data.heroes) {
      expect(m.winRate(h.id)).toBeGreaterThan(0.35);
      expect(m.winRate(h.id)).toBeLessThan(0.65);
    }
  });

  it('vs is antisymmetric', () => {
    const a = id('Anti-Mage'), b = id('Storm Spirit');
    const ab = m.vs(a, b), ba = m.vs(b, a);
    expect(ab.games).toBe(ba.games);
    expect(ab.value).toBeCloseTo(-ba.value, 6);
  });

  it('never suggests picked or banned heroes and respects position', () => {
    const draft = { allies: [id('Axe'), id('Lion')], enemies: [id('Pudge'), id('Sniper')], bans: [id('Invoker')] };
    const res = m.rank(draft, { position: 2 });
    const ids = res.map((p) => p.hero.id);
    for (const x of [...draft.allies, ...draft.enemies, ...draft.bans]) expect(ids).not.toContain(x);
    expect(res.some((p) => p.hero.name === 'Crystal Maiden')).toBe(false);
  });

  it('shrinks low-sample pairs toward zero', () => {
    const fake: Data = { ...data, vs: { '1-2': [10, 10, 0, 0, 0, 0] } };
    const fm = new Model(fake, 0);
    expect(Math.abs(fm.vs(1, 2).value)).toBeLessThan(10 / K);
  });

  it('known hard counters rank high', () => {
    // Anti-Mage's mana burn is a textbook counter to mana-reliant Medusa / Storm Spirit / OD.
    const draft = { allies: [], enemies: [id('Medusa'), id('Storm Spirit'), id('Outworld Devourer')], bans: [] };
    const top = m.rank(draft).slice(0, 25).map((p) => p.hero.name);
    expect(top).toContain('Anti-Mage');
  });
});
