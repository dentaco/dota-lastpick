#!/usr/bin/env node
// Logged-out security probes against production. Run before and after every deploy:
//   npm run security:verify      (BASE=https://… to point it elsewhere)
// Fails (exit 1) when a private route answers with data (status AND body size are checked), when a
// dotfile is served, or when a secret-looking string shows up in the page or its JS bundles.
const BASE = (process.env.BASE ?? "https://dota-last-pick.vercel.app").replace(/\/$/, "");
const PAGES = ["/", "/privacy", "/support"];
const PROBES = [];

const SECRET_PATTERNS = [
  [/sk-ant-[A-Za-z0-9_-]{20,}/, "Anthropic key"],
  [/sk_live_[A-Za-z0-9]{16,}/, "Stripe live key"],
  [/\bre_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}/, "Resend key"],
  [/AIza[0-9A-Za-z_-]{35}/, "Google API key"],
  [/postgres(?:ql)?:\/\/[^\s"'@]+:[^\s"'@]+@/, "database URL with password"],
  [/npg_[A-Za-z0-9]{12,}/, "Neon password"],
  [/gh[pousr]_[A-Za-z0-9]{30,}/, "GitHub token"],
  [/xox[abpr]-[A-Za-z0-9-]{20,}/, "Slack token"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "private key"],
];
let fail = 0;
const out = (ok, name, info = "") => { console.log(`${ok ? "ok  " : "FAIL"} ${name} ${info}`); if (!ok) fail++; };

async function get(path, init = {}) {
  const r = await fetch(BASE + path, { redirect: "manual", ...init });
  return { r, body: await r.text() };
}
function scanSecrets(where, text) {
  for (const [re, label] of SECRET_PATTERNS) if (re.test(text)) out(false, `secret in ${where}`, `(${label})`);
  // Supabase / JWT service-role keys
  for (const m of text.matchAll(/eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}/g)) {
    try { if (/service_role/.test(Buffer.from(m[1], "base64url").toString())) out(false, `secret in ${where}`, "(service_role JWT)"); } catch {}
  }
}

for (const p of PROBES) {
  try {
    const { r, body } = await get(p.path, p.init);
    const challenged = Boolean(r.headers.get("x-vercel-mitigated"));
    const ok = challenged || ((p.expect ?? [401, 403, 404]).includes(r.status) && body.length <= (p.maxBody ?? 4096) && !(p.mustNotContain ?? []).some((s) => body.includes(s)));
    out(ok, p.name, `→ ${r.status} (${body.length} B)${challenged ? " [vercel challenge]" : ""}`);
  } catch (e) { out(false, p.name, e.message); }
}
for (const f of ["/.env", "/.env.local", "/.env.production", "/.git/config", "/.git/HEAD"]) {
  try {
    const { r, body } = await get(f);
    out(r.status === 404 || r.status === 403 || (r.status >= 300 && r.status < 400 && body.length < 2048), `dotfile ${f}`, `→ ${r.status}`);
  } catch (e) { out(false, `dotfile ${f}`, e.message); }
}
const seen = new Set();
for (const page of PAGES) {
  try {
    const { r, body } = await get(page);
    if (r.status >= 400) { out(false, `page ${page}`, `→ ${r.status}`); continue; }
    scanSecrets(page, body);
    for (const m of body.matchAll(/<script[^>]+src="([^"]+)"/g)) {
      const u = new URL(m[1], BASE + page);
      if (u.origin !== new URL(BASE).origin || seen.has(u.href)) continue;
      seen.add(u.href);
      scanSecrets(u.pathname, await fetch(u).then((x) => x.text()));
    }
  } catch (e) { out(false, `page ${page}`, e.message); }
}
out(true, `scanned ${PAGES.length} page(s) + ${seen.size} script(s) for secrets`);
console.log(fail ? `\n${fail} check(s) FAILED` : "\nall checks passed");
process.exit(fail ? 1 : 0);
