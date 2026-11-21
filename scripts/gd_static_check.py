#!/usr/bin/env python3
"""Fast GDScript static type-checker and linter for BODYGUARD INC.

Runs:
1. Strict static typing & physics-separation static checks (always runs, zero external deps).
2. `gdlint` if installed (warns with setup hint if missing).
3. `godot --headless --path . --check-only --script <file>` if Godot 4 is installed
   (warns with setup hint if missing).
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent

FUNC_DEF_RE = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(->\s*[A-Za-z_][A-Za-z0-9_\[\],\s]*)?\s*:")
MEMBER_VAR_RE = re.compile(r"^(?:@export(?:_[a-z_]+)?(?:\([^)]*\))?\s+|@onready\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)")
PHYSICS_CALL_RE = re.compile(r"\b(apply_impulse|apply_central_impulse|apply_force|apply_central_force|apply_torque|apply_torque_impulse)\s*\(")


def find_godot() -> str | None:
    finder = ROOT_DIR / "scripts" / "find_godot.sh"
    if finder.exists():
        res = subprocess.run([str(finder)], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    return None


def discover_gd_files(args: list[str]) -> list[pathlib.Path]:
    if args:
        files: list[pathlib.Path] = []
        for raw in args:
            p = pathlib.Path(raw)
            if not p.is_absolute():
                p = ROOT_DIR / p
            if p.is_file() and p.suffix == ".gd":
                files.append(p)
            elif p.is_dir():
                files.extend(sorted(p.rglob("*.gd")))
        return files

    search_roots = [ROOT_DIR / "src", ROOT_DIR / "tests", ROOT_DIR / ".agent" / "skills"]
    found: list[pathlib.Path] = []
    for base in search_roots:
        if base.exists():
            found.extend(sorted(base.rglob("*.gd")))
    return found


def check_strict_typing_and_safety(path: pathlib.Path) -> list[str]:
    errors: list[str] = []
    rel = path.relative_to(ROOT_DIR) if path.is_relative_to(ROOT_DIR) else path
    lines = path.read_text(encoding="utf-8").splitlines()

    in_process_fn = False
    process_indent = 0

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # Track whether we are inside _process(...)
        fn_match = FUNC_DEF_RE.match(line)
        if fn_match:
            fn_name, params_str, ret_type = fn_match.groups()
            indent = len(line) - len(line.lstrip())
            in_process_fn = fn_name == "_process"
            process_indent = indent

            if not ret_type:
                errors.append(f"{rel}:{idx}: func '{fn_name}' missing explicit return type annotation (-> Type)")

            params_clean = params_str.strip()
            if params_clean:
                for raw_param in params_clean.split(","):
                    param = raw_param.strip()
                    if not param:
                        continue
                    # Parameter must have ': Type' or ':= default'
                    name_part = param.split("=")[0].strip()
                    if ":" not in name_part and ":=" not in param:
                        errors.append(
                            f"{rel}:{idx}: parameter '{name_part}' in func '{fn_name}' missing explicit type annotation"
                        )
            continue

        if in_process_fn:
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= process_indent and not stripped.startswith("#"):
                in_process_fn = False
            else:
                phys_hit = PHYSICS_CALL_RE.search(line)
                if phys_hit:
                    errors.append(
                        f"{rel}:{idx}: forbidden physics mutation '{phys_hit.group(1)}()' inside _process(); move to _physics_process()"
                    )

        # Check top-level member variables for static typing
        if not line.startswith((" ", "\t")):
            var_match = MEMBER_VAR_RE.match(line)
            if var_match:
                var_name, rest = var_match.groups()
                if not rest.startswith(":") and ":=" not in rest:
                    errors.append(f"{rel}:{idx}: member var '{var_name}' missing explicit static type annotation")

    return errors


def main() -> int:
    files = discover_gd_files(sys.argv[1:])
    if not files:
        print("[OK] No .gd files to check.")
        return 0

    print(f"[gd_static_check] Checking {len(files)} GDScript file(s)...")
    all_errors: list[str] = []

    # 1. Built-in strict typing & physics-safety rules
    for f in files:
        all_errors.extend(check_strict_typing_and_safety(f))

    # 2. gdlint if available
    gdlint_bin = shutil.which("gdlint")
    if gdlint_bin:
        res = subprocess.run([gdlint_bin, *[str(f) for f in files]], capture_output=True, text=True)
        if res.returncode != 0:
            all_errors.append(f"gdlint failed:\n{res.stdout}{res.stderr}")
    else:
        print("[WARN] gdlint not installed; ran built-in strict GDScript checker. Run ./scripts/setup_env.sh to install gdtoolkit.")

    # 3. Godot --check-only if available
    godot_bin = find_godot()
    if godot_bin:
        for f in files:
            res = subprocess.run(
                [godot_bin, "--headless", "--path", str(ROOT_DIR), "--check-only", "--script", str(f)],
                capture_output=True,
                text=True,
                timeout=30,
            )
            combined = f"{res.stdout}\n{res.stderr}"
            if res.returncode != 0 or "SCRIPT ERROR" in combined or "Parse Error" in combined:
                all_errors.append(f"godot --check-only failed for {f}:\n{combined.strip()}")
    else:
        print("[WARN] Godot 4 binary not found; skipped engine --check-only pass. Run ./scripts/setup_env.sh to install Godot 4.3+.")

    if all_errors:
        print("\n[FAIL] Static check violations found:")
        for err in all_errors:
            print(f"  - {err}")
        return 1

    print(f"[PASS] All {len(files)} GDScript file(s) passed strict typing & safety checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
