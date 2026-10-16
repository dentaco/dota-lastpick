# dota-lastpick


## Security: fail-closed (2026-10-16)
- Static site: no server routes, no database, nothing private. Forms only compose a WhatsApp / mailto message in the browser (user text is escaped before any innerHTML and URL-encoded into the link).
- Security headers (HSTS, nosniff, frame-ancestors none, referrer policy) live in the hosting config.
- Run `node scripts/security-verify.mjs` before and after each deploy: dotfiles must 403/404 and the pages + JS bundles must contain no secret-looking strings. If a server route is ever added, it must fail closed and get a probe in that script.
