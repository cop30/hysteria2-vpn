#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
source "${ROOT}/lib/common.sh"
require_root

image="${1:-}"
[[ ${image} =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,199}$ ]] || {
  log_error "Usage: sudo bash tests/smoke_image.sh IMAGE"
  exit 1
}
docker image inspect "${image}" >/dev/null

test_root="$(mktemp -d)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT
install -d -m 0700 "${test_root}/state"
cat > "${test_root}/state/runtime.env" <<'EOF'
PUBLIC_HOST=203.0.113.7
HYSTERIA_PORT=443
TLS_SNI=smoke.invalid
OBFS_PASSWORD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF
printf 'smoke\t%s\n' \
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  > "${test_root}/state/users.tsv"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -keyout "${test_root}/state/server.key" -out "${test_root}/state/server.crt" \
  -subj '/CN=smoke.invalid' >/dev/null 2>&1
render_server_config "${test_root}/state" "${test_root}/state/server.yaml"
config_check "${test_root}" "${image}" "${test_root}/state/server.yaml"
log_info "Image accepted the generated configuration: ${image}"
