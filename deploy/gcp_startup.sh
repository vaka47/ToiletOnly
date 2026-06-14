#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
APP_DIR="/opt/ToiletOnly"
DEPLOY_DIR="$APP_DIR/deploy"
PUBLIC_HOST="toiletonly-35-192-233-44.sslip.io"
POSTGRES_PASSWORD="$(openssl rand -hex 16)"
JWT_SECRET="$(openssl rand -hex 32)"

apt-get update
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  caddy \
  curl \
  debian-archive-keyring \
  debian-keyring \
  docker-compose \
  docker.io \
  git \
  gnupg \
  openssl

systemctl enable --now docker
systemctl enable --now caddy

if [ ! -d "$APP_DIR/.git" ]; then
  git clone https://github.com/vaka47/ToiletOnly.git "$APP_DIR"
else
  git -C "$APP_DIR" fetch --all
  git -C "$APP_DIR" reset --hard origin/main
fi

cat > "$DEPLOY_DIR/.env.production" <<EOF
ENVIRONMENT=production
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DATABASE_URL=postgresql+asyncpg://toiletonly:$POSTGRES_PASSWORD@postgres:5432/toiletonly
REDIS_URL=redis://redis:6379/0
JWT_SECRET=$JWT_SECRET
JWT_ISSUER=toiletonly
JWT_AUDIENCE=toiletonly-app
MEDIA_STORAGE_PATH=/app/uploads
MEDIA_PUBLIC_URL=https://$PUBLIC_HOST/media
APPLE_CLIENT_ID=com.toiletonly.app
ALLOW_DEV_APPLE_SUB_TOKENS=false
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_BUNDLE_ID=com.toiletonly.app
APNS_PRIVATE_KEY=
APNS_USE_SANDBOX=false
DB_POOL_SIZE=20
DB_MAX_OVERFLOW=40
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE_SECONDS=1800
EOF

cat > /etc/caddy/Caddyfile <<EOF
$PUBLIC_HOST {
  encode gzip
  reverse_proxy 127.0.0.1:8000
}
EOF

systemctl reload caddy || systemctl restart caddy

cd "$DEPLOY_DIR"
if docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose --env-file .env.production -f docker-compose.prod.yml up -d --build
else
  echo "No Docker Compose command is available" >&2
  exit 1
fi
