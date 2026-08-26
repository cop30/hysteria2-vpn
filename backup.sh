#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
require_root
[[ -d ${ROOT}/state ]] || { log_error "Nothing to back up."; exit 1; }
exec 9>"${ROOT}/state/deploy.lock"
flock -s 9
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="${1:-${ROOT}/backups/hysteria2-${timestamp}.tar.gz}"
install -d -m 0700 "$(dirname "${destination}")"
tar -C "${ROOT}" -czf "${destination}" state clients docker-compose.yml versions.env
chmod 0600 "${destination}"
sha256sum "${destination}" > "${destination}.sha256"
chmod 0600 "${destination}.sha256"
log_info "Encrypted storage is strongly recommended: this backup contains every client secret."
log_info "Created ${destination}"
