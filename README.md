# پرونده (The Case)

A daily crime-mystery game in Persian. Every night at 9 pm (Tehran time) a new criminal case opens for the whole country:
1. Read the case.
2. Study the evidence (CCTV, documents, forensics, phone records).
3. Question the suspects.
4. Accuse the culprit **and** pick the one piece of evidence that proves their lie.

| Folder | What |
|---|---|
| `server/` | FastAPI server: accounts, server-side coin wallet, daily case schedule, hints, accusations, leaderboards, Bazaar purchases, inbox, invites, admin |
| `server/app/content/cases/` | The case files (JSON). Add a file to add a case. Solutions never leave the server. |
| `app/` | Flutter client |
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

## Writing a new case

Copy a file in `server/app/content/cases/` and change the following:
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
