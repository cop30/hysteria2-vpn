#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
source "${ROOT}/lib/common.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEST_DIR}"' EXIT
mkdir -p "${TEST_DIR}/state"
cat > "${TEST_DIR}/state/runtime.env" <<'EOF'
PUBLIC_HOST=203.0.113.7
HYSTERIA_PORT=443
TLS_SNI=vpn.example.com
OBFS_PASSWORD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF
printf 'iphone\t%s\nwindows\t%s\n' \
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
  > "${TEST_DIR}/state/users.tsv"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -keyout "${TEST_DIR}/state/server.key" -out "${TEST_DIR}/state/server.crt" \
  -subj '/CN=vpn.example.com' >/dev/null 2>&1

render_server_config "${TEST_DIR}/state" "${TEST_DIR}/server.yaml"
grep -q '^listen: 0.0.0.0:8443$' "${TEST_DIR}/server.yaml" || fail "internal listener missing"
grep -q '^    "iphone": "bbbb' "${TEST_DIR}/server.yaml" || fail "iphone auth missing"
grep -q '^    "windows": "cccc' "${TEST_DIR}/server.yaml" || fail "windows auth missing"
grep -q '^      mode: 4$' "${TEST_DIR}/server.yaml" || fail "IPv4 outbound missing"
render_client_uri "${TEST_DIR}/state" iphone \
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  > "${TEST_DIR}/client.hy2"
grep -q '203\.0\.113\.7:443' "${TEST_DIR}/client.hy2" || fail "client endpoint missing"

mkdir -p "${TEST_DIR}/bin"
cat > "${TEST_DIR}/bin/qrencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -s ]]; then
  output="$4"
  cat > "${output}"
elif [[ ${1:-} == -t && ${2:-} == ANSIUTF8 ]]; then
  printf 'TERMINAL-QR\n'
  cat >/dev/null
else
  exit 2
fi
EOF
chmod +x "${TEST_DIR}/bin/qrencode"
qr_output="$(PATH="${TEST_DIR}/bin:${PATH}" write_client_artifacts "${TEST_DIR}" iphone \
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')"
[[ -s ${TEST_DIR}/clients/iphone.hy2 ]] || fail "client URI artifact missing"
[[ -s ${TEST_DIR}/clients/iphone.png ]] || fail "client QR PNG artifact missing"
grep -q 'TERMINAL-QR' <<< "${qr_output}" || fail "terminal QR was not printed"
[[ $(stat -c '%a' "${TEST_DIR}/clients/iphone.hy2") == 600 ]] || fail "client URI mode is not 0600"
[[ $(stat -c '%a' "${TEST_DIR}/clients/iphone.png") == 600 ]] || fail "client QR mode is not 0600"

printf 'bad name\t%s\n' \
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' \
  >> "${TEST_DIR}/state/users.tsv"
if render_server_config "${TEST_DIR}/state" "${TEST_DIR}/invalid.yaml" 2>/dev/null; then
  fail "invalid user record accepted"
fi
printf 'iphone\t%s\niphone\t%s\n' \
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
  > "${TEST_DIR}/state/users.tsv"
if render_server_config "${TEST_DIR}/state" "${TEST_DIR}/duplicate.yaml" 2>/dev/null; then
  fail "duplicate user record accepted"
fi
echo "OK: test_render"
