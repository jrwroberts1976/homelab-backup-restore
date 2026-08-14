# 07 — Backup Platform and Replica Recovery

Use this runbook when `ids-01`, the Restic REST server, or the primary backup storage is unavailable.

## Normal layout

Primary on `ids-01`:

```text
/home/homelab-backup/repository
/home/homelab-backup/remote-repositories
```

Second copy on `k3s-node-01`:

```text
/home/homelab-backup/replica/ids-01/repository
/home/homelab-backup/replica/ids-01/remote-repositories
```

## Scenario A — Restic server container failed, ids-01 storage healthy

1. Confirm repository data still exists.
2. Inspect the Docker stack under `/home/james/docker/stacks/restic-server`.
3. Validate Compose:

```bash
cd /home/james/docker/stacks/restic-server
docker compose config
```

4. Start/recreate only the Restic server:

```bash
docker compose up -d
```

5. Verify listening port and container state:

```bash
docker ps --filter name=restic-server
sudo ss -lntp | grep ':8000'
```

6. Verify anonymous access is rejected:

```bash
sudo curl --cacert /home/homelab-backup/rest-server/tls/rest-server.crt \
  -I https://192.168.2.242:8000/
```

Expected: HTTP 401.

7. Verify an authenticated repository path returns a valid authenticated response (HEAD commonly returns 405/Allow POST with this server setup).

## Scenario B — ids-01 repository disk/files lost, k3s replica healthy

Do **not** run the normal replication job with an empty/new ids-01 source, because `rsync --delete` could remove the good replica.

Disable replication until recovery completes:

```bash
sudo systemctl disable --now homelab-replication-k3s.timer
```

On a rebuilt/repaired ids-01, recreate the target directories and copy from k3s-node-01 **toward ids-01**.

Example using a temporary recovery SSH arrangement:

```bash
rsync -aHAX --numeric-ids \
  homelab-backup@192.168.2.195:/home/homelab-backup/replica/ids-01/repository/ \
  /home/homelab-backup/repository/

rsync -aHAX --numeric-ids \
  homelab-backup@192.168.2.195:/home/homelab-backup/replica/ids-01/remote-repositories/ \
  /home/homelab-backup/remote-repositories/
```

Use an authorized recovery account/key appropriate to the rebuilt host. Do not assume the original root replication private key survived.

After copying:

```bash
sudo du -sh /home/homelab-backup/repository
sudo du -sh /home/homelab-backup/remote-repositories
```

Validate Restic repositories before enabling any backup client or retention/prune job.

## Scenario C — ids-01 completely lost

1. Rebuild ids-01 base OS/network.
2. Install Docker/Restic/rsync.
3. Recover the repository trees from k3s-node-01.
4. Recover Restic repository passwords from the independent secure credential store.
5. Recover Rest server TLS certificate/key and authentication data from secure backup.
6. Restore/recreate the Restic server Compose stack.
7. Start the REST server.
8. Verify client access.
9. Restore the ids-01 host configuration from its local repository replica.
10. Restore Greenbone from `gvmd.dump` if required.
11. Validate all repositories with `restic snapshots` and `restic check` where appropriate.
12. Only then re-enable client backup timers.
13. Recreate the dedicated ids-01-to-k3s replication key and authorization if needed.
14. Re-enable replication only after confirming source and destination directions.

## Scenario D — k3s replica lost, ids-01 healthy

1. Disable the replica timer while preparing the target if needed.
2. Recreate on k3s-node-01:

```text
/home/homelab-backup/replica/ids-01
```

3. Recreate/authorize the dedicated `homelab-backup` SSH account/key.
4. Perform `rsync -n --delete` dry runs first.
5. Stop Restic server briefly.
6. Run a full real replication.
7. Restart Restic server.
8. Verify replica sizes.
9. Re-enable the daily replication timer.

## Replication safeguards

The normal job runs from ids-01 to k3s-node-01 and uses `--delete`. Therefore:

- never run it when the primary source is incomplete, empty, or known-corrupt;
- disable the timer immediately during primary-storage disaster recovery;
- check direction twice before any manual `rsync --delete`;
- dry-run first when changing paths or rebuilding either endpoint.

## Repository validation

For a local Restic repository:

```bash
export RESTIC_REPOSITORY=/path/to/repository
export RESTIC_PASSWORD_FILE=/secure/path/password
restic snapshots
restic check
```

For remote repositories copied to local storage, identify the exact Restic repository root beneath the replicated `remote-repositories` tree, then use that root as `RESTIC_REPOSITORY` and provide its matching repository password.

## Platform recovery success criteria

- primary repository trees are present and size is plausible;
- encrypted repositories open with expected passwords;
- snapshots are listed;
- `restic check` reports no repository errors for tested repositories;
- Restic REST server is reachable over TLS;
- unauthorized requests are rejected;
- authorized clients can access their repositories;
- daily host backups succeed;
- replica synchronization succeeds;
- a test file can be restored from the recovered platform.
