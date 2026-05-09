#!/usr/bin/env bash
# health_poller.sh — Polls /health on each active environment every 30s
# Marks environment as "degraded" after 3 consecutive failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$ROOT_DIR/envs"
LOGS_DIR="$ROOT_DIR/logs"
POLL_INTERVAL=30
FAILURE_THRESHOLD=3

# Associative array to track per-env failure counts
declare -A FAILURE_COUNTS

# Write a timestamped line to the env's health log
log_health() {
  local env_id="$1" http_code="$2" latency="$3"
  local log_file="$LOGS_DIR/$env_id/health.log"
  mkdir -p "$(dirname "$log_file")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] status=$http_code latency=${latency}ms" >> "$log_file"
}

# Update the status field inside the JSON state file
update_status() {
  local env_id="$1" new_status="$2"
  local state_file="$ENVS_DIR/$env_id.json"
  [[ -f "$state_file" ]] || return

  local tmp
  tmp=$(mktemp)
  python3 - <<EOF
import json
with open("$state_file") as f:
    d = json.load(f)
d["status"] = "$new_status"
with open("$tmp", "w") as f:
    json.dump(d, f, indent=2)
EOF
  mv "$tmp" "$state_file"
}

echo "🔍 Health poller started (checking every ${POLL_INTERVAL}s)"

while true; do
  shopt -s nullglob
  for STATE_FILE in "$ENVS_DIR"/*.json; do
    [[ -f "$STATE_FILE" ]] || continue

    ENV_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['id'])" 2>/dev/null)             || continue
    CONTAINER_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['container_name'])" 2>/dev/null) || continue

    # Skip if container is not running
    if ! docker inspect --format='{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
      COUNT=${FAILURE_COUNTS[$ENV_ID]:-0}
      COUNT=$(( COUNT + 1 ))
      FAILURE_COUNTS[$ENV_ID]=$COUNT
      log_health "$ENV_ID" "000" "0"
      if (( COUNT >= FAILURE_THRESHOLD )); then
        echo "⚠️  WARNING: $ENV_ID container is not running ($COUNT failures)"
        update_status "$ENV_ID" "degraded"
      fi
      continue
    fi

    # Hit the /health endpoint through Nginx
    URL="http://localhost/env/$ENV_ID/health"
    START_MS=$(date +%s%3N)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL" 2>/dev/null || echo "000")
    END_MS=$(date +%s%3N)
    LATENCY=$(( END_MS - START_MS ))

    log_health "$ENV_ID" "$HTTP_CODE" "$LATENCY"

    if [[ "$HTTP_CODE" == "200" ]]; then
      FAILURE_COUNTS[$ENV_ID]=0
      update_status "$ENV_ID" "running"
    else
      COUNT=${FAILURE_COUNTS[$ENV_ID]:-0}
      COUNT=$(( COUNT + 1 ))
      FAILURE_COUNTS[$ENV_ID]=$COUNT

      if (( COUNT >= FAILURE_THRESHOLD )); then
        echo "⚠️  WARNING: $ENV_ID — $COUNT consecutive failures (HTTP $HTTP_CODE)"
        update_status "$ENV_ID" "degraded"
      fi
    fi
  done
  shopt -u nullglob

  sleep "$POLL_INTERVAL"
done
