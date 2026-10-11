# Working rules for this repo

## Liara deploy budget (important)
Every push to `main` starts a Liara deployment, and Liara refuses deployments after a daily maximum
(error «Max deployment count in day», 11 Oct 2026, after about 20 pushes in a day). A refused deployment leaves
the server on the OLD version, so the newest code is not live.

- Work on a branch (CI runs on branches too). Push to `main` ONCE per task, when CI on the branch is green.
- Never push to `main` for docs, CHANGELOG, workflow-only or test-only changes alone: put them in the same push as
  real work, or leave them for the next one.
- Do not push repeatedly to fix CI on `main`; fix on the branch first.
- `git push -f origin main:release` builds the APK and does NOT deploy the server; it does not count.
- If a run sees the deployment error, stop pushing to `main` for that day and tell Amin.
