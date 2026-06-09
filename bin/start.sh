#!/usr/bin/env bash
# Hermes Agent pod entrypoint.
#
# Starts:
#   1. `hermes gateway`  — the OpenAI-compatible API on :8642
#   2. `hermes dashboard` — the v0.16.0 web admin UI on :9119
#   3. caddy             — reverse proxy on :8080 (public)
#
# All three are supervised by `tini` (PID 1) so signals are forwarded
# cleanly. If any child dies, tini kills the rest and the container
# exits, letting Fly / the devpod restart it.

set -euo pipefail

echo "[start.sh] HERMES_HOME=${HERMES_HOME:-/opt/data}"
echo "[start.sh] API_SERVER_HOST=${API_SERVER_HOST:-127.0.0.1}"
echo "[start.sh] API_SERVER_PORT=${API_SERVER_PORT:-8642}"
echo "[start.sh] HERMES_DASHBOARD_HOST=${HERMES_DASHBOARD_HOST:-127.0.0.1}"
echo "[start.sh] HERMES_DASHBOARD_PORT=${HERMES_DASHBOARD_PORT:-9119}"
echo "[start.sh] PORT=${PORT:-8080}"

# The persistent volume is owned by root on first mount. The `hermes`
# user (uid 10000 in the upstream image) needs write access to HERMES_HOME
# for config, sessions, skills, memory, logs, and credentials. Chown
# once at startup — it's a no-op on subsequent boots because the volume
# preserves the ownership.
if [ "$(id -u)" = "0" ]; then
    mkdir -p "${HERMES_HOME:-/opt/data}"
    chown -R 10000:10000 "${HERMES_HOME:-/opt/data}" 2>/dev/null || true
fi

# Make sure the hermes CLI is on PATH.
export PATH="/opt/hermes:${PATH}"

# If first run and no config exists, run non-interactive setup. The
# gateway will start with whatever it can; the user can add a real
# LLM API key later via the dashboard.
if [ ! -f "${HERMES_HOME:-/opt/data}/config.yaml" ] && [ -z "${HERMES_SKIP_CONFIG_MIGRATION:-}" ]; then
    echo "[start.sh] No config.yaml yet — running hermes setup (non-interactive)"
    gosu 10000 hermes setup --non-interactive 2>/dev/null || \
        gosu 10000 hermes setup --non-interactive 2>/dev/null || true
fi

# Start the gateway in the background. It exposes the OpenAI-compatible
# API on :8642 and (with HERMES_DASHBOARD=1) embeds the dashboard
# plugin — but we run the standalone `hermes dashboard` below for the
# richer web admin UI shipped in v0.16.0.
echo "[start.sh] starting hermes gateway..."
gosu 10000 hermes gateway &
GATEWAY_PID=$!

# Give the gateway a moment to bind.
sleep 2

# Start the standalone web admin dashboard on :9119.
echo "[start.sh] starting hermes dashboard on ${HERMES_DASHBOARD_HOST:-0.0.0.0}:${HERMES_DASHBOARD_PORT:-9119}..."
gosu 10000 hermes dashboard --host "${HERMES_DASHBOARD_HOST:-0.0.0.0}" --port "${HERMES_DASHBOARD_PORT:-9119}" &
DASHBOARD_PID=$!

# Trap signals so we clean up children on shutdown.
cleanup() {
    echo "[start.sh] shutting down..."
    kill -TERM "$GATEWAY_PID" 2>/dev/null || true
    kill -TERM "$DASHBOARD_PID" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# Caddy in the foreground — this is the process tini supervises. When
# caddy exits, everything else goes with it.
echo "[start.sh] starting caddy reverse proxy on :${PORT:-8080}..."
# Run caddy as the hermes user too, so its autosave + cert cache live
# inside the writable volume.
exec gosu 10000 caddy run --config /etc/caddy/Caddyfile --adapter ""
