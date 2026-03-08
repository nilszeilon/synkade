---
tracker:
  kind: github
  repo: nilszeilon/synkade
  api_key: $GITHUB_TOKEN

agent:
  kind: claude
  max_concurrent_agents: 5
---
Work on {{ issue.identifier }}: {{ issue.title }}

{{ issue.description }}
