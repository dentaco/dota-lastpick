# Last Pick for Dota 2 — App Store Connect listing (v1.0)

Pushed by `node scripts/asc-listing.mjs` (reads the fenced blocks below in order: keywords, promo, description).

## App information
| Field | Value |
|---|---|
| Name (≤30) | **Last Pick for Dota 2** (20) — the "for Dota 2" compatibility form many store apps use; Dota 2 stays out of the keywords |
| Subtitle (≤30) | **Counter picks, bans & meta** |
| Bundle ID / SKU | com.dentaco.lastpick / lastpick |
| Primary language | English (U.S.) |
| Categories | Reference / Entertainment |
| Content rights | **Uses third-party content**: hero portraits and names are Valve's Dota 2 game content (fan use, free app, no ads, credited); match statistics from OpenDota's public data (credited in-app) |
| Copyright | **2026 Alex Znamenskiy** (personal app) |
| Price | Free, no in-app purchases |
| Availability | All territories except the EU (no DSA trader status) |
| Release | Manual |

## URLs
| Support | https://dota-last-pick.vercel.app/support |
|---|---|
| Marketing | https://dota-last-pick.vercel.app |
| Privacy | https://dota-last-pick.vercel.app/privacy |

## Keywords (≤100)
```
counter,draft,hero,counterpick,ban,meta,tier,moba,matchup,winrate,carry,support,mid,ranked,stats
```

## Promotional text (≤170)
```
Enter both drafts and get the best last pick in seconds, with the reasons behind it. Rebuilt every day from about two million recent ranked matches.
```

## Description (≤4000)
```
Last Pick tells you which hero to pick into the enemy draft, and shows you exactly why.

BEST LAST PICK
• Tap or type the heroes on both teams. Shorthand like pa, sf, am or wr works, and the picker jumps to the next empty slot by itself
• Get the ten best picks for your draft, scored in win-rate points: the hero's own strength, its matchup against every enemy, its synergy with your allies, and a bonus when it fills a role your team is missing
• Tap any suggestion for the full breakdown, matchup by matchup, with the number of games behind each one
• Filter by the position you play (1 to 5) and your rank bracket
• See the worst picks into the draft too, so you know what to avoid

READ THE ENEMY
• They might pick next: the heroes the enemy is most likely to take, from how popular each hero is at your rank and how well it fits their draft against yours
• Ban suggestions: the heroes that would hurt your team the most

META AND HEROES
• Tier list (S to D) of every hero by win rate and pick rate, for each position and rank bracket
• Any hero's page shows who counters it, who it beats, and its best teammates

YOUR HERO POOL
Star the heroes you actually play and turn on "Only my hero pool". Hide the ones you never pick.

FRESH, HONEST DATA
Statistics are rebuilt every day from about two million ranked public matches from the last three days, split into three rank brackets. Pairs with few games are pulled toward zero, so a lucky streak can't top the list. Everything works offline with the latest copy.

No account, no ads, no tracking.

Match data from OpenDota. Dota 2 is a trademark of Valve Corporation. Last Pick is an independent fan-made tool and is not affiliated with or endorsed by Valve.
```

## Age rating
None/No to everything (no violence shown, just hero portraits; no UGC, chat, web access, ads, gambling) → **4+**. Made for Kids: No.

## App Privacy
**Data Not Collected.** No accounts, analytics, ads or SDKs. The only network calls: public data.json from dota-last-pick.vercel.app (no identifiers) and, only for heroes newer than the build, portraits from Valve's Steam CDN.

## Export compliance
`ITSAppUsesNonExemptEncryption = NO` (HTTPS only).

## Screenshots (6.9", 1320 × 2868) — `docs/app-store/screenshots/`, made by `scripts/app-store-screenshots.sh`
1. 01-draft — full draft + best last picks
2. 02-why — breakdown of the top pick
3. 03-they-might-pick — enemy next-pick odds + ban suggestions
4. 04-meta — tier list
5. 05-hero-matchups — hero page: countered by
iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), no iPad set.
