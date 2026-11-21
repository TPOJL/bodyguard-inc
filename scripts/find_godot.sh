#!/usr/bin/env bash
# Locates a Godot 4.3+ executable across PATH, env override, and macOS/Linux install paths.
set -euo pipefail

if [[ -n "${GODOT_BIN:-}" ]] && [[ -x "${GODOT_BIN}" ]]; then
    echo "${GODOT_BIN}"
    exit 0
fi

for candidate in \
    "$(command -v godot 2>/dev/null || true)" \
    "$(command -v godot4 2>/dev/null || true)" \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "/Applications/Godot_mono.app/Contents/MacOS/Godot" \
    "/opt/homebrew/bin/godot" \
    "/usr/local/bin/godot"; do
    if [[ -n "${candidate}" ]] && [[ -x "${candidate}" ]]; then
        echo "${candidate}"
        exit 0
    fi
done

exit 1
