#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"

require_root
for file in docker-compose.yml docker-compose.yml.previous \
  state/server.yaml state/server.yaml.previous; do
  [[ -f ${ROOT}/${file} ]] || { log_error "No complete rollback point: missing ${file}."; exit 1; }
done
read_runtime "${ROOT}/state"

exec 9>"${ROOT}/state/deploy.lock"
flock -x 9

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "${ROOT}/backups"
tar -C "${ROOT}" -czf "${ROOT}/backups/pre-rollback-${timestamp}.tar.gz" \
  state clients docker-compose.yml docker-compose.yml.previous versions.env
chmod 0600 "${ROOT}/backups/pre-rollback-${timestamp}.tar.gz"

cp -a docker-compose.yml docker-compose.yml.rollback-current
cp -a state/server.yaml state/server.yaml.rollback-current
[[ ! -f state/deployment.env ]] || cp -a state/deployment.env state/deployment.env.rollback-current

cp -a docker-compose.yml.previous docker-compose.yml.new
cp -a state/server.yaml.previous state/server.yaml.new
docker compose -f docker-compose.yml.new config --quiet
previous_image="$(awk '$1 == "image:" {print $2; exit}' docker-compose.yml.new)"
[[ -n ${previous_image} ]] || { log_error "Previous Compose file has no image."; exit 1; }
config_check "${ROOT}" "${previous_image}" "${ROOT}/state/server.yaml.new"

mv docker-compose.yml.new docker-compose.yml
mv state/server.yaml.new state/server.yaml
if [[ -f state/deployment.env.previous ]]; then
  cp -a state/deployment.env.previous state/deployment.env
fi

restore_current() {
  log_error "Rollback target failed; restoring the configuration active before rollback."
  mv -f docker-compose.yml.rollback-current docker-compose.yml
  mv -f state/server.yaml.rollback-current state/server.yaml
  if [[ -f state/deployment.env.rollback-current ]]; then
    mv -f state/deployment.env.rollback-current state/deployment.env
  fi
  docker compose up -d || true
}
trap restore_current ERR
docker compose up -d
wait_for_service "${HYSTERIA_PORT}"

mv docker-compose.yml.rollback-current docker-compose.yml.previous
mv state/server.yaml.rollback-current state/server.yaml.previous
if [[ -f state/deployment.env.rollback-current ]]; then
  mv state/deployment.env.rollback-current state/deployment.env.previous
fi
trap - ERR
log_info "Rollback completed. The replaced version is now the next rollback point."
log_info "Safety backup: ${ROOT}/backups/pre-rollback-${timestamp}.tar.gz"
