# Homelab Backup & Restore

This repository is the operational documentation set for the homelab backup, restore, and disaster-recovery design.

## Objectives

The backup system is intended to provide:

- recoverable configuration and application state for the core Linux hosts;
- application-aware database backups rather than blind copies of active database files;
- encrypted Restic repositories;
- a central backup service on `ids-01`;
- a second independent copy of the complete backup estate on `k3s-node-01`;
- tested procedures for restoring one file, an application, a host, or rebuilding from bare metal;
- a documented Stage 2 path for a third copy on dedicated/off-host storage;
- operational monitoring of backup freshness and restore-test health through Prometheus/Grafana.

## Current Stage 1 Architecture

```text
                         +-------------------+
                         |      ids-01       |
                         | Restic REST server|
                         | 192.168.2.242:8000|
                         +---------+---------+
                                   ^
                encrypted Restic  |  backups
                                   |
             +---------------------+----------------------+
             |                     |                      |
       +-----+------+        +-----+------+        +------+------+
       |   DietPi   |        |k3s-node-01 |        | TestServer  |
       | Pi-hole    |        | K3s server |        | Docker host |
       +------------+        +------------+        +-------------+

ids-01 also backs up its own configuration and Greenbone database to a
local encrypted Restic repository.

The complete backup estate on ids-01 is replicated daily to:

k3s-node-01:/home/homelab-backup/replica/ids-01
```

## Delivery Scope

### Stage 1 — implemented

- `ids-01` local encrypted Restic repository.
- Central authenticated TLS Restic REST server on `ids-01`.
- Append-only/private remote repositories.
- DietPi backup with Pi-hole-aware SQLite staging.
- k3s-node-01 backup with consistent embedded K3s SQLite datastore backup and server token.
- TestServer backup with application-aware database staging.
- Greenbone PostgreSQL custom-format dump on ids-01.
- Restore testing for critical datasets.
- Daily replica from ids-01 to k3s-node-01.
- Backup/restore health dashboard design for Prometheus/Grafana.

### Stage 2 — planned

- Dedicated USB SSD/HDD or other independent storage for the third copy.
- Monthly/long-term archive copy.
- Longer retention policy on the third copy.
- Full recovery exercise from the third copy.
- Prometheus/Grafana backup-health metrics and alerts.
- Optional off-site/object-storage copy.

## Documentation Index

- [Scope and architecture](docs/01-scope-and-architecture.md)
- [Backup inventory and schedules](docs/02-backup-inventory-and-schedules.md)
- [Restore one file or directory](docs/03-single-file-restore.md)
- [Application and database recovery](docs/04-application-recovery.md)
- [Full bare-metal recovery](docs/05-bare-metal-recovery.md)
- [Host-specific recovery notes](docs/06-host-recovery.md)
- [Backup server and replica recovery](docs/07-backup-platform-recovery.md)
- [Credentials, keys and security](docs/08-security-and-key-management.md)
- [Validation, testing and maintenance](docs/09-validation-and-maintenance.md)
- [Stage 2 roadmap](docs/10-stage-2-roadmap.md)
- [Backup health dashboard](monitoring/README.md)
- [Grafana dashboard JSON](monitoring/grafana-backup-health.json)
- [Prometheus textfile exporter](monitoring/backup-status-exporter.sh)

## Recovery Priorities

When recovering from a major outage, use this order unless the failure scenario dictates otherwise:

1. Network, DNS and basic host access.
2. `ids-01` backup service or its replica.
3. Core infrastructure configuration.
4. Pi-hole/DNS services.
5. K3s control-plane state.
6. Reverse proxy/authentication services.
7. Monitoring and observability.
8. Remaining applications.

## Important Principle

A backup is not considered complete merely because a backup command returned success. Critical datasets must periodically be restored into an isolated location and validated.

The dashboard follows the same principle: a repository is healthy only when a recent backup exists, and recovery confidence is healthy only when a recent validated restore test exists.

Do **not** commit Restic repository passwords, REST server passwords, private SSH keys, TLS private keys, K3s tokens, application secrets, or database credentials to this repository.
