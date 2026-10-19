# ViGenAiR for AdLens (AnalyticsLiv fork)

This fork runs Google's ViGenAiR engine (`service/`) as the processing backend of the
**Video Variants** module in AdLens. Only the engine is used — not the Apps Script UI.
Everything the UI did (uploads, polling, Gemini suggestions, `render.json`) lives in
`ABCD-backend/services/vigenair/`. Full design: `docs/05-vigenair-backend-guide.md` in the
AdLens workspace.

## What we changed vs upstream

Branch **`adlens`**, based on upstream `3d70141` (Sep 2026):

| Change | Why |
|---|---|
| `service/.env.yaml`: `GCP_PROJECT_ID=adlens-vigenair`, `GCP_LOCATION=europe-west1` | Dedicated project so ViGenAiR costs are billed separately |
| `service/.env.yaml`: `CONFIG_C2PA_ENABLED/REQUIRED='false'` | Upstream requires a C2PA certificate; without one every render fails |
| `adlens/` (this folder) | Deploy script, optional Cloud Build config, these notes |

No engine Python code is changed. Don't edit `service/` unless you must — it makes upstream
merges harder. Video handling AdLens needs (1080p downscale, credits, limits) is in the backend.

## Where it runs

| | Dev | Prod |
|---|---|---|
| Project / region | `adlens-vigenair` / `europe-west1` | same |
| Cloud Function | `vigenair-adlens-dev` | `vigenair-adlens` |
| Bucket (trigger) | `gs://adlens-vigenair-dev` | `gs://adlens-vigenair-prod` |
| Used by | local AdLens (`VIGENAIR_BUCKET=adlens-vigenair-dev`) | `abcd-backend` on Cloud Run |

## Deploy

```bash
git checkout adlens && git pull
adlens/deploy.sh dev      # then run the smoke test
adlens/deploy.sh prod     # asks for confirmation
```

The function's `git-sha` label shows which commit is running. On Windows Git Bash, if
`gcloud` says "Python was not found", first run:
`export CLOUDSDK_PYTHON="/c/Program Files (x86)/Google/Cloud SDK/google-cloud-sdk/platform/bundledpython/python.exe"`.

Automatic deploys: see `adlens/cloudbuild.yaml` (push to `adlens` → dev).

## Upgrade from Google

```bash
git fetch upstream
git checkout -b upgrade-$(date +%Y%m%d) adlens
git merge upstream/main            # keep our .env.yaml values on conflict
adlens/deploy.sh dev               # + smoke test + a full AdLens loop locally
```

Then check whether `ui/src/prompts.ts`, `ui/src/generation.ts` or the formats of
`data.json` / `render.json` / `combos.json` changed — if so, update
`ABCD-backend/services/vigenair/` (regenerate `prompts.py`). Merge into `adlens`, deploy prod.

## Smoke test

`ABCD-backend/scripts/vigenair_smoke.py` (needs `VIGENAIR_BUCKET` and signing credentials), or
the gcloud-only steps in the guide §2.5: upload `<name>--g--<ts>--test/input.mp4`, wait for
`data.json`, upload a `render.json` under `<ts>-combos/`, wait for `combos.json`.
