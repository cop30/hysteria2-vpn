#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
require_root
read_runtime "${ROOT}/state"

docker compose -f "${ROOT}/docker-compose.yml" ps
echo ""
docker inspect hysteria2 --format 'running={{.State.Running}} restarts={{.RestartCount}} started={{.State.StartedAt}} image={{.Config.Image}}'
ss -H -lunp "sport = :${HYSTERIA_PORT}"
printf 'clients=%s\n' "$(grep -cve '^$' "${ROOT}/state/users.tsv")"
docker compose -f "${ROOT}/docker-compose.yml" logs --tail 30 hysteria2
