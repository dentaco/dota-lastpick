// Internal TestFlight group "Internal" (all builds, auto-distributed) with Alex's tester Apple ID.
//   node scripts/asc-testflight.mjs
// Idempotent. Internal groups need no beta review and only accept people who are already App Store Connect users
// on the team (russkiytv@icloud.com is the Account Holder). Exits non-zero if the tester can't be added.
import { asc, appId } from "./asc-client.mjs";

const APP_ID = await appId();
const TESTER = "russkiytv@icloud.com";

let group = (await asc("GET", `/apps/${APP_ID}/betaGroups`)).data.find((g) => g.attributes.isInternalGroup);
if (!group) {
  group = (await asc("POST", "/betaGroups", { data: { type: "betaGroups",
    attributes: { name: "Internal", isInternalGroup: true, hasAccessToAllBuilds: true },
    relationships: { app: { data: { type: "apps", id: APP_ID } } } } })).data;
  console.log("✓ created internal group", group.id);
} else console.log("= internal group", group.id, group.attributes.name);

const existing = (await asc("GET", `/betaTesters?filter[email]=${encodeURIComponent(TESTER)}&filter[apps]=${APP_ID}`)).data;
if (existing.length) {
  console.log("= tester already on this app:", TESTER);
} else {
  await asc("POST", "/betaTesters", { data: { type: "betaTesters", attributes: { email: TESTER, firstName: "Alex", lastName: "Znamenskiy" },
    relationships: { betaGroups: { data: [{ type: "betaGroups", id: group.id }] } } } })
    .then(() => console.log("✓ invited", TESTER))
    .catch((e) => {
      console.error(`✗ couldn't add ${TESTER} to the internal group (must be an ASC user on the team): ${e.message.slice(0, 300)}`);
      process.exit(1);
    });
}
