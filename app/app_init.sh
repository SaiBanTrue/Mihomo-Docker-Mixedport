#!/bin/bash

set -e

chmod +x /app/mihomo

SOURCE_DIR="/app/res"
TARGET_DIR="/config"

mkdir -p "$TARGET_DIR"

if [ -d "$SOURCE_DIR" ]; then
    [ ! -d "$TARGET_DIR/WEBUI" ] && cp -rf "$SOURCE_DIR/WEBUI" "$TARGET_DIR/"
    cp -run "$SOURCE_DIR"/geoip.metadb "$SOURCE_DIR"/geosite.dat "$TARGET_DIR/"
fi
