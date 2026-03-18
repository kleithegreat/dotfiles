#!/usr/bin/env bash
# Wi-Fi speed test using Cloudflare endpoints.
# Outputs DOWN=<Mbps> and UP=<Mbps> as each completes.
set -uo pipefail

# Download test (10 MB)
down_bps=$(curl -o /dev/null -w '%{speed_download}' -s \
    'https://speed.cloudflare.com/__down?bytes=10000000')
if [ -n "$down_bps" ]; then
    down_mbps=$(awk "BEGIN{printf \"%.1f\", $down_bps * 8 / 1000000}")
    echo "DOWN=$down_mbps"
fi

# Upload test (5 MB)
up_bps=$(dd if=/dev/zero bs=1M count=5 2>/dev/null \
    | curl -X POST -w '%{speed_upload}' -s -d @- \
    'https://speed.cloudflare.com/__up')
if [ -n "$up_bps" ]; then
    up_mbps=$(awk "BEGIN{printf \"%.1f\", $up_bps * 8 / 1000000}")
    echo "UP=$up_mbps"
fi
