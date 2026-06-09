#!/usr/bin/env bash
# Deploy hermes-jarvis to Fly.io.
#
# Usage:
#   cp .env.example .env && $EDITOR .env
#   fly secrets import < .env        # or: fly secrets set KEY=VAL ...
#   bash deploy.sh
#
# Idempotent — safe to re-run.

set -euo pipefail

APP_NAME="${FLY_APP_NAME:-hermes-jarvis}"
ORG="${FLY_ORG:-elicify-devpods}"
REGION="${FLY_REGION:-iad}"

echo "==> Deploying ${APP_NAME} to Fly (region: ${REGION}, org: ${ORG})"

# Create the app on first run. fly launch --no-deploy writes fly.toml
# side-effects; since we already have fly.toml, we just `apps create`
# if it doesn't exist.
if ! fly apps list --json 2>/dev/null | grep -q "\"${APP_NAME}\""; then
    echo "==> Creating Fly app ${APP_NAME}"
    fly apps create "${APP_NAME}" --org "${ORG}"
fi

# Create the persistent volume if it doesn't exist.
if ! fly volumes list --app "${APP_NAME}" --json 2>/dev/null | grep -q '"Name":"hermes_data"'; then
    echo "==> Creating volume hermes_data (1 GB)"
    fly volumes create hermes_data --app "${APP_NAME}" --size 1 --region "${REGION}"
fi

# Deploy. Uses remote builders because this devpod has no local
# Docker daemon.
echo "==> Building and deploying"
fly deploy --app "${APP_NAME}" --remote-only --strategy rolling

echo "==> Done. Opening app..."
fly open --app "${APP_NAME}"

echo
echo "Your Hermes Agent pod is live at:"
echo "  https://${APP_NAME}.fly.dev"
echo
echo "Tail logs with: fly logs --app ${APP_NAME}"
echo "Set secrets with: fly secrets set KEY=VAL --app ${APP_NAME}"
