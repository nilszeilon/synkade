#!/bin/sh
set -eu

SECRETS_FILE="/app/data/.secrets"

# Generate secrets on first run if they don't exist
if [ ! -f "$SECRETS_FILE" ]; then
  echo "First run detected — generating secrets..."
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  SETTINGS_ENCRYPTION_KEY=$(openssl rand -base64 32)

  cat > "$SECRETS_FILE" <<EOF
export SECRET_KEY_BASE="${SECRET_KEY_BASE}"
export SETTINGS_ENCRYPTION_KEY="${SETTINGS_ENCRYPTION_KEY}"
EOF

  chmod 600 "$SECRETS_FILE"
  echo "Secrets written to ${SECRETS_FILE}"
fi

# Source secrets — only sets vars not already in the environment
. "$SECRETS_FILE"

# Apply defaults (env overrides take precedence)
export SECRET_KEY_BASE="${SECRET_KEY_BASE}"
export SETTINGS_ENCRYPTION_KEY="${SETTINGS_ENCRYPTION_KEY}"
export DATABASE_PATH="${DATABASE_PATH:-/app/data/synkade.db}"
export PHX_HOST="${PHX_HOST:-localhost}"
export PORT="${PORT:-4000}"

exec /app/bin/server
