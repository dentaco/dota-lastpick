# Launch status — Last Pick for Dota 2

**Stage:** config → TestFlight (submission held: one new app in review at a time on this account)
**Developer account:** Alex Znamenskiy, Individual (team ZBALKH9DFV), Alex = Account Holder. Personal app, not a client app.
**Bundle ID:** com.dentaco.lastpick    **ASC App ID:** (record not created yet)    **Current version/build:** 1.0 (1)
**Payments model:** none — free, no IAP, no ads.

Native SwiftUI (XcodeGen, iOS 17+), not a web wrapper: the account has 4.2.2 / 4.3 history from Capacitor shells.

## Blocked on Alex
- [ ] Create the App Store Connect record (API can't: POST /v1/apps is 403) — appstoreconnect.apple.com → Apps → + New App → iOS · Name **Last Pick for Dota 2** · English (U.S.) · Bundle ID **com.dentaco.lastpick** · SKU **lastpick** · Full access. Blocks: upload, listing, TestFlight.
- [ ] App Privacy questionnaire (web UI only): "No, we do not collect data" → Publish. Blocks: submission.
- [ ] Say go for Submit for Review — only after Hirostar Growth 1.0 (new app, in review since 10-13) gets its verdict. Blocks: release.

## Pre-flight
- [x] bundle ID final   - [x] build number bumped by `scripts/ios-release.sh`   - [x] supportsTablet: iPhone-only (TARGETED_DEVICE_FAMILY 1, checked in release script)
- [x] encryption flag (ITSAppUsesNonExemptEncryption NO)   - [x] purpose strings: none needed (no permissions)   - [x] privacy manifest (UserDefaults CA92.1, no collection)
- [x] icon 1024 opaque (`tools/make_icon.swift`)   - [x] APNs: not used   - [x] Xcode 26.5 / iOS 26 SDK

## Review traps
- [x] completeness (no placeholders; offline data bundled)   - [x] demo account: none needed (no accounts)   - [x] account deletion: n/a
- [x] login services: n/a   - [x] payments: none   - [x] privacy policy live + "Data Not Collected" matches code
- [x] UGC: none   - [x] metadata clean (no Android/beta; "Dota 2" only in name "for Dota 2" + description with Valve disclaimer; not in keywords)
- [x] 4.2 minimum functionality: native app, offline engine, 4 tabs   - [x] 4.3 answers in review-notes.txt
- [ ] 5.2.1 risk (Valve IP): portraits/names are Valve content, declared "uses third-party content", disclaimers in app + listing. If Apple asks for authorization, answer with Valve's fan-content stance / swap portraits for text-only tiles.

## Listing
- [x] name/subtitle/keywords  - [x] description  - [x] screenshots (5 × 6.9")  - [x] URLs (/support, /privacy live)  - [x] age rating 4+ (pushed by script)

## Scripts
- `node scripts/asc-provision.mjs` — bundle id + "Last Pick App Store" profile (done 2026-10-19)
- `scripts/ios-release.sh [--no-upload]` — tests, archive, bundle checks (iPhone-only, privacy manifest, data + portraits, no debug demo code, no secrets), export, upload
- `scripts/app-store-screenshots.sh` — 6.9" screenshots via DEBUG-only launch hooks (LASTPICK_DEMO*, LASTPICK_TAB)
- `node scripts/asc-listing.mjs` — pushes listing, review notes, screenshots, Free price, non-EU availability, attaches newest VALID build

## Smoke test (TestFlight build)
1. Launch offline (airplane mode): Draft shows suggestions from bundled data.
2. Tap enemy slot 1 → type "pa" → Return: Phantom Assassin fills slot, picker moves to slot 2. Fill 5 enemies + 4 allies.
3. Tap top suggestion → breakdown → Lock in → YOU slot shows hero; tap YOU to clear.
4. Remove an enemy (tap slot → Remove): "They might pick next" + "Ban suggestions" appear.
5. Position 2 + Rank Ancient+: list changes, only mid heroes.
6. Meta tab: tiers; tap a hero → matchups; Add to pool → Draft "Only my hero pool" toggle appears.
7. More → Check for new data (online): "Up to date" / "Updated".
8. Kill + relaunch: draft is restored.

## Log
- 2026-10-19: Native app built (engine port + enemy next-pick odds, ban suggestions, meta tiers, hero matchups, hero pool, offline data with 6-hourly refresh). 12 XCTests + 7 vitest pass. Signed IPA builds. Bundle id + profile registered. Web: privacy/support pages + enemy reads deployed. Next: ASC record → upload b2 → listing → hold for Hirostar Growth verdict → submit.
