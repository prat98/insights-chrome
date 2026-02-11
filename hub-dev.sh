#!/bin/bash
#
# Hub Development Environment Manager
#
# Single script to build, run, and manage the dual-hub development stack.
#
# Usage:
#   ./hub-dev.sh build                        # Build from local repos
#   ./hub-dev.sh build --remote               # Build from GitHub
#   ./hub-dev.sh build --remote --aap-ui=my-branch --galaxy-ng=main
#   ./hub-dev.sh start                        # Start all services
#   ./hub-dev.sh stop                         # Stop all services
#   ./hub-dev.sh status                       # Show service status
#   ./hub-dev.sh logs                         # Tail all logs
#   ./hub-dev.sh logs chrome                  # Tail specific service
#   ./hub-dev.sh user                         # Switch user interactively
#   ./hub-dev.sh user org-admin               # Switch user directly
#   ./hub-dev.sh clean                        # Stop and remove everything
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Detect container runtime
if podman --version &>/dev/null; then
    RUNTIME="podman"
    # Check for podman machine on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        SOCKET=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)
        if [ -n "$SOCKET" ]; then
            export DOCKER_HOST="unix://$SOCKET"
        fi
    fi
elif docker --version &>/dev/null; then
    RUNTIME="docker"
else
    echo -e "${RED}Error: Neither podman nor docker found${NC}"
    exit 1
fi

COMPOSE="$RUNTIME compose"

# Compose files
LOCAL_COMPOSE="$SCRIPT_DIR/docker-compose.dev-image.yaml"
REMOTE_COMPOSE="$SCRIPT_DIR/docker-compose.dev-remote.yaml"

header() {
    echo ""
    echo -e "${BLUE}${BOLD}Hub Development Environment${NC}"
    echo -e "${DIM}Using: $RUNTIME${NC}"
    echo ""
}

check_hosts() {
    if ! grep -q "prod.foo.redhat.com" /etc/hosts 2>/dev/null; then
        echo -e "${YELLOW}Missing /etc/hosts entry. Adding it (requires sudo)...${NC}"
        echo "127.0.0.1 prod.foo.redhat.com stage.foo.redhat.com" | sudo tee -a /etc/hosts
    fi
}

# ─── BUILD ───────────────────────────────────────────────────────────────────

cmd_build() {
    local remote=false
    local github_token=""
    local chrome_repo="" chrome_ref=""
    local hub_ui_repo="" hub_ui_ref=""
    local aap_ui_repo="" aap_ui_ref=""
    local galaxy_repo="" galaxy_ref=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remote|-r)         remote=true ;;
            --token=*)           github_token="${1#*=}" ;;
            --chrome=*)          chrome_ref="${1#*=}" ;;
            --chrome-repo=*)     chrome_repo="${1#*=}" ;;
            --hub-ui=*)          hub_ui_ref="${1#*=}" ;;
            --hub-ui-repo=*)     hub_ui_repo="${1#*=}" ;;
            --aap-ui=*)          aap_ui_ref="${1#*=}" ;;
            --aap-ui-repo=*)     aap_ui_repo="${1#*=}" ;;
            --galaxy-ng=*)       galaxy_ref="${1#*=}" ;;
            --galaxy-ng-repo=*)  galaxy_repo="${1#*=}" ;;
            *) echo "Unknown build option: $1"; exit 1 ;;
        esac
        shift
    done

    # Auto-detect GitHub token from gh CLI or environment
    if [ -z "$github_token" ]; then
        github_token="${GITHUB_TOKEN:-}"
    fi
    if [ -z "$github_token" ] && command -v gh &>/dev/null; then
        github_token=$(gh auth token 2>/dev/null || true)
    fi

    if [ "$remote" = true ]; then
        build_remote "$github_token" "$chrome_repo" "$chrome_ref" "$hub_ui_repo" "$hub_ui_ref" \
                     "$aap_ui_repo" "$aap_ui_ref" "$galaxy_repo" "$galaxy_ref"
    else
        build_local
    fi
}

build_local() {
    header
    echo -e "${BOLD}Building from local repos...${NC}"
    echo ""

    # Check repos exist
    local missing=false
    for repo in galaxy_ng ansible-hub-ui aap-ui insights-chrome; do
        if [ -d "$PARENT_DIR/$repo" ]; then
            local branch=$(cd "$PARENT_DIR/$repo" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}✓${NC} $repo ${DIM}($branch)${NC}"
        else
            echo -e "  ${RED}✗${NC} $repo not found at $PARENT_DIR/$repo"
            missing=true
        fi
    done

    if [ "$missing" = true ]; then
        echo ""
        echo -e "${RED}Missing repos. Clone them to $PARENT_DIR or use --remote${NC}"
        exit 1
    fi

    echo ""
    echo "Building frontend image..."
    cd "$PARENT_DIR"
    $RUNTIME build -t hub-dev-env:latest -f insights-chrome/Dockerfile.dev-env .

    echo ""
    echo -e "${GREEN}${BOLD}Build complete!${NC}"
    echo ""
    echo "Start with: $0 start"
}

build_remote() {
    local github_token="$1"
    local chrome_repo="$2" chrome_ref="$3"
    local hub_ui_repo="$4" hub_ui_ref="$5"
    local aap_ui_repo="$6" aap_ui_ref="$7"
    local galaxy_repo="$8" galaxy_ref="$9"

    header
    echo -e "${BOLD}Building from remote repos...${NC}"
    echo ""

    local build_args=""

    if [ -n "$github_token" ]; then
        build_args="$build_args --build-arg GITHUB_TOKEN=$github_token"
        echo -e "  GitHub auth: ${GREEN}✓ token provided${NC}"
    else
        echo -e "  GitHub auth: ${DIM}none (public repos only)${NC}"
    fi

    if [ -n "$chrome_repo" ]; then
        build_args="$build_args --build-arg INSIGHTS_CHROME_REPO=$chrome_repo"
    fi
    if [ -n "$chrome_ref" ]; then
        build_args="$build_args --build-arg INSIGHTS_CHROME_REF=$chrome_ref"
        echo -e "  insights-chrome: ${GREEN}$chrome_ref${NC}"
    else
        echo -e "  insights-chrome: ${DIM}AAP-61707-crc-hub-ui-local-proxy @ prat98/insights-chrome (default)${NC}"
    fi

    if [ -n "$hub_ui_repo" ]; then
        build_args="$build_args --build-arg ANSIBLE_HUB_UI_REPO=$hub_ui_repo"
    fi
    if [ -n "$hub_ui_ref" ]; then
        build_args="$build_args --build-arg ANSIBLE_HUB_UI_REF=$hub_ui_ref"
        echo -e "  ansible-hub-ui:  ${GREEN}$hub_ui_ref${NC}"
    else
        echo -e "  ansible-hub-ui:  ${DIM}master (default)${NC}"
    fi

    if [ -n "$aap_ui_repo" ]; then
        build_args="$build_args --build-arg AAP_UI_REPO=$aap_ui_repo"
    fi
    if [ -n "$aap_ui_ref" ]; then
        build_args="$build_args --build-arg AAP_UI_REF=$aap_ui_ref"
        echo -e "  aap-ui:          ${GREEN}$aap_ui_ref${NC}"
    else
        echo -e "  aap-ui:          ${DIM}test-changes-in-parallel-hub-migration (default)${NC}"
    fi

    if [ -n "$galaxy_repo" ]; then
        build_args="$build_args --build-arg GALAXY_NG_REPO=$galaxy_repo"
    fi
    if [ -n "$galaxy_ref" ]; then
        build_args="$build_args --build-arg GALAXY_NG_REF=$galaxy_ref"
        echo -e "  galaxy_ng:       ${GREEN}$galaxy_ref${NC}"
    else
        echo -e "  galaxy_ng:       ${DIM}proxy-setup @ prat98/galaxy_ng (default)${NC}"
    fi

    echo ""
    echo "Building image (cloning repos, installing deps)..."
    cd "$SCRIPT_DIR"
    $RUNTIME build -t hub-dev-env:latest -f Dockerfile.dev-env-remote $build_args .

    echo ""
    echo -e "${GREEN}${BOLD}Build complete!${NC}"
    echo ""
    echo "Start with: $0 start --remote"
}

# ─── START ───────────────────────────────────────────────────────────────────

cmd_start() {
    local compose_file="$LOCAL_COMPOSE"
    local dev_mode=false
    for arg in "$@"; do
        case $arg in
            --remote) compose_file="$REMOTE_COMPOSE" ;;
            --dev)    dev_mode=true ;;
        esac
    done

    header
    check_hosts

    # Verify image exists
    if ! $RUNTIME image inspect hub-dev-env:latest &>/dev/null; then
        echo -e "${YELLOW}Image not found. Build first:${NC}"
        echo "  $0 build          # from local repos"
        echo "  $0 build --remote # from GitHub"
        exit 1
    fi

    echo "Starting all services..."
    cd "$SCRIPT_DIR"
    if [ "$dev_mode" = true ]; then
        echo -e "${GREEN}Dev mode: mounting local aap-ui for hot-reload${NC}"
        $COMPOSE -f "$compose_file" -f "$SCRIPT_DIR/docker-compose.dev-override.yaml" up --build -d
    else
        $COMPOSE -f "$compose_file" up --build -d
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Services starting!${NC}"
    echo ""
    echo "Wait 1-2 minutes for webpack to compile, then access:"
    echo ""
    echo -e "  Old Hub: ${BOLD}https://prod.foo.redhat.com:1337/ansible/automation-hub${NC}"
    echo -e "  New Hub: ${BOLD}https://prod.foo.redhat.com:1337/ansible/automation-hub-new${NC}"
    echo ""
    echo -e "  Credentials: ${BOLD}org-admin${NC} / ${BOLD}redhat${NC}"
    echo ""
    echo "Commands:"
    echo "  $0 status    # check services"
    echo "  $0 logs      # view logs"
    echo "  $0 user      # switch user"
    echo "  $0 stop      # stop everything"
}

# ─── STOP ────────────────────────────────────────────────────────────────────

cmd_stop() {
    header
    echo "Stopping services..."
    cd "$SCRIPT_DIR"
    $COMPOSE -f "$LOCAL_COMPOSE" down --remove-orphans 2>/dev/null || true
    $COMPOSE -f "$REMOTE_COMPOSE" down --remove-orphans 2>/dev/null || true
    echo -e "${GREEN}Stopped.${NC}"
}

# ─── STATUS ──────────────────────────────────────────────────────────────────

cmd_status() {
    header

    local compose_file="$LOCAL_COMPOSE"
    # Try local first, fall back to remote
    cd "$SCRIPT_DIR"
    $COMPOSE -f "$compose_file" ps 2>/dev/null || $COMPOSE -f "$REMOTE_COMPOSE" ps 2>/dev/null || echo "No services running."

    echo ""

    # Check key endpoints
    echo -e "${BOLD}Endpoints:${NC}"
    for endpoint in "Chrome|https://localhost:1337/" "API|http://localhost:8080/api/automation-hub/" "Hub UI|http://localhost:8002/apps/automation-hub/fed-mods.json" "Config Proxy|http://localhost:9000/"; do
        local name="${endpoint%%|*}"
        local url="${endpoint##*|}"
        local code
        if [[ "$url" == https* ]]; then
            code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        else
            code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        fi
        if [ "$code" = "200" ]; then
            echo -e "  ${GREEN}✓${NC} $name ($code)"
        else
            echo -e "  ${RED}✗${NC} $name ($code)"
        fi
    done

    # Show current user
    local user
    user=$(curl -s http://localhost:8080/_proxy/user 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['current_user'])" 2>/dev/null || echo "unavailable")
    echo ""
    echo -e "  Current user: ${BOLD}$user${NC}"
    echo ""
}

# ─── LOGS ────────────────────────────────────────────────────────────────────

cmd_logs() {
    local service="$1"
    local compose_file="$LOCAL_COMPOSE"

    cd "$SCRIPT_DIR"

    # Map friendly names to service names
    case "$service" in
        chrome)    service="insights-chrome" ;;
        hub|old)   service="ansible-hub-ui" ;;
        new|aap)   service="aap-ui" ;;
        api)       service="galaxy-api" ;;
        proxy)     service="galaxy-proxy" ;;
        config)    service="config-proxy" ;;
        "")        ;; # all logs
    esac

    if [ -n "$service" ]; then
        $COMPOSE -f "$compose_file" logs -f "$service" 2>/dev/null || \
        $COMPOSE -f "$REMOTE_COMPOSE" logs -f "$service" 2>/dev/null
    else
        $COMPOSE -f "$compose_file" logs -f 2>/dev/null || \
        $COMPOSE -f "$REMOTE_COMPOSE" logs -f 2>/dev/null
    fi
}

# ─── USER ────────────────────────────────────────────────────────────────────

cmd_user() {
    exec "$SCRIPT_DIR/switch-user.sh" "$@"
}

# ─── CLEAN ───────────────────────────────────────────────────────────────────

cmd_clean() {
    header
    echo -e "${YELLOW}This will stop all services and remove volumes (database, etc.)${NC}"
    read -p "Continue? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$SCRIPT_DIR"
        $COMPOSE -f "$LOCAL_COMPOSE" down --volumes --remove-orphans 2>/dev/null || true
        $COMPOSE -f "$REMOTE_COMPOSE" down --volumes --remove-orphans 2>/dev/null || true
        echo -e "${GREEN}Cleaned.${NC}"
    fi
}

# ─── HELP ────────────────────────────────────────────────────────────────────

cmd_help() {
    echo ""
    echo -e "${BOLD}Hub Development Environment Manager${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  build                     Build from local repos"
    echo "  build --remote            Build from GitHub (no local repos needed)"
    echo "  start                     Start all services"
    echo "  start --dev               Start with local aap-ui mounted for hot-reload"
    echo "  stop                      Stop all services"
    echo "  status                    Show service status and health"
    echo "  logs [service]            Tail logs (chrome, hub, aap, api, proxy, config)"
    echo "  user [username]           Switch user (interactive or direct)"
    echo "  clean                     Stop and remove all data"
    echo ""
    echo -e "${BOLD}Build options:${NC}"
    echo "  --remote                  Clone repos from GitHub instead of using local"
    echo "  --chrome=<ref>            insights-chrome branch/tag/SHA"
    echo "  --hub-ui=<ref>            ansible-hub-ui branch/tag/SHA"
    echo "  --aap-ui=<ref>            aap-ui branch/tag/SHA"
    echo "  --galaxy-ng=<ref>         galaxy_ng branch/tag/SHA"
    echo "  --chrome-repo=<url>       Custom insights-chrome repo URL (fork)"
    echo "  --hub-ui-repo=<url>       Custom ansible-hub-ui repo URL (fork)"
    echo "  --aap-ui-repo=<url>       Custom aap-ui repo URL (fork)"
    echo "  --galaxy-ng-repo=<url>    Custom galaxy_ng repo URL (fork)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 build                                    # local repos"
    echo "  $0 build --remote                           # GitHub defaults"
    echo "  $0 build --remote --aap-ui=my-branch        # custom branch"
    echo "  $0 build --remote --aap-ui-repo=https://github.com/me/aap-ui.git --aap-ui=feat"
    echo "  $0 start"
    echo "  $0 user org-admin"
    echo "  $0 logs chrome"
    echo ""
}

# ─── MAIN ────────────────────────────────────────────────────────────────────

case "${1:-}" in
    build)   shift; cmd_build "$@" ;;
    start)   shift; cmd_start "$@" ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    logs)    shift; cmd_logs "$@" ;;
    user)    shift; cmd_user "$@" ;;
    clean)   cmd_clean ;;
    help|--help|-h) cmd_help ;;
    "")      cmd_help ;;
    *)       echo "Unknown command: $1"; cmd_help; exit 1 ;;
esac
