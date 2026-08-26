# Security

## Secrets

Never commit or publish `state/`, `clients/`, `backups/`, generated Compose
files, private keys, certificates, client URIs, QR codes, or environment files.
The repository ignores these paths, and `.dockerignore` keeps them out of image
build contexts as a second boundary.

Treat every Hysteria URI as a credential. If one is exposed, revoke that client
with `remove-client.sh` and create a replacement with a new name.

## Reports

Do not include live credentials, private keys, production configuration, or
unredacted logs in a public issue. Describe the problem with synthetic values.

## Scope

The scripts reduce deployment risk but do not secure the VPS itself. SSH,
system updates, host and provider firewalls, encrypted backups, and monitoring
remain operator responsibilities.
