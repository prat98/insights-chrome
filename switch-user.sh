#!/bin/bash
#
# Switch the active user in the galaxy_ng proxy
#
# Usage:
#   ./switch-user.sh              # Interactive picker
#   ./switch-user.sh org-admin    # Switch directly
#   ./switch-user.sh --status     # Show current user
#

PROXY_URL="${PROXY_URL:-http://localhost:8080}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

get_users() {
    curl -s "$PROXY_URL/_proxy/user" 2>/dev/null
}

show_status() {
    local data
    data=$(get_users)

    if [ -z "$data" ] || echo "$data" | grep -q "Connection refused"; then
        echo -e "${YELLOW}Cannot reach proxy at $PROXY_URL${NC}"
        echo "Is the deployment running?"
        exit 1
    fi

    local current
    current=$(echo "$data" | python3 -c "import sys,json; print(json.load(sys.stdin)['current_user'])" 2>/dev/null)

    echo ""
    echo -e "${BOLD}Current user: ${GREEN}$current${NC}"
    echo ""

    echo "$data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for u in sorted(data['available_users'], key=lambda x: x['username']):
    marker = ' ← active' if u['active'] else ''
    admin = ' (org admin)' if u['is_org_admin'] else ''
    print(f\"  {u['username']:<25} {u['email']:<35} {admin}{marker}\")
" 2>/dev/null
    echo ""
}

switch_user() {
    local username="$1"
    local result
    result=$(curl -s -X POST "$PROXY_URL/_proxy/user" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"$username\"}" 2>/dev/null)

    if echo "$result" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}Switched to: $username${NC}"
        echo "Refresh your browser to pick up the change."
    else
        local error
        error=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error','Unknown error'))" 2>/dev/null)
        echo -e "${YELLOW}Error: $error${NC}"
    fi
}

pick_user() {
    local data
    data=$(get_users)

    if [ -z "$data" ] || echo "$data" | grep -q "Connection refused"; then
        echo -e "${YELLOW}Cannot reach proxy at $PROXY_URL${NC}"
        exit 1
    fi

    local current
    current=$(echo "$data" | python3 -c "import sys,json; print(json.load(sys.stdin)['current_user'])" 2>/dev/null)

    local users
    users=$(echo "$data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for u in sorted(data['available_users'], key=lambda x: x['username']):
    print(u['username'])
" 2>/dev/null)

    echo ""
    echo -e "${BOLD}Select a user:${NC}"
    echo ""

    local i=1
    local user_array=()
    while IFS= read -r user; do
        user_array+=("$user")
        local admin=""
        local marker=""

        echo "$data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for u in data['available_users']:
    if u['username'] == '$user':
        admin = ' (org admin)' if u['is_org_admin'] else ''
        active = ' ← current' if u['active'] else ''
        print(f'$admin{active}')
" 2>/dev/null | read extra

        if [ "$user" = "$current" ]; then
            echo -e "  ${GREEN}$i) $user${NC}$extra ${GREEN}← current${NC}"
        else
            echo -e "  $i) $user$extra"
        fi
        ((i++))
    done <<< "$users"

    echo ""
    read -p "Choice [1-${#user_array[@]}]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#user_array[@]}" ]; then
        local selected="${user_array[$((choice-1))]}"
        echo ""
        switch_user "$selected"
    else
        echo "Invalid choice."
    fi
}

case "${1:-}" in
    --status|-s)
        show_status
        ;;
    --help|-h)
        echo "Usage: $0 [username | --status | --help]"
        echo ""
        echo "  (no args)     Interactive user picker"
        echo "  <username>    Switch to user directly"
        echo "  --status      Show current user"
        echo "  --help        Show this help"
        ;;
    "")
        show_status
        pick_user
        ;;
    *)
        switch_user "$1"
        ;;
esac
