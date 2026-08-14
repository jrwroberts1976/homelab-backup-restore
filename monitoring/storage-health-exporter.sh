#!/bin/bash
set -euo pipefail

# Backup storage health exporter for node_exporter's textfile collector.
# Configure STORAGE_TARGETS as newline-separated entries:
#   name:/path
# Example:
#   ids-01:/home/homelab-backup
#   k3s-node-01:/home/homelab-backup/replica

CONFIG=${CONFIG:-/etc/homelab-backup-storage.env}
[[ -r "$CONFIG" ]] && . "$CONFIG"

OUTPUT=${OUTPUT:-/var/lib/node_exporter/textfile_collector/homelab_backup_storage.prom}
STORAGE_TARGETS=${STORAGE_TARGETS:-}

mkdir -p "$(dirname "$OUTPUT")"
tmp="${OUTPUT}.tmp.$$"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" <<'EOF'
# HELP homelab_backup_storage_size_bytes Total size of the filesystem containing backup storage.
# TYPE homelab_backup_storage_size_bytes gauge
# HELP homelab_backup_storage_free_bytes Free space on the filesystem containing backup storage.
# TYPE homelab_backup_storage_free_bytes gauge
# HELP homelab_backup_storage_used_bytes Used space on the filesystem containing backup storage.
# TYPE homelab_backup_storage_used_bytes gauge
# HELP homelab_backup_storage_used_percent Percentage of filesystem space used by backup storage.
# TYPE homelab_backup_storage_used_percent gauge
# HELP homelab_backup_storage_mounted Whether the backup storage path is on a mounted filesystem.
# TYPE homelab_backup_storage_mounted gauge
# HELP homelab_backup_storage_writable Whether the backup storage path is writable.
# TYPE homelab_backup_storage_writable gauge
EOF

while IFS=: read -r name path; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue

  labels="storage=\"$name\",path=\"$path\""
  mounted=0
  writable=0

  if mountpoint -q -- "$path" 2>/dev/null; then mounted=1; fi
  if [[ -d "$path" && -w "$path" ]]; then writable=1; fi

  printf 'homelab_backup_storage_mounted{%s} %s\n' "$labels" "$mounted" >> "$tmp"
  printf 'homelab_backup_storage_writable{%s} %s\n' "$labels" "$writable" >> "$tmp"

  if [[ -d "$path" ]]; then
    read -r size used free _ < <(df -B1 --output=size,used,avail,pcent "$path" | tail -1)
    used_percent=$(awk -v u="$used" -v s="$size" 'BEGIN { if (s>0) printf "%.2f", (u/s)*100; else print "0" }')
    printf 'homelab_backup_storage_size_bytes{%s} %s\n' "$labels" "$size" >> "$tmp"
    printf 'homelab_backup_storage_used_bytes{%s} %s\n' "$labels" "$used" >> "$tmp"
    printf 'homelab_backup_storage_free_bytes{%s} %s\n' "$labels" "$free" >> "$tmp"
    printf 'homelab_backup_storage_used_percent{%s} %s\n' "$labels" "$used_percent" >> "$tmp"
  fi
done <<< "$STORAGE_TARGETS"

mv "$tmp" "$OUTPUT"
trap - EXIT
