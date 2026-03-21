# Synkade

Self-hosted orchestrator for autonomous coding agents.

Point it at your repos, configure your agents, and let them work through your issue backlog — with real-time visibility, cost tracking, and automatic retries.

## What it does

- **Multi-agent pool** — Configure Claude Code, Codex, or any CLI agent with their own API keys, models, and system prompts
- **Multi-project** — Manage multiple repos from one instance, each with its own agent and prompt template
- **Automatic dispatch** — Issues move from backlog to queue to in-progress without manual intervention
- **Live dashboard** — See what every agent is doing right now, streaming events via WebSocket
- **Cost tracking** — Per-session and per-project token usage
- **Retry & recovery** — Exponential backoff on failures, automatic continuation
- **Isolated workspaces** — Each agent session gets its own workspace with lifecycle hooks
- **Encrypted secrets** — API keys and tokens encrypted at rest

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/synkade/synkade/main/docker-compose.yml -o docker-compose.yml
docker compose up -d
```

Open [localhost:4000](http://localhost:4000) to set up your admin account.

The `docker-compose.yml` includes a Postgres 17 database. Secrets are generated automatically on first run and persisted to the data volume.

### Environment variables

All optional — defaults work out of the box.

| Variable | Default | Description |
|----------|---------|-------------|
| `PHX_HOST` | `localhost` | Your domain name |
| `PORT` | `4000` | HTTP port |
| `DATABASE_URL` | `postgres://postgres:postgres@db:5432/synkade_prod` | PostgreSQL connection URL |

## License

MIT with SaaS restriction — see [LICENSE](LICENSE).
