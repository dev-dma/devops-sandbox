
# DevOps Sandbox Platform

A self-service platform to spin up isolated temporary app environments,
simulate outages, monitor health, and auto-destroy environments on TTL expiry.

## Architecture
┌─────────────────────────────────────────────────────────┐
│                        HOST VM                          │
│                                                         │
│  ┌──────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │ Control  │  │   Cleanup   │  │  Health Poller   │   │
│  │  API     │  │   Daemon    │  │  (monitor/)      │   │
│  │ :5000    │  │ (60s loop)  │  │  (30s loop)      │   │
│  └────┬─────┘  └──────┬──────┘  └────────┬─────────┘   │
│       └───────────────┼──────────────────┘             │
│                       │  calls bash scripts             │
│  ╔════════════════════╪════════════════════════════════╗ │
│  ║         Docker (sandbox-main network)               ║ │
│  ║                                                     ║ │
│  ║  ┌───────────┐  ┌──────────┐  ┌──────────┐        ║ │
│  ║  │   Nginx   │  │ app-env1 │  │ app-env2 │        ║ │
│  ║  │   :80     │  │  :3000   │  │  :3000   │        ║ │
│  ║  └─────┬─────┘  └──────────┘  └──────────┘        ║ │
│  ╚════════╪════════════════════════════════════════════╝ │
│           │ port 80                                     │
└───────────┼─────────────────────────────────────────────┘
            │
       Browser / curl

## Prerequisites

- Linux VM (Ubuntu 20.04+)
- Docker installed and running
- Python 3.8+
- `pip3 install flask`
- Ports 80 and 5000 open

## Quick Start (5 commands)

\`\`\`bash
git clone https://github.com/dev-dma/devops-sandbox && cd devops-sandbox
chmod +x platform/*.sh monitor/*.sh
pip3 install flask
make up
make create
\`\`\`

## Demo Walkthrough

\`\`\`bash
# 1. Create an environment (30 min TTL)
make create
# Enter name: myapp  |  TTL: 1800

# 2. Visit the app
curl http://localhost/env/<env-id>/
curl http://localhost/env/<env-id>/health

# 3. Check health status
make health

# 4. Simulate a crash
make simulate ENV=<env-id> MODE=crash

# 5. Watch it degrade (wait ~35s)
make health

# 6. Recover
make simulate ENV=<env-id> MODE=recover

# 7. Check logs
make logs ENV=<env-id>

# 8. Destroy
make destroy ENV=<env-id>
\`\`\`

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST   | \`/envs\`              | Create env (\`{"name":"x","ttl":1800}\`) |
| GET    | \`/envs\`              | List all envs + TTL remaining |
| DELETE | \`/envs/:id\`          | Destroy env |
| GET    | \`/envs/:id/logs\`     | Last 100 log lines |
| GET    | \`/envs/:id/health\`   | Last 10 health checks |
| POST   | \`/envs/:id/outage\`   | Simulate (\`{"mode":"crash"}\`) |

## All Make Targets

| Command | Description |
|---------|-------------|
| \`make up\` | Start Nginx + daemon + poller + API |
| \`make down\` | Stop everything + destroy all envs |
| \`make create\` | Create new env (interactive) |
| \`make destroy ENV=…\` | Destroy specific env |
| \`make logs ENV=…\` | Tail env logs |
| \`make health\` | Show all env health statuses |
| \`make simulate ENV=… MODE=…\` | Run outage simulation |
| \`make clean\` | Wipe all state and logs |

## Known Limitations

- Single VM only — no multi-host support
- Path-based Nginx routing (not subdomain-based)
- Log shipping uses \`docker logs -f\` (Approach A)
- No authentication on the control API
- Demo app image must be rebuilt after changes to \`demo-app/\`
EOF
