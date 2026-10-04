# پرونده (The Case)

A daily crime-mystery game in Persian. Every night at 9 pm (Tehran time) a new criminal case opens for the whole country:
1. Read the case.
2. Study the evidence (CCTV, documents, forensics, phone records).
3. Question the suspects.
4. Accuse the culprit **and** pick the one piece of evidence that proves their lie.

| Folder | What |
|---|---|
| `server/` | FastAPI server: accounts, server-side coin wallet, daily case schedule, hints, accusations, leaderboards, Bazaar purchases, inbox, invites, admin |
| `server/app/content/cases/` | The 50 case files (JSON). Add a file to add a case. Solutions never leave the server. |
| `server/tools/` | `casekit.py` + `cases_src/` (cases written compactly, `build_cases.py` turns them into JSON) and `smoke_test.py` (checks a running server) |
| `app/` | Flutter client: 20 animated scenes, procedural sound (`app/tools/make_sounds.py`) |
| `demo/` | The first clickable HTML demo |

## Deploy (Liara)

`liara.json` and `Dockerfile` at the top of the repo build only `server/`. The server listens on port 3000.

Set these in Liara (app `thecase`), under Environment variables:
```
ENV=dev                      # prod once real Bazaar payments are in the app
DATABASE_URL=<your Liara PostgreSQL URL>
JWT_SECRET=<long random string>
ADMIN_API_KEY=<another long random string>
AUTO_CREATE_TABLES=false
BAZAAR_MODE=fake             # api_secret + BAZAAR_API_SECRET for real payments
BAZAAR_PACKAGE_NAME=ir.aminsalem.the_case
```
To check that it's running, open `https://thecase.liara.run/health`. It shows how many cases are loaded.

## Run the server locally

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt      # Iran: add  -i https://package-mirror.liara.ir/repository/pypi/simple/
cp .env.example .env
pytest
uvicorn app.main:app --reload --host 0.0.0.0
```

## The cases

50 cases, one opens every night at 21:00 (c001 on 29 Sep 2026 ... c050 on 17 Nov 2026). 34 are difficulty 4, five are
difficulty 5. Every new case (c007+) has five suspects, eight or nine pieces of evidence, decoys that look guilty but
are cleared by a detail, and exactly one suspect whose own words are broken by the evidence. Mechanisms vary: sensor and
card logs, a clock that is wrong, a time zone, a forged stamp, a weekday, a candle that burned for 50 minutes, a
"only one of five told the truth" logic puzzle, and an arrival-order puzzle for the finale.
`pytest` plays all 50 through the real API (right and wrong accusations).

## Sound

Every case scene has its own mystery bed (`amb_<scene>.ogg`, a seamless 10 s loop) and a case-opening sting
(`sting_<scene>.ogg`). There are also interface sounds. All of it is synthesised, so there are no licences:
`python3 app/tools/make_sounds.py` (needs numpy and ffmpeg) rewrites `app/assets/sounds/`. The speaker button on the
home screen and in a case mutes everything.

## Check that the server works

```bash
cd server
python tools/smoke_test.py https://thecase.liara.run            # the live server
python tools/smoke_test.py http://127.0.0.1:8000 --solve        # a local one, also solves today's case
```
It lists every call the app makes with the status and time, and ends with a pass/fail count.

## Writing a new case

Easiest: copy a case in `server/tools/cases_src/`, edit it, run `python tools/build_cases.py`. Or copy a JSON file in
`server/app/content/cases/` and change the following:
* `id` and `number`: must be new
* `publish`: the day the case opens at 21:00 Tehran time
* `suspects`: 3–6, each with an `avatar` that the app draws
* `evidence`
* `hints`: exactly 3
* `solution`: `culprit` is a suspect id; `proof` lists the evidence ids that prove the lie

The server checks every case file when it starts. A broken file stops the deploy, so check the log if a deploy fails.

## Admin

Every admin call needs the header `X-Admin-Key: <ADMIN_API_KEY>`.

| Call | What it does |
|---|---|
| `GET /admin/stats` | Players, today's case, purchases |
| `GET /admin/cases` | Per case: opened, solved, average stars (to tune difficulty) |
| `POST /admin/gifts` | Gift for one player or for everyone: `{"title":"...","grants":[{"type":"coins","amount":200}]}` |
| `PUT /admin/config` | Shop price labels, forced update, maintenance mode |
