# Synkade

### Open-source orchestration for autonomous coding teams

**Synkade is the manager. Your agents are the engineers.**

Synkade is a self-hosted Phoenix server and LiveView dashboard that orchestrates a pool of AI coding agents across your projects. Point it at your GitHub repos, configure your agents, and let them work through your issue backlog — with concurrency control, retry logic, cost tracking, and real-time visibility.

It looks like a project dashboard — but under the hood it has multi-agent pools, per-project agent assignment, isolated workspaces, and automatic dispatch.

**Manage projects and agents, not terminal tabs.**

|        | Step              | Example                                                        |
| ------ | ----------------- | -------------------------------------------------------------- |
| **01** | Add your projects | Point at your GitHub repos — `acme/api`, `acme/frontend`, etc. |
| **02** | Configure agents  | Set up Claude, Codex, or any CLI agent with keys and models.   |
| **03** | Watch them work   | Agents pick up issues, create PRs, and report back.            |

<br/>

<div align="center">
<table>
  <tr>
    <td align="center"><strong>Works with</strong></td>
    <td align="center"><strong>Claude Code</strong></td>
    <td align="center"><strong>Codex</strong></td>
  </tr>
</table>

<em>If it has a CLI, it can be an agent.</em>

</div>

<br/>

## Synkade is right for you if

- You want agents **autonomously working through your GitHub issues** while you sleep
- You have **multiple repos** and want one place to manage agent dispatch across all of them
- You're running **multiple agents in parallel** and losing track of who's doing what
- You want **per-project agent configuration** — different models, tools, or prompts per repo
- You want to **monitor costs and token usage** across all your agent sessions
- You want **retry logic and error recovery** without babysitting terminals
- You want a **real-time dashboard** showing what every agent is doing right now

<br/>

## Features

<table>
<tr>
<td align="center" width="33%">
<h3>Multi-Agent Pool</h3>
Configure multiple agents with different models, API keys, and tools. Assign agents per project.
</td>
<td align="center" width="33%">
<h3>Multi-Project</h3>
Manage multiple GitHub repos from one instance. Each project gets its own agent, prompt template, and concurrency settings.
</td>
<td align="center" width="33%">
<h3>Automatic Dispatch</h3>
Synkade polls for open issues, claims them, spins up isolated workspaces, and dispatches agents — no manual intervention.
</td>
</tr>
<tr>
<td align="center">
<h3>Real-Time Dashboard</h3>
See running agents, token usage, retry status, and PRs awaiting review — all updating live via WebSocket.
</td>
<td align="center">
<h3>Cost Tracking</h3>
Per-session and per-project token usage. Know exactly what your agents are spending.
</td>
<td align="center">
<h3>Retry & Recovery</h3>
Exponential backoff on failures, continuation retries on normal exits. Agents don't just crash — they come back.
</td>
</tr>
<tr>
<td align="center">
<h3>Isolated Workspaces</h3>
Each agent session runs in its own workspace with configurable lifecycle hooks (clone, setup, cleanup).
</td>
<td align="center">
<h3>Prompt Templates</h3>
Liquid templates with full issue context. Per-project or per-agent prompt overrides.
</td>
<td align="center">
<h3>Encrypted Secrets</h3>
API keys and tokens are encrypted at rest with Cloak. No plaintext credentials in your database.
</td>
</tr>
</table>

<br/>

## Without Synkade vs. With Synkade

| Without Synkade | With Synkade |
| --- | --- |
| You have 10 Claude Code terminals open and can't remember which issue each one is working on. | One dashboard shows every running agent, its issue, token usage, and last activity. |
| An agent crashes at 3am and the issue sits untouched until you notice. | Automatic retry with exponential backoff. The agent picks it back up. |
| You manually copy-paste issue descriptions into agent prompts. | Liquid templates inject full issue context automatically. |
| Switching between repos means reconfiguring your agent each time. | Per-project agent config. Each repo gets its own agent, model, and tools. |
| No idea how many tokens you've burned across all your agent sessions. | Per-session and per-project token tracking on the dashboard. |
| You have to manually check if the agent created a PR. | PRs show up in the "awaiting review" column automatically. |

<br/>

## Quickstart

**Requirements:** Elixir 1.15+, PostgreSQL 17+, a GitHub PAT

```bash
git clone https://github.com/nilszeilon/synkade.git
cd synkade

# Start Postgres (or use your own)
docker compose up -d

# Install deps, create DB, run migrations
mix setup

# Start the server
mix phx.server
```

Open [localhost:4000](http://localhost:4000) and configure your settings:

1. **Settings > GitHub** — Add your Personal Access Token
2. **Settings > Agents** — Create an agent (name, kind, API key, model)
3. **Projects** — Add a project pointing at your GitHub repo, assign an agent

Synkade starts polling for issues and dispatching agents automatically.

<br/>

## Configuration

All configuration happens through the web UI — no config files to manage.

### Settings

| Tab | What you configure |
| --- | --- |
| **GitHub** | Personal Access Token, webhook secret |
| **Agents** | Agent pool — name, kind (Claude/Codex), auth mode, API key, model, max turns, allowed tools, system prompt |
| **Execution** | Backend (local or Sprites for remote execution) |

### Projects

Each project has:
- **Name** and **Repository** (`owner/repo`)
- **Default Agent** — which agent from your pool handles this project
- **Prompt Template** — Liquid template with issue context variables

### Prompt Template Variables

- `{{ issue.identifier }}` — e.g. `owner/repo#42`
- `{{ issue.id }}` — issue number
- `{{ issue.title }}` — issue title
- `{{ issue.description }}` — issue body
- `{{ issue.state }}` — e.g. `open`, `closed`
- `{{ issue.url }}` — link to the issue
- `{{ issue.labels }}` — list of label strings
- `{{ issue.priority }}` — numeric priority
- `{{ project.name }}` — project name
- `{{ attempt }}` — retry attempt number

<br/>

## API

| Endpoint | Description |
|----------|-------------|
| `GET /api/v1/state` | Full orchestrator state |
| `GET /api/v1/projects` | List configured projects |
| `GET /api/v1/projects/:name` | Single project details |
| `POST /api/v1/refresh` | Force an immediate poll cycle |

## GitHub Webhooks

Synkade receives GitHub webhook events at `POST /github/webhooks` for faster reaction times. Set a webhook secret in Settings > GitHub to verify payload signatures.

<br/>

## Development

```bash
mix test              # Run tests
mix precommit         # Compile, format, test
mix phx.server        # Start dev server
```

## Production

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Postgres connection string |
| `SECRET_KEY_BASE` | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Your domain name |
| `PHX_SERVER` | Set to `true` |
| `PORT` | HTTP port (default `4000`) |
| `CLOAK_KEY` | Encryption key for secrets at rest |

See the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for details.

<br/>

## License

MIT with SaaS restriction — see [LICENSE](LICENSE) for details.
