# 03 — Restore One File or Directory

This is the preferred procedure when only a file, directory, configuration, or small data set needs to be recovered.

## Safety rules

1. Do not restore directly over a live file on the first attempt.
2. Restore into `/home/homelab-backup/restore-test` or another temporary directory.
3. Inspect and compare the restored content.
4. Stop/reload the affected service only if required.
5. Copy the recovered item into place deliberately.

## 1. Identify the correct repository

| Host | Repository |
|---|---|
| ids-01 | local `/home/homelab-backup/repository` |
| DietPi | `rest:https://192.168.2.242:8000/dietpi/` |
| k3s-node-01 | `rest:https://192.168.2.242:8000/k3s-node-01/` |
| TestServer | `rest:https://192.168.2.242:8000/testserver/` |

## 2. List snapshots

### Remote-client repository

```bash
sudo -u homelab-backup bash -c '
set -a
. /home/homelab-backup/.restic-rest-env
set +a
export RESTIC_REPOSITORY="rest:https://192.168.2.242:8000/REPOSITORY/"
export RESTIC_PASSWORD_FILE=/home/homelab-backup/.restic-password
restic --cacert /home/homelab-backup/certs/rest-server.crt snapshots
'
```

Replace `REPOSITORY` with `dietpi`, `k3s-node-01`, or `testserver`.

### ids-01 local repository

```bash
sudo -u homelab-backup \
  RESTIC_REPOSITORY=/home/homelab-backup/repository \
  RESTIC_PASSWORD_FILE=/home/homelab-backup/.restic-password \
  restic snapshots
```

## 3. Search for the file in a snapshot

Example:

```bash
restic ls latest | grep 'docker-compose.yml'
```

For remote repositories, use the same environment/CA setup shown above.

## 4. Restore only the required item

Create a clean target:

```bash
sudo rm -rf /home/homelab-backup/restore-test/*
sudo mkdir -p /home/homelab-backup/restore-test
```

Example — restore one Compose file from TestServer:

```bash
sudo -u homelab-backup bash -c '
set -a
. /home/homelab-backup/.restic-rest-env
set +a
export RESTIC_REPOSITORY="rest:https://192.168.2.242:8000/testserver/"
export RESTIC_PASSWORD_FILE=/home/homelab-backup/.restic-password
restic --cacert /home/homelab-backup/certs/rest-server.crt \
  restore latest \
  --target /home/homelab-backup/restore-test \
  --include /home/james/docker/stacks/monitoring/docker-compose.yml
'
```

The restored file will appear beneath the target using its original absolute path, for example:

```text
/home/homelab-backup/restore-test/home/james/docker/stacks/monitoring/docker-compose.yml
```

## 5. Compare before replacing

```bash
sudo diff -u \
  /home/james/docker/stacks/monitoring/docker-compose.yml \
  /home/homelab-backup/restore-test/home/james/docker/stacks/monitoring/docker-compose.yml
```

For binary files use checksums instead:

```bash
sha256sum LIVE_FILE RESTORED_FILE
```

## 6. Put the file back

Take a safety copy first:

```bash
sudo cp -a /path/to/live/file /path/to/live/file.pre-restore-$(date +%Y%m%d-%H%M%S)
```

Then install the restored copy preserving the appropriate owner/mode:

```bash
sudo cp -a /home/homelab-backup/restore-test/path/to/file /path/to/file
```

If the file belongs to a service, validate configuration before reload/restart where the service supports it.

Examples:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

or for Compose:

```bash
cd /home/james/docker/stacks/<stack>
docker compose config
docker compose up -d
```

## 7. Directory restore

Use `--include` on the directory path:

```bash
restic restore SNAPSHOT_ID \
  --target /home/homelab-backup/restore-test \
  --include /home/james/docker/stacks/proxy-auth
```

Inspect before copying it over the live directory.

## 8. Restore from the k3s-node-01 replica if ids-01 is unavailable

The second copy is stored at:

```text
/home/homelab-backup/replica/ids-01/
```

on k3s-node-01.

For the ids-01 local repository replica:

```bash
export RESTIC_REPOSITORY=/home/homelab-backup/replica/ids-01/repository
export RESTIC_PASSWORD_FILE=/path/to/recovered/restic-password
restic snapshots
restic restore latest --target /recovery/target --include /path/to/file
```

For remote repositories, identify the required repository directory beneath:

```text
/home/homelab-backup/replica/ids-01/remote-repositories
```

and use it as a local Restic repository once its exact repository root is identified.

## Success criteria

A single-file recovery is complete when:

- the desired snapshot was identified;
- the item was restored into an isolated location;
- content/ownership/permissions were checked;
- the live file was backed up before replacement;
- the affected service validates and runs normally.
