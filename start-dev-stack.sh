#!/bin/bash
#
# Quick Start Script for Dual-Hub Development
#
# This script starts all services needed for dual-hub development.
# It uses tmux to manage multiple terminal sessions.
#
# Usage:
#   ./start-dev-stack.sh         # Start everything in tmux
#   ./start-dev-stack.sh --help  # Show help
#
# Requirements:
#   - tmux (brew install tmux / apt install tmux)
#   - All repos cloned as siblings (galaxy_ng, ansible-hub-ui, aap-ui)
#   - /etc/hosts configured with stage.foo.redhat.com
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDHAT_INSIGHTS_DIR="$(dirname "$SCRIPT_DIR")"
SESSION_NAME="hub-dev"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    echo ""
    echo "Dual-Hub Development Stack Quick Start"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  (no args)   Start all services in a tmux session"
    echo "  --backend   Start only backend (galaxy_ng)"
    echo "  --attach    Attach to existing session"
    echo "  --kill      Kill the tmux session"
    echo "  --status    Show service status"
    echo "  --help      Show this help"
    echo ""
    echo "Services started:"
    echo "  1. galaxy_ng backend (Docker)"
    echo "  2. Config proxy (port 9000)"
    echo "  3. ansible-hub-ui (port 8002)"
    echo "  4. aap-ui (port 8003)"
    echo "  5. insights-chrome (port 1337)"
    echo ""
    echo "Access:"
    echo "  • Old Hub: https://stage.foo.redhat.com:1337/ansible/automation-hub"
    echo "  • New Hub: https://stage.foo.redhat.com:1337/ansible/automation-hub-new"
    echo ""
}

check_tmux() {
    if ! command -v tmux &> /dev/null; then
        echo -e "${RED}Error: tmux is not installed${NC}"
        echo ""
        echo "Install with:"
        echo "  macOS:  brew install tmux"
        echo "  Ubuntu: sudo apt install tmux"
        echo "  Fedora: sudo dnf install tmux"
        exit 1
    fi
}

check_prereqs() {
    local missing=false
    
    if [ ! -d "$REDHAT_INSIGHTS_DIR/galaxy_ng" ]; then
        echo -e "${RED}Error: galaxy_ng not found at $REDHAT_INSIGHTS_DIR/galaxy_ng${NC}"
        missing=true
    fi
    
    if [ ! -d "$REDHAT_INSIGHTS_DIR/ansible-hub-ui" ]; then
        echo -e "${RED}Error: ansible-hub-ui not found at $REDHAT_INSIGHTS_DIR/ansible-hub-ui${NC}"
        missing=true
    fi
    
    if [ ! -d "$REDHAT_INSIGHTS_DIR/aap-ui" ]; then
        echo -e "${RED}Error: aap-ui not found at $REDHAT_INSIGHTS_DIR/aap-ui${NC}"
        missing=true
    fi
    
    if ! grep -q "stage.foo.redhat.com" /etc/hosts 2>/dev/null; then
        echo -e "${YELLOW}Warning: stage.foo.redhat.com not in /etc/hosts${NC}"
        echo "Add this line to /etc/hosts:"
        echo "  127.0.0.1 stage.foo.redhat.com prod.foo.redhat.com"
    fi
    
    if [ "$missing" = true ]; then
        echo ""
        echo "Clone missing repos to: $REDHAT_INSIGHTS_DIR"
        exit 1
    fi
}

start_backend_only() {
    echo -e "${BLUE}Starting galaxy_ng backend...${NC}"
    cd "$REDHAT_INSIGHTS_DIR/galaxy_ng"
    docker compose -f dev/compose/insights.yaml up --build
}

start_full_stack() {
    check_tmux
    check_prereqs
    
    # Kill existing session if any
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    
    echo -e "${BLUE}Starting development stack in tmux session: $SESSION_NAME${NC}"
    echo ""
    
    # Create new tmux session with first window for galaxy_ng
    tmux new-session -d -s "$SESSION_NAME" -n "galaxy_ng"
    tmux send-keys -t "$SESSION_NAME:galaxy_ng" "cd '$REDHAT_INSIGHTS_DIR/galaxy_ng' && docker compose -f dev/compose/insights.yaml up --build" Enter
    
    # Wait a moment then create other windows
    sleep 2
    
    # Config proxy window
    tmux new-window -t "$SESSION_NAME" -n "config-proxy"
    tmux send-keys -t "$SESSION_NAME:config-proxy" "cd '$SCRIPT_DIR' && echo 'Waiting for backend...' && sleep 30 && node local-config-proxy.js" Enter
    
    # ansible-hub-ui window
    tmux new-window -t "$SESSION_NAME" -n "hub-ui-old"
    tmux send-keys -t "$SESSION_NAME:hub-ui-old" "cd '$REDHAT_INSIGHTS_DIR/ansible-hub-ui' && echo 'Waiting for backend...' && sleep 60 && npm run start-insights" Enter
    
    # aap-ui window
    tmux new-window -t "$SESSION_NAME" -n "hub-ui-new"
    tmux send-keys -t "$SESSION_NAME:hub-ui-new" "cd '$REDHAT_INSIGHTS_DIR/aap-ui/frontend/hub/insights' && echo 'Waiting for backend...' && sleep 60 && APP_NAME=automation-hub-new UI_PORT=8003 npm start" Enter
    
    # insights-chrome window
    tmux new-window -t "$SESSION_NAME" -n "chrome"
    tmux send-keys -t "$SESSION_NAME:chrome" "cd '$SCRIPT_DIR' && echo 'Waiting for frontends...' && sleep 90 && NAV_CONFIG=9000 npm run dev" Enter
    
    # Select the galaxy_ng window
    tmux select-window -t "$SESSION_NAME:galaxy_ng"
    
    echo -e "${GREEN}✓ tmux session '$SESSION_NAME' created${NC}"
    echo ""
    echo "Windows:"
    echo "  0: galaxy_ng    - Backend (Docker)"
    echo "  1: config-proxy - Nav injection proxy"
    echo "  2: hub-ui-old   - ansible-hub-ui (port 8002)"
    echo "  3: hub-ui-new   - aap-ui (port 8003)"
    echo "  4: chrome       - insights-chrome (port 1337)"
    echo ""
    echo "Commands:"
    echo "  Attach:         tmux attach -t $SESSION_NAME"
    echo "  Switch windows: Ctrl-b then 0-4"
    echo "  Detach:         Ctrl-b then d"
    echo "  Kill session:   $0 --kill"
    echo ""
    echo -e "${YELLOW}Note: Services start with delays. Backend takes ~2-3 minutes.${NC}"
    echo ""
    
    read -p "Attach to session now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        tmux attach -t "$SESSION_NAME"
    fi
}

show_status() {
    echo ""
    echo -e "${BLUE}Service Status${NC}"
    echo ""
    
    # Check Docker services
    echo "Docker services:"
    if docker compose -f "$REDHAT_INSIGHTS_DIR/galaxy_ng/dev/compose/insights.yaml" ps 2>/dev/null | grep -q "Up"; then
        echo -e "  ${GREEN}✓${NC} galaxy_ng backend running"
    else
        echo -e "  ${RED}✗${NC} galaxy_ng backend not running"
    fi
    
    # Check ports
    echo ""
    echo "Ports:"
    for port in 8080 8002 8003 9000 1337; do
        if lsof -i :"$port" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Port $port in use"
        else
            echo -e "  ${RED}✗${NC} Port $port free"
        fi
    done
    
    # Check tmux
    echo ""
    echo "tmux session:"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Session '$SESSION_NAME' exists"
    else
        echo -e "  ${YELLOW}!${NC} Session '$SESSION_NAME' not found"
    fi
    echo ""
}

kill_session() {
    echo -e "${YELLOW}Stopping tmux session...${NC}"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null && echo -e "${GREEN}Session killed${NC}" || echo "No session to kill"
    
    echo ""
    echo -e "${YELLOW}Stopping Docker services...${NC}"
    cd "$REDHAT_INSIGHTS_DIR/galaxy_ng" 2>/dev/null && docker compose -f dev/compose/insights.yaml down 2>/dev/null || true
    
    echo -e "${GREEN}Done${NC}"
}

# Main
case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --backend)
        check_prereqs
        start_backend_only
        ;;
    --attach)
        check_tmux
        tmux attach -t "$SESSION_NAME"
        ;;
    --kill)
        kill_session
        ;;
    --status)
        show_status
        ;;
    "")
        start_full_stack
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run '$0 --help' for usage."
        exit 1
        ;;
esac

