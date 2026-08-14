# 04 — Application and Database Recovery

Use this runbook when configuration alone is insufficient and application state/database contents must be recovered.

## General method

1. Stop or isolate the affected application.
2. Restore the staged backup copy to a temporary location.
3. Validate it.
4. Back up the current live database/state.
5. Replace the live state deliberately.
6. Correct ownership and permissions.
7. Start the application and validate behaviour.

Never overwrite the only remaining live copy before confirming the restored data is readable.

---

## TestServer SQLite applications

The staged SQLite backup directory is restored as:

```text
/home/homelab-backup/staging
```

and contains:

```text
kuma.db
birdnet.db
authelia.db
npm.db
crowdsec.db
grafana.db
```

### Validate a restored SQLite DB

```bash
sqlite3 /recovery/path/database.db 'PRAGMA integrity_check;'
```

Expected:

```text
ok
```

### Uptime Kuma

Live DB:

```text
/home/james/docker/data/availability/uptime-kuma/data/kuma.db
```

Procedure:

```bash
cd /home/james/docker/stacks/availability
docker compose stop uptime-kuma
sudo cp -a /home/james/docker/data/availability/uptime-kuma/data/kuma.db \
  /home/james/docker/data/availability/uptime-kuma/data/kuma.db.pre-restore
sudo cp /recovery/path/kuma.db \
  /home/james/docker/data/availability/uptime-kuma/data/kuma.db
sudo rm -f /home/james/docker/data/availability/uptime-kuma/data/kuma.db-wal \
  /home/james/docker/data/availability/uptime-kuma/data/kuma.db-shm
# Restore original ownership/mode as appropriate.
docker compose start uptime-kuma
```

Then verify container health and the Kuma UI.

### BirdNET

Live DB:

```text
/home/james/docker/data/birdnet-go/data/birdnet.db
```

Stop `birdnet-go` before replacing the DB. Preserve the current file first, replace it with staged `birdnet.db`, remove stale WAL/SHM only while the application is stopped, restore ownership, then start BirdNET and verify detections/history.

### Authelia

Live DB:

```text
/home/james/docker/data/proxy-auth/authelia/config/db.sqlite3
```

Stop Authelia, preserve the live DB, restore staged `authelia.db`, correct ownership, restart, and test authentication.

### Nginx Proxy Manager

Live DB:

```text
/home/james/docker/data/proxy-auth/npm/data/database.sqlite
```

Stop NPM before replacement. Preserve the current DB, restore staged `npm.db`, correct ownership, restart NPM, then validate proxy hosts and certificates.

The NPM letsencrypt/config directories are backed up separately and should normally be recovered together with the database for a complete NPM recovery.

### CrowdSec

Live DB:

```text
/home/james/docker/data/security/crowdsec/data/crowdsec.db
```

Stop CrowdSec, preserve live DB, restore staged `crowdsec.db`, correct ownership, start CrowdSec, and verify decisions/acquisitions.

### Grafana

Live DB:

```text
/home/james/docker/data/monitoring/grafana/data/grafana.db
```

Stop Grafana, preserve live DB, restore staged `grafana.db`, correct ownership (Grafana container currently uses UID/GID appropriate to its deployment), restart and verify dashboards, data sources and alerting.

---

## File Browser BoltDB

File Browser does not use SQLite for this deployment. Its database is copied while the container is stopped.

Live database:

```text
/home/james/docker/data/management/filebrowser/database/filebrowser.db
```

Recovery:

```bash
docker stop filebrowser
sudo cp -a /home/james/docker/data/management/filebrowser/database/filebrowser.db \
  /home/james/docker/data/management/filebrowser/database/filebrowser.db.pre-restore
sudo cp /recovery/path/filebrowser.db \
  /home/james/docker/data/management/filebrowser/database/filebrowser.db
# Restore owner/mode expected by the deployment.
docker start filebrowser
docker ps --filter name=filebrowser
```

Verify the container becomes healthy and the UI/login/configuration are correct.

---

## Pi-hole / DietPi

Pi-hole's live SQLite files are deliberately excluded from direct Restic backup. Consistent snapshots are staged by the DietPi backup job.

During recovery:

1. restore `/etc/pihole` configuration and staged DB copies;
2. stop Pi-hole/FTL before replacing database files;
3. preserve current files;
4. place restored DB files at the expected live names/paths;
5. correct ownership and permissions;
6. restart FTL/Pi-hole;
7. test DNS resolution through Pi-hole and then through Unbound.

Validate a restored SQLite copy before use:

```bash
sqlite3 restored.db 'PRAGMA integrity_check;'
```

---

## K3s embedded datastore

The backup set contains a consistent copy of the embedded SQLite datastore:

```text
/home/homelab-backup/staging/k3s-state.db
```

and the server token:

```text
/var/lib/rancher/k3s/server/token
```

The datastore should never be replaced while K3s is running.

High-level recovery:

```bash
sudo systemctl stop k3s
```

Preserve the current server DB directory before making changes. Restore the validated staged database to the correct K3s datastore location (`/var/lib/rancher/k3s/server/db/state.db`) and restore the server token with restrictive permissions. Restore `/etc/rancher/k3s` and K3s service overrides/config as required. Then start K3s and verify:

```bash
sudo systemctl start k3s
sudo systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl get pods -A
```

Before replacing the live datastore, always validate the staged/restored DB:

```bash
sqlite3 k3s-state.db 'PRAGMA integrity_check;'
```

---

## Greenbone/GVM PostgreSQL

The ids-01 backup stages a custom-format PostgreSQL dump of the `gvmd` database.

Validate the dump catalog:

```bash
pg_restore -l gvmd.dump >/dev/null
```

For recovery, use a clean PostgreSQL/GVM deployment at a compatible version where possible. Stop application access, create/prepare the target database owned by the correct `gvmd` user, then restore using `pg_restore`.

Typical pattern (exact container names/users may change after rebuild):

```bash
pg_restore --clean --if-exists --no-owner \
  --dbname=gvmd /path/to/gvmd.dump
```

If restoring inside the Greenbone PostgreSQL container, copy/stream the dump into that environment and use the database owner/user configured by the deployment.

After restore:

- start GVM services;
- verify tasks, targets and findings are visible;
- verify feeds and scanner connectivity;
- run a controlled scan or status query.

---

## Docker application configuration

Most TestServer applications can be recreated from:

```text
/home/james/docker/stacks
/home/james/docker/data
```

After restoring those trees:

```bash
cd /home/james/docker/stacks/<stack>
docker compose config
docker compose pull
docker compose up -d
```

Do not blindly start all stacks simultaneously after a bare-metal rebuild. Bring up dependencies first and validate each group.
