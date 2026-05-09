#!/usr/bin/env bash
# destroy_env.sh — Tear down an environment completely
# Usage: bash platform/destroy_env.sh <env-id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$ROOT_DIR/envs"
NGINX_CONF_D="$ROOT_DIR/nginx/conf.d"
LOGS_DIR="$ROOT_DIR/logs"
NGINX_CONTAINER="sandbox-nginx"

ENV_ID="${1:-}"
if [[ -z "$ENV_ID" ]]; then
  echo "❌ Usage: $0 <env-id>"
  exit 1
fi

STATE_FILE="$ENVS_DIR/$ENV_ID.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ Environment $ENV_ID not found (state file missing)"
  exit 1
fi

echo "🗑️  Destroying environment: $ENV_ID..."

# ── Read state ────────────────────────────────────────────────────────────────
CONTAINER_NAME=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['container_name'])")
ENV_NETWORK=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['network'])")

LOG_DIR="$LOGS_DIR/$ENV_ID"
ARCHIVE_DIR="$LOGS_DIR/archived/$ENV_ID"

# ── Kill log shipper (prevents zombie processes) ───────────────────────────────
PID_FILE="$LOG_DIR/log_shipper.pid"
if [[ -f "$PID_FILE" ]]; then
  LPID=$(cat "$PID_FILE")
  if kill -0 "$LPID" 2>/dev/null; then
    kill "$LPID"
    echo "  ✔ Log shipper stopped (PID: $LPID)"
  fi
  rm -f "$PID_FILE"
fi

# ── Stop and remove all containers with this env's label ─────────────────────
CONTAINERS=$(docker ps -aq --filter "label=sandbox.env=$ENV_ID")
if [[ -n "$CONTAINERS" ]]; then
  echo "$CONTAINERS" | xargs docker rm -f > /dev/null 2>&1
  echo "  ✔ Containers removed"
fi

# ── Remove env-specific Docker network ───────────────────────────────────────
if docker network inspect "$ENV_NETWORK" > /dev/null 2>&1; then
  docker network rm "$ENV_NETWORK" > /dev/null 2>&1 || true
  echo "  ✔ Network removed: $ENV_NETWORK"
fi

# ── Delete Nginx config and reload ───────────────────────────────────────────
NGINX_CONF="$NGINX_CONF_D/$ENV_ID.conf"
if [[ -f "$NGINX_CONF" ]]; then
  rm -f "$NGINX_CONF"
  docker exec "$NGINX_CONTAINER" nginx -s reload 2>/dev/null || true
  echo "  ✔ Nginx route removed"
fi

# ── Archive logs ──────────────────────────────────────────────────────────────
if [[ -d "$LOG_DIR" ]]; then
  mkdir -p "$ARCHIVE_DIR"
  cp -r "$LOG_DIR/." "$ARCHIVE_DIR/"
  rm -rf "$LOG_DIR"
  echo "  ✔ Logs archived to $ARCHIVE_DIR"
fi

# ── Delete state file ─────────────────────────────────────────────────────────
rm -f "$STATE_FILE"

echo "✅ Environment $ENV_ID destroyed"
