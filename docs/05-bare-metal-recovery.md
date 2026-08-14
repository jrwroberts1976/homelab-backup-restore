# 05 — Full Bare-Metal Recovery

This runbook covers rebuilding a failed host from replacement/blank storage. It is intentionally conservative: reinstall the OS and required platform software first, restore configuration/state into a staging area, then reintroduce services deliberately.

## Bare-metal principles

- Do not attempt to clone a failed filesystem blindly from Restic.
- Restic restores protected files and state; it does not recreate partition tables, bootloaders, firmware or every package automatically.
- Reinstall a compatible base OS, then restore configuration/application state.
- Use the same hostname and IP where possible to reduce service/configuration changes.
- Keep the failed disk untouched until recovery is proven if it is still readable.

## Information required before disaster

Maintain or be able to determine:

- hostname;
- IP address/subnet/gateway/DNS;
- CPU architecture (`amd64`/`arm64`);
- OS family/release;
- disk layout;
- Docker/K3s installation method;
- repository password(s);
- REST credentials if recovering via ids-01;
- TLS CA certificate;
- SSH/admin access.

Secrets are **not** stored in this Git repository. They must exist in a secure independent location.

---

## Generic bare-metal workflow

### Phase 1 — Prepare replacement hardware/storage

1. Replace or wipe the failed system disk only after confirming the correct target.
2. Install a compatible Debian/Raspberry Pi/DietPi OS as appropriate.
3. Configure networking and hostname.
4. Fully patch the base OS.
5. Install SSH and verify remote access.

Useful checks:

```bash
hostname
ip addr
ip route
lsblk -f
df -hT
uname -a
```

### Phase 2 — Install recovery tools

At minimum:

```bash
sudo apt update
sudo apt install -y restic rsync sqlite3 ca-certificates curl
```

Install Docker/K3s/application prerequisites only where required.

Create a recovery directory:

```bash
sudo mkdir -p /recovery/restic
```

### Phase 3 — Obtain the repository and credentials

Preferred source when ids-01 is healthy:

```text
https://192.168.2.242:8000/<repository>/
```

If ids-01 is unavailable, use the replicated repository on k3s-node-01:

```text
/home/homelab-backup/replica/ids-01/
```

Recover the repository password and, for REST access, the REST credentials and CA certificate from the secure credential store/off-host copy.

Never copy secrets into this Git repository.

### Phase 4 — Validate repository before restoring

```bash
restic snapshots
restic check
```

For REST repositories also specify `--cacert` and the repository/credential environment.

### Phase 5 — Restore into staging

Do not initially restore over `/`.

```bash
sudo mkdir -p /recovery/restore
restic restore latest --target /recovery/restore
```

Inspect:

```bash
sudo du -sh /recovery/restore
sudo find /recovery/restore -maxdepth 3 -type d | head -100
```

### Phase 6 — Restore OS configuration selectively

Restore `/etc` carefully. Avoid blindly replacing files that are specific to the newly installed OS/kernel before comparing them.

Priority areas normally include:

- network configuration;
- systemd custom units/overrides;
- cron/timers;
- Docker configuration;
- application configuration;
- SSH configuration/authorized keys where appropriate;
- monitoring exporters/scripts;
- firewall configuration.

Use `diff` before replacing files where practical.

### Phase 7 — Restore application data/state

Follow [Application and database recovery](04-application-recovery.md).

### Phase 8 — Bring services up in dependency order

Recommended order:

1. networking/firewall;
2. Docker/K3s runtime;
3. databases/stateful services;
4. DNS/proxy/authentication;
5. monitoring/logging;
6. application services;
7. optional/non-critical services.

### Phase 9 — Validate

Check:

```bash
systemctl --failed
docker ps
```

where relevant:

```bash
kubectl get nodes
kubectl get pods -A
```

Test DNS, reverse proxy, authentication and application endpoints.

### Phase 10 — Re-enable backups

Do not immediately enable timers until the restored host is stable and you are certain it will not overwrite/delete the only useful recovery source.

Once validated:

```bash
systemctl enable --now <backup-timer>
systemctl list-timers --all | grep homelab-backup
```

Run a fresh backup and then a small restore test.

---

# Host-specific bare-metal outlines

## ids-01

1. Install compatible Debian on replacement NVMe/storage.
2. Configure hostname `ids-01` and network (`192.168.2.242` if still correct).
3. Install Docker, Restic and required monitoring/security packages.
4. Recover the ids-01 Restic repository from k3s-node-01 replica if the original disk is lost.
5. Restore `/etc`, `/home/james/scripts`, Docker stack definitions and selected monitoring configuration.
6. Recreate/restage Greenbone deployment.
7. Restore `gvmd.dump` with `pg_restore` into the Greenbone PostgreSQL database.
8. Recreate the Restic REST server using the documented stack/settings.
9. Recover `remote-repositories` from the k3s-node-01 replica.
10. Restore TLS certificate/key and `.htpasswd` from a secure backup/recovery source.
11. Start Restic server and verify authenticated access.
12. Reconnect client backup jobs.
13. Validate monitoring, Suricata and Greenbone.
14. Re-enable ids-01 backup and replication timer.

## k3s-node-01

1. Install compatible Debian/Raspberry Pi OS to replacement storage.
2. Configure hostname and networking.
3. Install K3s using the same server role/options (`--disable servicelb`, kubeconfig mode/other overrides as documented on the host).
4. Stop K3s before datastore replacement.
5. Restore `/etc/rancher/k3s`, systemd overrides, the K3s server token and staged `k3s-state.db`.
6. Place the validated DB at `/var/lib/rancher/k3s/server/db/state.db` with correct owner/mode.
7. Start K3s.
8. Validate node, pods, Traefik, MetalLB and local workloads.
9. Recreate the homelab backup client and timer.
10. Recreate the ids-01 replica target directory and replication SSH authorization if this host also lost the replica.

## TestServer

1. Install compatible Debian/Raspberry Pi OS.
2. Configure hostname `TestServer` and networking.
3. Install Docker/Compose, Restic and SQLite.
4. Restore `/home/james/docker/stacks`, selected `/home/james/docker/data`, `/home/james/homelab`, scripts and configuration.
5. Restore application databases using the application recovery runbook.
6. Validate Compose files with `docker compose config`.
7. Bring up stacks gradually: proxy/auth, monitoring, availability, dashboards, management, applications.
8. Verify NPM, Authelia, Uptime Kuma, Grafana, CrowdSec, File Browser and BirdNET.
9. Recreate/enable TestServer backup service/timer.
10. Run fresh backup and test restore.

## DietPi

1. Install a compatible DietPi/Raspberry Pi OS.
2. Configure hostname/networking.
3. Install Pi-hole and Unbound at compatible/current supported versions.
4. Stop Pi-hole/FTL before restoring state.
5. Restore `/etc`, Pi-hole configuration, Unbound configuration and staged SQLite databases.
6. Correct ownership and permissions.
7. Start Unbound then Pi-hole/FTL.
8. Test direct Unbound resolution and Pi-hole client resolution.
9. Restore any additional `/opt`, `/var/www` and selected home content.
10. Recreate/enable the DietPi Restic client backup.

---

## Bare-metal success criteria

A host is considered recovered when:

- it boots normally from replacement storage;
- intended hostname/network identity is restored;
- no unexpected critical systemd failures remain;
- stateful applications have validated databases/state;
- core services respond correctly;
- monitoring can see the host;
- backups are re-enabled;
- a new backup and isolated restore test both succeed.
