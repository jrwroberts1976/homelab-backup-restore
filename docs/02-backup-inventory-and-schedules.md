# 02 — Backup Inventory and Schedules

## ids-01

### Repository

```text
/home/homelab-backup/repository
```

Repository password file:

```text
/home/homelab-backup/.restic-password
```

Backup script:

```text
/home/homelab-backup/scripts/backup-ids-01.sh
```

Systemd units:

```text
homelab-backup-ids01.service
homelab-backup-ids01.timer
```

Normal schedule: around 02:30 daily with randomized delay.

### Important protected data

- `/etc`
- `/home/james/scripts`
- `/home/james/docker/stacks`
- monitoring configuration
- Grafana configuration/data as selected
- Prometheus rules/configuration
- Loki configuration
- staged Greenbone PostgreSQL database dump

### Greenbone database

The backup script creates a fresh custom-format PostgreSQL dump from container:

```text
greenbone-community-edition-pg-gvm-1
```

database:

```text
gvmd
```

The staged dump is validated with `pg_restore -l` before/after recovery as appropriate.

### Retention

The ids-01 local repository uses:

```text
--keep-daily 7
--keep-weekly 4
--keep-monthly 12
```

and prune is performed locally.

---

## DietPi

### Remote repository

```text
rest:https://192.168.2.242:8000/dietpi/
```

### Important protected data

- `/boot/firmware`
- `/etc`
- selected home directories
- `/opt`
- `/var/www`
- staged Pi-hole databases

Live Pi-hole databases are excluded and replaced by consistent SQLite copies in staging.

### Typical timer

DietPi is intended to run after ids-01 and before the later TestServer window. Verify actual timer state on the host with:

```bash
systemctl list-timers --all | grep homelab-backup
```

---

## k3s-node-01

### Remote repository

```text
rest:https://192.168.2.242:8000/k3s-node-01/
```

Repository ID at initial creation:

```text
fa71e33ca3
```

### Important protected data

- `/etc`
- `/boot/firmware`
- selected scripts/Docker config
- `.kube`
- homelab software tooling
- staged K3s SQLite datastore
- `/var/lib/rancher/k3s/server/token`

### Excluded bulk data

- ROMs
- videos
- GoPro/media data
- caches
- logs

### Timer

Normal schedule: around 02:50 daily with randomized delay.

---

## TestServer

### Remote repository

```text
rest:https://192.168.2.242:8000/testserver/
```

Repository ID at initial creation:

```text
0b1d890a0e
```

### Important protected data

- `/etc`
- `/boot/firmware`
- `/home/james/docker/stacks`
- selected `/home/james/docker/data`
- scripts
- homelab software collector
- `/home/james/homelab`
- staged application databases

### Staged databases

SQLite staging is used for:

- Uptime Kuma (`kuma.db`)
- BirdNET (`birdnet.db`)
- Authelia (`authelia.db`)
- Nginx Proxy Manager (`npm.db`)
- CrowdSec (`crowdsec.db`)
- Grafana (`grafana.db`)

File Browser uses BoltDB rather than SQLite. Its container is stopped briefly, the DB is copied to staging, and the container is restarted.

### Excluded data

- Prometheus TSDB history
- Loki log history
- BirdNET bulk data/recordings
- live database files replaced by staged copies
- cache/log data
- crash/core files

### Timer

Normal schedule: around 03:30 daily with randomized delay.

---

## Central replica

Replication service on ids-01:

```text
homelab-replication-k3s.service
homelab-replication-k3s.timer
```

Normal schedule: around 04:15 daily with randomized delay.

Destination:

```text
k3s-node-01:/home/homelab-backup/replica/ids-01/
```

Protected trees:

```text
repository/
remote-repositories/
```

## Operational commands

List backup timers:

```bash
systemctl list-timers --all | grep -E 'homelab-backup|homelab-replication'
```

Review recent service status:

```bash
systemctl status <service> --no-pager -l
```

List snapshots for a remote repository:

```bash
set -a
. /home/homelab-backup/.restic-rest-env
set +a
export RESTIC_REPOSITORY='rest:https://192.168.2.242:8000/<repo>/'
export RESTIC_PASSWORD_FILE=/home/homelab-backup/.restic-password
restic --cacert /home/homelab-backup/certs/rest-server.crt snapshots
```

Do not run client-side `forget --prune` against append-only remote repositories. Retention/maintenance for those repositories must be performed centrally with appropriate privileges/design.
