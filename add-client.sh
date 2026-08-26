#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
require_root
client="${1:-}"
validate_client_name "${client}"
[[ -f ${ROOT}/state/deployment.env ]] || { log_error "Run deploy.sh first."; exit 1; }
read_deployment "${ROOT}/state"

exec 9>"${ROOT}/state/deploy.lock"
flock -x 9
grep -qF "${client}"$'\t' "${ROOT}/state/users.tsv" && { log_error "Client already exists: ${client}"; exit 1; }

password="$(openssl rand -hex 32)"
cp -a "${ROOT}/state/users.tsv" "${ROOT}/state/users.tsv.bak"
cp -a "${ROOT}/state/server.yaml" "${ROOT}/state/server.yaml.bak"
printf '%s\t%s\n' "${client}" "${password}" >> "${ROOT}/state/users.tsv"

rollback() {
  mv "${ROOT}/state/users.tsv.bak" "${ROOT}/state/users.tsv"
  mv "${ROOT}/state/server.yaml.bak" "${ROOT}/state/server.yaml"
  rm -f "${ROOT}/clients/${client}.hy2" "${ROOT}/clients/${client}.png"
  docker compose -f "${ROOT}/docker-compose.yml" restart hysteria2 >/dev/null 2>&1 || true
}
trap rollback ERR
render_server_config "${ROOT}/state" "${ROOT}/state/server.yaml.new"
config_check "${ROOT}" "${IMAGE}" "${ROOT}/state/server.yaml.new"
mv "${ROOT}/state/server.yaml.new" "${ROOT}/state/server.yaml"
docker compose -f "${ROOT}/docker-compose.yml" restart hysteria2
wait_for_service "${HYSTERIA_PORT}"
write_client_artifacts "${ROOT}" "${client}" "${password}"
rm -f "${ROOT}/state/users.tsv.bak" "${ROOT}/state/server.yaml.bak"
trap - ERR
log_info "Added ${client}. Secret artifacts are in ${ROOT}/clients."
