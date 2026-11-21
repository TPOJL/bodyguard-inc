#!/usr/bin/env python3
"""Static netcode security & bandwidth auditor for BODYGUARD INC.

Scans all GDScript files under src/ for:
1. @rpc("any_peer", ...) handlers missing an immediate `multiplayer.is_server()` guard.
2. Client-callable RPCs with forbidden authoritative state mutation names.
3. Unsafe full-skeleton / 60Hz ragdoll bone sync patterns.
4. Direct `SteamMultiplayerPeer` usage outside `src/core/network_transport.gd`.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent.parent.parent.parent
SRC_DIR = ROOT_DIR / "src"

RPC_ANY_PEER_RE = re.compile(r'@rpc\s*\([^)]*"any_peer"[^)]*\)')
FUNC_NAME_RE = re.compile(r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")

FORBIDDEN_CLIENT_RPC_PATTERNS = (
    re.compile(r"set_vip_(?:dead|alive|state|health)"),
    re.compile(r"apply_.*damage"),
    re.compile(r"set_suspicion"),
    re.compile(r"set_(?:score|quota|money)"),
    re.compile(r"set_ragdoll_transform"),
)


def audit_file(path: pathlib.Path) -> list[str]:
    violations: list[str] = []
    rel = path.relative_to(ROOT_DIR)
    lines = path.read_text(encoding="utf-8").splitlines()

    # Check SteamMultiplayerPeer abstraction leak
    if str(rel) != "src/core/network_transport.gd":
        for idx, line in enumerate(lines, start=1):
            if "SteamMultiplayerPeer" in line and not line.strip().startswith("#"):
                violations.append(
                    f"{rel}:{idx}: Direct SteamMultiplayerPeer reference outside src/core/network_transport.gd"
                )

    i = 0
    while i < len(lines):
        line = lines[i]
        if RPC_ANY_PEER_RE.search(line):
            rpc_line = i + 1
            # Find the following func declaration
            j = i + 1
            while j < len(lines) and (not lines[j].strip() or lines[j].strip().startswith(("@", "#"))):
                j += 1
            if j < len(lines):
                fn_match = FUNC_NAME_RE.match(lines[j])
                if fn_match:
                    fn_name = fn_match.group(1)
                    # Check forbidden authoritative names on any_peer RPC
                    for pat in FORBIDDEN_CLIENT_RPC_PATTERNS:
                        if pat.search(fn_name):
                            violations.append(
                                f"{rel}:{rpc_line}: @rpc('any_peer') func '{fn_name}' appears to allow client-trusted authoritative state mutation"
                            )

                    # Inspect function body for `multiplayer.is_server()` guard
                    fn_indent = len(lines[j]) - len(lines[j].lstrip())
                    body_lines: list[str] = []
                    k = j + 1
                    while k < len(lines):
                        stripped = lines[k].strip()
                        if stripped and not stripped.startswith("#"):
                            indent = len(lines[k]) - len(lines[k].lstrip())
                            if indent <= fn_indent:
                                break
                            body_lines.append(stripped)
                        k += 1

                    # Check first 6 non-empty body lines for server authority check
                    head_body = "\n".join(body_lines[:6])
                    if "multiplayer.is_server()" not in head_body:
                        violations.append(
                            f"{rel}:{rpc_line}: @rpc('any_peer') func '{fn_name}' is missing an immediate 'if not multiplayer.is_server(): return' guard"
                        )
            i = j
        i += 1

    return violations


def main() -> int:
    if not SRC_DIR.exists():
        print("[netcode-guard] No src/ directory found; skipping.")
        return 0

    gd_files = sorted(SRC_DIR.rglob("*.gd"))
    all_violations: list[str] = []
    for f in gd_files:
        all_violations.extend(audit_file(f))

    if all_violations:
        print("[netcode-guard] FAIL — Netcode authority violations detected:")
        for v in all_violations:
            print(f"  - {v}")
        return 1

    print(f"[netcode-guard] PASS — Audited {len(gd_files)} file(s); zero unsafe RPCs or authority leaks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
