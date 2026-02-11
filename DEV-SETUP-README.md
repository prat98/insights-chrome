# Dual-Hub Local Development Environment

This guide explains how to set up a complete local development environment for testing Hub UI changes on console.redhat.com (Insights/CRC). It allows running **both** Hub frontends simultaneously for side-by-side comparison:

- **ansible-hub-ui** (old) → `/ansible/automation-hub`
- **aap-ui** (new) → `/ansible/automation-hub-new`

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Browser                                          │
│  https://stage.foo.redhat.com:1337/ansible/automation-hub[-new]         │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     insights-chrome (port 1337)                          │
│  • Dev server with HTTPS                                                 │
│  • Proxy routes requests to appropriate services                         │
│  • Provides Chrome shell (navigation, user menu, etc.)                   │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐    ┌───────────────────┐    ┌─────────────────────┐
│ config-proxy  │    │ /apps/automation- │    │ /apps/automation-   │
│   (9000)      │    │    hub (8002)     │    │    hub-new (8003)   │
│               │    │                   │    │                     │
│ Injects new   │    │  ansible-hub-ui   │    │  aap-ui             │
│ app into nav  │    │  (old frontend)   │    │  (new frontend)     │
└───────────────┘    └───────────────────┘    └─────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    /api/automation-hub → galaxy_ng (port 8080)           │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     Insights Auth Proxy (Go)                      │   │
│  │                     Simulates CRC authentication                   │   │
│  └──────────────────────────┬───────────────────────────────────────┘   │
│                             ▼                                            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────┐     │
│  │  API       │  │  Content   │  │  Worker    │  │  PostgreSQL    │     │
│  │  (Django)  │  │  (Pulp)    │  │  (Celery)  │  │  + Redis       │     │
│  └────────────┘  └────────────┘  └────────────┘  └────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

1. **Docker & Docker Compose** (v2.34.0+)
2. **Node.js 20.x+** and npm
3. **Git**

### Clone Required Repositories

All repositories should be in the same parent directory:

```bash
cd ~/code/RedHatInsights  # or your preferred location

git clone https://github.com/ansible/galaxy_ng.git
git clone https://github.com/ansible/ansible-hub-ui.git
git clone https://github.com/ansible/aap-ui.git
git clone https://github.com/RedHatInsights/insights-chrome.git
```

### Setup /etc/hosts

Add this line to `/etc/hosts`:

```
127.0.0.1 stage.foo.redhat.com prod.foo.redhat.com
```

### Interactive Setup

Run the setup script:

```bash
cd insights-chrome
./dev-setup.sh
```

This provides an interactive menu to:
- Check prerequisites
- Install all dependencies
- Start services

### Manual Setup

If you prefer manual control:

```bash
# 1. Install all dependencies
cd insights-chrome && npm ci --legacy-peer-deps
cd ../ansible-hub-ui && npm ci --legacy-peer-deps
cd ../aap-ui && npm ci --legacy-peer-deps
cd frontend/hub/insights && npm install --legacy-peer-deps

# 2. Start galaxy_ng backend
cd ../galaxy_ng
docker compose -f dev/compose/insights.yaml up --build

# 3. Wait for "READY" message, then in separate terminals:

# Terminal 2 - Config proxy (injects automation-hub-new)
cd insights-chrome
node local-config-proxy.js

# Terminal 3 - Old frontend
cd ansible-hub-ui
npm run start-insights

# Terminal 4 - New frontend
cd aap-ui/frontend/hub/insights
APP_NAME=automation-hub-new UI_PORT=8003 npm start

# Terminal 5 - insights-chrome
cd insights-chrome
NAV_CONFIG=9000 npm run dev
```

## Accessing the UIs

After all services are running:

| UI | URL |
|---|---|
| Old Hub | https://stage.foo.redhat.com:1337/ansible/automation-hub |
| New Hub | https://stage.foo.redhat.com:1337/ansible/automation-hub-new |

### Test Credentials

- `org-admin` / `redhat` - Organization admin user
- `jdoe` / `redhat` - Regular user

## Docker Compose Options

### Start Backend Only (Recommended)

Run frontends locally with npm for hot reload:

```bash
cd insights-chrome
docker compose -f docker-compose.dev.yaml up --build \
    postgres redis galaxy-base galaxy-base-dev galaxy-migrations \
    galaxy-api galaxy-content galaxy-worker galaxy-proxy config-proxy
```

### Start Everything with Docker

Run all services in Docker (slower, no hot reload for frontends):

```bash
cd insights-chrome
docker compose -f docker-compose.dev.yaml --profile frontends up --build
```

### Stop Services

```bash
docker compose -f docker-compose.dev.yaml --profile frontends down
```

### Reset Database

```bash
docker compose -f docker-compose.dev.yaml --profile frontends down -v
```

## Configuration

### insights-chrome webpack routes

The proxy routes in `config/webpack.config.js`:

```javascript
routes: {
  // New frontend (must come first - uses includes() matching)
  '/apps/automation-hub-new': { host: 'http://localhost:8003' },
  // Old frontend  
  '/apps/automation-hub': { host: 'http://localhost:8002' },
  // API proxy to galaxy_ng
  '/api/automation-hub': { host: 'http://localhost:8080' },
}
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAV_CONFIG` | - | Port for config proxy (use 9000) |
| `APP_NAME` | `automation-hub` | Set to `automation-hub-new` for new UI |
| `UI_PORT` | `8002` | Frontend dev server port |
| `DEV_SOURCE_PATH` | - | Enable hot reload for Python code |

## Troubleshooting

### "Connection refused" for API calls

Check that galaxy_ng proxy is running on port 8080:

```bash
curl http://localhost:8080/api/automation-hub/
```

### "automation-hub-new" not appearing in navigation

Ensure config-proxy is running and insights-chrome is started with `NAV_CONFIG=9000`:

```bash
# Check config proxy
curl http://localhost:9000/api/chrome-service/v1/static/stable/prod/navigation/ansible-navigation.json

# Should see "automationHubNew" in the response
```

### SSL Certificate Warning

This is expected. Click "Advanced" → "Proceed to stage.foo.redhat.com".

### Docker build fails

```bash
# Clean up and rebuild
docker compose -f docker-compose.dev.yaml down -v
docker system prune -f
docker compose -f docker-compose.dev.yaml up --build
```

### Hot reload not working

For Python code changes in galaxy_ng:

```bash
DEV_SOURCE_PATH=galaxy_ng docker compose -f dev/compose/insights.yaml up
```

For frontend changes, ensure you're running with npm directly (not Docker).

## Sharing with Team Members

To share this setup with a team member:

1. **Share the repository URLs** they need to clone
2. **Share any local code changes** via:
   - Git branch/PR
   - Patch files: `git diff > my-changes.patch`
   - Direct file sharing

3. **They run the setup**:
   ```bash
   cd insights-chrome
   ./dev-setup.sh
   ```

4. **Apply any patches**:
   ```bash
   git apply my-changes.patch
   ```

### Creating a Development Package

To create a tarball of your changes for offline sharing:

```bash
# From parent directory containing all repos
tar -czvf hub-dev-$(date +%Y%m%d).tar.gz \
    --exclude='*/node_modules' \
    --exclude='*/.git' \
    --exclude='*/dist' \
    --exclude='*/__pycache__' \
    galaxy_ng ansible-hub-ui aap-ui insights-chrome
```

## File Reference

| File | Purpose |
|------|---------|
| `docker-compose.dev.yaml` | Full stack Docker Compose |
| `dev-setup.sh` | Interactive setup script |
| `local-config-proxy.js` | Injects automation-hub-new into chrome config |
| `start-dual-hub.sh` | Quick start instructions |
| `config/webpack.config.js` | Chrome proxy configuration |

## Related Documentation

- [galaxy_ng development](../galaxy_ng/dev/compose/README.md)
- [aap-ui insights build](../aap-ui/frontend/hub/insights/README.md)
- [ansible-hub-ui development](../ansible-hub-ui/README.md)

