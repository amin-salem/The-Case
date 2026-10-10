# Health watch (spec, built by the hardening run)

Extend `.github/workflows/uptime.yml` (every 30 min; GitHub runners are the only place that can reach Liara and gammly.ir).
Alert = a failed run (GitHub emails/pushes Amin). Add an optional Telegram message if secrets TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID exist.

Checks:
1. Both addresses (gammly.ir, thecase.liara.run): DNS resolves, HTTPS ok, TLS certificate days left (fail at < 14, warn at < 30).
2. `/health/deep` (new, server): DB query ok, content loads (cases, weekly, story), today's case exists, a weekend case has all 3 chapters, SMS provider balance if configured. Never reveals secrets.
3. Liara (only if LIARA_API_TOKEN set): wallet balance vs LIARA_MIN_BALANCE, plan/payment expiry < 7 days.
4. `/v1/config`: valid JSON, maintenance flag readable.
5. Domain expiry: keep the 8 Sep 2027 reminder; add a WHOIS/RDAP check if reachable.
6. One daily "all green" summary run (e.g. 08:00 Tehran) so silence never means "broken".

Server: maintenance switch in remote config (app shows a calm «به‌زودی برمی‌گردیم» screen); SMS provider failure falls back to email sign-in.
Document each alert and what to do in docs/operations.md.
