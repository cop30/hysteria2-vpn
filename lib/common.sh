#!/usr/bin/env bash

log_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

require_root() {
  [[ ${EUID} -eq 0 ]] || { log_error "Run with sudo."; return 1; }
}

validate_client_name() {
  [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$ ]] || {
    log_error "Client name must be 1-32 characters: letters, digits, '_' or '-'."
    return 1
  }
}

validate_port() {
  [[ ${1:-} =~ ^[0-9]+$ ]] && (( 1 <= $1 && $1 <= 65535 ))
}

validate_ipv4() {
  local ip="${1:-}" octet="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
  [[ ${ip} =~ ^${octet}\.${octet}\.${octet}\.${octet}$ ]]
}

validate_hostname() {
  [[ ${1:-} =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

valid_public_host() {
  validate_ipv4 "${1:-}" || validate_hostname "${1:-}"
}

urlencode() {
  local LC_ALL=C value="${1:-}" out="" char hex i
  for ((i=0; i<${#value}; i++)); do
    char="${value:i:1}"
    case "${char}" in
      [A-Za-z0-9._~-]) out+="${char}" ;;
      *) printf -v hex '%%%02X' "'${char}"; out+="${hex}" ;;
    esac
  done
  printf '%s' "${out}"
}

read_runtime() {
  local state_dir="$1" key value
  [[ -f ${state_dir}/runtime.env ]] || { log_error "Missing ${state_dir}/runtime.env"; return 1; }
  PUBLIC_HOST=''
  HYSTERIA_PORT=''
  TLS_SNI=''
  OBFS_PASSWORD=''
  while IFS='=' read -r key value; do
    case "${key}" in
      PUBLIC_HOST) PUBLIC_HOST="${value}" ;;
      HYSTERIA_PORT) HYSTERIA_PORT="${value}" ;;
      TLS_SNI) TLS_SNI="${value}" ;;
      OBFS_PASSWORD) OBFS_PASSWORD="${value}" ;;
      '') ;;
      *) log_error "Unknown runtime setting: ${key}"; return 1 ;;
    esac
  done < "${state_dir}/runtime.env"
  valid_public_host "${PUBLIC_HOST}" || { log_error "Invalid saved PUBLIC_HOST."; return 1; }
  validate_port "${HYSTERIA_PORT}" || { log_error "Invalid saved HYSTERIA_PORT."; return 1; }
  validate_hostname "${TLS_SNI}" || { log_error "Invalid saved TLS_SNI."; return 1; }
  [[ ${OBFS_PASSWORD} =~ ^[0-9a-f]{64}$ ]] || { log_error "Invalid saved obfuscation secret."; return 1; }
}

read_deployment() {
  local state_dir="$1" key value
  [[ -f ${state_dir}/deployment.env ]] || { log_error "Run deploy.sh first."; return 1; }
  HYSTERIA_RELEASE=''
  HYSTERIA_COMMIT=''
  IMAGE=''
  while IFS='=' read -r key value; do
    case "${key}" in
      HYSTERIA_RELEASE) HYSTERIA_RELEASE="${value}" ;;
      HYSTERIA_COMMIT) HYSTERIA_COMMIT="${value}" ;;
      IMAGE) IMAGE="${value}" ;;
      '') ;;
      *) log_error "Unknown deployment setting: ${key}"; return 1 ;;
    esac
  done < "${state_dir}/deployment.env"
  [[ ${HYSTERIA_RELEASE} =~ ^app/v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ ${HYSTERIA_COMMIT} =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ ${IMAGE} =~ ^local/hysteria2:v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
}

render_server_config() {
  local state_dir="$1" output="$2" name password count=0
  local -A seen=()
  read_runtime "${state_dir}"
  {
    # The container listens above 1024 and therefore needs no Linux capability;
    # Compose maps the selected public UDP port to this fixed internal port.
    printf 'listen: 0.0.0.0:8443\n\n'
    printf 'tls:\n  cert: /etc/hysteria/server.crt\n  key: /etc/hysteria/server.key\n  sniGuard: disable\n\n'
    printf 'auth:\n  type: userpass\n  userpass:\n'
    while IFS=$'\t' read -r name password; do
      [[ -n ${name} ]] || continue
      validate_client_name "${name}" >/dev/null || return 1
      [[ -z ${seen[${name}]+x} ]] || { log_error "Duplicate client record: ${name}."; return 1; }
      [[ ${password} =~ ^[0-9a-f]{64}$ ]] || { log_error "Invalid password record for ${name}."; return 1; }
      seen["${name}"]=1
      printf '    "%s": "%s"\n' "${name}" "${password}"
      count=$((count + 1))
    done < "${state_dir}/users.tsv"
    (( count > 0 )) || { log_error "At least one client is required."; return 1; }
    printf '\nobfs:\n  type: salamander\n  salamander:\n    password: "%s"\n\n' "${OBFS_PASSWORD}"
    printf 'outbounds:\n  - name: direct-v4\n    type: direct\n    direct:\n      mode: 4\n'
  } > "${output}"
}

render_client_uri() {
  local state_dir="$1" client="$2" password="$3" pin userinfo
  read_runtime "${state_dir}"
  pin=$(openssl x509 -noout -fingerprint -sha256 -in "${state_dir}/server.crt" | cut -d= -f2)
  userinfo="$(urlencode "${client}"):$(urlencode "${password}")"
  printf 'hysteria2://%s@%s:%s/?obfs=salamander&obfs-password=%s&insecure=1&pinSHA256=%s&sni=%s#%s-Hysteria2\n' \
    "${userinfo}" "${PUBLIC_HOST}" "${HYSTERIA_PORT}" "${OBFS_PASSWORD}" "${pin}" \
    "$(urlencode "${TLS_SNI}")" "$(urlencode "${client}")"
}

write_client_artifacts() {
  local root="$1" client="$2" password="$3" uri_file
  uri_file="${root}/clients/${client}.hy2"
  install -d -m 0700 "${root}/clients"
  render_client_uri "${root}/state" "${client}" "${password}" > "${uri_file}"
  chmod 0600 "${uri_file}"
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -s 8 -o "${root}/clients/${client}.png" < "${uri_file}"
    chmod 0600 "${root}/clients/${client}.png"
  else
    log_warn "qrencode is not installed; URI created without PNG."
  fi
}

config_check() {
  local root="$1" image="$2" config_file="$3"
  local check_name="hysteria2-config-check-$$-${RANDOM}" running logs
  docker run -d --name "${check_name}" --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,noexec,nosuid,size=16m \
    -v "${config_file}:/etc/hysteria/server.yaml:ro" \
    -v "${root}/state/server.crt:/etc/hysteria/server.crt:ro" \
    -v "${root}/state/server.key:/etc/hysteria/server.key:ro" \
    "${image}" server --config /etc/hysteria/server.yaml >/dev/null
  sleep 2
  running="$(docker inspect -f '{{.State.Running}}' "${check_name}" 2>/dev/null || true)"
  if [[ ${running} != true ]]; then
    logs="$(docker logs "${check_name}" 2>&1 || true)"
    docker rm -f "${check_name}" >/dev/null 2>&1 || true
    log_error "Hysteria rejected the candidate configuration:"
    printf '%s\n' "${logs}" >&2
    return 1
  fi
  docker rm -f "${check_name}" >/dev/null
}

container_running() {
  [[ $(docker inspect -f '{{.State.Running}}' hysteria2 2>/dev/null || true) == true ]]
}

wait_for_service() {
  local port="$1"
  for _ in {1..20}; do
    if container_running && ss -H -lun "sport = :${port}" | grep -q .; then return 0; fi
    sleep 1
  done
  return 1
}
