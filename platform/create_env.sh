#!/usr/bin/env bash
# create_env.sh — Spin up a new isolated environment
# Usage: bash platform/create_env.sh <name> [ttl-in-seconds]

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$ROOT_DIR/envs"
NGINX_CONF_D="$ROOT_DIR/nginx/conf.d"
LOGS_DIR="$ROOT_DIR/logs"

# ── Config ────────────────────────────────────────────────────────────────────
NGINX_CONTAINER="sandbox-nginx"
MAIN_NETWORK="sandbox-main"
APP_INTERNAL_PORT=3000
DEFAULT_TTL=1800

# ── Arguments ────────────────────────────────────────────────────────────────
ENV_NAME="${1:-}"
TTL="${2:-$DEFAULT_TTL}"

if [[ -z "$ENV_NAME" ]]; then
  echo "❌ Usage: $0 <env-name> [ttl-seconds]"
  exit 1
fi

# ── Generate unique ID (e.g. env-a3f2b891) ───────────────────────────────────
ENV_ID="env-$(openssl rand -hex 4)"
CONTAINER_NAME="sandbox-app-$ENV_ID"
ENV_NETWORK="sandbox-net-$ENV_ID"
STATE_FILE="$ENVS_DIR/$ENV_ID.json"
LOG_DIR="$LOGS_DIR/$ENV_ID"

echo "🚀 Creating environment '$ENV_NAME' (ID: $ENV_ID)..."

# ── Create directories ────────────────────────────────────────────────────────
mkdir -p "$ENVS_DIR" "$LOG_DIR" "$NGINX_CONF_D"

# ── Create dedicated Docker network ──────────────────────────────────────────
docker network create "$ENV_NETWORK" > /dev/null
echo "  ✔ Network created: $ENV_NETWORK"

# ── Start app container ───────────────────────────────────────────────────────
docker run -d \
  --name "$CONTAINER_NAME" \
  --network "$MAIN_NETWORK" \
  --label "sandbox.env=$ENV_ID" \
  --label "sandbox.name=$ENV_NAME" \
  -e ENV_ID="$ENV_ID" \
  -e ENV_NAME="$ENV_NAME" \
  --restart unless-stopped \
  sandbox-demo-app > /dev/null

# Also attach to the env-specific network (for isolation features)
docker network connect "$ENV_NETWORK" "$CONTAINER_NAME"
echo "  ✔ Container started: $CONTAINER_NAME"

# ── Start log shipping (Approach A) ───────────────────────────────────────────
docker logs -f "$CONTAINER_NAME" >> "$LOG_DIR/app.log" 2>&1 &
LOG_PID=$!
echo "$LOG_PID" > "$LOG_DIR/log_shipper.pid"
echo "  ✔ Log shipper started (PID: $LOG_PID)"

# ── Write Nginx config ────────────────────────────────────────────────────────
cat > "$NGINX_CONF_D/$ENV_ID.conf" <<EOF
location /env/$ENV_ID/ {
    proxy_pass         http://$CONTAINER_NAME:$APP_INTERNAL_PORT/;
    proxy_set_header   Host              \$host;
    proxy_set_header   X-Real-IP         \$remote_addr;
    proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_connect_timeout 5s;
    proxy_read_timeout    30s;
}
EOF

docker exec "$NGINX_CONTAINER" nginx -s reload
echo "  ✔ Nginx route registered"

# ── Write state file (atomically: write to temp, then mv) ─────────────────────
CREATED_AT=$(date +%s)
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" <<EOF
{
  "id":             "$ENV_ID",
  "name":           "$ENV_NAME",
  "created_at":     $CREATED_AT,
  "ttl":            $TTL,
  "status":         "running",
  "container_name": "$CONTAINER_NAME",
  "network":        "$ENV_NETWORK",
  "log_pid":        $LOG_PID
}
EOF
mv "$TEMP_FILE" "$STATE_FILE"
echo "  ✔ State file written"

# ── Print summary ─────────────────────────────────────────────────────────────
TTL_MIN=$(( TTL / 60 ))
echo ""
echo "✅ Environment ready!"
echo "   ENV_ID:  $ENV_ID"
echo "   URL:     http://localhost/env/$ENV_ID/"
echo "   Health:  http://localhost/env/$ENV_ID/health"
echo "   TTL:     ${TTL_MIN} minutes"
echo "   Logs:    make logs ENV=$ENV_ID"
