#!/bin/bash
# XMRig health check
# Restart the miner when it is running but NOT actually mining.
# Two failure modes this catches:
#   1. RandomX dataset init hangs  -> no "H/s" line ever, no shares
#   2. Another process steals a CPU core -> hashrate collapses
#
# Exit 0 = healthy, exit 1 = unhealthy (caller may restart)

LOG=/var/log/xmrig-health.log
STALL_MIN=20      # no hashrate reported for this many minutes = stalled
SHARE_MIN=45      # no accepted share for this many minutes = broken
MIN_HS=50         # below this hashrate the miner is effectively dead

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# --- 1. service state ---
if ! systemctl is-active --quiet xmrig; then
    log "FAIL service not active"
    exit 1
fi

# Grab all speed lines: "TS PID: [ts] miner speed a/b/c H H H max M H/s"
mapfile -t SPEED_LINES < <(journalctl -u xmrig --no-pager -o short-unix \
    | grep -E 'miner +speed .*H/s')

if [ "${#SPEED_LINES[@]}" -eq 0 ]; then
    log "FAIL no hashrate line ever (dataset init likely hung)"
    exit 1
fi

last="${SPEED_LINES[-1]}"
newest_speed_ts="${last%%.*}"                 # strip fractional seconds
# pattern: speed 10s/60s/15m  481.6 437.0 450.2 H/s
newest_speed=$(echo "$last" \
    | grep -oE 'speed [0-9]+s/[0-9]+s/[0-9]+m +[0-9.]+ +[0-9.]+' \
    | awk '{print $4}' | tail -1)

if [ -z "$newest_speed" ]; then
    log "FAIL could not parse hashrate from: $last"
    exit 1
fi

# --- 2. hashrate freshness ---
age_min=$(( ( $(date +%s) - newest_speed_ts ) / 60 ))
if [ "$age_min" -gt "$STALL_MIN" ]; then
    log "FAIL hashrate line stale (${age_min}m > ${STALL_MIN}m)"
    exit 1
fi

# --- 3. hashrate value ---
if awk "BEGIN{exit !($newest_speed < $MIN_HS)}"; then
    log "FAIL hashrate ${newest_speed} H/s below ${MIN_HS}"
    exit 1
fi

# --- 4. share freshness (only meaningful once mining is proven) ---
if journalctl -u xmrig --no-pager | grep -q 'accepted ('; then
    newest_share_ts=$(journalctl -u xmrig --no-pager -o short-unix \
        | grep 'accepted (' | tail -1 | cut -d' ' -f1 | cut -d'.' -f1)
    share_age_min=$(( ( $(date +%s) - newest_share_ts ) / 60 ))
    if [ "$share_age_min" -gt "$SHARE_MIN" ]; then
        log "FAIL no accepted share for ${share_age_min}m"
        log "top cpu: $(ps aux --sort=-%cpu | head -4 | tail -3 | awk '{print $3"% "$11}' | tr '\n' ' ')"
        exit 1
    fi
fi

log "OK speed=${newest_speed} H/s age=${age_min}m"
exit 0
