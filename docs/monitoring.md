# CtrlX Relay monitoring runbook

## Stack
- **Source:** Vapor `/metrics` (token-protected) + `node_exporter` on the VM
- **Collector:** Grafana Alloy (systemd) on the VM, push to Grafana Cloud Prometheus
- **Storage / UI:** an operator-owned Grafana Cloud stack
- **Alerts:** an operator-owned Discord webhook
- **Config-as-code:** `CtrlxPackage/monitoring/grizzly/` applied via `grr apply`

## Initial Setup

The following is an operator checklist, not a record of any existing CtrlX
production service. Keep credentials outside the repository.

### Grafana Cloud (Phase 3)
- [ ] Create an operator-owned Grafana stack and record its Prometheus URL/user.
- [ ] Create a `metrics:write` access token and a separate Grizzly service-account token.
- [ ] Generate `METRICS_TOKEN` with `openssl rand -hex 32`; add it to `/opt/ctrlx/.env.production` and redeploy.
- [ ] Verify `/metrics` through loopback with the bearer token and verify port 8080 is not public.
- [ ] Copy `CtrlxPackage/monitoring/agents` to `/opt/ctrlx-monitoring` on the Relay host.
- [ ] Run `install.sh` with `METRICS_TOKEN`, `GRAFANA_PROM_URL`, `GRAFANA_PROM_USER`, and `GRAFANA_PROM_TOKEN`.
- [ ] Confirm `node_exporter` and `alloy` are active.
- [ ] Query `ctrlx_active_pairs` and `node_filesystem_avail_bytes` in Grafana.

### Discord (Phase 4)
- [ ] Create a private alert channel and save its webhook as `DISCORD_WEBHOOK_URL`.
- [ ] Smoke-test the webhook without committing it.

### grizzly config-as-code (Phase 5)
- [ ] Install Grizzly and copy `.env.example` to the ignored `.env` file.
- [ ] Set `GRAFANA_URL`, `GRAFANA_TOKEN`, and `DISCORD_WEBHOOK_URL`.
- [ ] If the Prometheus datasource UID is not `grafanacloud-prom`, replace that UID in the checked-in alert and dashboard YAML before applying it.
- [ ] Run `make diff`, then `make apply`, and test the contact point in Grafana.

### Smoke test (Phase 6 / Task 24)
- [ ] Stop `relay` with Docker Compose from `/opt/ctrlx`; expect an alert after 2–3 minutes.
- [ ] Start `relay` again; expect a resolved notification.

## Daily life

### Re-apply after editing alerts/dashboards
```bash
cd CtrlxPackage/monitoring/grizzly
set -a; . ./.env; set +a
make diff   # see what would change
make apply  # actually apply
```

### Pull current state from Grafana
```bash
make pull
ls pulled/
```
Use this if you've edited something in the UI and want to bring it into git.

## Troubleshooting

### Alloy is not pushing metrics
```bash
ssh root@$DEPLOY_HOST 'systemctl status alloy'
ssh root@$DEPLOY_HOST 'journalctl -u alloy -n 100 --no-pager'
```
Common causes: bad `GRAFANA_PROM_TOKEN`, expired access policy, network egress blocked.

### `/metrics` returns 401 from Alloy
The token in `/etc/alloy/alloy.env` does not match `METRICS_TOKEN` in
`/opt/ctrlx/.env.production`. Re-run `install.sh` with the correct value.

### node_exporter shows no data
```bash
ssh root@$DEPLOY_HOST 'curl -fsS http://127.0.0.1:9100/metrics | head'
```
If empty, the binary may have failed — check `journalctl -u node_exporter`.

### A host metric (oom_kill, pswpin, etc.) is missing
The unit at `/etc/systemd/system/node_exporter.service` runs with `--collector.disable-defaults` and an explicit allowlist. New collectors only appear after the corresponding flag is added. The repo's `monitoring/agents/node_exporter.service` is the source of truth — edit it, re-run `install.sh`, and restart node_exporter on the host.

### Discord notifications stopped arriving
Test the contact point in Grafana UI (Alerting → Contact points → `discord-alerts` → Test). If that fails, regenerate the webhook in Discord and update `DISCORD_WEBHOOK_URL`, then `make apply`.

### A new metric I added isn't visible
1. Confirm the relay actually exposes it: `curl -H "Authorization: Bearer $METRICS_TOKEN" http://127.0.0.1:8080/metrics | grep <name>`
2. Wait one scrape interval (30s).
3. Query in Grafana Explore: `<metric_name>` against the Prometheus datasource.

## Rotating the metrics token

1. Generate a new value: `openssl rand -hex 32`.
2. Update `/opt/ctrlx/.env.production` on the VM and restart Relay with Docker Compose.
3. Update `/etc/alloy/alloy.env` and restart Alloy: `systemctl restart alloy`.

## Free-tier limits

Confirm the current limits with the selected monitoring provider. CtrlX metrics
deliberately avoid per-pair labels to prevent unbounded cardinality.

## Metrics emitted

| Metric | Type | Description |
|--------|------|-------------|
| `ctrlx_messages_relayed_total` | counter | Encrypted messages relayed since process start |
| `ctrlx_push_notifications_total` | counter | Push notifications sent to APNs since process start |
| `ctrlx_trial_starts_total` | counter | Trial licenses started; 0 if licensing is disabled |
| `ctrlx_license_activations_total` | counter | License keys activated; 0 if licensing is disabled |
| `ctrlx_license_deactivations_total` | counter | License keys deactivated; 0 if licensing is disabled |
| `ctrlx_license_validation_failures_total` | counter | License validation failures from Lemon Squeezy; 0 if licensing is disabled |
| `ctrlx_blocked_host_attempts_total` | counter | Connection attempts blocked due to licensing; 0 if licensing is disabled |
| `ctrlx_paused_pairing_attempts_total` | counter | Pairing registrations refused by the pairing-pause switch (`PAIRING_PAUSED_MESSAGE`) |
| `ctrlx_active_pairs` | gauge | Currently-paired devices |
| `ctrlx_ws_connections{device_type="host\|viewer"}` | gauge | Active WebSocket connections per device type |
| `ctrlx_uptime_seconds` | gauge | Process uptime |
| `ctrlx_build_info{version="..."}` | gauge | Always 1; the `version` label carries the build identifier |

Plus the standard `node_exporter` metrics for host CPU/RAM/disk/net, including the `vmstat` collector (`node_vmstat_oom_kill`, `node_vmstat_pswpin`, `node_vmstat_pswpout`) used by the host-pressure alerts.

## Alerts

| Alert | Severity | Fires when | Hint |
|-------|----------|------------|------|
| `relay-down` | critical | `up{job="ctrlx-relay"} == 0` for 2m | Vapor process or alloy scrape is broken |
| `host-oom-kill` | critical | `increase(node_vmstat_oom_kill[5m]) > 0` | A process was OOM-killed; check `journalctl -k \| grep -i oom` |
| `host-load-high` | warning | `node_load5 / cpu_count > 2` for 10m | Sustained CPU contention; usually a noisy-neighbor container |
| `host-swap-thrash` | warning | `rate(pswpin+pswpout) > 100` for 5m | Memory pressure; an OOM kill is usually imminent |
| `high-memory` | warning | host MemAvailable < 15% for 10m | General memory pressure |
| `disk-full` | warning | `/` > 85% used for 30m | Investigate `du -shx /var/lib/docker/*` |
| `high-relay-rate` | warning | message rate > 50/s for 15m | Legitimate spike or runaway client |

### Diagnosing host-pressure alerts

When `host-oom-kill`, `host-load-high`, or `host-swap-thrash` fires, the relay is rarely the cause — the box is shared with other apps. Walkthrough:

1. `ssh root@$DEPLOY_HOST 'uptime; free -h; docker ps'` — confirm load, mem, container restart counts.
2. `ssh root@$DEPLOY_HOST 'docker stats --no-stream'` — find the container hogging memory or CPU.
3. `ssh root@$DEPLOY_HOST 'journalctl -k --since "30 min ago" | grep -i oom'` — find the OOM victim.
4. If a container is in a restart loop, apply a `--memory` cgroup limit so it dies in its own cgroup without taking down the host: `docker update --memory=2g --memory-swap=2g <name>`.
