#!/usr/bin/env bash
# Deploy the ViGenAiR engine (service/) for AdLens Video Variants.
#
#   adlens/deploy.sh dev      # → vigenair-adlens-dev on gs://adlens-vigenair-dev
#   adlens/deploy.sh prod     # → vigenair-adlens     on gs://adlens-vigenair-prod (asks to confirm)
#
# Only service/ is deployed (no Apps Script UI). Config comes from service/.env.yaml.
# The deployed git commit is stored as a label so you can always tell what is running:
#   gcloud functions describe vigenair-adlens-dev --gen2 --region=europe-west1 --project=adlens-vigenair --format="value(labels)"
set -euo pipefail

ENV="${1:-}"
PROJECT="adlens-vigenair"
REGION="europe-west1"
case "$ENV" in
  dev)  FUNCTION="vigenair-adlens-dev"; BUCKET="adlens-vigenair-dev" ;;
  prod) FUNCTION="vigenair-adlens";     BUCKET="adlens-vigenair-prod" ;;
  *) echo "usage: $0 dev|prod" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain -- service)" ] && [ "${ALLOW_DIRTY:-}" != "1" ]; then
  echo "service/ has uncommitted changes — commit first (or ALLOW_DIRTY=1 to deploy anyway)." >&2
  exit 1
fi
SHA="$(git rev-parse --short=12 HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
grep -q "GCP_PROJECT_ID: '${PROJECT}'" service/.env.yaml || { echo "service/.env.yaml isn't set to ${PROJECT}" >&2; exit 1; }
grep -q "CONFIG_C2PA_REQUIRED: 'false'" service/.env.yaml || { echo "C2PA is required in .env.yaml — every render would fail without a certificate" >&2; exit 1; }

if [ "$ENV" = "prod" ] && [ "${YES:-}" != "1" ]; then
  read -r -p "Deploy ${BRANCH}@${SHA} to PROD (${FUNCTION})? [y/N] " a
  [ "$a" = "y" ] || exit 1
fi

if ! gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Creating bucket gs://${BUCKET} (private, files deleted after 30 days)…"
  gcloud storage buckets create "gs://${BUCKET}" --project="$PROJECT" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention
  tmp="$(mktemp)"; echo '{"rule":[{"action":{"type":"Delete"},"condition":{"age":30}}]}' > "$tmp"
  gcloud storage buckets update "gs://${BUCKET}" --lifecycle-file="$tmp"; rm -f "$tmp"
fi

echo "Deploying ${BRANCH}@${SHA} → ${FUNCTION} (${REGION}), bucket gs://${BUCKET} … (first build ~15 min, later ~5)"
cd service
gcloud functions deploy "$FUNCTION" \
  --project="$PROJECT" --gen2 --region="$REGION" --runtime=python310 --source=. \
  --entry-point=gcs_file_uploaded --env-vars-file=.env.yaml \
  --timeout=540s --memory=32Gi --cpu=8 \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=${BUCKET}" \
  --trigger-location="$REGION" \
  --update-labels="app=adlens,env=${ENV},git-sha=${SHA}"

echo "Done. State: $(gcloud functions describe "$FUNCTION" --project="$PROJECT" --gen2 --region="$REGION" --format='value(state)')"
echo "Next: run the smoke test (docs/05-vigenair-backend-guide.md §2.5 or ABCD-backend scripts/vigenair_smoke.py)."
