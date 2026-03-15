#!/usr/bin/env bash
#
# One-time server setup for Synkade on Ubuntu/Debian (Hetzner VPS)
# Run as root: bash setup.sh
#
set -euo pipefail

REPO_URL="https://github.com/nilszeilon/synkade.git"  # adjust if different
APP_DIR="/opt/synkade"

echo "==> Installing system packages"
apt-get update
apt-get install -y git curl wget build-essential automake autoconf libncurses-dev \
  libssl-dev unzip

echo "==> Installing Erlang & Elixir via asdf"
if ! command -v asdf &>/dev/null; then
  git clone https://github.com/asdf-vm/asdf.git /opt/asdf --branch v0.14.1
  echo '. /opt/asdf/asdf.sh' >> /etc/profile.d/asdf.sh
  export PATH="/opt/asdf/bin:/opt/asdf/shims:$PATH"
  source /opt/asdf/asdf.sh
fi

asdf plugin add erlang || true
asdf plugin add elixir || true

# Install Erlang & Elixir (adjust versions as needed)
asdf install erlang 27.2
asdf install elixir 1.18.3-otp-27
asdf global erlang 27.2
asdf global elixir 1.18.3-otp-27

echo "==> Installing Caddy"
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

echo "==> Creating synkade user and directories"
useradd -r -m -d "$APP_DIR" -s /bin/bash synkade 2>/dev/null || true
mkdir -p "$APP_DIR"
chown synkade:synkade "$APP_DIR"

echo "==> Cloning repo"
if [ ! -d "$APP_DIR/repo" ]; then
  sudo -u synkade git clone "$REPO_URL" "$APP_DIR/repo"
fi

echo "==> Setting up env file"
if [ ! -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/repo/tools/deploy/env.example" "$APP_DIR/.env"
  chown synkade:synkade "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"

  # Auto-generate secrets
  SECRET_KEY_BASE=$(mix phx.gen.secret 2>/dev/null || openssl rand -base64 64 | tr -d '\n')
  ENCRYPTION_KEY=$(openssl rand -base64 32)
  WEBHOOK_SECRET=$(openssl rand -hex 32)

  sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY_BASE|" "$APP_DIR/.env"
  sed -i "s|^SETTINGS_ENCRYPTION_KEY=.*|SETTINGS_ENCRYPTION_KEY=$ENCRYPTION_KEY|" "$APP_DIR/.env"
  sed -i "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$WEBHOOK_SECRET|" "$APP_DIR/.env"

  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "IMPORTANT: Edit /opt/synkade/.env to set:"
  echo "  - DATABASE_PATH (SQLite database file path)"
  echo "  - Verify the auto-generated secrets"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
fi

echo "==> Installing webhook config"
# Read WEBHOOK_SECRET from .env and inject into hooks.json
source "$APP_DIR/.env"
cp "$APP_DIR/repo/tools/deploy/hooks.json" "$APP_DIR/hooks.json"
sed -i "s|WEBHOOK_SECRET_PLACEHOLDER|$WEBHOOK_SECRET|" "$APP_DIR/hooks.json"

echo "==> Installing deploy script"
cp "$APP_DIR/repo/tools/deploy/deploy.sh" "$APP_DIR/deploy.sh"
chmod +x "$APP_DIR/deploy.sh"

echo "==> Allow synkade user to restart its own service without password"
cat > /etc/sudoers.d/synkade << 'EOF'
synkade ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart synkade, /usr/bin/systemctl stop synkade, /usr/bin/systemctl start synkade
EOF

echo "==> Installing systemd services"
cp "$APP_DIR/repo/tools/deploy/synkade.service" /etc/systemd/system/
cp "$APP_DIR/repo/tools/deploy/webhook.service" /etc/systemd/system/

echo "==> Installing Caddy config"
cp "$APP_DIR/repo/tools/deploy/Caddyfile" /etc/caddy/Caddyfile

echo "==> Enabling services"
systemctl daemon-reload
systemctl enable synkade webhook caddy
systemctl start caddy
systemctl start webhook

echo "==> Running initial deploy"
sudo -u synkade bash "$APP_DIR/deploy.sh"

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Point synkade.com A record to this server's IP"
echo "  2. Edit /opt/synkade/.env if you haven't already"
echo "  3. Add GitHub webhook:"
echo "     URL: https://synkade.com/hooks/deploy"
echo "     Secret: (from /opt/synkade/.env WEBHOOK_SECRET)"
echo "     Events: Just the push event"
echo "  4. Caddy will auto-provision HTTPS once DNS propagates"
