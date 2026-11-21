#!/usr/bin/env bash
# Environment bootstrap & dependency installer for BODYGUARD INC.
# Checks and optionally installs Godot 4.3+, gdtoolkit (gdlint/gdformat), and Git hooks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_NAME="$(uname -s)"

echo "=== BODYGUARD INC. Environment Setup ==="
echo "Workspace: ${ROOT_DIR}"
echo "OS: ${OS_NAME}"

# 1. Configure Git hooks
if [[ -d "${ROOT_DIR}/.git" ]]; then
    git -C "${ROOT_DIR}" config core.hooksPath .githooks
    echo "[OK] Git hooks path set to .githooks"
else
    echo "[WARN] Not a git repository yet; run 'git init && git config core.hooksPath .githooks'"
fi

# 2. Ensure executable permissions on all hook and skill scripts
chmod +x "${ROOT_DIR}"/scripts/*.sh "${ROOT_DIR}"/scripts/*.py 2>/dev/null || true
chmod +x "${ROOT_DIR}"/.githooks/* 2>/dev/null || true
chmod +x "${ROOT_DIR}"/.agent/hooks/*.sh 2>/dev/null || true
chmod +x "${ROOT_DIR}"/.agent/skills/*/scripts/*.py 2>/dev/null || true
echo "[OK] Script permissions updated"

# 3. Check Python 3
if command -v python3 >/dev/null 2>&1; then
    echo "[OK] python3: $(python3 --version)"
else
    echo "[ERROR] python3 is required. Please install Python 3.10+."
    exit 1
fi

# 4. Check / Install gdtoolkit (gdlint, gdformat)
if command -v gdlint >/dev/null 2>&1; then
    echo "[OK] gdlint: $(gdlint --version 2>&1 | head -n1)"
else
    echo "[MISSING] gdlint (gdtoolkit) not found."
    if [[ "${1:-}" == "--install" ]]; then
        echo "Installing gdtoolkit via pip3..."
        python3 -m pip install --user gdtoolkit
    else
        echo "  -> Install with: python3 -m pip install --user gdtoolkit"
        echo "  -> Or re-run: ./scripts/setup_env.sh --install"
    fi
fi

# 5. Check / Install Godot 4.3+
if GODOT_PATH="$("${ROOT_DIR}/scripts/find_godot.sh" 2>/dev/null)"; then
    echo "[OK] Godot found: ${GODOT_PATH} ($("${GODOT_PATH}" --version 2>/dev/null || echo 'unknown version'))"
else
    echo "[MISSING] Godot 4.3+ binary not found."
    if [[ "${1:-}" == "--install" ]]; then
        if [[ "${OS_NAME}" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
            echo "Installing Godot via Homebrew..."
            brew install --cask godot
        else
            echo "Please download Godot 4.3+ from https://godotengine.org/download/ and set GODOT_BIN."
            exit 1
        fi
    else
        if [[ "${OS_NAME}" == "Darwin" ]]; then
            echo "  -> Install with: brew install --cask godot"
            echo "  -> Or re-run: ./scripts/setup_env.sh --install"
        else
            echo "  -> Download Godot 4.3+ from https://godotengine.org/download/ and add to PATH or set GODOT_BIN."
        fi
    fi
fi

echo "=== Setup Check Complete ==="
