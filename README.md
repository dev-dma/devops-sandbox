# DevOps Sandbox Platform

A self-service platform to spin up isolated temporary app environments,
simulate outages, monitor health, and auto-destroy environments on TTL expiry.

## Architecture
```
┌─────────────────────────────────────────────────────────┐
│                        HOST VM                          │
│  ┌──────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │ Control  │  │   Cleanup   │  │  Health Poller   │   │
│  │  API     │  │ (60s loop)  │  │  (30s loop)      │   │
│  └────┬─────┘  └──────┬──────┘  └────────┬─────────┘   │
│       └───────────────┼──────────────────┘              │
│  ╔════════════════════╪═════════════════════════════╗    │
│  ║      Docker (sandbox-main network)               ║    │
│  ║  ┌───────────┐  ┌──────────┐  ┌──────────┐     ║    │
│  ║  │   Nginx   │  │ app-env1 │  │ app-env2 │     ║    │
│  ║  │   :80     │  │  :3000   │  │  :3000   │     ║    │
│  ║  └─────┬─────┘  └──────────┘  └──────────┘     ║    │
│  ╚════════╪═════════════════════════════════════════╝    │
└───────────┼──────────────────────────────────────────────┘
            │
       Browser / curl
```
## Prerequisites

- Linux VM (Ubuntu 20.04+)
- Docker installed and running
- Python 3.8+
- Ports 80 and 5000 open

## Quick Start

```bash
git clone https://github.com/dev-dma/devops-sandbox && cd devops-sandbox
chmod +x platform/*.sh monitor/*.sh
pip3 install flask
make up
make create
```

## Known Limitations

- Single VM only — no multi-host support
- Path-based Nginx routing (not subdomain-based)
- No authentication on the control API
