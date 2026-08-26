#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "${ROOT}/tests/test_common.sh"
bash "${ROOT}/tests/test_render.sh"
