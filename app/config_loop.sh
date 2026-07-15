#!/bin/bash

set -e

awk -v n="$UPDATE_INTERVAL" 'BEGIN{exit !(n>0)}' || exit 0

while true; do
    sleep "${UPDATE_INTERVAL}h"
    bash /app/config_update.sh
    curl -s -X PUT \
        -H "Authorization: Bearer ${WEBUI_SECRET}" \
        -H "Content-Type: application/json" \
        -d '{"path": "", "payload": ""}' \
        "http://${API_ADDR}/configs?force=true" >/dev/null 2>&1 || true
    echo "====> Mihomo configuration reloaded."
done
