# elicify-jarvis

Deployment harness for two self-hosted AI agent stacks on Fly.io:

- **`hermes-jarvis.fly.dev`** — [Hermes Agent](https://github.com/NousResearch/hermes-agent) v0.16.0 (Nous Research) with the built-in web admin dashboard, configured to use **MiniMax** (`MiniMax-M3`).
- **`openclaw-jarvis.fly.dev`** — [OpenClaw](https://github.com/openclaw/openclaw) (the rival agent that has been gaining market share fast in 2026), with MiniMax as the primary provider and **OpenRouter** (`anthropic/claude-3.5-sonnet`) as fallback.

Both share the same deployment shape: a single public port, Caddy in front, persistent Fly volume, MiniMax auth via Fly secrets, single-binary-style control UI accessible from any browser.

## Layout

```
.
├── Dockerfile             # Hermes: nousresearch/hermes-agent + caddy + tini
├── Caddyfile              # 8080 → 9119 (dashboard) + 8642 (gateway)
├── fly.toml               # hermes-jarvis app — shared-cpu-8x, 8 GB, 10 GB vol
├── docker-compose.yml     # local dev for Hermes
├── deploy.sh              # fly launch + volume + deploy
├── bin/start.sh           # supervises hermes gateway + dashboard + caddy
├── pyproject.toml         # Python: hermes-agent[web]>=0.16.0
├── package.json           # node: declares the Docker image as a dep
├── .env.example           # template for secrets
│
└── openclaw/              # OpenClaw deploy (sibling app)
    ├── Dockerfile         # ghcr.io/openclaw/openclaw:latest + caddy + tini + gosu
    ├── Caddyfile          # 8080 → 18789 (gateway + control UI)
    ├── fly.toml           # openclaw-jarvis app — shared-cpu-4x, 8 GB, 20 GB vol
    ├── start.sh           # supervises openclaw gateway + caddy; bakes openclaw.json
    └── deploy.sh
```

## Live deployments

| | Hermes (`hermes-jarvis`) | OpenClaw (`openclaw-jarvis`) |
|---|---|---|
| **URL** | `https://hermes-jarvis.fly.dev/` | `https://openclaw-jarvis.fly.dev/` |
| **Dashboard login** | `admin` / `hermesdev2026` (Fly secret) | Enter the `OPENCLAW_API_KEY` Fly secret into the dashboard's Connect form |
| **Version** | v0.16.0 (Surface Release, 2026.6.5) | v2026.6.5 |
| **Machine** | shared-cpu-8x, 8 GB | shared-cpu-4x, 8 GB |
| **Volume** | `hermes_data` — 10 GB encrypted | `openclaw_data` — 20 GB encrypted |
| **Primary LLM** | MiniMax `MiniMax-M3` | MiniMax `MiniMax-M3` |
| **Fallback LLM** | (none) | OpenRouter `anthropic/claude-3.5-sonnet` |
| **Health** | `{"status":"ok","platform":"hermes-agent"}` | gateway reports `ready` + 8 plugins |
| **Image source** | `nousresearch/hermes-agent:v2026.6.5` (Docker Hub) | `ghcr.io/openclaw/openclaw:latest` (GHCR) |

## Architecture (both apps follow the same pattern)

```
                          public internet
                                 │
                                 ▼
                  ┌────────────────────────────┐
                  │  Fly edge proxy (TLS, 443) │
                  └─────────────┬──────────────┘
                                │
                                ▼
                  ┌────────────────────────────┐
                  │  Container (Firecracker)   │
                  │                            │
                  │  caddy (:8080)             │
                  │     │                      │
                  │     ├── /            ──►  agent gateway (UI + API)
                  │     │                      │
                  │  Volume: /opt/data  or    │
                  │           /data           │
                  │     ├── config            │
                  │     ├── sessions/skills/  │
                  │     ├── memory/creds/     │
                  │     └── workspace/        │
                  └────────────────────────────┘
```

## Configuration reference

### Hermes

| Env var | Purpose |
|---|---|
| `MINIMAX_API_KEY` (Fly secret) | LLM credentials |
| `MINIMAX_BASE_URL` | `https://api.minimax.io/anthropic` |
| `MINIMAX_MODEL` | `MiniMax-M3` |
| `API_SERVER_KEY` (Fly secret) | Bearer token for the OpenAI-compatible API |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/PASSWORD` | Dashboard login |
| `HERMES_SKIP_CONFIG_MIGRATION` | Optional — inspect config before the image rewrites it |

### OpenClaw

| Env var | Purpose |
|---|---|
| `MINIMAX_API_KEY` (Fly secret) | Primary LLM credentials |
| `MINIMAX_BASE_URL` | `https://api.minimax.io/anthropic` |
| `MINIMAX_MODEL` | `MiniMax-M3` |
| `OPENROUTER_API_KEY` (Fly secret) | Fallback LLM credentials |
| `OPENCLAW_API_KEY` (Fly secret) | Bearer token for the WebSocket gateway |
| `OPENROUTER_API_KEY` | (set in `openclaw.json` via Fly secret) |

## How to deploy

### 1. Hermes

```bash
fly secrets set --app hermes-jarvis \
    MINIMAX_API_KEY=sk-... \
    API_SERVER_KEY=$(openssl rand -hex 32) \
    HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin \
    HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$(openssl rand -hex 16)
bash deploy.sh
# → https://hermes-jarvis.fly.dev/
```

### 2. OpenClaw

```bash
cd openclaw
fly secrets set --app openclaw-jarvis \
    MINIMAX_API_KEY=sk-... \
    OPENROUTER_API_KEY=sk-or-... \
    OPENCLAW_API_KEY=$(openssl rand -hex 32)
bash deploy.sh
# → https://openclaw-jarvis.fly.dev/
# Open the URL, paste the OPENCLAW_API_KEY into the dashboard's Connect form.
```

## What you can do once it's running

- **Web admin dashboard in a browser** — chat, memory, skills, MCP servers, channels, settings
- **Point the Hermes Desktop app** at either pod as a remote backend
- **Use the OpenAI-compatible API** at `/v1/chat/completions` with `Authorization: Bearer $API_SERVER_KEY` for Hermes, or via WebSocket for OpenClaw
- **Run both in parallel** — different Fly apps, different secrets, no interference

## Security notes

- All Fly volumes are encrypted at rest.
- Hermes dashboard uses HTTP basic auth; OpenClaw uses token auth via the WebSocket.
- Always set `HERMES_DASHBOARD_BASIC_AUTH_*` and `OPENCLAW_API_KEY` for any non-loopback deploy.
- Don't paste the API keys into the dashboard UI — they're configured via Fly secrets and read at runtime.
- Both projects had CVEs in early 2026 — Hermes v0.16.0 + OpenClaw v2026.6.5 are pinned past the relevant fixes.

## License

MIT
