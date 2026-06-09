#!/usr/bin/env bash
# OpenClaw pod entrypoint.
#
# Starts:
#   1. `openclaw gateway` — the gateway + control UI on :18789
#   2. caddy               — reverse proxy on :8080 (public)
#
# Both are supervised by tini (PID 1). If either dies, tini kills
# the rest and the container exits, letting Fly / the devpod restart it.

set -euo pipefail

echo "[start.sh] OPENCLAW_HOME=${OPENCLAW_HOME:-/data}"
echo "[start.sh] OPENCLAW_GATEWAY_HOST=${OPENCLAW_GATEWAY_HOST:-127.0.0.1}"
echo "[start.sh] OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT:-18789}"
echo "[start.sh] PORT=${PORT:-8080}"

# The persistent volume is owned by root on first mount. OpenClaw's
# upstream image runs as the `node` user (uid 1000), which needs
# write access for config, sessions, skills, logs, and workspace.
# Chown once at startup — it's a no-op on subsequent boots because
# the volume preserves the ownership. We do it for the WHOLE tree
# (not just .openclaw) because the gateway creates things like
# /data/.openclaw/devices/pending.json that the CLI may have touched
# as root before the chown.
mkdir -p "${OPENCLAW_HOME:-/data}"
if [ "$(id -u)" = "0" ]; then
    chown -R 1000:1000 "${OPENCLAW_HOME:-/data}" 2>/dev/null || true
fi

# OpenClaw looks for config at $OPENCLAW_HOME/.openclaw/openclaw.json
# (i.e. /data/.openclaw/openclaw.json when OPENCLAW_HOME=/data).
mkdir -p "${OPENCLAW_HOME:-/data}/.openclaw"
chown -R 1000:1000 "${OPENCLAW_HOME:-/data}/.openclaw" 2>/dev/null || true

# Bake an openclaw.json that selects MiniMax as the primary provider
# (using the Anthropic-compatible endpoint exposed by MiniMax) and
# OpenRouter as the fallback. Env-var substitution in values is
# supported by OpenClaw, so the actual keys stay in Fly secrets
# (read by the process) — they never appear in this file.
OC_CONFIG="${OPENCLAW_HOME:-/data}/.openclaw/openclaw.json"
# Always (re)write the config on boot. This is a single-tenant
# pod with a single provider stack, so we treat the file as
# code: any change to start.sh's config template takes effect on
# the next deploy. (We don't merge with user-edited fields; for
# a multi-tenant setup we'd write only when the file is missing
# and let the user edit from there.)
echo "[start.sh] writing MiniMax (primary) + OpenRouter (fallback) config to ${OC_CONFIG}"
cat > "${OC_CONFIG}" <<'JSON5'
{
  // Required by `openclaw gateway run` — skips the interactive
  // "first-run" setup wizard. Also pin the public Fly origin to
  // the control-UI allowlist so the dashboard's WebSocket isn't
  // rejected with "Browser origin not allowed".
  gateway: {
    mode: "local",
    controlUi: {
      allowedOrigins: [
        "http://localhost:18789",
        "http://127.0.0.1:18789",
        "https://openclaw-jarvis.fly.dev",
      ],
    },
  },

  // MiniMax — Anthropic-compatible endpoint. Default model is
  // MiniMax-M3 (the "3.0" generation). Provider is added to the
  // built-in catalog; OpenRouter remains a built-in provider and is
  // reached via its own OPENROUTER_API_KEY env var.
  models: {
    mode: "merge",
    providers: {
      minimax: {
        baseUrl: "${MINIMAX_BASE_URL}",
        apiKey:  "${MINIMAX_API_KEY}",
        api:     "anthropic-messages",
        models: [
          {
            id:           "MiniMax-M3",
            name:         "MiniMax-M3 (MiniMax)",
            reasoning:    false,
            input:        ["text", "image"],
            contextWindow: 200000,
            maxTokens:    8192,
            cost:         { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          },
        ],
      },
    },
  },

  // Default agent: MiniMax-M3 primary, OpenRouter (Claude) fallback.
  agents: {
    defaults: {
      model: {
        primary:   "minimax/MiniMax-M3",
        // Built-in OpenRouter provider; just needs OPENROUTER_API_KEY
        // in the env (Fly secret). Falls back here if MiniMax errors.
        fallbacks: [
          "openrouter/anthropic/claude-3.5-sonnet",
        ],
      },
      models: {
        "minimax/MiniMax-M3":                       { alias: "MiniMax (default)" },
        "openrouter/anthropic/claude-3.5-sonnet":   { alias: "OpenRouter fallback" },
      },
    },
  },
}
JSON5
chown 1000:1000 "${OC_CONFIG}" 2>/dev/null || true

# Start the OpenClaw gateway in the background. It serves both the
# WebSocket API and the control UI on the configured port.
# `--bind lan` makes it listen on 0.0.0.0 (Fly proxy reaches us via
# the machine's private IP). `--auth token` with OPENCLAW_API_KEY
# (set as a Fly secret) gates the WebSocket.
echo "[start.sh] starting openclaw gateway on port ${OPENCLAW_GATEWAY_PORT:-18789}..."
gosu 1000 openclaw gateway run \
    --bind lan \
    --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
    --auth token \
    --token "${OPENCLAW_API_KEY:-}" \
    --force \
    &
GATEWAY_PID=$!

# Give the gateway a moment to bind.
sleep 3

# Trap signals so we clean up on shutdown.
cleanup() {
    echo "[start.sh] shutting down..."
    kill -TERM "$GATEWAY_PID" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# Caddy in the foreground — this is the process tini supervises. When
# caddy exits, everything else goes with it.
echo "[start.sh] starting caddy reverse proxy on :${PORT:-8080}..."
exec gosu 1000 caddy run --config /etc/caddy/Caddyfile --adapter ""
