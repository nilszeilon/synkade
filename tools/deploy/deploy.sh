#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/synkade"
REPO_DIR="$APP_DIR/repo"
LOG="$APP_DIR/deploy.log"

# Load asdf if available
[ -f /opt/asdf/asdf.sh ] && source /opt/asdf/asdf.sh

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

log "Deploy started"

cd "$REPO_DIR"

# Pull latest
git fetch origin main
git reset --hard origin/main

# Load env for build
set -a
source "$APP_DIR/.env"
set +a

export MIX_ENV=prod

# Install deps (incremental — only fetches new ones)
mix deps.get --only prod

# Compile (incremental — only recompiles changed files)
mix compile

# Build assets
mix assets.deploy

# Build release (overwrites in place)
mix release --overwrite

# Run migrations
"$REPO_DIR/_build/prod/rel/synkade/bin/migrate"

# Restart the service
sudo systemctl restart synkade

log "Deploy complete"
