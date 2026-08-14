# Backup Health Dashboard

This dashboard turns the backup design into an operational status view in Grafana.

It is designed for the existing Prometheus + node_exporter + Grafana stack.
The exporter writes Prometheus textfile metrics; Prometheus scrapes them through node_exporter.

## What the dashboard shows

### Backup health

For each protected host/repository:

- last successful backup time;
- backup age;
- snapshot count;
- last processed snapshot size;
- current backup-service state;
- repository availability.

### Restore-test health

For each repository:

- last successful restore-test time;
- restore-test age;
- whether a validated restore-test marker exists.

A restore test is only counted as successful when the restore script completes its validation and creates the marker. Merely running `restic restore` is not enough.

## Recommended status rules

| Condition | Dashboard state | Action |
|---|---|---|
| Backup age < 26h | Healthy | None |
| Backup age 26–48h | Warning | Investigate missed schedule |
| Backup age > 48h | Critical | Treat as backup failure |
| Restore test age < 31d | Healthy | None |
| Restore test age 31–90d | Warning | Schedule a restore test |
| Restore test age > 90d | Critical | Run a restore test |
| No snapshot visible | Critical | Investigate repository/client |
| Replica age > 48h | Critical | Investigate replication |

The exact thresholds can be changed in Grafana to match the operational policy.

## Installation

### 1. Install the exporter

Copy `backup-status-exporter.sh` to each monitoring host or, preferably, run the central exporter on `ids-01` where it can inspect all Restic repositories.

Example:

```bash
sudo install -m 0755 monitoring/backup-status-exporter.sh \
  /usr/local/sbin/homelab-backup-status-exporter
```

### 2. Create a root-readable configuration

Do not put passwords in GitHub.

Example `/etc/homelab-backup-monitor.env`:

```bash
OUTPUT=/var/lib/node_exporter/textfile_collector/homelab_backup.prom
RESTORE_TEST_DIR=/var/lib/homelab-backup/restore-tests

JOBS='ids-01:ids-01:homelab-backup-ids01.service
dietpi:dietpi:homelab-backup-dietpi.service
k3s-node-01:k3s-node-01:homelab-backup-k3s-node-01.service
testserver:testserver:homelab-backup-testserver.service'

RESTIC_ENV_ids_01=/etc/homelab-backup/ids-01.env
RESTIC_ENV_dietpi=/etc/homelab-backup/dietpi.env
RESTIC_ENV_k3s_node_01=/etc/homelab-backup/k3s-node-01.env
RESTIC_ENV_testserver=/etc/homelab-backup/testserver.env
```

Each repository environment file should define the appropriate connection without exposing secrets in this repository:

```bash
RESTIC_REPOSITORY='rest:https://192.168.2.242:8000/testserver/'
RESTIC_PASSWORD_FILE='/home/homelab-backup/.restic-password'
RESTIC_CACERT='/home/homelab-backup/certs/rest-server.crt'
```

Use the actual credential files for each repository.

Protect the configuration:

```bash
sudo chown root:root /etc/homelab-backup-monitor.env /etc/homelab-backup/*.env
sudo chmod 600 /etc/homelab-backup-monitor.env /etc/homelab-backup/*.env
```

### 3. Enable the node_exporter textfile collector

The exporter must write into the directory configured for node_exporter's textfile collector.

Confirm the active collector directory first:

```bash
ps aux | grep '[n]ode_exporter'
```

On hosts where node_exporter runs in Docker, mount the host directory into the container and expose it as `/textfile` (or use the existing textfile path).

### 4. Schedule the exporter

Use a short systemd timer, for example every 5 minutes. The exporter is read-only against repositories and should not run backup or prune operations.

Example service:

```ini
[Unit]
Description=Export homelab backup health metrics

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/homelab-backup-status-exporter
```

Example timer:

```ini
[Unit]
Description=Refresh homelab backup health metrics

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

### 5. Verify the metric endpoint

```bash
curl -s http://127.0.0.1:9100/metrics | grep '^homelab_backup_'
curl -s http://127.0.0.1:9100/metrics | grep '^homelab_restore_test_'
```

Then verify in Prometheus:

```promql
homelab_backup_last_success_timestamp_seconds
homelab_backup_age_seconds
homelab_restore_test_age_seconds
```

## Restore-test markers

A restore-test script should create the marker only after all validation succeeds.

Example:

```bash
marker=/var/lib/homelab-backup/restore-tests/testserver.success
mkdir -p "$(dirname "$marker")"
touch "$marker"
```

If the restore fails or validation fails, do not touch the marker. This prevents the dashboard from reporting a false green state.

## Grafana dashboard

Import:

```text
grafana-backup-health.json
```

The dashboard expects a Prometheus datasource and uses only the `homelab_backup_*` and `homelab_restore_test_*` metrics defined by the exporter.

## Alerts to add

The dashboard should eventually have alert rules for:

```promql
homelab_backup_age_seconds > 48 * 3600
```

```promql
homelab_restore_test_age_seconds > 90 * 86400
```

```promql
homelab_backup_snapshot_count == 0
```

For Stage 2, add equivalent metrics for the third-copy/archive age and capacity.
