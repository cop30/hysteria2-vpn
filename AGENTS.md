# Agent and contributor guide

This repository deploys Hysteria 2 from reviewed, pinned upstream source.

- Read `README.md` before changing deployment behavior.
- Never commit `state/`, `clients/`, generated Compose files, credentials, keys,
  certificates, URIs, QR codes, backups, `.env` files, or real host inventory.
- Audit a target host before mutation. Preserve mail, monitoring, and unrelated
  VPN services. TCP and UDP ports are separate resources.
- Keep `versions.conf` tag and SHA changes together and verify the upstream tag.
- Shell files use `#!/usr/bin/env bash`, `set -euo pipefail`, and pass ShellCheck.
- Changes to client state must be locked, validated, atomic, and rolled back if
  Hysteria does not restart cleanly.
- Test on supported Ubuntu hosts before release. Commit and push only after an
  explicit secrets review and separate user approval.
