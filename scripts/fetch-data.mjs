// Builds public/data.json from OpenDota: hero list + pairwise vs/with stats from recent public matches.
// Usage: node scripts/fetch-data.mjs [days=3]
import { writeFileSync } from 'node:fs';

const API = 'https://api.opendota.com/api';
const DAYS = Number(process.argv[2] || 3);
const CHUNK = 400_000; // match_id range per explorer query (keeps each query well under the timeout)
const MODES = '(1,2,3,4,16,22)'; // AP, CM, RD, SD, CD, ranked AP — no turbo / all random
// bracket from avg_rank_tier: 0 = Herald–Crusader, 1 = Archon–Legend, 2 = Ancient+
const BR = `CASE WHEN avg_rank_tier >= 60 THEN 2 WHEN avg_rank_tier >= 40 THEN 1 ELSE 0 END`;

const UA = 'Mozilla/5.0 (compatible; dota-lastpick/1.0; +https://github.com/dentaco/dota-lastpick)';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function get(url, tries = 5) {
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } });
      const body = await res.json();
      if (res.ok && !body.err) return body;
      console.warn(`  retry ${i + 1}: ${res.status} ${body.err || ''}`);
    } catch (e) {
      console.warn(`  retry ${i + 1}: ${e.message}`);
    }
    await sleep(3000 * (i + 1));
  }
  throw new Error(`failed: ${url.slice(0, 160)}`);
}

const sql = (q) => get(`${API}/explorer?sql=${encodeURIComponent(q)}`);

const vsSql = (lo, hi) => `
SELECT ${BR} br, least(r,d) a, greatest(r,d) b, count(*) g,
  sum(CASE WHEN (r < d) = radiant_win THEN 1 ELSE 0 END) w
FROM public_matches, unnest(radiant_team) r, unnest(dire_team) d
WHERE match_id > ${lo} AND match_id <= ${hi} AND radiant_team[1] <> 0 AND dire_team[1] <> 0
  AND avg_rank_tier IS NOT NULL AND game_mode IN ${MODES}
GROUP BY 1,2,3`;

const withSql = (lo, hi) => `
SELECT br, a, b, count(*) g, sum(win) w FROM (
  SELECT ${BR} br, x a, y b, radiant_win::int win
  FROM public_matches, unnest(radiant_team) x, unnest(radiant_team) y
  WHERE match_id > ${lo} AND match_id <= ${hi} AND x < y AND radiant_team[1] <> 0
    AND avg_rank_tier IS NOT NULL AND game_mode IN ${MODES}
  UNION ALL
  SELECT ${BR} br, x a, y b, (NOT radiant_win)::int win
  FROM public_matches, unnest(dire_team) x, unnest(dire_team) y
  WHERE match_id > ${lo} AND match_id <= ${hi} AND x < y AND dire_team[1] <> 0
    AND avg_rank_tier IS NOT NULL AND game_mode IN ${MODES}
) t GROUP BY 1,2,3`;

const stats = await get(`${API}/heroStats`);
const heroes = stats
  .map((h) => ({
    id: h.id,
    name: h.localized_name,
    slug: h.name.replace('npc_dota_hero_', ''),
    attr: h.primary_attr,
    melee: h.attack_type === 'Melee',
    roles: h.roles,
  }))
  .sort((a, b) => a.name.localeCompare(b.name));
const ids = new Set(heroes.map((h) => h.id));
console.log(`${heroes.length} heroes`);

const { rows: [{ m: maxId }] } = await sql('SELECT max(match_id) m FROM public_matches');
const { rows: [{ t: maxT }] } = await sql(`SELECT max(start_time) t FROM public_matches WHERE match_id > ${maxId - 50000}`);
const cutoff = maxT - DAYS * 86400;

// pair key -> [g,w] per bracket
const vs = new Map();
const wi = new Map();
let matches = 0;
let hi = maxId;
let oldest = maxT;
while (oldest > cutoff) {
  const lo = hi - CHUNK;
  const [v, w, t] = await Promise.all([
    sql(vsSql(lo, hi)),
    sql(withSql(lo, hi)),
    sql(`SELECT min(start_time) t FROM public_matches WHERE match_id > ${lo} AND match_id <= ${lo + 2000}`),
  ]);
  let pairs = 0;
  for (const [rows, map] of [[v.rows, vs], [w.rows, wi]]) {
    for (const r of rows) {
      if (!ids.has(r.a) || !ids.has(r.b)) continue;
      const k = `${r.a}-${r.b}`;
      const cur = map.get(k) || [0, 0, 0, 0, 0, 0];
      cur[r.br * 2] += Number(r.g);
      cur[r.br * 2 + 1] += Number(r.w);
      map.set(k, cur);
      if (map === vs) pairs += Number(r.g);
    }
  }
  matches += pairs / 25;
  oldest = t.rows[0].t ?? oldest - 3600;
  console.log(`  ${lo}..${hi}: ${Math.round(pairs / 25)} matches, back to ${new Date(oldest * 1000).toISOString()}`);
  hi = lo;
  await sleep(1000);
}

const pack = (map) => Object.fromEntries([...map].map(([k, v]) => [k, v]));
const out = {
  updated: new Date(maxT * 1000).toISOString(),
  days: DAYS,
  matches: Math.round(matches),
  brackets: ['Herald–Crusader', 'Archon–Legend', 'Ancient+'],
  heroes,
  vs: pack(vs), // "a-b" (a<b): [g0,wA0,g1,wA1,g2,wA2] — wins for hero a
  with: pack(wi), // "a-b" (a<b): [g0,w0,...] — wins when a and b are on the same team
};
writeFileSync(new URL('../public/data.json', import.meta.url), JSON.stringify(out));
console.log(`wrote data.json: ${out.matches} matches, ${vs.size} vs pairs, ${wi.size} with pairs`);
