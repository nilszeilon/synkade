# Synkade

Synkade is a self-hosted orchestrator that automatically assigns coding agents to issues from your project tracker. It polls for open issues, spins up isolated workspaces, and dispatches AI agents to work on them — with retry logic, concurrency control, and a real-time dashboard.

Currently supported:
- **Agents:** Claude Code
- **Trackers:** GitHub (with PAT or GitHub App auth)

## Prerequisites

- [Elixir](https://elixir-lang.org/install.html) ~> 1.15
- [PostgreSQL](https://www.postgresql.org/) 17+ (or use the included Docker Compose)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- A GitHub personal access token or GitHub App credentials

## Setup

1. **Clone the repo**

   ```sh
   git clone https://github.com/nilszeilon/synkade.git
   cd synkade
   ```

2. **Start PostgreSQL**

   Using the included Docker Compose (exposes Postgres on port 5437):

   ```sh
   docker compose up -d
   ```

   Or point to your own Postgres instance by editing `config/dev.exs`.

3. **Install dependencies and set up the database**

   ```sh
   mix setup
   ```

   This runs `deps.get`, `ecto.create`, `ecto.migrate`, seeds the database, and builds assets.

4. **Configure your workflow**

   Edit `WORKFLOW.md` in the project root. This file uses YAML front matter for configuration and a Liquid template for the agent prompt:

   ```markdown
   ---
   tracker:
     kind: github
     repo: your-org/your-repo
     api_key: $GITHUB_TOKEN

   agent:
     kind: claude
     max_concurrent_agents: 5
   ---
   Work on {{ issue.identifier }}: {{ issue.title }}

   {{ issue.description }}
   ```

   The `api_key: $GITHUB_TOKEN` syntax resolves the `GITHUB_TOKEN` environment variable at runtime. Changes to `WORKFLOW.md` are picked up automatically via a file watcher — no restart needed.

5. **Set your GitHub token**

   ```sh
   export GITHUB_TOKEN=ghp_your_token_here
   ```

6. **Start the server**

   ```sh
   mix phx.server
   ```

   Or inside IEx:

   ```sh
   iex -S mix phx.server
   ```

   The dashboard is available at [localhost:4000](http://localhost:4000).

## Workflow Configuration

The `WORKFLOW.md` file controls all orchestrator behavior. Here are the available options:

### Tracker

| Key | Description | Default |
|-----|-------------|---------|
| `tracker.kind` | `github` | `github` |
| `tracker.repo` | GitHub `owner/repo` (required for PAT mode) | — |
| `tracker.api_key` | PAT or `$ENV_VAR` reference | `$GITHUB_TOKEN` |
| `tracker.endpoint` | Custom API endpoint URL | `https://api.github.com` |
| `tracker.labels` | Only process issues with these labels | all issues |
| `tracker.active_states` | Issue states to pick up | `["open"]` |
| `tracker.terminal_states` | States that mean "done" | `["closed"]` |
| `tracker.webhook_secret` | Secret for verifying GitHub webhook payloads | — |

### GitHub App Auth (alternative to PAT)

| Key | Description |
|-----|-------------|
| `tracker.app_id` | GitHub App ID |
| `tracker.private_key` | Inline PEM private key |
| `tracker.private_key_path` | Path to `.pem` file (alternative to `private_key`) |
| `tracker.installation_id` | Installation ID (optional — auto-discovered if omitted) |

### Agent

| Key | Description | Default |
|-----|-------------|---------|
| `agent.kind` | `claude` | `claude` |
| `agent.max_concurrent_agents` | Global max parallel agents | `10` |
| `agent.max_concurrent_agents_by_state` | Per-state concurrency limits (e.g. `{"open": 3}`) | no limit |
| `agent.max_turns` | Max agent turns per issue | `20` |
| `agent.allowed_tools` | Tools the agent can use | `["Read", "Edit", "Write", "Bash", "Glob", "Grep"]` |
| `agent.model` | Model override (e.g. `claude-sonnet-4-5-20250929`) | CLI default |
| `agent.command` | Custom command to run the agent | `claude` |
| `agent.append_system_prompt` | Extra text appended to the agent system prompt | — |
| `agent.turn_timeout_ms` | Timeout per agent turn | `3600000` (1h) |
| `agent.max_tokens` | Max tokens per agent response | — |
| `agent.stall_timeout_ms` | Kill stalled agents after this | `300000` (5min) |
| `agent.max_retry_backoff_ms` | Max backoff between retries | `300000` (5min) |

### Polling

| Key | Description | Default |
|-----|-------------|---------|
| `polling.interval_ms` | How often to poll for new issues | `30000` |

### Workspace

| Key | Description | Default |
|-----|-------------|---------|
| `workspace.root` | Directory for agent workspaces | System temp dir |

### Hooks

| Key | Description |
|-----|-------------|
| `hooks.after_create` | Shell command run after workspace is created (e.g. `git clone ...`) |
| `hooks.before_run` | Shell command run before each agent session |
| `hooks.after_run` | Shell command run after each agent session |
| `hooks.before_remove` | Shell command run before workspace cleanup |
| `hooks.timeout_ms` | Hook execution timeout (default `60000`) |

### Multi-project

You can define multiple projects in a single workflow:

```markdown
---
agent:
  max_concurrent_agents: 10

projects:
  - name: frontend
    tracker:
      repo: your-org/frontend
  - name: backend
    tracker:
      repo: your-org/backend
---
Work on {{ issue.identifier }}: {{ issue.title }}

{{ issue.description }}
```

Per-project settings override the global `tracker`, `agent`, `workspace`, and `hooks` sections. Each project can also define its own `prompt` to override the global template.

### Prompt Template

The body of `WORKFLOW.md` (after the `---` front matter) is a [Liquid](https://shopify.github.io/liquid/) template. Available variables:

- `{{ issue.identifier }}` — e.g. `owner/repo#42`
- `{{ issue.id }}` — issue number
- `{{ issue.title }}` — issue title
- `{{ issue.description }}` — issue body
- `{{ issue.state }}` — e.g. `open`, `closed`
- `{{ issue.url }}` — link to the issue
- `{{ issue.labels }}` — list of label strings
- `{{ issue.priority }}` — numeric priority (from `priority:N` labels)
- `{{ project.name }}` — project name
- `{{ attempt }}` — retry attempt number (nil on first run)

## API

Synkade exposes a JSON API:

| Endpoint | Description |
|----------|-------------|
| `GET /api/v1/state` | Full orchestrator state |
| `GET /api/v1/projects` | List configured projects |
| `GET /api/v1/projects/:name` | Single project details |
| `POST /api/v1/refresh` | Force an immediate poll cycle |

## GitHub Webhooks

Synkade can receive GitHub webhook events at `POST /github/webhooks`. Configure your GitHub repo or App to send issue events to this endpoint for faster reaction times instead of relying solely on polling.

If you set `tracker.webhook_secret`, Synkade will verify the `X-Hub-Signature-256` header on incoming payloads.

## Running Tests

```sh
mix test
```

## Pre-commit Checks

```sh
mix precommit
```

This runs compilation with warnings-as-errors, unlocks unused deps, formats code, and runs the test suite.

## Production

For production deployment, set these environment variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Postgres connection string (`ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Your domain name |
| `PHX_SERVER` | Set to `true` to start the web server |
| `PORT` | HTTP port (default `4000`) |
| `GITHUB_TOKEN` | GitHub API token |

See the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for more details.

## License

MIT with SaaS restriction — see [LICENSE](LICENSE) for details.
