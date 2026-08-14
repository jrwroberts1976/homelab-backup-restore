# 09 — Validation, Testing and Maintenance

## Backup success is not enough

A backup is considered operationally trustworthy only when both of these are true:

1. the backup job completes successfully;
2. representative recovery tests succeed.

## Daily checks

On each host:

```bash
systemctl list-timers --all | grep homelab-backup
systemctl --failed
```

On ids-01 also check replication:

```bash
systemctl list-timers --all | grep homelab-replication
sudo tail -100 /home/homelab-backup/logs/replication-k3s.log
```

The Restic server should be running after replication:

```bash
docker ps --filter name=restic-server
```

## Snapshot checks

List snapshots for each repository at least periodically and confirm timestamps move forward as expected.

For remote clients:

```bash
restic --cacert /home/homelab-backup/certs/rest-server.crt snapshots
```

using that host's repository/password/REST credential environment.

## Repository checks

Run `restic check` periodically.

Example local repository:

```bash
sudo -u homelab-backup \
  RESTIC_REPOSITORY=/home/homelab-backup/repository \
  RESTIC_PASSWORD_FILE=/home/homelab-backup/.restic-password \
  restic check
```

For a remote client repository, set its REST environment and CA first.

## Restore test cadence

Recommended minimum:

- monthly: restore one configuration file from each protected host;
- quarterly: restore/validate each critical staged database type;
- quarterly: restore from the k3s-node-01 replica rather than the primary;
- after major backup-script changes: run an immediate restore test;
- Stage 2: at least annually perform a full bare-metal exercise from the third copy.

## Database validation

### SQLite

```bash
sqlite3 restored.db 'PRAGMA integrity_check;'
```

Expected:

```text
ok
```

### Greenbone PostgreSQL custom dump

```bash
pg_restore -l gvmd.dump >/dev/null
```

A real test restore into an isolated database is stronger than catalog validation alone and should be part of later exercises.

### File Browser BoltDB

The deployment copies BoltDB while File Browser is stopped. Validation is ultimately application-level: restore a copy to an isolated/test deployment or controlled maintenance window and confirm File Browser opens it normally.

## Replication validation

From ids-01:

```bash
sudo ssh -i /root/.ssh/homelab-replica-ed25519 \
  homelab-backup@192.168.2.195 \
  'du -sh /home/homelab-backup/replica/ids-01/*; df -h /'
```

The replica sizes should be plausible compared with the primary. Exact allocated sizes can differ slightly between filesystems.

## Capacity monitoring

Check primary:

```bash
df -h /home/homelab-backup
sudo du -sh /home/homelab-backup/repository
sudo du -sh /home/homelab-backup/remote-repositories
```

Check replica:

```bash
df -h /home/homelab-backup/replica
```

Plan Stage 2 storage well before either filesystem reaches critical utilization.

## Retention

The ids-01 local repository currently uses daily/weekly/monthly retention through its backup script.

Remote repositories are served append-only to clients. Do not bolt client-side `forget --prune` onto those backup jobs. Centralized retention/maintenance must be designed so deletion privileges are separated from normal client credentials.

## Before changing any backup path

1. list the current source and destination;
2. perform an rsync/Restic dry run where available;
3. confirm no `--delete` operation points from an incomplete source toward the only good copy;
4. make the change;
5. run a fresh backup;
6. perform a restore test.

## After software upgrades

Restic, rest-server, Docker, K3s and applications may change behavior over time. After significant upgrades:

- verify backup commands still run;
- verify TLS/authentication;
- verify database staging;
- run `restic snapshots` and `restic check`;
- restore at least one representative item.

## Incident evidence

Do not delete failed-backup logs until root cause is understood. During a disaster, preserve the failed disk/repository if possible and recover to separate media rather than experimenting destructively on the only remaining source.
