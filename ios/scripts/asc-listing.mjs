// Push the Last Pick App Store listing (docs/app-store/listing.md + review-notes.txt + screenshots) into App Store Connect.
//   node scripts/asc-listing.mjs
// Idempotent. Web UI only: App Privacy questionnaire ("Data Not Collected") and Submit (only after Alex says go).
import fs from "fs"; import path from "path"; import crypto from "crypto";
import { asc, appId } from "./asc-client.mjs";
const APP_ID = await appId();

const listing = fs.readFileSync("docs/app-store/listing.md", "utf8");
const blocks = [...listing.matchAll(/```\n([\s\S]*?)\n```/g)].map(m => m[1].trim());
const [KEYWORDS, PROMO, DESCRIPTION] = blocks;
const SUBTITLE = "Counter picks, bans & meta";
const SITE = "https://dota-last-pick.vercel.app";
const SUPPORT = `${SITE}/support`, MARKETING = SITE, PRIVACY = `${SITE}/privacy`;
const NOTES = fs.readFileSync("docs/app-store/review-notes.txt", "utf8").trim();
for (const [k, v, max] of [["subtitle", SUBTITLE, 30], ["keywords", KEYWORDS, 100], ["promo", PROMO, 170], ["description", DESCRIPTION, 4000], ["notes", NOTES, 4000]])
  if (!v || v.length > max) throw new Error(`${k} missing or over ${max} (${v?.length})`);

const vers = (await asc("GET", `/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS`)).data;
const ver = vers.find(v => v.attributes.appStoreState === "PREPARE_FOR_SUBMISSION") ?? vers[0];
const infos = (await asc("GET", `/apps/${APP_ID}/appInfos`)).data;
const info = infos.find(i => i.attributes.appStoreState === "PREPARE_FOR_SUBMISSION") ?? infos[0];
console.log("version", ver.attributes.versionString, ver.id, "| appInfo", info.id);

// 1. Subtitle + privacy URL
const il = (await asc("GET", `/appInfos/${info.id}/appInfoLocalizations`)).data.find(l => l.attributes.locale === "en-US");
await asc("PATCH", `/appInfoLocalizations/${il.id}`, { data: { type: "appInfoLocalizations", id: il.id, attributes: { subtitle: SUBTITLE, privacyPolicyUrl: PRIVACY } } });
console.log("✓ subtitle + privacy URL");

// 2. Categories
await asc("PATCH", `/appInfos/${info.id}`, { data: { type: "appInfos", id: info.id, relationships: {
  primaryCategory: { data: { type: "appCategories", id: "REFERENCE" } },
  secondaryCategory: { data: { type: "appCategories", id: "ENTERTAINMENT" } } } } });
console.log("✓ categories Reference / Entertainment");

// 3. Age rating: hero portraits only, no UGC, no chat, no web access → 4+
const ar = (await asc("GET", `/appInfos/${info.id}/ageRatingDeclaration`)).data;
const none = {};
for (const k of ["alcoholTobaccoOrDrugUseOrReferences","contests","gamblingSimulated","horrorOrFearThemes","matureOrSuggestiveThemes","medicalOrTreatmentInformation","profanityOrCrudeHumor","sexualContentGraphicAndNudity","sexualContentOrNudity","violenceCartoonOrFantasy","violenceRealistic","violenceRealisticProlongedGraphicOrSadistic","gunsOrOtherWeapons"]) none[k] = "NONE";
await asc("PATCH", `/ageRatingDeclarations/${ar.id}`, { data: { type: "ageRatingDeclarations", id: ar.id, attributes: { ...none, gambling: false, unrestrictedWebAccess: false, lootBox: false, advertising: false, messagingAndChat: false, userGeneratedContent: false, parentalControls: false, ageAssurance: false, healthOrWellnessTopics: false } } }).catch(async e => {
  console.log("  full age-rating set rejected, retrying minimal:", e.message.slice(0, 200));
  await asc("PATCH", `/ageRatingDeclarations/${ar.id}`, { data: { type: "ageRatingDeclarations", id: ar.id, attributes: { ...none, gambling: false, unrestrictedWebAccess: false } } });
});
console.log("✓ age rating");

// 4. Description, keywords, promo, URLs
const vl = (await asc("GET", `/appStoreVersions/${ver.id}/appStoreVersionLocalizations`)).data.find(l => l.attributes.locale === "en-US");
await asc("PATCH", `/appStoreVersionLocalizations/${vl.id}`, { data: { type: "appStoreVersionLocalizations", id: vl.id, attributes: {
  description: DESCRIPTION, keywords: KEYWORDS, promotionalText: PROMO, supportUrl: SUPPORT, marketingUrl: MARKETING } } });
console.log("✓ description / keywords / promo / URLs");

// 5. Copyright (personal app — never the company), manual release
await asc("PATCH", `/appStoreVersions/${ver.id}`, { data: { type: "appStoreVersions", id: ver.id, attributes: { copyright: "2026 Alex Znamenskiy", releaseType: "MANUAL" } } });
console.log("✓ copyright + manual release");

// 6. Content rights: Valve hero names/portraits + OpenDota statistics (explained in the review notes)
await asc("PATCH", `/apps/${APP_ID}`, { data: { type: "apps", id: APP_ID, attributes: { contentRightsDeclaration: "USES_THIRD_PARTY_CONTENT" } } });
console.log("✓ content rights");

// 7. Review contact + notes (notes only once the placeholder is gone)
let rd = (await asc("GET", `/appStoreVersions/${ver.id}/appStoreReviewDetail`).catch(() => ({ data: null }))).data;
const rdAttrs = { contactFirstName: "Alex", contactLastName: "Znamenskiy", contactPhone: "+971525300996", contactEmail: "dentaco.alex@gmail.com", demoAccountRequired: false };
rdAttrs.notes = NOTES;
if (rd) await asc("PATCH", `/appStoreReviewDetails/${rd.id}`, { data: { type: "appStoreReviewDetails", id: rd.id, attributes: rdAttrs } });
else await asc("POST", `/appStoreReviewDetails`, { data: { type: "appStoreReviewDetails", attributes: rdAttrs, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: ver.id } } } } });
console.log("✓ review contact");

// 8. Screenshots (6.9", 1320×2868 → APP_IPHONE_67 set)
const DIR = "docs/app-store/screenshots";
const SHOTS = fs.readdirSync(DIR).filter(f => f.endsWith(".png")).sort();
let set = (await asc("GET", `/appStoreVersionLocalizations/${vl.id}/appScreenshotSets`)).data.find(s => s.attributes.screenshotDisplayType === "APP_IPHONE_67");
if (!set) set = (await asc("POST", `/appScreenshotSets`, { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: "APP_IPHONE_67" }, relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: vl.id } } } } })).data;
const have = new Set((await asc("GET", `/appScreenshotSets/${set.id}/appScreenshots`)).data.map(s => s.attributes.fileName));
for (const name of SHOTS) {
  if (have.has(name)) { console.log("  = already uploaded", name); continue; }
  const buf = fs.readFileSync(path.join(DIR, name));
  const res = (await asc("POST", `/appScreenshots`, { data: { type: "appScreenshots", attributes: { fileName: name, fileSize: buf.length }, relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set.id } } } } })).data;
  for (const op of res.attributes.uploadOperations) {
    const headers = Object.fromEntries(op.requestHeaders.map(h => [h.name, h.value]));
    for (let i = 0; ; i++) { // Apple's object storage flakes — retry
      const r = await fetch(op.url, { method: op.method, headers, body: buf.subarray(op.offset, op.offset + op.length) }).catch(e => ({ ok: false, status: e.message }));
      if (r.ok) break;
      if (i === 4) throw new Error(`upload ${name} -> ${r.status}`);
      await new Promise(r => setTimeout(r, 2000 * (i + 1)));
    }
  }
  await asc("PATCH", `/appScreenshots/${res.id}`, { data: { type: "appScreenshots", id: res.id, attributes: { uploaded: true, sourceFileChecksum: crypto.createHash("md5").update(buf).digest("hex") } } });
  console.log("  ↑ uploaded", name);
}
console.log("✓ screenshots");

// 9. Price: Free (base territory USA)
const sched = await asc("GET", `/apps/${APP_ID}/appPriceSchedule`).catch(() => null);
const hasPrice = sched && (await asc("GET", `/appPriceSchedules/${sched.data.id}/manualPrices`).catch(() => ({ data: [] }))).data.length > 0;
if (!hasPrice) {
  const free = (await asc("GET", `/apps/${APP_ID}/appPricePoints?filter[territory]=USA&limit=200`)).data.find(p => Number(p.attributes.customerPrice) === 0);
  await asc("POST", `/appPriceSchedules`, { data: { type: "appPriceSchedules", relationships: {
      app: { data: { type: "apps", id: APP_ID } }, baseTerritory: { data: { type: "territories", id: "USA" } },
      manualPrices: { data: [{ type: "appPrices", id: "${p0}" }] } } },
    included: [{ type: "appPrices", id: "${p0}", attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: "appPricePoints", id: free.id } } } }] });
}
console.log("✓ price Free");

// 10. Availability: every territory except the EU (no DSA trader status → can't be sold there)
const EU = new Set(["AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA","DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD","POL","PRT","ROU","SVK","SVN","ESP","SWE"]);
const all = (await asc("GET", `/territories?limit=200`)).data.map(t => t.id);
const terrs = all.filter(t => !EU.has(t));
const avail = await asc("GET", `/apps/${APP_ID}/appAvailabilityV2`).catch(() => null);
if (!avail) {
  await asc("POST", `/../v2/appAvailabilities`, { data: { type: "appAvailabilities", attributes: { availableInNewTerritories: false },
      relationships: { app: { data: { type: "apps", id: APP_ID } }, territoryAvailabilities: { data: all.map(t => ({ type: "territoryAvailabilities", id: `\${${t}}` })) } } },
    included: all.map(t => ({ type: "territoryAvailabilities", id: `\${${t}}`, attributes: { available: !EU.has(t) }, relationships: { territory: { data: { type: "territories", id: t } } } })) });
}
console.log(`✓ availability: ${terrs.length} territories (EU excluded)`);

// 11. Attach the newest VALID build
const build = (await asc("GET", `/builds?filter[app]=${APP_ID}&filter[processingState]=VALID&sort=-uploadedDate&limit=1`)).data[0];
if (build) { await asc("PATCH", `/appStoreVersions/${ver.id}/relationships/build`, { data: { type: "builds", id: build.id } }); console.log("✓ build", build.attributes.version, "attached"); }
else console.log("  ! no VALID build yet (still processing?)");
console.log("\nLeft for the web UI: App Privacy → Data Not Collected. Submit only after Alex says go (one new app in review at a time).");
