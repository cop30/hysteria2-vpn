#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh
source "${ROOT}/lib/common.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

validate_client_name phone || fail "valid client rejected"
validate_client_name iphone-15 || fail "valid hyphen rejected"
validate_client_name '../oops' && fail "path traversal accepted"
validate_client_name 'two words' && fail "space accepted"
validate_port 443 || fail "valid port rejected"
validate_port 0 && fail "port zero accepted"
validate_port 65536 && fail "oversized port accepted"
validate_ipv4 203.0.113.7 || fail "valid IPv4 rejected"
validate_ipv4 999.0.0.1 && fail "invalid IPv4 accepted"
validate_hostname mail.example.com || fail "valid hostname rejected"
validate_hostname '-bad.example' && fail "invalid hostname accepted"
[[ $(urlencode 'a b:c') == 'a%20b%3Ac' ]] || fail "URL encoding failed"
echo "OK: test_common"
