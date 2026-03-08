---
tracker:
  kind: github
  repo: nilszeilon/synkade
  api_key: $GITHUB_TOKEN

agent:
  kind: claude
  max_concurrent_agents: 5


execution:
    backend: sprites
    sprites_token: $FLY_API_TOKEN

---
Work on {{ issue.identifier }}: {{ issue.title }}

{{ issue.description }}
