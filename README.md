# hermes-jarvis

Deploy [Hermes Agent](https://github.com/NousResearch/hermes-agent) by
Nous Research to a [Fly.io](https://fly.io) pod with the v0.16.0 web
admin dashboard exposed at a single public URL.

This repo is a **deployment harness** — Hermes Agent is the dependency.
We pin to `nousresearch/hermes-agent:v2026.6.5` (the "Surface Release"
that shipped the web admin dashboard) and wrap it in a small Caddy
reverse proxy so the gateway, dashboard, and OpenAI-compatible API
are all reachable on a single port.

## What's inside

```
.
├── Dockerfile           # nousresearch/hermes-agent + caddy + start.sh
├── Caddyfile            # 8080 → :9119 (dashboard) + :8642 (gateway)
├── fly.toml             # Fly app config (1 GB machine, 1 GB volume)
├── docker-compose.yml   # Local dev (mirrors prod)
├── bin/start.sh         # Supervises gateway + dashboard + caddy
├── deploy.sh            # `fly deploy --remote-only` wrapper
├── pyproject.toml       # Python: hermes-agent[web]>=0.16.0
├── package.json         # Node: declares the Docker image as a dep
└── .env.example         # Template for LLM keys + dashboard auth
```

## Architecture

```
                          public internet
                                 │
                                 ▼
                  ┌────────────────────────────┐
                  │  Fly edge proxy            │
                  │  (TLS, HTTPS, port 443)    │
                  └─────────────┬──────────────┘
                                │
                                ▼
                  ┌────────────────────────────┐
                  │  Container                 │
                  │                            │
                  │  caddy (:8080)  ◄── public │
                  │     │                      │
                  │     ├── /  /api/*  ──► dashboard (:9119)
                  │     │                      │   (web admin UI,
                  │     │                      │    v0.16.0)
                  │     │                      │
                  │     └── /v1/*  /health ──► gateway   (:8642)
                  │                            │   (OpenAI-compat
                  │                            │    API server)
                  │                            │
                  │  Volume: /opt/data         │
                  │    ├── config.yaml         │
                  │    ├── sessions/ skills/   │
                  │    ├── memory/ creds/      │
                  └────────────────────────────┘
```

## Quick start

### 1. Local (docker compose)

```bash
cp .env.example .env
$EDITOR .env                      # set ANTHROPIC_API_KEY, dashboard auth
docker compose up --build
# open http://localhost:8080
```

### 2. Fly.io (this devpod or anywhere)

```bash
cp .env.example .env
$EDITOR .env                      # set ANTHROPIC_API_KEY, dashboard auth
fly secrets import < .env         # or: fly secrets set KEY=VAL
bash deploy.sh                    # creates app, volume, deploys
# open https://hermes-jarvis.fly.dev
```

## What you can do once it's running

- **Web admin dashboard** — channels, MCP servers, credentials,
  memory, webhooks, gateway controls, all in the browser
- **Chat with Hermes** — same backend as the Hermes Desktop app
- **Connect the Hermes Desktop app** to this pod as a remote backend
  (`HERMES_DESKTOP_REMOTE_URL=https://hermes-jarvis.fly.dev` +
  `HERMES_DASHBOARD_BASIC_AUTH_*`)
- **OpenAI-compatible API** at `/v1/chat/completions`, `/v1/models`,
  `/v1/runs`, `/health` — any client that speaks OpenAI can talk to it

## Configuration reference

| Env var | Required | Purpose |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` (or another provider key) | yes | LLM credentials |
| `API_SERVER_KEY` | yes (prod) | Bearer token for the OpenAI API |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/PASSWORD` | recommended | Dashboard login |
| `API_SERVER_CORS_ORIGINS` | optional | Browser CORS for `/v1/*` |
| `HERMES_SKIP_CONFIG_MIGRATION` | optional | Inspect config before the image rewrites it |

Full reference: https://hermes-agent.nousresearch.com/docs/reference/environment-variables

## Security notes

- Hermes' permission model is broad by design (it can shell into the
  machine). Treat dashboard access like machine access.
- Always set `HERMES_DASHBOARD_BASIC_AUTH_*` for any non-loopback deploy.
- The `hermes-webui` ecosystem component had a path-traversal CVE in
  April 2026 (CVE-2026-6829, fixed in v0.50.34+). Pinning the official
  `nousresearch/hermes-agent:v2026.6.5` image avoids that surface.
- Recent CVEs in `hermes-agent` itself are closed in v0.16.0 — don't
  pin to an image older than `v2026.5.16`.

## License

MIT
