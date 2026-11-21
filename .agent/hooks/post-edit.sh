#!/usr/bin/env bash
# Antigravity / Gemini PostToolUse lifecycle hook:
# Runs fast static type-checking & linting on modified .gd files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGETS=()

if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        [[ "${arg}" == *.gd ]] && TARGETS+=("${arg}")
    done
elif [[ ! -t 0 ]]; then
    # Parse optional Antigravity PostToolUse JSON stdin payload
    EXTRACTED="$(python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
args = data.get("toolCall", {}).get("args", {})
for key in ("Path", "file_path", "path", "TargetFile"):
    val = args.get(key)
    if isinstance(val, str) and val.endswith(".gd"):
        print(val)
        break
' 2>/dev/null || true)"
    if [[ -n "${EXTRACTED}" ]]; then
        TARGETS+=("${EXTRACTED}")
    fi
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    if [[ -d "${ROOT_DIR}/.git" ]]; then
        while IFS= read -r f; do
            [[ -n "${f}" ]] && TARGETS+=("${f}")
        done < <(git -C "${ROOT_DIR}" diff --name-only -- '*.gd' 2>/dev/null || true)
    fi
fi

if [[ ${#TARGETS[@]} -gt 0 ]]; then
    python3 "${ROOT_DIR}/scripts/gd_static_check.py" "${TARGETS[@]}"
else
    python3 "${ROOT_DIR}/scripts/gd_static_check.py"
fi
