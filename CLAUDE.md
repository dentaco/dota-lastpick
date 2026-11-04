# dota-lastpick


## Security: fail-closed (2026-10-16)
- Static site: no server routes, no database, nothing private. Forms only compose a WhatsApp / mailto message in the browser (user text is escaped before any innerHTML and URL-encoded into the link).
- Security headers (HSTS, nosniff, frame-ancestors none, referrer policy) live in the hosting config.
- Run `node scripts/security-verify.mjs` before and after each deploy: dotfiles must 403/404 and the pages + JS bundles must contain no secret-looking strings. If a server route is ever added, it must fail closed and get a probe in that script.

## iOS app (`ios/`, added 2026-10-19)
- Native SwiftUI + XcodeGen, bundle com.dentaco.lastpick. Launch board: `ios/LAUNCH.md` (read first).
- Engine is a Swift port of `src/engine.ts` (+ predictEnemy/banThreats, mirrored in TS). Change both together; `ios/Sources/Model/Positions.swift` is generated from `src/positions.ts` + `src/aliases.ts`.
- The app ships `public/data.json` (copied at build) and refreshes from https://dota-last-pick.vercel.app/data.json — keep that URL and the JSON shape stable, old app builds depend on it.
- New hero from Valve: add it to positions.ts/aliases.ts, regenerate Positions.swift, add `ios/LastPick/Resources/Portraits/<slug>.jpg` (256×144); older builds fall back to Valve's CDN.

## Cloudflare (since 2026-11-04, branch `cloudflare`)
- Worker `dota-lastpick` (static assets only) → https://dota-lastpick.dentaco.workers.dev. Deploy: `npm run build && npx wrangler deploy`. Headers live in `public/_headers` (was vercel.json).
- The daily data Action deploys after committing once repo secrets CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID exist.
- iOS still points at dota-last-pick.vercel.app (AppModel.remoteURL, MoreView, DraftView, ASC listing): needs a new build + listing URLs once a stable domain is chosen.
