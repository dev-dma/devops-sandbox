#!/usr/bin/env bash
# cleanup_daemon.sh — Background process that auto-destroys expired environments
# Run with: nohup bash platform/cleanup_daemon.sh &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$ROOT_DIR/envs"
LOG_FILE="$ROOT_DIR/logs/cleanup.log"
DESTROY_SCRIPT="$SCRIPT_DIR/destroy_env.sh"
SLEEP_INTERVAL=60

mkdir -p "$(dirname "$LOG_FILE")"

# Helper: write a timestamped log line
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "🔄 Cleanup daemon started (PID $$)"

while true; do
  NOW=$(date +%s)

  # nullglob: if envs/ is empty, the loop just doesn't run
  shopt -s nullglob
  for STATE_FILE in "$ENVS_DIR"/*.json; do
    [[ -f "$STATE_FILE" ]] || continue

    # Safely parse values — skip file if malformed
    ENV_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['id'])" 2>/dev/null)       || continue
    CREATED_AT=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['created_at'])" 2>/dev/null) || continue
    TTL=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['ttl'])" 2>/dev/null)          || continue

    EXPIRES_AT=$(( CREATED_AT + TTL ))
    REMAINING=$(( EXPIRES_AT - NOW ))

    if (( NOW >= EXPIRES_AT )); then
      log "⏰ TTL expired for $ENV_ID — destroying now"
      if bash "$DESTROY_SCRIPT" "$ENV_ID" >> "$LOG_FILE" 2>&1; then
        log "✅ Successfully destroyed $ENV_ID"
      else
        log "❌ Failed to destroy $ENV_ID"
      fi
    else
      log "ℹ️  $ENV_ID — ${REMAINING}s remaining"
    fi
  done
  shopt -u nullglob

  sleep "$SLEEP_INTERVAL"
done
