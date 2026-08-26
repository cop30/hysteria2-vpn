#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=versions.env
source "${ROOT}/versions.env"

require_root
for cmd in docker git openssl curl ss awk sed flock; do
  command -v "${cmd}" >/dev/null || { log_error "Missing command: ${cmd}"; exit 1; }
done
docker compose version >/dev/null

install -d -m 0700 state
exec 9>"${ROOT}/state/deploy.lock"
flock -x 9

[[ ${HYSTERIA_RELEASE} =~ ^app/v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ ${HYSTERIA_COMMIT} =~ ^[0-9a-f]{40}$ ]]
resolved_sha="$(git ls-remote https://github.com/HyNetworks/hysteria.git "refs/tags/${HYSTERIA_RELEASE}^{}" | awk 'NR==1 {print $1}')"
[[ -n ${resolved_sha} ]] || resolved_sha="$(git ls-remote https://github.com/HyNetworks/hysteria.git "refs/tags/${HYSTERIA_RELEASE}" | awk 'NR==1 {print $1}')"
[[ ${resolved_sha} == "${HYSTERIA_COMMIT}" ]] || { log_error "Release tag does not resolve to pinned commit."; exit 1; }

image_tag="${HYSTERIA_RELEASE#app/}"
image="local/hysteria2:${image_tag}"
port="${HYSTERIA_PORT:-443}"
validate_port "${port}" || { log_error "Invalid HYSTERIA_PORT: ${port}"; exit 1; }

if [[ ! -f state/runtime.env ]]; then
  public_host="${PUBLIC_HOST:-}"
  if [[ -z ${public_host} ]]; then public_host="$(curl -4fsS --max-time 10 https://api.ipify.org)"; fi
  valid_public_host "${public_host}" || { log_error "Invalid PUBLIC_HOST: ${public_host}"; exit 1; }
  tls_sni="${TLS_SNI:-hysteria.local}"
  validate_hostname "${tls_sni}" || { log_error "Invalid TLS_SNI: ${tls_sni}"; exit 1; }
  initial_client="${INITIAL_CLIENT:-default}"
  validate_client_name "${initial_client}"

  install -d -m 0700 clients backups
  obfs_password="$(openssl rand -hex 32)"
  initial_password="$(openssl rand -hex 32)"
  cat > state/runtime.env <<EOF
PUBLIC_HOST=${public_host}
HYSTERIA_PORT=${port}
TLS_SNI=${tls_sni}
OBFS_PASSWORD=${obfs_password}
EOF
  printf '%s\t%s\n' "${initial_client}" "${initial_password}" > state/users.tsv
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
    -keyout state/server.key -out state/server.crt \
    -subj "/CN=${tls_sni}" -addext "subjectAltName=DNS:${tls_sni}"
  chmod 0600 state/runtime.env state/users.tsv state/server.key
  chmod 0644 state/server.crt
else
  read_runtime "${ROOT}/state"
  [[ ${port} == "${HYSTERIA_PORT}" ]] || { log_error "Port is already fixed at ${HYSTERIA_PORT}."; exit 1; }
fi

if ! docker image inspect "${image}" >/dev/null 2>&1; then
  log_info "Building Hysteria ${HYSTERIA_RELEASE} from ${HYSTERIA_COMMIT} on this server..."
  docker build --pull \
    --build-arg "HYSTERIA_RELEASE=${HYSTERIA_RELEASE}" \
    --build-arg "HYSTERIA_COMMIT=${HYSTERIA_COMMIT}" \
    -t "${image}" .
fi
docker run --rm "${image}" version

if [[ -f ${ROOT}/state/server.yaml ]]; then
  cp -a "${ROOT}/state/server.yaml" "${ROOT}/state/server.yaml.previous"
fi
render_server_config "${ROOT}/state" "${ROOT}/state/server.yaml.new"
config_check "${ROOT}" "${image}" "${ROOT}/state/server.yaml.new"
mv "${ROOT}/state/server.yaml.new" "${ROOT}/state/server.yaml"
chmod 0600 "${ROOT}/state/server.yaml"

sed -e "s|__IMAGE__|${image}|g" -e "s|__PORT__|${HYSTERIA_PORT}|g" \
  docker-compose.yml.tmpl > docker-compose.yml.new
docker compose -f docker-compose.yml.new config --quiet

if [[ -f docker-compose.yml ]]; then
  cp -a docker-compose.yml docker-compose.yml.previous
elif ss -H -lun "sport = :${HYSTERIA_PORT}" | grep -q .; then
  log_error "UDP ${HYSTERIA_PORT} is already in use by another service."
  exit 1
fi

if [[ -f state/deployment.env ]]; then
  cp -a state/deployment.env state/deployment.env.previous
fi

ufw_added=0
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  if ! ufw status | grep -Eq "^${HYSTERIA_PORT}/udp[[:space:]]+ALLOW IN"; then
    ufw allow "${HYSTERIA_PORT}/udp" comment 'Hysteria2'
    : > state/ufw-rule-owned
    ufw_added=1
  fi
else
  log_warn "UFW is not active; open UDP ${HYSTERIA_PORT} in the host/cloud firewall."
fi

mv docker-compose.yml.new docker-compose.yml
if ! docker compose up -d || ! wait_for_service "${HYSTERIA_PORT}"; then
  log_error "New deployment failed; attempting rollback."
  docker compose logs --tail 100 hysteria2 >&2 || true
  if [[ -f docker-compose.yml.previous ]]; then
    mv docker-compose.yml.previous docker-compose.yml
    if [[ -f state/server.yaml.previous ]]; then
      mv state/server.yaml.previous state/server.yaml
    fi
    if [[ -f state/deployment.env.previous ]]; then
      mv state/deployment.env.previous state/deployment.env
    fi
    docker compose up -d || true
  else
    docker compose down || true
    if (( ufw_added == 1 )); then
      ufw --force delete allow "${HYSTERIA_PORT}/udp" || true
      rm -f state/ufw-rule-owned
    fi
  fi
  exit 1
fi

printf 'HYSTERIA_RELEASE=%s\nHYSTERIA_COMMIT=%s\nIMAGE=%s\n' \
  "${HYSTERIA_RELEASE}" "${HYSTERIA_COMMIT}" "${image}" > state/deployment.env
chmod 0600 state/deployment.env

while IFS=$'\t' read -r client_name client_password; do
  [[ -n ${client_name} ]] || continue
  write_client_artifacts "${ROOT}" "${client_name}" "${client_password}"
done < state/users.tsv

log_info "Hysteria2 is running on UDP ${HYSTERIA_PORT}."
log_info "Client artifacts: ${ROOT}/clients (secret, gitignored)."
