#!/bin/bash
# MC Heartbeat - Agent liveness pinger
# Runs every 30s via cron/systemd-timer
# Usage: MC_AGENT_ID=4 MC_AGENT_NAME=白起 bash heartbeat.sh

MC_URL="${MC_URL:-http://100.80.136.1:3000}"
MC_API_KEY="${MC_API_KEY:-mc_08c9022bb3c89453004c2cce9b05a7881492c96c9add6c29}"
MC_AGENT_ID="${MC_AGENT_ID:?MC_AGENT_ID required}"
MC_AGENT_NAME="${MC_AGENT_NAME:-unknown}"

# Send heartbeat
RESP=$(curl -s -X POST "${MC_URL}/api/agents/${MC_AGENT_ID}/heartbeat" \
  -H "x-api-key: ${MC_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "x-agent-name: ${MC_AGENT_NAME}" \
  -d '{}' 2>/dev/null)

# Check for work items
WORK_ITEMS=$(echo "$RESP" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    items = d.get('work_items', [])
    print(len(items))
except: print(0)
" 2>/dev/null)

if [ "$WORK_ITEMS" -gt 0 ] 2>/dev/null; then
    # Log work items to idle-log
    echo "$(date -Iseconds) | MC heartbeat: ${WORK_ITEMS} pending work items" >> ~/wiki-1/raw/idle-$(date +%Y-%m-%d).log
fi

# Silent success
exit 0
