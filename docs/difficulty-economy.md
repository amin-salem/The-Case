# Difficulty economy, version 1

Server policy only; the proposed numbers were assessed for this branch, not selected
explicitly by the owner. Difficulty must be an integer 1..5; missing/invalid values
(including booleans/strings) use level 3. Content loading still validates its own schema.

| Difficulty | Nightly/archive unlock | Base 1 plaque | Base 2 plaques | Base 3 plaques | Expired weekend unlock | Live weekend 1 | Live weekend 2 | Live weekend 3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 100 | 6 | 12 | 20 | 170 | 72 | 120 | 200 |
| 2 | 120 | 8 | 16 | 25 | 200 | 96 | 160 | 250 |
| 3 | 150 | 10 | 20 | 30 | 250 | 120 | 200 | 300 |
| 4 | 180 | 12 | 24 | 36 | 300 | 144 | 240 | 360 |
| 5 | 220 | 15 | 30 | 45 | 370 | 180 | 300 | 450 |

Stars remain a separate factor. Nightly, ordinary archive, story and expired-weekend
completion use the normal base reward (as before, story has no nightly daily bonus).
Only a currently live weekend uses the higher weekend base. The expired-weekend
purchase premium remains; its prices round the normal difficulty ratios upward to
ten coins against the old 250 baseline. Difficulty 3 retains every old mode baseline.

Daily bonus +15, streak milestone +60 and live-weekend early bonus +80 are added
after the base, once, under their existing eligibility rules. Login/ad/invite/grants,
night-1 liar rewards, XP, ranks, hints, story warrants/skips, attempt limits and free
access to tonight's/live-weekend case are unchanged. No historical balance/payment,
finished case, existing ownership or purchase grant is rewritten. Already-owned,
finished and VIP-accessible archive cases do not charge again.

## Content-weighted source/sink assessment

Latest main inspected: 9bab613ec9c6610d3d293e504405b5df65a0f4b9.
Its 50 nightly cases have difficulty counts [0, 2, 5, 39, 4]; the 6 weekend cases
have counts [0, 0, 1, 2, 3] for levels 1..5. Every JSON was read from that remote tree.
Assuming each written case is played equally (not a forecast of real user behavior):

- Nightly average 3-plaque base: 30 -> 35.68 (+18.93%); with the unchanged daily bonus,
  45 -> 50.68 (+12.62%). Average archive price: 150 -> 177.80 (+18.53%).
- Nightly 2/1-plaque base: 20/10 -> 23.76/11.88 (+18.8%).
- Live-weekend average 3/2/1-plaque base: 300/200/120 -> 395/263.33/158 (+31.67%).
  Expired-weekend price: 250 -> 326.67 (+30.67%); its normal 3-plaque solve base is 39.5.

The price/reward ratios stay close to their old baselines while harder cases cost
and pay more. This increases both coin sources and optional archive sinks; actual net
coin flow and purchase conversion depend on completion rates, stars, archive purchases
and existing balances. No user analytics were inferred from this content-only sample.

## Quote/API compatibility

Existing CaseRow.unlock_cost is the effective price. New optional base_solve_rewards
maps stars to base coins; clients label bonuses separately. Config includes
economy.difficulty_policy (full tables) and its legacy weekly_reward scalar reflects
the currently live weekend's effective 3-plaque base.

The new app confirms a quoted price and sends {"expected_cost": amount} to unlock.
If it changed, the server returns HTTP 409 {"error":"price_changed","cost":new_amount}
before any debit/progress mutation; the app asks again and never silently retries.
Insufficient-funds UI uses the server's need value. Old clients can still send no body
and pay the server's current price; they cannot guarantee re-confirmation of a stale
cached quote, so ship the updated app before relying on this consent protection.

## Integration dependency and review

This independent branch is based on main and does NOT duplicate fix/wallet-atomic.
It changes quote checks and amount calculation, keeping the existing add_coins call
sites so that the wallet branch's awaited atomic calls can merge at those same sites.
Production cross-worker guarantees require combining the wallet branch's player-row
locks, async atomic deltas, ledger and idempotency contract before deployment. Run the
combined server/Flutter and PostgreSQL concurrency suite after integration. Do not
deploy this feature alone on the known non-atomic main wallet.

Tests cover the entire table/fallback, normal/live/expired modes, bonuses added once,
free/VIP/owned access, old-client requests, insufficient funds, quote changes, sequential
repeat transactions, displayed-versus-debited amounts and UI confirmation/dismissal.
No production database, environment variable or schema migration is needed. Reverting
the feature affects future quotes/payments only; it does not recompute old transactions.
