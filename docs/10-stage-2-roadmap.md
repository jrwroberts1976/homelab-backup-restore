# 10 — Stage 2 Roadmap

Stage 2 adds a third recovery copy and improves long-term resilience without consuming DietPi's limited system disk.

## Goal

Move from a strong two-copy design to a three-copy design with a genuinely separate failure domain.

## Preferred third-copy targets

Priority order:

1. dedicated USB SSD/HDD attached to a suitable host;
2. NAS with independent disks/power where available;
3. encrypted object/cloud storage.

DietPi's root filesystem is not the preferred target unless additional dedicated storage is attached.

## Proposed Stage 2 design

```text
Protected hosts
      |
      v
ids-01 primary encrypted Restic repositories
      |
      +---- daily ----> k3s-node-01 replica
      |
      +---- monthly --> dedicated/off-host third copy
```

## Stage 2 deliverables

### Third-copy storage

- choose hardware/location;
- format/mount with stable UUID/path;
- restrict access to backup service account;
- monitor free space and mount health.

### Monthly archive

- replicate/copy the primary repository estate only after daily backup completion;
- maintain a longer retention horizon;
- prevent a failed/empty primary from automatically deleting the last good archive;
- log and alert on failures.

### Recovery testing

Perform a recovery without using ids-01 or the k3s-node-01 replica:

1. mount/access Stage 2 copy;
2. open repositories with independently stored passwords;
3. restore a configuration file;
4. restore and validate a database;
5. perform at least one full host recovery exercise.

### Monitoring

Expose and alert on:

- last successful backup timestamp per host;
- last successful replica timestamp;
- Stage 2 archive age;
- repository check status;
- backup/replica storage utilization;
- Restic server availability;
- backup service/timer failures.

Prometheus/Grafana should display a compact backup/DR dashboard.

### Retention

Define and test a retention model for remote repositories and Stage 2. A candidate policy for the third copy is:

- several recent monthly points;
- quarterly points;
- annual point where storage permits.

Final values should be chosen after measuring real repository growth.

## Optional off-site extension

A later Stage 2/3 enhancement may use encrypted object storage for protection against theft, fire, electrical damage, or a site-wide incident.

Restic encryption remains mandatory. Cloud credentials should have the minimum required permissions and should never be stored in this repository.

## Exit criteria for Stage 2

Stage 2 is complete when:

- the third copy is on storage independent of the normal system disks;
- archive jobs run unattended;
- repository growth/capacity is monitored;
- credentials required to recover are independently accessible;
- a restore from the third copy has succeeded;
- at least one documented full-host recovery drill has been completed using that copy.
