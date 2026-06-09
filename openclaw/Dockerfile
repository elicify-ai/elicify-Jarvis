# syntax=docker/dockerfile:1.7
#
# OpenClaw by OpenClaw — runtime image for the Fly pod.
# https://docs.openclaw.ai
# https://github.com/openclaw/openclaw
# https://hub.docker.com/r/openclaw/openclaw
#
# The upstream image already bundles the Node-based gateway, the
# CLI, and the control UI. We layer on:
#   * caddy  — single-port reverse proxy (:8080) fronting the gateway
#              (:18789, which serves both the API and the control UI)
#   * tini   — clean PID 1 signal handling
#   * start.sh — runs `openclaw gateway` + caddy under tini, and
#              bakes the per-deploy openclaw.json with MiniMax as the
#              default provider and OpenRouter as the fallback.
#
# Pinned to the GitHub Container Registry (the official pre-built
# image, per docs.openclaw.ai/install/docker). The Docker Hub
# `openclaw/openclaw` namespace is empty — all official images live
# on ghcr.io. Re-built daily upstream.

FROM ghcr.io/openclaw/openclaw:latest

ENV DEBIAN_FRONTEND=noninteractive \
    # OpenClaw state directory inside the container. Fly mounts a
    # persistent volume here (see fly.toml).
    OPENCLAW_HOME=/data \
    # Bind the gateway to all interfaces — Fly's edge proxy and the
    # devpod preview proxy both reach us via the pod's private IP,
    # not loopback.
    OPENCLAW_GATEWAY_HOST=0.0.0.0 \
    OPENCLAW_GATEWAY_PORT=18789 \
    # Caddy listens here — Fly's edge proxy forwards 80/443 to 8080,
    # and the devpod preview proxy also targets 8080.
    PORT=8080

# Add caddy + tini + gosu. The upstream image defaults to USER
# node (uid 1000), so we explicitly switch to root for the apt
# install. The runtime (start.sh) also runs as root, drops to
# uid 1000 via gosu for the gateway + caddy children (after
# chowning the volume).
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        caddy \
        tini \
        gosu \
 && rm -rf /var/lib/apt/lists/* \
 && caddy version

# Caddyfile: route 8080 → 18789 (OpenClaw gateway + control UI). The
# OpenClaw gateway serves both the API and the web UI on a single
# port, so the proxy is trivially "1:1 forward".
COPY --chmod=0644 Caddyfile /etc/caddy/Caddyfile

# Our start script: writes the openclaw.json with MiniMax + OpenRouter
# if not present, then starts the gateway + caddy.
COPY --chmod=0755 start.sh /usr/local/bin/start.sh

# Persistent state — config, sessions, skills, memory, workspace.
# In Fly, replaced by a volume (see fly.toml).
VOLUME ["/data"]
WORKDIR /data

EXPOSE 8080

# Healthcheck hits the gateway's /health endpoint through caddy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["/usr/local/bin/start.sh"]
