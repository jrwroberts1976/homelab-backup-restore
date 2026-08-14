#!/bin/bash
set -euo pipefail

# Homelab backup health exporter for node_exporter's textfile collector.
#
# Configure one or more jobs in /etc/homelab-backup-monitor.env, for example:
#   OUTPUT=/var/lib/node_exporter/textfile_collector/homelab_backup.prom
#   JOBS='testserver:k3s-node-01:homelab-backup-testserver.service'
#
# Each job is: host:repo:systemd-service
# RESTIC_REPOSITORY, RESTIC_PASSWORD_FILE and RESTIC_CACERT must be supplied
# through a root-readable environment/config on the monitoring host. Do not
# put credentials in this script or in Git.

CONFIG=${CONFIG:-/etc/homelab-backup-monitor.env}
if [[ -r "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

OUTPUT=${OUTPUT:-/var/lib/node_exporter/textfile_collector/homelab_backup.prom}
JOBS=${JOBS:-}
RESTIC_BIN=${RESTIC_BIN:-restic}

mkdir -p "$(dirname "$OUTPUT")"
tmp="${OUTPUT}.tmp.$$"
trap 'rm -f "$tmp"' EXIT

printf '# HELP homelab_backup_last_success_timestamp_seconds Unix timestamp of the last successful backup.\n'
printf '# TYPE homelab_backup_last_success_timestamp_seconds gauge\n'
printf '# HELP homelab_backup_last_duration_seconds Duration of the last successful backup.\n'
printf '# TYPE homelab_backup_last_duration_seconds gauge\n'
printf '# HELP homelab_backup_last_size_bytes Repository snapshot size reported by Restic.\n'
printf '# TYPE homelab_backup_last_size_bytes gauge\n'
printf '# HELP homelab_backup_age_seconds Age of the latest Restic snapshot.\n'
printf '# TYPE homelab_backup_age_seconds gauge\n'
printf '# HELP homelab_backup_snapshot_count Number of Restic snapshots visible in the repository.\n'
printf '# TYPE homelab_backup_snapshot_count gauge\n'
printf '# HELP homelab_backup_service_active Whether the backup systemd service is active/running (1/0).\n'
printf '# TYPE homelab_backup_service_active gauge\n'
printf '# HELP homelab_backup_last_success Whether the most recent backup completed successfully (1/0).\n'
printf '# TYPE homelab_backup_last_success gauge\n'
printf '# HELP homelab_restore_test_last_success_timestamp_seconds Unix timestamp of the last successful restore test.\n'
printf '# TYPE homelab_restore_test_last_success_timestamp_seconds gauge\n'
printf '# HELP homelab_restore_test_age_seconds Age of the latest successful restore test.\n'
printf '# TYPE homelab_restore_test_age_seconds gauge\n'
printf '# HELP homelab_restore_test_success Whether a successful restore test marker exists (1/0).\n'
printf '# TYPE homelab_restore_test_success gauge\n'

now=$(date +%s)

while IFS=: read -r host repo service; do
  [[ -z "${host:-}" || "$host" == \#* ]] && continue

  labels="host=\"$host\",repo=\"$repo\""
  active=0
  if systemctl is-active --quiet "$service" 2>/dev/null; then active=1; fi
  printf 'homelab_backup_service_active{%s} %s\n' "$labels" "$active"

  # Load per-repository credentials from RESTIC_ENV_<repo>, e.g.
  # RESTIC_ENV_testserver=/etc/homelab-backup/testserver.env
  env_var="RESTIC_ENV_${repo//-/_}"
  env_file="${!env_var:-}"
  if [[ -n "$env_file" && -r "$env_file" ]]; then
    # shellcheck disable=SC1090
    . "$env_file"
  fi

  if [[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD_FILE:-}" && -n "${RESTIC_CACERT:-}" ]]; then
    snapshots=$($RESTIC_BIN snapshots --json 2>/dev/null || true)
    if [[ -n "$snapshots" ]]; then
      latest=$(printf '%s' "$snapshots" | python3 -c 'import json,sys; x=json.load(sys.stdin); print(json.dumps(max(x,key=lambda r:r["time"])) if x else "")' 2>/dev/null || true)
      count=$(printf '%s' "$snapshots" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
      if [[ -n "$latest" ]]; then
        ts=$(printf '%s' "$latest" | python3 -c 'import json,sys,datetime; x=json.load(sys.stdin); print(int(datetime.datetime.fromisoformat(x["time"].replace("Z","+00:00")).timestamp()))')
        size=$(printf '%s' "$latest" | python3 -c 'import json,sys; print(int(json.load(sys.stdin).get("summary",{}).get("total_bytes_processed",0)))')
        printf 'homelab_backup_last_success_timestamp_seconds{%s} %s\n' "$labels" "$ts"
        printf 'homelab_backup_age_seconds{%s} %s\n' "$labels" "$((now-ts))"
        printf 'homelab_backup_last_size_bytes{%s} %s\n' "$labels" "$size"
        printf 'homelab_backup_snapshot_count{%s} %s\n' "$labels" "$count"
        printf 'homelab_backup_last_success{%s} 1\n' "$labels"
      fi
    fi
  fi

  # A restore-test script should touch this marker only after validation passes.
  # Example: /var/lib/homelab-backup/restore-tests/<repo>.success
  marker="${RESTORE_TEST_DIR:-/var/lib/homelab-backup/restore-tests}/$repo.success"
  if [[ -f "$marker" ]]; then
    rts=$(stat -c %Y "$marker")
    printf 'homelab_restore_test_last_success_timestamp_seconds{%s} %s\n' "$labels" "$rts"
    printf 'homelab_restore_test_age_seconds{%s} %s\n' "$labels" "$((now-rts))"
    printf 'homelab_restore_test_success{%s} 1\n' "$labels"
  else
    printf 'homelab_restore_test_success{%s} 0\n' "$labels"
  fi

done <<< "$JOBS"

mv "$tmp" "$OUTPUT"
trap - EXIT
