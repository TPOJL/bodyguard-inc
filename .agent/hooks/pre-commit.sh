#!/usr/bin/env bash
# Pre-commit hook:
# 1. Blocks API keys, secrets, private keys, OS/IDE junk, and files > 10MB.
# 2. Runs fast unit & physics stability tests.
# 3. Runs multiplayer-netcode-guard static security audit.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== [pre-commit] 1/3 Secret, API key, junk & >10MB bloat guard ==="
python3 "${ROOT_DIR}/scripts/secret_guard.py" --staged

echo "=== [pre-commit] 2/3 Running fast unit & physics stability tests ==="
python3 "${ROOT_DIR}/tests/unit/run_unit_tests.py"

echo "=== [pre-commit] 3/3 Running multiplayer-netcode-guard static audit ==="
python3 "${ROOT_DIR}/.agent/skills/multiplayer-netcode-guard/scripts/audit_netcode.py"

echo "=== [pre-commit] ALL CHECKS PASSED ==="
