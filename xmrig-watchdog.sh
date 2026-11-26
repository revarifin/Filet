#!/bin/bash
# Runs the XMRig health check and restarts the miner if it is unhealthy.
# Called by xmrig-watchdog.timer every 10 minutes.

if /usr/local/bin/xmrig-healthcheck.sh; then
    exit 0
fi

# Unhealthy -> restart, but not too often (avoid restart loops)
STAMP=/var/log/xmrig-last-restart
NOW=$(date +%s)
if [ -f "$STAMP" ]; then
    LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
    if [ $(( NOW - LAST )) -lt 1800 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') healthcheck failed but restarted <30min ago, skipping" \
            >> /var/log/xmrig-health.log
        exit 1
    fi
fi

echo "$NOW" > "$STAMP"
echo "$(date '+%Y-%m-%d %H:%M:%S') restarting xmrig (healthcheck failed)" >> /var/log/xmrig-health.log
systemctl restart xmrig
