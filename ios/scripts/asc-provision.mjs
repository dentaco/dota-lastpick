// One-time App Store Connect provisioning for Last Pick: registers com.dentaco.lastpick (no extra
// capabilities) and creates the "Last Pick App Store" distribution profile with the team's ASC API key.
//
//   node scripts/asc-provision.mjs
//
// Idempotent: re-running reuses what already exists.

import crypto from "crypto";
import fs from "fs";
import os from "os";
import path from "path";

const KEY_ID = "86VY69CXCB";
const ISSUER = "1a17aac3-131a-4085-9f1f-8e8023cb043c";
const KEY_PATH = path.join(os.homedir(), ".appstoreconnect/private_keys", `AuthKey_${KEY_ID}.p8`);
const BUNDLE_ID = "com.dentaco.lastpick";
const PROFILE_NAME = "Last Pick App Store";

function jwt() {
  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: ISSUER, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" };
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const signingInput = `${b64(header)}.${b64(payload)}`;
  const key = fs.readFileSync(KEY_PATH, "utf8");
  const sig = crypto.sign("sha256", Buffer.from(signingInput), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${sig.toString("base64url")}`;
}

const TOKEN = jwt();
const API = "https://api.appstoreconnect.apple.com/v1";

async function asc(method, pathname, body) {
  const res = await fetch(`${API}${pathname}`, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = res.status === 204 ? {} : await res.json();
  if (!res.ok) {
    throw new Error(`${method} ${pathname} -> ${res.status}: ${JSON.stringify(json.errors ?? json)}`);
  }
  return json;
}

// Distribution certificate .
const certs = (await asc("GET", "/certificates?filter[certificateType]=DISTRIBUTION")).data;
if (certs.length === 0) throw new Error("no distribution certificate on the account");
const cert = certs[0];
console.log("using distribution cert:", cert.id, cert.attributes.name);

const TARGETS = [
  { identifier: BUNDLE_ID, name: "Last Pick", profile: PROFILE_NAME, caps: [] },
];

for (const t of TARGETS) {
  // 1. Bundle id (reuse if present).
  let bundle = (await asc("GET", `/bundleIds?filter[identifier]=${t.identifier}`)).data.find(
    (b) => b.attributes.identifier === t.identifier
  );
  if (!bundle) {
    bundle = (
      await asc("POST", "/bundleIds", {
        data: { type: "bundleIds", attributes: { identifier: t.identifier, name: t.name, platform: "IOS" } },
      })
    ).data;
    console.log(`registered bundle id ${t.identifier}:`, bundle.id);
  } else {
    console.log(`bundle id exists ${t.identifier}:`, bundle.id);
  }

  // 2. Capabilities (a profile created before a capability existed won't carry it — retire it).
  const caps = (await asc("GET", `/bundleIds/${bundle.id}/bundleIdCapabilities`)).data;
  for (const cap of t.caps) {
    if (caps.some((c) => c.attributes.capabilityType === cap)) continue;
    await asc("POST", "/bundleIdCapabilities", {
      data: {
        type: "bundleIdCapabilities",
        attributes: { capabilityType: cap },
        relationships: { bundleId: { data: { type: "bundleIds", id: bundle.id } } },
      },
    });
    console.log(`enabled capability ${cap} on ${t.identifier}`);
    for (const p of (await asc("GET", `/profiles?filter[name]=${encodeURIComponent(t.profile)}`)).data) {
      await asc("DELETE", `/profiles/${p.id}`);
      console.log("deleted stale profile:", p.id);
    }
  }

  // 3. App Store provisioning profile (recreate if an active one is missing).
  let profile = (await asc("GET", `/profiles?filter[name]=${encodeURIComponent(t.profile)}`)).data.find(
    (p) => p.attributes.name === t.profile && p.attributes.profileState === "ACTIVE"
  );
  if (!profile) {
    profile = (
      await asc("POST", "/profiles", {
        data: {
          type: "profiles",
          attributes: { name: t.profile, profileType: "IOS_APP_STORE" },
          relationships: {
            bundleId: { data: { type: "bundleIds", id: bundle.id } },
            certificates: { data: [{ type: "certificates", id: cert.id }] },
          },
        },
      })
    ).data;
    console.log(`created profile "${t.profile}":`, profile.id);
  } else {
    console.log(`profile exists "${t.profile}":`, profile.id);
  }

  // 4. Install the profile locally so xcodebuild can find it.
  const content = Buffer.from(profile.attributes.profileContent, "base64");
  const uuidMatch = content.toString("latin1").match(/<key>UUID<\/key>\s*<string>([-A-F0-9a-f]+)<\/string>/);
  const uuid = uuidMatch ? uuidMatch[1] : profile.id;
  for (const dir of ["Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"]) {
    const dest = path.join(os.homedir(), dir);
    fs.mkdirSync(dest, { recursive: true });
    fs.writeFileSync(path.join(dest, `${uuid}.mobileprovision`), content);
  }
  console.log(`installed profile "${t.profile}":`, uuid);
}

// 5. Report whether the App Store Connect app record exists yet.
const apps = (await asc("GET", `/apps?filter[bundleId]=${BUNDLE_ID}`)).data;
console.log(
  apps.length > 0
    ? `app record exists: ${apps[0].id} (${apps[0].attributes.name})`
    : "NO app record yet — create it once at appstoreconnect.apple.com (New App → iOS, name Last Pick for Dota 2, bundle com.dentaco.lastpick, SKU lastpick). POST /v1/apps is not allowed by the API."
);
