# 01 — Scope and Architecture

## Purpose

This document defines what the homelab backup and recovery system protects, what it deliberately excludes, and how recovery copies are arranged.

## Stage 1 scope

### Protected hosts

| Host | Role | Backup method | Primary destination |
|---|---|---|---|
| `ids-01` | IDS, monitoring, Greenbone/OpenVAS, Restic server | Local Restic + PostgreSQL dump | `/home/homelab-backup/repository` |
| `dietpi` | Pi-hole + Unbound | Remote Restic + consistent SQLite staging | `ids-01` REST server |
| `k3s-node-01` | K3s control-plane | Remote Restic + consistent SQLite K3s datastore | `ids-01` REST server |
| `TestServer` | Main Docker/application host | Remote Restic + application-aware DB staging | `ids-01` REST server |

### Backup server

`ids-01` exposes the Restic REST server on:

```text
https://192.168.2.242:8000
```

Remote repositories are stored beneath:

```text
/home/homelab-backup/remote-repositories
```

The service is configured for authenticated private repositories, TLS, and append-only operation.

### Second copy

After client backup windows have completed, `ids-01` replicates both:

```text
/home/homelab-backup/repository
/home/homelab-backup/remote-repositories
```

to:

```text
k3s-node-01:/home/homelab-backup/replica/ids-01/
```

The replication uses a dedicated SSH key and rsync. The Restic REST server is stopped for the short synchronization window and restarted even if replication fails.

## Design principles

### 1. Configuration and state over recreatable bulk data

The Stage 1 objective is rapid infrastructure recovery, not general-purpose media backup. Large media, logs and regenerable monitoring history are excluded where appropriate.

### 2. Database-aware backup

Active databases are not blindly copied where a consistent application/database backup method is available.

Examples:

- Greenbone/GVM: PostgreSQL `pg_dump -Fc`.
- Pi-hole: SQLite backup into staging.
- K3s embedded datastore: SQLite backup into staging.
- TestServer applications: SQLite backup into staging.
- File Browser: application stopped briefly and BoltDB copied while offline.

### 3. Encrypted repositories

Each Restic repository is encrypted independently. Knowledge of the repository password is required for recovery.

### 4. Restore validation

A successful backup job alone is insufficient. Critical datasets are periodically restored into an isolated test directory and validated.

### 5. Separate failure domains

Stage 1 protects against failure of the primary backup disk by maintaining a second complete repository copy on k3s-node-01. Stage 2 will introduce a third copy on dedicated or off-host storage.

## Recovery point and recovery time expectations

Current schedules are daily, so the normal Recovery Point Objective (RPO) is approximately 24 hours or less for protected configuration/state.

Recovery Time Objective (RTO) depends on the failure type:

- single file: minutes;
- application config/state: typically tens of minutes;
- individual host rebuild: hours;
- full multi-host disaster: potentially several hours depending on hardware replacement and image installation.

These are operational targets, not contractual guarantees.

## Explicit Stage 1 exclusions

Depending on host, the following are intentionally excluded or deprioritized:

- large video/media libraries;
- ROM collections;
- BirdNET audio/history bulk data;
- Prometheus TSDB history;
- Loki log history;
- routine caches and package caches;
- routine system/application logs;
- Docker image layers and other data reproducible from Compose definitions/images;
- crash/core files.

## Stage 2 scope

Stage 2 will add a third copy using storage that does not compete with DietPi's system disk. Preferred options are:

1. dedicated USB SSD/HDD;
2. NAS storage;
3. encrypted object/cloud storage.

Stage 2 should also add longer retention, health monitoring, and a complete disaster-recovery exercise from the third copy.
