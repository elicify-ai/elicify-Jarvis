# syntax=docker/dockerfile:1.7
#
# Hermes Agent by Nous Research — runtime image for the Fly pod.
# https://github.com/NousResearch/hermes-agent
# https://hermes-agent.nousresearch.com
#
# We start FROM the official image (which already has the hermes CLI,
# the Python venv, the gateway, and the v0.16.0 dashboard plugin) and
# layer on:
#   * caddy   — single-port reverse proxy (:8080) that fronts the
#               gateway (:8642, OpenAI-compatible API) and the
#               dashboard (:9119, web admin UI)
#   * tini    — PID 1 / signal forwarding
#   * gosu    — already in the upstream image, but we re-install via
#               apt so /usr/bin/gosu is on PATH
#   * start.sh — runs `hermes gateway` + `hermes dashboard` + caddy
#
# Pinned to v2026.6.5 (Hermes v0.16.0, the "Surface Release" that
# shipped the web admin dashboard).
ARG HERMES_VERSION=v2026.6.5
FROM nousresearch/hermes-agent:${HERMES_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    # Hermes data location inside the container. In Fly this is a
    # persistent volume (see fly.toml).
    HERMES_HOME=/opt/data \
    HERMES_DASHBOARD=1 \
    API_SERVER_ENABLED=true \
    # Bind on all interfaces — required because Fly's edge proxy and
    # the devpod preview proxy both reach us via the pod's private IP,
    # not loopback.
    API_SERVER_HOST=0.0.0.0 \
    HERMES_DASHBOARD_HOST=0.0.0.0 \
    HERMES_DASHBOARD_PORT=9119 \
    # Caddy listens here — Fly's edge proxy forwards 80/443 to 8080,
    # and the devpod preview proxy also targets 8080.
    PORT=8080

# Add caddy + tini + gosu. The upstream image has gosu at a non-PATH
# location, so we install it via apt for a predictable /usr/bin/gosu.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        caddy \
        tini \
        gosu \
 && rm -rf /var/lib/apt/lists/* \
 && caddy version

# Caddyfile: route 8080 → 9119 (dashboard) for / and /api/*, 8080 → 8642
# (gateway) for /v1/* and /health. Single public port keeps the Fly
# config and any reverse-proxy in front simple.
COPY Caddyfile /etc/caddy/Caddyfile

# Our start script: drops to the hermes user, then runs the gateway,
# the dashboard, and caddy under tini. We invoke it as root in the
# ENTRYPOINT and gosu down to `hermes` inside the script.
COPY bin/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Persistent state — config, sessions, skills, memory, credentials.
# In Fly, replaced by a volume (see fly.toml).
VOLUME ["/opt/data"]
WORKDIR /opt/data

EXPOSE 8080

# Healthcheck hits the gateway's /health endpoint through caddy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["/usr/local/bin/start.sh"]
