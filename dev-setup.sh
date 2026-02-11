#!/bin/bash
#
# Full Development Stack Setup Script
#
# This script sets up the complete dual-hub development environment:
# - Verifies prerequisites
# - Configures /etc/hosts
# - Installs dependencies
# - Provides options for starting the stack
#
# Usage:
#   ./dev-setup.sh           # Interactive setup
#   ./dev-setup.sh --check   # Just check prerequisites
#   ./dev-setup.sh --start   # Start the full stack
#   ./dev-setup.sh --stop    # Stop all services
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDHAT_INSIGHTS_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║       Dual-Hub Development Environment Setup                           ║"
    echo "╠════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                        ║"
    echo "║  This setup allows you to run BOTH Hub frontends simultaneously:       ║"
    echo "║                                                                        ║"
    echo "║    • ansible-hub-ui (old) → /ansible/automation-hub                    ║"
    echo "║    • aap-ui (new)         → /ansible/automation-hub-new                ║"
    echo "║                                                                        ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 found"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 not found"
        return 1
    fi
}

check_directory() {
    if [ -d "$1" ]; then
        echo -e "  ${GREEN}✓${NC} $2 found at $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $2 not found at $1"
        return 1
    fi
}

check_hosts_entry() {
    if grep -q "$1" /etc/hosts 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 in /etc/hosts"
        return 0
    else
        echo -e "  ${YELLOW}!${NC} $1 not in /etc/hosts"
        return 1
    fi
}

check_prerequisites() {
    echo ""
    echo -e "${BLUE}Checking prerequisites...${NC}"
    echo ""
    
    local all_ok=true
    
    echo "Required commands:"
    check_command "docker" || all_ok=false
    check_command "docker-compose" || check_command "docker compose" || all_ok=false
    check_command "node" || all_ok=false
    check_command "npm" || all_ok=false
    check_command "git" || all_ok=false
    
    echo ""
    echo "Required repositories (should be siblings of insights-chrome):"
    check_directory "$REDHAT_INSIGHTS_DIR/galaxy_ng" "galaxy_ng" || all_ok=false
    check_directory "$REDHAT_INSIGHTS_DIR/ansible-hub-ui" "ansible-hub-ui" || all_ok=false
    check_directory "$REDHAT_INSIGHTS_DIR/aap-ui" "aap-ui" || all_ok=false
    
    echo ""
    echo "/etc/hosts entries:"
    check_hosts_entry "stage.foo.redhat.com" || all_ok=false
    check_hosts_entry "prod.foo.redhat.com" || all_ok=false
    
    echo ""
    
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}All prerequisites met!${NC}"
        return 0
    else
        echo -e "${YELLOW}Some prerequisites are missing. See above for details.${NC}"
        return 1
    fi
}

setup_hosts() {
    echo ""
    echo -e "${BLUE}Setting up /etc/hosts...${NC}"
    
    local needs_update=false
    
    if ! grep -q "stage.foo.redhat.com" /etc/hosts 2>/dev/null; then
        needs_update=true
    fi
    
    if ! grep -q "prod.foo.redhat.com" /etc/hosts 2>/dev/null; then
        needs_update=true
    fi
    
    if [ "$needs_update" = true ]; then
        echo "Adding entries to /etc/hosts (requires sudo)..."
        echo "127.0.0.1 stage.foo.redhat.com prod.foo.redhat.com" | sudo tee -a /etc/hosts
        echo -e "${GREEN}Done!${NC}"
    else
        echo -e "${GREEN}/etc/hosts already configured${NC}"
    fi
}

install_dependencies() {
    echo ""
    echo -e "${BLUE}Installing dependencies...${NC}"
    
    echo ""
    echo "Installing insights-chrome dependencies..."
    cd "$SCRIPT_DIR"
    npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
    
    echo ""
    echo "Installing ansible-hub-ui dependencies..."
    cd "$REDHAT_INSIGHTS_DIR/ansible-hub-ui"
    npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
    
    echo ""
    echo "Installing aap-ui dependencies..."
    cd "$REDHAT_INSIGHTS_DIR/aap-ui"
    npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
    
    echo ""
    echo "Installing aap-ui insights build dependencies..."
    cd "$REDHAT_INSIGHTS_DIR/aap-ui/frontend/hub/insights"
    npm install --legacy-peer-deps
    
    echo -e "${GREEN}All dependencies installed!${NC}"
}

start_backend_only() {
    echo ""
    echo -e "${BLUE}Starting backend services (galaxy_ng)...${NC}"
    
    cd "$SCRIPT_DIR"
    docker compose -f docker-compose.dev.yaml up --build -d \
        postgres redis galaxy-base galaxy-base-dev galaxy-migrations \
        galaxy-api galaxy-content galaxy-worker galaxy-proxy config-proxy
    
    echo ""
    echo -e "${GREEN}Backend services starting...${NC}"
    echo ""
    echo "Monitor logs with:"
    echo "  docker compose -f docker-compose.dev.yaml logs -f"
    echo ""
    echo "Wait for 'READY' message in logs, then start frontends manually."
}

start_full_stack_docker() {
    echo ""
    echo -e "${BLUE}Starting full stack with Docker (backend + frontends)...${NC}"
    
    cd "$SCRIPT_DIR"
    docker compose -f docker-compose.dev.yaml --profile frontends up --build -d
    
    echo ""
    echo -e "${GREEN}Full stack starting...${NC}"
    echo ""
    echo "Monitor logs with:"
    echo "  docker compose -f docker-compose.dev.yaml logs -f"
    echo ""
    echo "Note: First run may take several minutes to build images and install deps."
}

print_manual_start_instructions() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Manual Start Instructions:${NC}"
    echo ""
    echo "After backend is ready, start the frontends in separate terminals:"
    echo ""
    echo -e "${GREEN}Terminal 1 - ansible-hub-ui (old):${NC}"
    echo "  cd $REDHAT_INSIGHTS_DIR/ansible-hub-ui"
    echo "  npm run start-insights"
    echo ""
    echo -e "${GREEN}Terminal 2 - aap-ui (new):${NC}"
    echo "  cd $REDHAT_INSIGHTS_DIR/aap-ui/frontend/hub/insights"
    echo "  APP_NAME=automation-hub-new UI_PORT=8003 npm start"
    echo ""
    echo -e "${GREEN}Terminal 3 - insights-chrome:${NC}"
    echo "  cd $SCRIPT_DIR"
    echo "  NAV_CONFIG=9000 npm run dev"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}Access URLs:${NC}"
    echo "  • Old Hub: https://stage.foo.redhat.com:1337/ansible/automation-hub"
    echo "  • New Hub: https://stage.foo.redhat.com:1337/ansible/automation-hub-new"
    echo ""
    echo -e "${YELLOW}Test Credentials:${NC}"
    echo "  • org-admin / redhat"
    echo "  • jdoe / redhat"
    echo ""
}

stop_services() {
    echo ""
    echo -e "${BLUE}Stopping all services...${NC}"
    
    cd "$SCRIPT_DIR"
    docker compose -f docker-compose.dev.yaml --profile frontends down
    
    echo -e "${GREEN}All services stopped.${NC}"
}

clean_volumes() {
    echo ""
    echo -e "${YELLOW}Warning: This will delete all data (database, pulp storage, etc.)${NC}"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$SCRIPT_DIR"
        docker compose -f docker-compose.dev.yaml --profile frontends down -v
        echo -e "${GREEN}Volumes cleaned.${NC}"
    else
        echo "Cancelled."
    fi
}

show_menu() {
    echo ""
    echo -e "${BLUE}What would you like to do?${NC}"
    echo ""
    echo "  1) Check prerequisites"
    echo "  2) Full setup (hosts + dependencies)"
    echo "  3) Start backend only (run frontends manually)"
    echo "  4) Start full stack with Docker"
    echo "  5) Stop all services"
    echo "  6) Clean volumes (reset database)"
    echo "  7) Show manual start instructions"
    echo "  8) Exit"
    echo ""
    read -p "Choice [1-8]: " choice
    
    case $choice in
        1) check_prerequisites ;;
        2) 
            setup_hosts
            install_dependencies
            echo ""
            echo -e "${GREEN}Setup complete!${NC}"
            print_manual_start_instructions
            ;;
        3) 
            start_backend_only
            print_manual_start_instructions
            ;;
        4) start_full_stack_docker ;;
        5) stop_services ;;
        6) clean_volumes ;;
        7) print_manual_start_instructions ;;
        8) exit 0 ;;
        *) echo "Invalid choice" ;;
    esac
}

# Main
case "${1:-}" in
    --check)
        print_header
        check_prerequisites
        ;;
    --start)
        print_header
        start_backend_only
        print_manual_start_instructions
        ;;
    --start-all)
        print_header
        start_full_stack_docker
        ;;
    --stop)
        print_header
        stop_services
        ;;
    --clean)
        print_header
        clean_volumes
        ;;
    --help|-h)
        print_header
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  --check      Check prerequisites only"
        echo "  --start      Start backend services (frontends manual)"
        echo "  --start-all  Start full stack with Docker"
        echo "  --stop       Stop all services"
        echo "  --clean      Stop and remove all volumes"
        echo "  --help       Show this help"
        echo ""
        echo "Run without options for interactive menu."
        ;;
    "")
        print_header
        while true; do
            show_menu
        done
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run '$0 --help' for usage."
        exit 1
        ;;
esac

