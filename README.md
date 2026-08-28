**English** | [Русский](README.ru.md)

# Hysteria 2 self-hosted stack

This project builds Hysteria 2 from a pinned upstream commit on an Ubuntu VPS
and runs it with Docker Compose. Server secrets, client URIs, QR codes and
backups are generated on the VPS and excluded from Git.

## Properties

- The release and immutable commit are pinned together in `versions.conf`.
- Every device gets a separate username and password.
- Candidate configurations are tested in an isolated no-network container and
  failed changes are rolled back.
- The service container is read-only, drops all Linux capabilities, enables
  `no-new-privileges`, and has memory/PID limits.
- Hysteria can use `443/udp` while another service uses `443/tcp`.
- UFW cleanup removes a rule only when this project created it.

Defaults: public `443/udp`, Salamander obfuscation, IPv4 egress, and a
self-signed certificate whose SHA-256 pin is included in every client URI.

## Architecture

```text
Internet client
      │ Hysteria 2 + QUIC + Salamander, UDP/<public port>
      ▼
UFW / provider firewall
      ▼
Docker publish: <public port>/udp → 8443/udp
      ▼
read-only hysteria2 container → direct IPv4 Internet egress
```

| Item | Purpose | Secret |
|---|---|---|
| `versions.conf` | pinned release and commit | no |
| `Dockerfile` | build Hysteria from source | no |
| `docker-compose.yml.tmpl` | container limits and launch | no |
| `state/` | certificate, key, auth, and runtime configuration | **yes** |
| `clients/` | client URIs and QR codes | **yes** |
| `backups/` | local backup archives | **yes** |

`state/`, `clients/`, `backups/`, and generated `docker-compose.yml` are
excluded from Git.

## Requirements

- Ubuntu 24.04 or newer, root or sudo
- `git`, `curl`, `openssl`, `iproute2`, and `util-linux`
- Docker Engine, Compose v2, and buildx
- `qrencode` for QR PNG files and terminal QR output
- the selected UDP port allowed by both host and provider firewalls
- about 1.5 GB RAM or swap during compilation; runtime use is much lower

Inspect capacity before building:

```bash
free -h
df -h /
sudo docker system df
```

### Install Docker

```bash
sudo ./docker-install.sh
```

The installer is adapted from the MIT-licensed
[`seb0ch/vpn`](https://github.com/seb0ch/vpn) installer. It installs
`docker.io`, `docker-compose-v2`, and `docker-buildx` from Ubuntu's own archive,
adds no third-party apt repository or signing key, skips installed components,
and refuses to mix Ubuntu `docker.io` with a detected
`docker-ce`/`containerd.io` stack. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

### Install QR support

The server and `.hy2` files work without `qrencode`, but no PNG or terminal QR
will be produced:

```bash
sudo apt-get update
sudo apt-get install -y qrencode
qrencode --version
```

## Deploy

```bash
git clone https://github.com/cop30/hysteria2-vpn.git
cd hysteria2-vpn
sudo ./docker-install.sh       # only when Docker is absent
sudo apt-get install -y qrencode
sudo INITIAL_CLIENT=iphone ./deploy.sh
```

`deploy.sh` verifies dependencies and the pinned commit, generates server and
initial-client secrets, builds from source, validates the candidate config,
opens the UDP port in active UFW, starts Compose, checks the listener, writes a
non-empty `.hy2`, and—when `qrencode` exists—writes a checked PNG and prints the
secret QR in the terminal.

Override endpoint discovery when required:

```bash
sudo PUBLIC_HOST=vpn.example.com HYSTERIA_PORT=443 \
  TLS_SNI=vpn.example.com INITIAL_CLIENT=iphone ./deploy.sh
```

## Clients

```bash
sudo ./add-client.sh windows
sudo ./add-client.sh iphone-15
sudo ./remove-client.sh old-phone
```

Names are 1–32 ASCII letters, digits, `_`, or `-`. Give every device a separate
client. Artifacts are stored with mode `0600` under the gitignored `clients/`
directory. With `qrencode`, client creation writes a PNG and immediately prints
the QR in the terminal.

Show an existing client again:

```bash
sudo qrencode -t ANSIUTF8 -r clients/iphone.hy2
```

Treat `.hy2` and QR files as full credentials. Never paste them into chat, Git,
logs, or documentation. Enable client IPv6 only after verifying VPS IPv6
egress.

### Tested client applications

- **iOS:** [v2RAGE in the Russian App Store](https://apps.apple.com/ru/app/v2rage/id6761075402).
  Import the generated `.hy2` URI or scan its QR code. Tests over mobile data
  and a fixed-line ISP were stable with both Dutch and Finnish Hysteria 2
  servers.
- **Windows:** [Hiddify](https://github.com/hiddify/hiddify-app/releases).
  Import the same URI or QR code. Long-running tests through an iPhone hotspot
  and a fixed-line ISP were stable.

These are field-tested recommendations, not a guarantee for every device,
carrier, ISP, or future application version. Keep the application current and
test it on the networks you actually use. Do not change only the client port:
`443/udp` must match the server, URI, UFW, and provider firewall. Do not disable
Salamander/obfuscation for this project's profile; the server expects the
matching secret, so a one-sided change breaks the connection.

## Operations

```bash
sudo ./status.sh
sudo docker compose logs --tail 100 hysteria2
sudo ./backup.sh /secure/off-repo/path/hysteria2-backup.tar.gz
sudo ./deploy.sh
sudo ./rollback.sh
sudo ./cleanup.sh
```

A local listener does not prove that the provider firewall passes UDP; test
from an external client. Redeploy preserves secrets and clients. Upgrading
Hysteria requires an explicit reviewed release+SHA change in `versions.conf`, a
backup, tests, deploy, and status/client verification.

### Why both release and commit are pinned

`HYSTERIA_RELEASE` is the human-readable upstream tag, such as `app/v2.12.2`.
`HYSTERIA_COMMIT` is the exact 40-character Git SHA of its source. A tag can in
principle be moved; a SHA alone does not identify the intended named release.
The pair provides both intent and immutable identity.

During deploy, the script resolves the tag from the official repository and
requires its SHA to match `versions.conf`; the Dockerfile then checks out that
exact SHA. A new upstream release therefore does not change an ordinary
`git pull` plus redeploy. This is deliberate protection, not an automatic
updater.

### Upgrade the Hysteria server

Use `app/vX.Y.Z` below as a placeholder, not as a literal version.

1. Review the official
   [Hysteria Releases](https://github.com/HyNetworks/hysteria/releases),
   especially configuration and client-compatibility changes.
2. Resolve the annotated tag, falling back to the lightweight tag only when the
   first command returns nothing:

   ```bash
   git ls-remote https://github.com/HyNetworks/hysteria.git \
     'refs/tags/app/vX.Y.Z^{}'
   git ls-remote https://github.com/HyNetworks/hysteria.git \
     'refs/tags/app/vX.Y.Z'
   ```

3. In a review branch, update both `HYSTERIA_RELEASE` and the full
   `HYSTERIA_COMMIT` in `versions.conf`.
4. Review the diff, run tests and ShellCheck, and commit only reviewed source.
   Never add `state/`, `clients/`, `.env`, backups, or generated Compose files.
5. On the VPS, back up first, then deploy the reviewed project commit:

   ```bash
   git pull --ff-only
   sudo ./backup.sh /secure/path/hysteria2-before-upgrade.tar.gz
   sudo ./deploy.sh
   sudo ./status.sh
   ```

6. Verify a real external client. Retain the previous image and backup until
   testing is complete; use `sudo ./rollback.sh` on failure.

The new release gets a new Docker image tag. The certificate, Salamander
secret, users, and `.hy2` profiles are preserved, so rescanning QR codes is
normally unnecessary.

### Client application updates

This repository does **not** install or update client applications. Update
v2RAGE through the App Store and Hiddify through its official distribution
channel. Updating the app does not require a new VPN password or QR code.

Read upstream compatibility notes before upgrading the server. If a release
requires a newer client core, update and test one client first, then upgrade
the server. Server and client version numbers do not always have to match;
upstream's stated compatibility is what matters.

Backups contain every client password. Store them encrypted outside Git and
test restoration. `rollback.sh` validates the previous configuration and makes
a local safety backup before switching.

Source builds grow Docker cache. Inspect before deleting anything:

```bash
df -h /
sudo docker system df
sudo docker builder prune -af   # unused build cache only
```

Do not run `docker system prune -a` without auditing other projects on the
host. `cleanup.sh` is destructive and requires hostname confirmation; it does
not prune the shared Docker build cache.

## VPS security boundary

This project hardens the Hysteria container and its own secret files. It does
**not** fully harden the VPS, SSH, operating system, provider account, backups,
or unrelated services.

Before Internet exposure, configure a provider firewall and UFW with default
deny inbound; verify SSH key login in a second session before disabling
password, keyboard-interactive, and root login; validate config with `sshd -t`;
configure Fail2ban for the actual SSH port; enable unattended security updates;
keep encrypted off-host backups and test restore; monitor disk, RAM, container,
and port health; and protect provider/GitHub accounts with MFA and offline
recovery codes.

Indicative SSH settings—not a drop-in recipe for every VPS—are:

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
```

A mistake can lock you out. Keep the existing session open until a new
key-only session succeeds.

## Troubleshooting

```bash
sudo docker compose ps
sudo docker compose logs --tail 200 hysteria2
sudo ss -lunp | grep ':443'
sudo ufw status
command -v qrencode
sudo test -s clients/iphone.hy2 && echo 'URI exists'
```

Remove URIs, passwords, QR codes, private keys, and all `state/`/`clients/`
contents before sharing diagnostics.

## Tests

```bash
sudo bash tests/run.sh
sudo bash tests/smoke_image.sh local/hysteria2:v2.12.2
shellcheck -x docker-install.sh deploy.sh add-client.sh remove-client.sh \
  status.sh backup.sh cleanup.sh rollback.sh lib/common.sh tests/*.sh
```

## License and credits

MIT licensed. The Docker installer and parts of the operational guidance are
adapted from [`seb0ch/vpn`](https://github.com/seb0ch/vpn); see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

The project is owned and published by **cop30**. Its architecture,
implementation, deployment tooling, tests, and documentation were developed
primarily by **OpenAI Codex**, working with cop30, who defined the requirements,
provided the infrastructure, reviewed the results, and performed real-world
client and network testing.
