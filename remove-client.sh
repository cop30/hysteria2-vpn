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
grep -qF "${client}"$'\t' "${ROOT}/state/users.tsv" || { log_error "Unknown client: ${client}"; exit 1; }
[[ $(grep -cve '^$' "${ROOT}/state/users.tsv") -gt 1 ]] || { log_error "Refusing to remove the last client."; exit 1; }

cp -a "${ROOT}/state/users.tsv" "${ROOT}/state/users.tsv.bak"
cp -a "${ROOT}/state/server.yaml" "${ROOT}/state/server.yaml.bak"
[[ ! -f ${ROOT}/clients/${client}.hy2 ]] || cp -a "${ROOT}/clients/${client}.hy2" "${ROOT}/clients/${client}.hy2.bak"
[[ ! -f ${ROOT}/clients/${client}.png ]] || cp -a "${ROOT}/clients/${client}.png" "${ROOT}/clients/${client}.png.bak"
awk -F '\t' -v client="${client}" '$1 != client' "${ROOT}/state/users.tsv" > "${ROOT}/state/users.tsv.new"
mv "${ROOT}/state/users.tsv.new" "${ROOT}/state/users.tsv"

rollback() {
  mv "${ROOT}/state/users.tsv.bak" "${ROOT}/state/users.tsv"
  mv "${ROOT}/state/server.yaml.bak" "${ROOT}/state/server.yaml"
  [[ ! -f ${ROOT}/clients/${client}.hy2.bak ]] || mv "${ROOT}/clients/${client}.hy2.bak" "${ROOT}/clients/${client}.hy2"
  [[ ! -f ${ROOT}/clients/${client}.png.bak ]] || mv "${ROOT}/clients/${client}.png.bak" "${ROOT}/clients/${client}.png"
  docker compose -f "${ROOT}/docker-compose.yml" restart hysteria2 >/dev/null 2>&1 || true
}
trap rollback ERR
render_server_config "${ROOT}/state" "${ROOT}/state/server.yaml.new"
config_check "${ROOT}" "${IMAGE}" "${ROOT}/state/server.yaml.new"
mv "${ROOT}/state/server.yaml.new" "${ROOT}/state/server.yaml"
docker compose -f "${ROOT}/docker-compose.yml" restart hysteria2
wait_for_service "${HYSTERIA_PORT}"
rm -f "${ROOT}/clients/${client}.hy2" "${ROOT}/clients/${client}.png"
rm -f "${ROOT}/state/users.tsv.bak" "${ROOT}/state/server.yaml.bak" \
  "${ROOT}/clients/${client}.hy2.bak" "${ROOT}/clients/${client}.png.bak"
trap - ERR
log_info "Revoked ${client}."
