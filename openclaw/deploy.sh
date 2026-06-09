#!/usr/bin/env bash
# Deploy openclaw-jarvis to Fly.io.
#
# Usage (from the openclaw/ subdirectory):
#   fly secrets import < ../.env   # or: fly secrets set KEY=VAL
#   bash deploy.sh
#
# Idempotent — safe to re-run.

set -euo pipefail

APP_NAME="${FLY_APP_NAME:-openclaw-jarvis}"
ORG="${FLY_ORG:-elicify-devpods}"
REGION="${FLY_REGION:-iad}"

echo "==> Deploying ${APP_NAME} to Fly (region: ${REGION}, org: ${ORG})"

# Create the app on first run.
if ! fly apps list --json 2>/dev/null | grep -q "\"${APP_NAME}\""; then
    echo "==> Creating Fly app ${APP_NAME}"
    fly apps create "${APP_NAME}" --org "${ORG}"
fi

# Create the persistent volume if it doesn't exist.
if ! fly volumes list --app "${APP_NAME}" --json 2>/dev/null | grep -q '"Name":"openclaw_data"'; then
    echo "==> Creating volume openclaw_data (20 GB)"
    fly volumes create openclaw_data --app "${APP_NAME}" --size 20 --region "${REGION}"
fi

# Deploy from this directory.
echo "==> Building and deploying"
cd "$(dirname "$0")"
fly deploy --app "${APP_NAME}" --remote-only --strategy rolling

echo "==> Done. Opening app..."
fly open --app "${APP_NAME}"

echo
echo "Your OpenClaw pod is live at:"
echo "  https://${APP_NAME}.fly.dev"
echo
echo "Tail logs with: fly logs --app ${APP_NAME}"
echo "Set secrets with: fly secrets set KEY=VAL --app ${APP_NAME}"
