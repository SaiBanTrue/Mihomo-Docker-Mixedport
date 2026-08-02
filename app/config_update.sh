#!/bin/bash

set -e

CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
HISTORY_DIR="$CONFIG_DIR/history"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_CONFIG_FILE="/tmp/mihomo_download_config.yaml"
TEMP_UA_CACHE_FILE="/tmp/mihomo_success_ua.txt"

VALID_DOWNLOAD=false

if [[ -n "$SUB_URL" && "$SUB_URL" == http?(s)://* ]]; then
    USER_AGENTS=("clash meta mihomo" "clash" "meta" "mihomo")

    if [ -f "$TEMP_UA_CACHE_FILE" ]; then
        LAST_UA=$(cat "$TEMP_UA_CACHE_FILE")
        USER_AGENTS=("$LAST_UA" $(echo "${USER_AGENTS[@]}" | sed "s/\b$LAST_UA\b//g"))
    fi

    mkdir -p "$HISTORY_DIR"

    for ua in "${USER_AGENTS[@]}"; do
        if [ "$USE_PROXYSCOTCH" = "true" ]; then
            echo "====> Downloading via Proxyscotch..."
            PAYLOAD="{\"url\":\"$SUB_URL\",\"method\":\"GET\",\"wantsBinary\":true,\"headers\":{\"User-Agent\":\"$ua\"}}"

            RESPONSE=$(curl -s -L --noproxy "*" --connect-timeout 10 -m 10 --retry 3 \
                -X POST "https://proxy.hoppscotch.io/" \
                -H "Content-Type: application/json" \
                -H "Origin: https://hoppscotch.io" \
                -d "$PAYLOAD") || echo "====> Config download failed."

            B64_DATA=$(echo "$RESPONSE" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')

            MOD=$((${#B64_DATA} % 4))
            [ "$MOD" -eq 2 ] && B64_DATA="${B64_DATA}=="
            [ "$MOD" -eq 3 ] && B64_DATA="${B64_DATA}="
            echo "$B64_DATA" | base64 -d > "$TEMP_CONFIG_FILE" 2>/dev/null || touch "$TEMP_CONFIG_FILE"
        else
            echo "====> Downloading via direct curl..."
            curl -s -L --noproxy "*" --connect-timeout 10 -m 10 --retry 3 -H "User-Agent: $ua" "$SUB_URL" -o "$TEMP_CONFIG_FILE" || echo "====> Config download failed."
        fi

        if ! /app/mihomo -t -d "$CONFIG_DIR" -f "$TEMP_CONFIG_FILE" >/dev/null 2>&1; then
            SAFE_UA=${ua// /_}
            mv "$TEMP_CONFIG_FILE" "$HISTORY_DIR/config_${TIMESTAMP}_failed_${SAFE_UA,,}.yaml"
            continue
        fi

        [ -f "$CONFIG_FILE" ] && mv "$CONFIG_FILE" "$HISTORY_DIR/config_${TIMESTAMP}.yaml"
        mv "$TEMP_CONFIG_FILE" "$CONFIG_FILE"

        VALID_DOWNLOAD=true
        echo "$ua" > "$TEMP_UA_CACHE_FILE"
        break
    done

    find "$HISTORY_DIR" -type f -mtime +7 -name "config_*.yaml" -exec rm -f {} +
fi

if [ -f "$CONFIG_FILE" ]; then
    YQ_EXPR=""
    DEL_KEYS=""
    OBJ_KEYS=""

    register_key() {
        local key="$1"
        DEL_KEYS="${DEL_KEYS}.${key}, "
        OBJ_KEYS="${OBJ_KEYS}\"${key}\": .${key}, "
    }

    [ -n "$MIXED_PORT" ] && YQ_EXPR="${YQ_EXPR} .mixed-port = $MIXED_PORT |" && register_key "mixed-port"
    [ -n "$ALLOW_LAN" ] && YQ_EXPR="${YQ_EXPR} .allow-lan = $ALLOW_LAN |" && register_key "allow-lan"
    [ -n "$IPV6" ] && YQ_EXPR="${YQ_EXPR} .ipv6 = $IPV6 |" && register_key "ipv6"
    [ -n "$MIHOMO_MODE" ] && YQ_EXPR="${YQ_EXPR} .mode = \"$MIHOMO_MODE\" |" && register_key "mode"
    [ -n "$BIND_ADDRESS" ] && YQ_EXPR="${YQ_EXPR} .bind-address = \"$BIND_ADDRESS\" |" && register_key "bind-address"
    [ -n "$AUTHENTICATION" ] && export AUTHENTICATION && YQ_EXPR="${YQ_EXPR} .authentication = (env(AUTHENTICATION) | split(\",\") | .[] style=\"double\") |" && register_key "authentication"
    [ -n "$SKIP_AUTH_PREFIXES" ] && export SKIP_AUTH_PREFIXES && YQ_EXPR="${YQ_EXPR} .skip-auth-prefixes = (env(SKIP_AUTH_PREFIXES) | split(\",\")) |" && register_key "skip-auth-prefixes"

    if [ -n "$YQ_EXPR" ]; then
        yq eval -i "${YQ_EXPR% |}" "$CONFIG_FILE"
        yq eval -i ". as \$rest | ({ ${OBJ_KEYS%, } } | with_entries(select(.value != null))) + (\$rest | del(${DEL_KEYS%, }))" "$CONFIG_FILE"
    fi
fi
