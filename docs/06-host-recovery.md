# 06 — Host Recovery Quick Reference

This is the shorter operational reference. For a full rebuild, use [05 — Full Bare-Metal Recovery](05-bare-metal-recovery.md).

## ids-01

### Critical items

- Restic local repository: `/home/homelab-backup/repository`
- Restic REST repositories: `/home/homelab-backup/remote-repositories`
- Restic server stack: `/home/james/docker/stacks/restic-server`
- Greenbone database dump: staged `gvmd.dump`
- monitoring/security configuration under `/etc`, scripts, and selected Docker data

### If only ids-01 storage fails

Use the second copy on `k3s-node-01`:

```text
/home/homelab-backup/replica/ids-01/repository
/home/homelab-backup/replica/ids-01/remote-repositories
```

Recreate ids-01, restore both trees, recreate the REST service and restore required TLS/authentication material from the secure credential store.

## DietPi

### Critical items

- Pi-hole configuration under `/etc/pihole`
- Unbound configuration
- staged consistent Pi-hole SQLite DBs
- `/boot/firmware`
- selected `/opt`, `/var/www`, home content

### Validation

- Pi-hole FTL active
- DNS queries resolve through Pi-hole
- Unbound resolves upstream successfully
- blocklists/gravity database available

## k3s-node-01

### Critical items

- `/etc/rancher/k3s`
- service overrides/options
- staged `k3s-state.db`
- `/var/lib/rancher/k3s/server/token`
- `.kube` and selected scripts/configuration

### Validation

```bash
sudo systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl get pods -A
```

Expected core components include K3s DNS/networking/ingress components and deployed workloads.

## TestServer

### Critical items

- `/home/james/docker/stacks`
- selected `/home/james/docker/data`
- staged application DBs
- `/home/james/homelab`
- scripts and system configuration

### Application DB mapping

| Staged file | Application | Live location |
|---|---|---|
| `kuma.db` | Uptime Kuma | `/home/james/docker/data/availability/uptime-kuma/data/kuma.db` |
| `birdnet.db` | BirdNET | `/home/james/docker/data/birdnet-go/data/birdnet.db` |
| `authelia.db` | Authelia | `/home/james/docker/data/proxy-auth/authelia/config/db.sqlite3` |
| `npm.db` | Nginx Proxy Manager | `/home/james/docker/data/proxy-auth/npm/data/database.sqlite` |
| `crowdsec.db` | CrowdSec | `/home/james/docker/data/security/crowdsec/data/crowdsec.db` |
| `grafana.db` | Grafana | `/home/james/docker/data/monitoring/grafana/data/grafana.db` |
| `filebrowser.db` | File Browser BoltDB | `/home/james/docker/data/management/filebrowser/database/filebrowser.db` |

### Suggested stack recovery order

1. management/runtime basics
2. proxy/authentication
3. security
4. monitoring
5. availability
6. dashboards
7. BirdNET/application workloads

Validate each Compose stack before starting:

```bash
cd /home/james/docker/stacks/<stack>
docker compose config
docker compose up -d
```

## Recovery decision guide

| Incident | Runbook |
|---|---|
| One deleted/misconfigured file | `03-single-file-restore.md` |
| One application DB corrupted | `04-application-recovery.md` |
| Docker application lost | `04-application-recovery.md` + this document |
| Host OS/storage failed | `05-bare-metal-recovery.md` |
| ids-01 and backup service failed | `07-backup-platform-recovery.md` |
| Credentials/keys unavailable | `08-security-and-key-management.md` |
