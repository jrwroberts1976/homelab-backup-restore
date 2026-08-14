# 08 — Security and Key Management

Recovery depends on more than repository data. The following secrets and keys must exist outside this Git repository.

## Never commit these items

- Restic repository passwords.
- REST server account passwords.
- `/home/homelab-backup/.restic-password`.
- `/home/homelab-backup/.restic-rest-env`.
- Restic server `.htpasswd` contents if it reveals hashes/accounts you do not intend to publish.
- TLS private keys.
- SSH private keys, including the ids-01 replication key.
- K3s server token.
- application credentials/secrets.
- database passwords.

## Required off-host recovery material

At minimum, maintain a secure independent copy of:

1. Restic repository passwords for:
   - ids-01 local repository;
   - DietPi repository;
   - k3s-node-01 repository;
   - TestServer repository.
2. Rest server TLS certificate and private key, or a documented procedure to replace them and redistribute trust.
3. Rest server authentication data or account passwords.
4. Administrative credentials needed to reach hosts/network devices.
5. Any encryption/password-manager recovery material required to retrieve the above.

## Recommended storage

Use a password manager and/or encrypted offline medium. The recovery credential store should not depend solely on any one homelab host.

## SSH replication key

The primary-to-replica job uses a dedicated key on ids-01:

```text
/root/.ssh/homelab-replica-ed25519
```

The corresponding public key is authorized for the `homelab-backup` account on k3s-node-01.

If ids-01 is rebuilt, generate a new dedicated key and replace the authorization rather than trying to recreate the exact lost private key.

## TLS

The Restic REST server uses a private/self-signed certificate with the ids-01 address/name in the certificate identity. Clients trust the public CA/certificate using:

```text
/home/homelab-backup/certs/rest-server.crt
```

The server private key belongs only on the server/recovery-secret storage and must not be published.

## Permissions

Typical sensitive client files should be mode `0600` and owned by the backup service account:

```bash
chmod 600 /home/homelab-backup/.restic-password
chmod 600 /home/homelab-backup/.restic-rest-env
```

Private SSH keys should be mode `0600`; `.ssh` directories should be `0700`.

## Rotation

Rotate credentials after:

- suspected compromise;
- accidental publication;
- lost/stolen hardware containing credentials;
- major rebuild where old credentials are no longer needed.

After any rotation, validate a real Restic `snapshots` operation and a small restore before considering the change complete.

## Public repository warning

This GitHub repository is public. Documentation may include hostnames, private RFC1918 IP addresses, paths, repository IDs and recovery procedures, but **must never contain live secrets**.
