# Hysteria2 self-hosted stack

A small, auditable Hysteria 2 server project for Ubuntu. Hysteria is compiled
from a reviewed upstream commit on the VPS. Server secrets and client profiles
are generated locally on that VPS and are excluded from Git.

## What is different

- The upstream release and immutable commit are committed together in
  `versions.conf`; an ordinary redeploy cannot silently upgrade the server.
- Every device gets its own username and password. Revoking one device does not
  invalidate the others.
- User changes are locked, rendered atomically, smoke-tested in an isolated
  no-network container, and rolled back if restart verification fails.
- The container is read-only, drops every Linux capability, uses
  `no-new-privileges`, and has memory/PID limits.
- Existing TCP services may keep the same numeric port: Hysteria uses UDP.
- UFW cleanup removes a rule only when this project created it.

## Requirements

- Ubuntu 24.04 or newer
- root or sudo
- Docker Engine with Compose v2
- `git`, `curl`, `openssl`, `iproute2`, `util-linux`
- about 1.5 GB RAM or swap while compiling; runtime use is small
- the selected UDP port allowed in both UFW and the provider firewall

`qrencode` is optional. Without it, `.hy2` URI files are still created.

## Deploy

```bash
git clone https://github.com/cop30/hysteria2-vpn.git
cd hysteria2-vpn
sudo INITIAL_CLIENT=iphone ./deploy.sh
```

Defaults: UDP `443`, IPv4-only server egress, Salamander obfuscation, a
self-signed certificate pinned in every client URI, and an automatically
detected public IPv4. Override discovery explicitly when needed:

```bash
sudo PUBLIC_HOST=vpn.example.com HYSTERIA_PORT=443 TLS_SNI=vpn.example.com \
  INITIAL_CLIENT=iphone ./deploy.sh
```

Heavy downloads and compilation happen on the VPS. Generated files are in
`state/` and `clients/`; both are secret and gitignored.

## Clients

```bash
sudo ./add-client.sh windows
sudo ./add-client.sh iphone
sudo ./remove-client.sh old-phone
```

Import `clients/<name>.hy2`, or scan `clients/<name>.png` when `qrencode` is
installed. For iOS mobile networks, a client keepalive of 10 seconds is a good
starting point. Prefer IPv4 when the server has no verified IPv6 egress.

## Operations

```bash
sudo ./status.sh
sudo ./backup.sh /secure/off-repo/path/hysteria2-backup.tar.gz
sudo ./deploy.sh                 # idempotent; does not rotate secrets
sudo ./rollback.sh               # switch to the previous checked deployment
sudo ./cleanup.sh                # destructive; requires hostname confirmation
```

Backups contain all credentials. Store them encrypted and never commit them.

## Upgrade policy

Upgrades are code changes, not a side effect of redeploying:

1. Review the new upstream release.
2. Update both values in `versions.conf`.
3. Run tests and ShellCheck.
4. Back up the server state.
5. Run `sudo ./deploy.sh` and verify `sudo ./status.sh`.

The previous Compose/config pair and older image remain available for
`rollback.sh`. Before switching, it creates a secret local safety archive. A
successful rollback keeps the replaced version as the next rollback point, so
the operation can be reversed.

## Tests

```bash
sudo bash tests/run.sh
sudo bash tests/smoke_image.sh local/hysteria2:v2.12.2
shellcheck -x deploy.sh add-client.sh remove-client.sh status.sh backup.sh \
  cleanup.sh rollback.sh lib/common.sh tests/*.sh
```

## Security boundary

This project secures the Hysteria process and its generated state. It does not
replace SSH hardening, unattended security updates, Fail2ban, provider firewall
rules, encrypted backups, or external monitoring.
