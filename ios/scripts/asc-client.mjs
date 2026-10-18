// Shared App Store Connect client for the Last Pick release scripts. The app id is looked up from the bundle id.
import crypto from "crypto"; import fs from "fs"; import os from "os"; import path from "path";
const KEY_ID = "86VY69CXCB", ISSUER = "1a17aac3-131a-4085-9f1f-8e8023cb043c";
export const BUNDLE_ID = "com.dentaco.lastpick";
export function token() {
  const key = fs.readFileSync(path.join(os.homedir(), ".appstoreconnect/private_keys", `AuthKey_${KEY_ID}.p8`), "utf8");
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const inp = `${b64({ alg: "ES256", kid: KEY_ID, typ: "JWT" })}.${b64({ iss: ISSUER, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" })}`;
  return `${inp}.${crypto.sign("sha256", Buffer.from(inp), { key, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}
const TOK = token();
export async function asc(method, p, body) {
  const r = await fetch("https://api.appstoreconnect.apple.com/v1" + p, {
    method, headers: { Authorization: `Bearer ${TOK}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = r.status === 204 ? {} : await r.json();
  if (!r.ok) throw new Error(`${method} ${p} -> ${r.status}: ${JSON.stringify(j.errors ?? j)}`);
  return j;
}
export async function appId() {
  const apps = (await asc("GET", `/apps?filter[bundleId]=${BUNDLE_ID}`)).data;
  if (!apps.length) throw new Error(`no App Store Connect record for ${BUNDLE_ID} yet — create it in the web UI (New App, SKU lastpick)`);
  return apps[0].id;
}
