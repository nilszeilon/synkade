---
name: synkade
description: Git workflow, Synkade API, status reporting, and pull-based agent protocol
user-invocable: false
allowed-tools: Bash(git *), Bash(gh *), Bash(curl *)
---

## Git & Pull Requests

You have a `GITHUB_TOKEN` environment variable. After making changes, commit and open a PR:

```bash
git checkout -b fix/short-description
git add -A && git commit -m "Description of changes"
gh pr create --title "Short title" --body "Description"
```

Always create a PR with your changes so they can be reviewed.

## Synkade API

Environment variables: `$SYNKADE_API_URL`, `$SYNKADE_API_TOKEN`.

```bash
# List issues for this project
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/issues?project_id=aafde329-f689-4d47-9df9-15457b4a86f3"

# Create an issue
curl -s -X POST "$SYNKADE_API_URL/issues" \
  -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"project_id":"aafde329-f689-4d47-9df9-15457b4a86f3","body":"# Title\n\nDetails"}'

# Update an issue
curl -s -X PATCH "$SYNKADE_API_URL/issues/<issue_id>" \
  -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"state":"done"}'

# Read issue history
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/issues/<issue_id>"
```

## Status Reporting

Send heartbeats every 2-3 minutes during long tasks to prevent stall detection:

```bash
curl -s -X POST "$SYNKADE_API_URL/heartbeat" \
  -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"issue_id":"<issue_id>","status":"working","message":"Brief status"}'
```

Valid statuses: `working`, `error`, `blocked`.

## Follow-Up Issues

When you discover out-of-scope work (bugs, tech debt, follow-ups), create issues rather than scope-creeping:

```bash
curl -s -X POST "$SYNKADE_API_URL/issues" \
  -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"project_id":"aafde329-f689-4d47-9df9-15457b4a86f3","body":"# Issue Title\n\nDescription"}'
```

## Pull-Based Protocol

For persistent agents: discover and claim work between tasks.

```bash
# Who am I?
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" "$SYNKADE_API_URL/me"

# Find queued work assigned to me
curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/issues?state=queued&assigned_to=me"

# Claim an issue (409 if already claimed)
curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  "$SYNKADE_API_URL/issues/<issue_id>/checkout"

# Mark complete
curl -s -X PATCH "$SYNKADE_API_URL/issues/<issue_id>" \
  -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"state":"awaiting_review","agent_output":"Summary of work"}'
```

Workflow: poll → checkout → heartbeat → complete.
