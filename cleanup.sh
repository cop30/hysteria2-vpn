#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
require_root
read_runtime "${ROOT}/state"

exec 9>"${ROOT}/state/deploy.lock"
flock -x 9

echo "This permanently revokes all Hysteria2 clients and deletes server secrets."
printf "Type the hostname '%s' to continue: " "$(hostname)"
read -r confirmation
[[ ${confirmation} == "$(hostname)" ]] || { log_info "Aborted."; exit 0; }

docker compose -f "${ROOT}/docker-compose.yml" down --remove-orphans || true
if [[ -f ${ROOT}/state/ufw-rule-owned ]] && command -v ufw >/dev/null; then
  ufw --force delete allow "${HYSTERIA_PORT}/udp" || true
fi
rm -rf -- "${ROOT}/state" "${ROOT}/clients"
rm -f -- "${ROOT}/docker-compose.yml" "${ROOT}/docker-compose.yml.previous"
log_info "Runtime state removed. Docker images were preserved for rollback/audit."
