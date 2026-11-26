# Filet — XMRig Deploy Kit

One-command XMRig Monero miner deployment for supportxmr, with systemd
auto-restart and a watchdog that catches the "alive but not mining" case.

## Why this repo

Uploading an 8 MB binary over a flaky SSH tunnel fails constantly (zero-byte
files, connection drops mid-transfer). Fetching from GitHub instead is one
small command and supports range/resume, so it works where uploads do not.

## Deploy on a new host

```bash
curl -fsSL https://raw.githubusercontent.com/revarifin/Filet/main/install-xmrig.sh \
  | bash -s -- <WORKER_NAME>
```

Optional wallet / version override:

```bash
bash install-xmrig.sh hermes-s4-1234 <WALLET_ADDRESS> 6.22.2
```

The installer:
1. Downloads the XMRig static binary (this repo's mirror, else the official release)
2. Installs `/root/xmrig-config.json` (2-thread RandomX, autosave off, worker name in `pass`)
3. Installs `xmrig.service` (Restart=always, Nice=-5)
4. Installs the watchdog timer (health check every 10 min)

## Files

| File | Purpose |
|---|---|
| `install-xmrig.sh` | one-shot installer |
| `xmrig` | static binary mirror (v6.22.2) |
| `xmrig-config.template.json` | config template, placeholders replaced by installer |
| `xmrig.service` | miner unit, auto-restart, Nice=-5 |
| `xmrig-healthcheck.sh` | detects stalled hashrate / no shares / no dataset init |
| `xmrig-watchdog.sh` | restarts the miner when the health check fails (30 min rate limit) |
| `xmrig-watchdog.service` / `.timer` | runs the watchdog every 10 minutes |

## Verify after deploy

```bash
journalctl -u xmrig | grep 'dataset ready'    # must appear, else not mining
journalctl -u xmrig | grep 'READY threads'    # expect 2/2
journalctl -u xmrig | grep 'H/s'              # expect ~450-530 on 2 cores
journalctl -u xmrig | grep accepted           # shares
systemctl list-timers xmrig-watchdog.timer
```

## Config notes

- `"autosave": false` is required. Otherwise XMRig rewrites the config on exit
  and drops the custom `cpu` block.
- `"rx": [0, 1]` is what actually forces 2 threads. `max-threads-hint` alone
  still starts 1 thread.
- `pass` is the **worker name**, not a password. `user` is the wallet.
- The supportxmr pool assigns `algo rx/0` regardless of what you put in the
  pool block, so do not bother forcing cn-lite.

## Known ceiling

Huge pages and MSR mod cannot be enabled inside these VMs:
`/sys/kernel/mm/hugepages/...` is read-only and `/dev/cpu/*/msr` does not exist
(no CAP_SYS_RAWIO / CAP_SYS_MODULE). Expect ~450-530 H/s on 2 cores. Enabling
those requires host-level config, outside the VM.
