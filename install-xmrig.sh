#!/bin/bash
# XMRig one-shot installer for supportxmr.
# Downloads the official XMRig static binary, installs config, systemd
# service, and the watchdog (health check + auto restart).
#
# Usage:
#   bash install-xmrig.sh <WORKER_NAME> [WALLET_ADDRESS] [XMRIG_VERSION]
#
# Example:
#   bash install-xmrig.sh hermes-s3-5180
#
set -euo pipefail

WORKER="${1:?usage: install-xmrig.sh <WORKER_NAME> [WALLET] [VERSION]}"
WALLET="${2:-88si6ZSuV4ESgjfJXuyqiyZHwaPabnp4jT2fpLvt5vC3Xk17Keio2nVRXHAc1LniCbHK3TqJidyFsH71SstnN4sm4Azd5rD}"
XMRIG_VERSION="${3:-6.22.2}"
BASE_URL="${FILET_BASE_URL:-https://raw.githubusercontent.com/revarifin/Filet/main}"
TARBALL="xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz"

log() { echo "[install-xmrig] $*"; }

# --- 1. binary: try the GitHub mirror first, fall back to the official release
get_binary() {
    local tmp=/tmp/xmrig-install-$$
    mkdir -p "$tmp"
    if curl -fsSL -o "$tmp/xmrig" "$BASE_URL/xmrig" 2>/dev/null; then
        log "binary downloaded from Filet mirror"
    else
        log "mirror unavailable, downloading official release ${XMRIG_VERSION}"
        curl -fsSL "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/${TARBALL}" -o "$tmp/xmrig.tar.gz"
        tar -xzf "$tmp/xmrig.tar.gz" -C "$tmp"
        cp "$tmp/xmrig-${XMRIG_VERSION}/xmrig" "$tmp/xmrig"
    fi
    install -m 0755 "$tmp/xmrig" /usr/local/bin/xmrig
    rm -rf "$tmp"
    /usr/local/bin/xmrig --version | head -1
}

# --- 2. scripts: prefer the repo copy so every node runs identical logic
get_scripts() {
    local f
    for f in xmrig-healthcheck.sh xmrig-watchdog.sh; do
        if curl -fsSL -o "/tmp/$f" "$BASE_URL/$f" 2>/dev/null; then
            install -m 0755 "/tmp/$f" "/usr/local/bin/$f"
        else
            log "ERROR cannot fetch $f from $BASE_URL" >&2
            exit 1
        fi
    done
}

# --- 3. config
write_config() {
    local tpl=/tmp/xmrig-config.template.json
    if curl -fsSL -o "$tpl" "$BASE_URL/xmrig-config.template.json" 2>/dev/null; then
        sed -e "s/WALLET_ADDRESS_HERE/${WALLET}/" \
            -e "s/WORKER_NAME_HERE/${WORKER}/" "$tpl" > /root/xmrig-config.json
    else
        log "template unavailable, writing config inline"
        cat > /root/xmrig-config.json <<EOF
{
  "autosave": false,
  "pools": [
    {
      "url": "pool-eu.supportxmr.com:3333",
      "user": "${WALLET}",
      "pass": "${WORKER}",
      "coin": "monero"
    }
  ],
  "cpu": {
    "enabled": true,
    "huge-pages": false,
    "max-threads-hint": 100,
    "rx": [0, 1],
    "rx/wow": [0, 1]
  },
  "donate-level": 1,
  "print-time": 30
}
EOF
    fi
    grep -E '"pass"|"user"' /root/xmrig-config.json
}

# --- 4. systemd units
write_units() {
    local f
    for f in xmrig.service xmrig-watchdog.service xmrig-watchdog.timer; do
        if ! curl -fsSL -o "/etc/systemd/system/$f" "$BASE_URL/$f" 2>/dev/null; then
            log "ERROR cannot fetch $f from $BASE_URL" >&2
            exit 1
        fi
    done
    systemctl daemon-reload
    systemctl enable xmrig
    systemctl enable --now xmrig-watchdog.timer
}

log "worker=${WORKER}"
get_binary
get_scripts
write_config
write_units

systemctl restart xmrig
sleep 5
systemctl is-active xmrig
log "done. verify with:"
log "  journalctl -u xmrig | grep -E 'dataset ready|READY threads|H/s|accepted'"
