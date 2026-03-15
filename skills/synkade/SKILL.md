---
name: synkade
description: >
  Interact with the Synkade control plane API to discover work, claim issues,
  send heartbeats, and report completion. Use this skill when operating as a
  pull-based agent connected to a Synkade instance.
required_environment_variables:
  - SYNKADE_API_URL
  - SYNKADE_API_TOKEN
---

# Synkade Pull Agent Skill

You are a pull-based agent connected to a Synkade instance. Follow this
heartbeat procedure to discover work, claim issues, and report progress.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SYNKADE_API_URL` | Base URL of the Synkade instance (e.g. `http://localhost:4000`) |
| `SYNKADE_API_TOKEN` | Bearer token for API authentication |

All API requests require the header:
```
Authorization: Bearer $SYNKADE_API_TOKEN
```

## Heartbeat Procedure

### Step 1: Discover identity

```bash
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/api/v1/agent/me"
```

Response:
```json
{
  "data": {
    "id": "uuid",
    "name": "my-agent",
    "kind": "hermes",
    "pull": true,
    "projects": [{"id": "uuid", "name": "my-project"}]
  }
}
```

### Step 2: Find work

Poll for queued issues assigned to you, or unassigned queued issues in your
projects:

```bash
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/api/v1/agent/issues?state=queued"
```

### Step 3: Checkout issue (atomic claim)

Checkout transitions the issue to `in_progress` and assigns it to you. This is
atomic -- if another agent already claimed it you'll get a 409.

```bash
curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/api/v1/agent/issues/:id/checkout"
```

- **200**: Issue claimed successfully
- **409**: Already claimed by another agent -- skip and find another issue

**Never retry a 409.** Move on to the next queued issue.

### Step 4: Read issue details

```bash
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/api/v1/agent/issues/:id"
```

Response includes `body` (full markdown), `children`, `parent_id`, `depth`,
and `agent_output`.

### Step 5: Do the work

Perform the task described in the issue body. Use the project workspace and
any tools available to you.

### Step 6: Send heartbeats every 2-3 minutes

While working, send heartbeats to signal you are alive:

```bash
curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"issue_id": ":id", "status": "working", "message": "implementing feature X"}' \
  "$SYNKADE_API_URL/api/v1/agent/heartbeat"
```

Valid statuses: `working`, `error`, `blocked`

### Step 7: Complete

When done, update the issue state to `awaiting_review` and optionally attach
output:

```bash
curl -s -X PATCH -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"state": "awaiting_review", "agent_output": "PR #42 created"}' \
  "$SYNKADE_API_URL/api/v1/agent/issues/:id"
```

### Step 8: Loop

Go back to Step 2 and look for more work.

## Creating Sub-Issues

Break large tasks into children:

```bash
curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"children": [{"title": "Subtask 1", "description": "Details..."}]}' \
  "$SYNKADE_API_URL/api/v1/agent/issues/:id/children"
```

## Creating New Issues

Create standalone issues in a project:

```bash
curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"project_id": ":project_id", "title": "New task", "description": "Details..."}' \
  "$SYNKADE_API_URL/api/v1/agent/issues"
```

## API Quick Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/agent/me` | Agent identity and projects |
| GET | `/api/v1/agent/issues` | List issues (filter: `state`, `project_id`, `assigned_to=me`) |
| POST | `/api/v1/agent/issues` | Create a new issue |
| GET | `/api/v1/agent/issues/:id` | Get issue details |
| PATCH | `/api/v1/agent/issues/:id` | Update issue (state, body, agent_output) |
| POST | `/api/v1/agent/issues/:id/checkout` | Claim a queued issue (409 if taken) |
| POST | `/api/v1/agent/issues/:id/children` | Create child issues |
| POST | `/api/v1/agent/heartbeat` | Send heartbeat (issue_id, status, message) |

## Critical Rules

1. **Always checkout before working** -- the checkout is your atomic claim
2. **Never retry a 409** -- another agent claimed it, move on
3. **Send heartbeats every 2-3 minutes** during work so Synkade knows you're alive
4. **Valid heartbeat statuses**: `working`, `error`, `blocked`
5. **Agents cannot transition to**: `queued` or `cancelled` (server will reject)
