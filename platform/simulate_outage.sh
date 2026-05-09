#!/usr/bin/env bash
# simulate_outage.sh — Inject failures into a running environment
# Usage: bash platform/simulate_outage.sh --env <id> --mode <crash|pause|network|recover|stress>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$ROOT_DIR/envs"
MAIN_NETWORK="sandbox-main"

# ── Parse --env and --mode flags ─────────────────────────────────────────────
ENV_ID=""
MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)  ENV_ID="$2";  shift 2 ;;
    --mode) MODE="$2";    shift 2 ;;
    *) echo "❌ Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ -z "$ENV_ID" || -z "$MODE" ]]; then
  echo "❌ Usage: $0 --env <env-id> --mode <crash|pause|network|recover|stress>"
  exit 1
fi

STATE_FILE="$ENVS_DIR/$ENV_ID.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ Environment $ENV_ID not found"
  exit 1
fi

CONTAINER_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['container_name'])")
ENV_NETWORK=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['network'])")

# ── GUARD: Never simulate on platform containers ──────────────────────────────
PROTECTED=("sandbox-nginx" "sandbox-api" "sandbox-monitor" "sandbox-daemon")
for P in "${PROTECTED[@]}"; do
  if [[ "$CONTAINER_NAME" == "$P" ]]; then
    echo "🚫 BLOCKED: Cannot simulate outage on protected container '$P'"
    exit 1
  fi
done

echo "⚡ Simulating mode='$MODE' on container '$CONTAINER_NAME'..."

case "$MODE" in
  crash)
    docker kill "$CONTAINER_NAME"
    echo "💥 Container killed. Health monitor will detect within 90s."
    ;;

  pause)
    docker pause "$CONTAINER_NAME"
    echo "⏸️  Container paused. All processes frozen."
    echo "   Recover with: make simulate ENV=$ENV_ID MODE=recover"
    ;;

  network)
    docker network disconnect "$MAIN_NETWORK" "$CONTAINER_NAME"
    echo "🔌 Disconnected from main network. Nginx can no longer reach it."
    echo "   Recover with: make simulate ENV=$ENV_ID MODE=recover"
    ;;

  recover)
    echo "🔧 Attempting recovery..."
    # Restart if stopped/killed
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")
    if [[ "$STATUS" == "exited" || "$STATUS" == "dead" ]]; then
      docker start "$CONTAINER_NAME"
      echo "  ✔ Container restarted"
    fi
    # Unpause if paused
    if docker inspect --format='{{.State.Paused}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
      docker unpause "$CONTAINER_NAME"
      echo "  ✔ Container unpaused"
    fi
    # Reconnect to main network if disconnected
    if ! docker network inspect "$MAIN_NETWORK" --format='{{range .Containers}}{{.Name}} {{end}}' \
        | grep -q "$CONTAINER_NAME"; then
      docker network connect "$MAIN_NETWORK" "$CONTAINER_NAME"
      echo "  ✔ Reconnected to $MAIN_NETWORK"
    fi
    echo "✅ Recovery complete for $ENV_ID"
    ;;

  stress)
    if docker exec "$CONTAINER_NAME" which stress-ng > /dev/null 2>&1; then
      docker exec -d "$CONTAINER_NAME" stress-ng --cpu 2 --timeout 60s
      echo "📈 CPU stress started for 60 seconds inside container"
    else
      echo "⚠️  stress-ng not found in container. Installing and retrying..."
      docker exec "$CONTAINER_NAME" apt-get install -y stress-ng -q > /dev/null 2>&1 && \
        docker exec -d "$CONTAINER_NAME" stress-ng --cpu 2 --timeout 60s || \
        echo "  Could not install stress-ng. Skipping."
    fi
    ;;

  *)
    echo "❌ Unknown mode: '$MODE'"
    echo "   Valid modes: crash, pause, network, recover, stress"
    exit 1
    ;;
esac
