#!/bin/bash
#
# Start both Hub frontends for side-by-side comparison
#
# This script:
# 1. Starts the local config proxy (injects automation-hub-new)
# 2. Provides instructions for starting the frontends and chrome
#
# Prerequisites:
# - galaxy_ng running with insights proxy (docker compose -f dev/compose/insights.yaml up)
# - /etc/hosts: 127.0.0.1 prod.foo.redhat.com stage.foo.redhat.com
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDHAT_INSIGHTS_DIR="$(dirname "$SCRIPT_DIR")"

echo "
╔═══════════════════════════════════════════════════════════════════════╗
║         Dual Hub Frontend Development Setup                           ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  This setup allows you to run BOTH Hub frontends simultaneously:      ║
║                                                                       ║
║    • ansible-hub-ui (old) → /ansible/automation-hub                   ║
║    • aap-ui (new)         → /ansible/automation-hub-new               ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝

Step 1: Make sure galaxy_ng is running with insights proxy
   cd $REDHAT_INSIGHTS_DIR/galaxy_ng
   docker compose -f dev/compose/insights.yaml up --build

Step 2: Start the config proxy (this terminal)
   node $SCRIPT_DIR/local-config-proxy.js

Step 3: Start ansible-hub-ui on port 8002 (new terminal)
   cd $REDHAT_INSIGHTS_DIR/ansible-hub-ui
   npm run start-insights

Step 4: Start aap-ui on port 8003 (new terminal)  
   cd $REDHAT_INSIGHTS_DIR/aap-ui/frontend/hub/insights
   APP_NAME=automation-hub-new UI_PORT=8003 npm start

Step 5: Start insights-chrome (new terminal)
   cd $SCRIPT_DIR
   NAV_CONFIG=9000 npm run dev

Step 6: Access the UIs
   • Old Hub: https://stage.foo.redhat.com:1337/ansible/automation-hub
   • New Hub: https://stage.foo.redhat.com:1337/ansible/automation-hub-new

═══════════════════════════════════════════════════════════════════════════

Starting config proxy...
"

exec node "$SCRIPT_DIR/local-config-proxy.js"


