#!/usr/bin/env python3
"""
DevOps Sandbox Control API
6 REST endpoints that wrap the bash scripts.
Run with: python3 platform/api.py
"""

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Optional

from flask import Flask, jsonify, request

app = Flask(__name__)

# ── Paths ────────────────────────────────────────────────────────────────────
ROOT      = Path(__file__).parent.parent
ENVS_DIR  = ROOT / "envs"
LOGS_DIR  = ROOT / "logs"
PLATFORM  = ROOT / "platform"


# ── Helpers ──────────────────────────────────────────────────────────────────

def read_state(env_id: str) -> Optional[dict]:
    """Load a state file, or return None if missing/corrupt."""
    state_file = ENVS_DIR / f"{env_id}.json"
    if not state_file.exists():
        return None
    try:
        with open(state_file) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def ttl_remaining(state: dict) -> int:
    return max(0, state["created_at"] + state["ttl"] - int(time.time()))


def run_script(script: str, args: list) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(PLATFORM / script)] + args,
        capture_output=True,
        text=True,
        timeout=60
    )


# ── Routes ───────────────────────────────────────────────────────────────────

@app.route("/envs", methods=["POST"])
def create_env():
    """POST /envs — Create a new environment."""
    body = request.get_json(silent=True) or {}
    name = body.get("name", "").strip()
    ttl  = int(body.get("ttl", 1800))

    if not name:
        return jsonify({"error": "name is required"}), 400

    result = run_script("create_env.sh", [name, str(ttl)])

    if result.returncode != 0:
        return jsonify({"error": result.stderr.strip()}), 500

    # Extract ENV_ID from script stdout
    env_id = None
    for line in result.stdout.splitlines():
        if "ENV_ID:" in line:
            env_id = line.split("ENV_ID:")[1].strip()
            break

    if not env_id:
        return jsonify({"error": "Failed to parse env ID", "output": result.stdout}), 500

    state = read_state(env_id)
    return jsonify({
        "id":            env_id,
        "name":          name,
        "url":           f"http://localhost/env/{env_id}/",
        "ttl_remaining": ttl_remaining(state) if state else ttl,
        "status":        state["status"] if state else "starting"
    }), 201


@app.route("/envs", methods=["GET"])
def list_envs():
    """GET /envs — List all active environments with TTL remaining."""
    envs = []
    for state_file in sorted(ENVS_DIR.glob("*.json")):
        try:
            with open(state_file) as f:
                state = json.load(f)
            envs.append({
                "id":            state["id"],
                "name":          state["name"],
                "status":        state["status"],
                "ttl_remaining": ttl_remaining(state),
                "url":           f"http://localhost/env/{state['id']}/"
            })
        except (json.JSONDecodeError, KeyError, OSError):
            continue

    return jsonify({"envs": envs, "count": len(envs)})


@app.route("/envs/<env_id>", methods=["DELETE"])
def destroy_env(env_id: str):
    """DELETE /envs/:id — Destroy a specific environment."""
    if not read_state(env_id):
        return jsonify({"error": f"Environment '{env_id}' not found"}), 404

    result = run_script("destroy_env.sh", [env_id])

    if result.returncode != 0:
        return jsonify({"error": result.stderr.strip()}), 500

    return jsonify({"message": f"Environment '{env_id}' destroyed successfully"})


@app.route("/envs/<env_id>/logs", methods=["GET"])
def get_logs(env_id: str):
    """GET /envs/:id/logs — Last 100 lines of app.log."""
    active   = LOGS_DIR / env_id / "app.log"
    archived = LOGS_DIR / "archived" / env_id / "app.log"
    target   = active if active.exists() else archived if archived.exists() else None

    if not target:
        return jsonify({"error": "Log file not found for this environment"}), 404

    result = subprocess.run(["tail", "-n", "100", str(target)],
                            capture_output=True, text=True)
    return jsonify({"env_id": env_id, "lines": result.stdout.splitlines()})


@app.route("/envs/<env_id>/health", methods=["GET"])
def get_health(env_id: str):
    """GET /envs/:id/health — Last 10 health check results."""
    state      = read_state(env_id)
    health_log = LOGS_DIR / env_id / "health.log"

    checks = []
    if health_log.exists():
        result = subprocess.run(["tail", "-n", "10", str(health_log)],
                                capture_output=True, text=True)
        for line in result.stdout.splitlines():
            # Format: [2026-05-09 12:00:00] status=200 latency=14ms
            parts = line.split("] ", 1)
            if len(parts) == 2:
                ts, rest = parts[0].lstrip("["), parts[1]
                entry = {"timestamp": ts}
                for kv in rest.split():
                    k, _, v = kv.partition("=")
                    entry[k] = v
                checks.append(entry)

    return jsonify({
        "env_id":  env_id,
        "status":  state["status"] if state else "unknown",
        "checks":  checks
    })


@app.route("/envs/<env_id>/outage", methods=["POST"])
def trigger_outage(env_id: str):
    """POST /envs/:id/outage — Trigger an outage simulation."""
    if not read_state(env_id):
        return jsonify({"error": f"Environment '{env_id}' not found"}), 404

    body = request.get_json(silent=True) or {}
    mode = body.get("mode", "").strip()

    if not mode:
        return jsonify({"error": "mode is required (crash|pause|network|recover|stress)"}), 400

    result = run_script("simulate_outage.sh", ["--env", env_id, "--mode", mode])

    if result.returncode != 0:
        return jsonify({"error": result.stderr.strip()}), 500

    return jsonify({"env_id": env_id, "mode": mode, "result": result.stdout.strip()})


@app.route("/health", methods=["GET"])
def api_health():
    """API self-health check."""
    return jsonify({"status": "ok", "service": "sandbox-control-api"})


# ── Start ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    ENVS_DIR.mkdir(exist_ok=True)
    LOGS_DIR.mkdir(exist_ok=True)
    print("🖥️  Sandbox Control API running on http://0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
