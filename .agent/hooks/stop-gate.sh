#!/usr/bin/env bash
# Stop / Pre-push Verification Gate:
# 1. Runs full-repo secret, API key, junk & bloat guard.
# 2. Runs headless-coop-playtester (1 Host + 2 Clients, 10s automated run).
# 3. Runs clip-telemetry-profiler (1,000-tick benchmark + orphan-node == 0 check).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== [verification-gate] 1/3 Full-repo Secret, API Key & Junk Guard ==="
python3 "${ROOT_DIR}/scripts/secret_guard.py" --all

echo "=== [verification-gate] 2/3 Headless Co-op Playtester (1 Host + 2 Clients) ==="
python3 "${ROOT_DIR}/.agent/skills/headless-coop-playtester/scripts/run_coop_smoke.py" --duration 10

echo "=== [verification-gate] 3/3 Clip Telemetry Profiler (1,000 ticks + Orphan Check) ==="
python3 "${ROOT_DIR}/.agent/skills/clip-telemetry-profiler/scripts/run_profiler.py"

echo "=== [verification-gate] PASSED — Milestone cleared ==="
