# Last Pick — Dota 2 counter picker

Enter your 4 allies and the 5 enemy heroes; get the best last pick to counter their draft.

- **Data:** ~2M ranked public matches from the last 3 days via the OpenDota explorer (`scripts/fetch-data.mjs`), split into three rank brackets. Refreshed daily by `.github/workflows/refresh-data.yml`.
- **Score** (win-rate points): hero's own edge over 50% + Σ matchup advantage vs each enemy (actual pair win rate minus what the two heroes' base win rates predict, shrunk toward 0 for small samples) + 0.6 × Σ synergy with allies + a small bonus for filling a missing role. See `src/engine.ts`.
- **UI:** keyboard-first (type `pa`, `sf`, `am`… + Enter), position filter, rank bracket, hide heroes you don't play, shareable URL.

```bash
npm i
npm run dev      # local
npm test         # engine tests
npm run data     # refetch public/data.json (~2 min)
```
