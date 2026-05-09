# DevOps Sandbox Platform — Makefile
# Every action has a target. Run `make help` to see them all.

.PHONY: help up down build-demo create destroy logs health simulate clean \
        _network _nginx _stop-services

ROOT_DIR       := $(shell pwd)
PLATFORM_DIR   := $(ROOT_DIR)/platform
NGINX_CONTAINER := sandbox-nginx
MAIN_NETWORK   := sandbox-main
API_PORT       := 5000

# ─────────────────────────────────────────────────────────────────────────────
## help: Show all available targets
help:
	@echo "╔══════════════════════════════════════════════════════╗"
	@echo "║        DevOps Sandbox Platform — Make Targets        ║"
	@echo "╚══════════════════════════════════════════════════════╝"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  make /'

# ─────────────────────────────────────────────────────────────────────────────
## up: Start Nginx, cleanup daemon, health poller, and control API
up: build-demo _network _nginx
	@mkdir -p logs envs nginx/conf.d
	@echo "🚀 Starting background services..."
	@nohup bash $(PLATFORM_DIR)/cleanup_daemon.sh > /dev/null 2>&1 & echo $$! > .daemon.pid
	@echo "  ✔ Cleanup daemon started (PID: $$(cat .daemon.pid))"
	@nohup bash monitor/health_poller.sh > /dev/null 2>&1 & echo $$! > .monitor.pid
	@echo "  ✔ Health poller started  (PID: $$(cat .monitor.pid))"
	@nohup python3 $(PLATFORM_DIR)/api.py > logs/api.log 2>&1 & echo $$! > .api.pid
	@echo "  ✔ Control API started    (PID: $$(cat .api.pid))"
	@echo ""
	@echo "✅ Platform is UP"
	@echo "   Web (Nginx): http://localhost"
	@echo "   API:         http://localhost:$(API_PORT)"
	@echo "   API health:  http://localhost:$(API_PORT)/health"

## build-demo: Build the demo app Docker image
build-demo:
	@echo "🔨 Building demo app image (sandbox-demo-app)..."
	@docker build -t sandbox-demo-app demo-app/ -q
	@echo "  ✔ Image built"

## down: Stop all services and destroy all active environments
down: _stop-services
	@echo "🛑 Destroying all active environments..."
	@bash -c '\
		shopt -s nullglob; \
		for f in envs/*.json; do \
			[ -f "$$f" ] || continue; \
			ENV_ID=$$(python3 -c "import json; print(json.load(open(\"$$f\"))[\"id\"])") && \
			bash $(PLATFORM_DIR)/destroy_env.sh "$$ENV_ID" || true; \
		done'
	@docker rm -f $(NGINX_CONTAINER) > /dev/null 2>&1 || true
	@echo "✅ Platform is DOWN"

_stop-services:
	@echo "🛑 Stopping background services..."
	@for PF in .daemon.pid .monitor.pid .api.pid; do \
		[ -f "$$PF" ] && kill $$(cat $$PF) 2>/dev/null || true; \
		rm -f "$$PF"; \
	done

## create: Create a new environment (prompts for name and TTL)
create:
	@bash -c 'read -p "Environment name: " NAME; \
		read -p "TTL in seconds [1800]: " TTL; \
		TTL=$${TTL:-1800}; \
		bash $(PLATFORM_DIR)/create_env.sh "$$NAME" "$$TTL"'

## destroy: Destroy a specific environment  (usage: make destroy ENV=env-xxxx)
destroy:
	@test -n "$(ENV)" || (echo "❌ Usage: make destroy ENV=<env-id>" && exit 1)
	@bash $(PLATFORM_DIR)/destroy_env.sh $(ENV)

## logs: Tail an environment's app log  (usage: make logs ENV=env-xxxx)
logs:
	@test -n "$(ENV)" || (echo "❌ Usage: make logs ENV=<env-id>" && exit 1)
	@bash -c '\
		ACTIVE="logs/$(ENV)/app.log"; \
		ARCHIVED="logs/archived/$(ENV)/app.log"; \
		if [ -f "$$ACTIVE" ]; then tail -f "$$ACTIVE"; \
		elif [ -f "$$ARCHIVED" ]; then tail -f "$$ARCHIVED"; \
		else echo "No logs found for $(ENV)"; fi'

## health: Show health status of all active environments
health:
	@echo "═══════════════════════════════════════════════"
	@echo "        Environment Health Status"
	@echo "═══════════════════════════════════════════════"
	@bash -c '\
		shopt -s nullglob; \
		COUNT=0; \
		for f in envs/*.json; do \
			[ -f "$$f" ] || continue; \
			COUNT=$$((COUNT+1)); \
			python3 -c "\
import json,time; \
d=json.load(open(\"$$f\")); \
remaining=max(0,d[\"created_at\"]+d[\"ttl\"]-int(time.time())); \
status_icon={\"running\":\"🟢\",\"degraded\":\"🔴\"}.get(d[\"status\"],\"🟡\"); \
print(f\"  \$$status_icon  {d[\"id\"]}  |  {d[\"name\"]}  |  status={d[\"status\"]}  |  ttl_remaining={remaining}s\")"; \
		done; \
		[ "$$COUNT" -eq 0 ] && echo "  (no active environments)" || true'

## simulate: Run an outage simulation  (usage: make simulate ENV=env-xxxx MODE=crash)
simulate:
	@test -n "$(ENV)"  || (echo "❌ Usage: make simulate ENV=<env-id> MODE=<mode>" && exit 1)
	@test -n "$(MODE)" || (echo "❌ Usage: make simulate ENV=<env-id> MODE=<mode>" && exit 1)
	@bash $(PLATFORM_DIR)/simulate_outage.sh --env $(ENV) --mode $(MODE)

## clean: Wipe ALL state, logs, configs (destructive!)
clean: down
	@echo "🧹 Wiping all state..."
	@rm -rf logs/* envs/* nginx/conf.d/*.conf
	@echo "✅ Clean complete"

# ── Internal: create Docker network (idempotent) ─────────────────────────────
_network:
	@docker network inspect $(MAIN_NETWORK) > /dev/null 2>&1 \
		|| (docker network create $(MAIN_NETWORK) > /dev/null && echo "  ✔ Network created: $(MAIN_NETWORK)")

# ── Internal: start Nginx container ──────────────────────────────────────────
_nginx:
	@mkdir -p nginx/conf.d
	@docker rm -f $(NGINX_CONTAINER) > /dev/null 2>&1 || true
	@docker run -d \
		--name $(NGINX_CONTAINER) \
		--network $(MAIN_NETWORK) \
		-p 80:80 \
		-v $(ROOT_DIR)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(ROOT_DIR)/nginx/conf.d:/etc/nginx/conf.d \
		nginx:alpine > /dev/null
	@echo "  ✔ Nginx container started"
