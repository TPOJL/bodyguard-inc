#!/usr/bin/env python3
"""Secret, API Key, Junk File & Asset Bloat Guard for BODYGUARD INC.

Protects the repository from leaking credentials, API keys, private keys,
OS/IDE junk files, or oversized binaries (> 10 MB) to GitHub.

Modes:
  --staged  Scan git-staged files (reads staged index content; used in pre-commit).
  --all     Scan all tracked + non-ignored workspace files (used in make check / CI).
"""

from __future__ import annotations

import argparse
import fnmatch
import math
import pathlib
import re
import subprocess
import sys

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent
MAX_FILE_BYTES = 10 * 1024 * 1024  # 10 MB

# Filenames that must NEVER be committed to the repository
FORBIDDEN_FILENAME_PATTERNS: tuple[str, ...] = (
    ".env",
    ".env.*",
    "*.pem",
    "*.key",
    "*.p12",
    "*.pfx",
    "*.jks",
    "*.keystore",
    "id_rsa",
    "id_rsa.*",
    "id_ed25519",
    "id_ed25519.*",
    "*credentials*.json",
    "*service-account*.json",
    "export_presets.cfg",
    "steam_appid.txt",
    ".DS_Store",
    "Thumbs.db",
    "Desktop.ini",
    "*.swp",
    "*.swo",
    "*.tmp",
    "*.bak",
    "*.orig",
    "*.log",
)

ALLOWED_EXACT_NAMES: set[str] = {
    ".env.example",
    "secret_guard.py",
    "SECURITY.md",
}

# High-confidence secret & API key signatures
SECRET_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Google / Gemini API Key", re.compile(r"AIza[0-9A-Za-z\-_]{35}")),
    ("GitHub Classic Token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36}\b")),
    ("GitHub Fine-Grained PAT", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}\b")),
    ("OpenAI / Anthropic API Key", re.compile(r"\bsk-(?:proj-|ant-)?[A-Za-z0-9\-_]{20,}\b")),
    ("AWS Access Key ID", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("Stripe Live/Restricted Key", re.compile(r"\b[sr]k_live_[0-9a-zA-Z]{24,}\b")),
    ("Slack Token", re.compile(r"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b")),
    ("Discord Webhook URL", re.compile(r"https://discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_\-]+")),
    ("Telegram Bot Token", re.compile(r"\b\d{8,10}:[A-Za-z0-9_\-]{35}\b")),
    ("Private Key PEM Block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----")),
    ("Database URL with Credentials", re.compile(r"(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://[^:\s]+:[^@\s]+@[^\s]+")),
)

# Generic sensitive assignment: API_KEY = "real_secret_here"
GENERIC_ASSIGN_RE = re.compile(
    r"""(?i)\b([A-Z0-9_]*(?:API_KEY|SECRET_KEY|ACCESS_TOKEN|AUTH_TOKEN|PRIVATE_KEY|CLIENT_SECRET|STEAM_WEB_API_KEY|PASSWORD|PASSWD))\s*[:=]\s*['"]?([^\s'"#;,]{12,})['"]?"""
)

PLACEHOLDER_HINTS: tuple[str, ...] = (
    "your_",
    "placeholder",
    "example",
    "changeme",
    "dummy",
    "fake",
    "test_",
    "sample",
    "<",
    "${",
    "xxxx",
    "0000",
)

# Paths allowed to contain regex pattern definitions (this scanner itself)
SELF_REL_PATH = "scripts/secret_guard.py"


def shannon_entropy(value: str) -> float:
    if not value:
        return 0.0
    freq: dict[str, int] = {}
    for ch in value:
        freq[ch] = freq.get(ch, 0) + 1
    length = float(len(value))
    return -sum((c / length) * math.log2(c / length) for c in freq.values())


def is_placeholder(value: str) -> bool:
    low = value.lower()
    if any(hint in low for hint in PLACEHOLDER_HINTS):
        return True
    if low.startswith(("res://", "uid://", "http://127.0.0.1", "http://localhost")):
        return True
    return False


def check_filename(rel_path: str) -> list[str]:
    p = pathlib.Path(rel_path)
    name = p.name
    if name in ALLOWED_EXACT_NAMES:
        return []
    issues: list[str] = []
    for pat in FORBIDDEN_FILENAME_PATTERNS:
        if fnmatch.fnmatch(name, pat):
            issues.append(f"{rel_path}: forbidden/sensitive or junk filename matching '{pat}'")
            break
    if any(part in {".claude", "__pycache__", ".godot", "logs"} for part in p.parts):
        issues.append(f"{rel_path}: forbidden directory in repository path")
    return issues


def scan_bytes(rel_path: str, data: bytes) -> list[str]:
    issues: list[str] = []
    if len(data) > MAX_FILE_BYTES:
        mb = len(data) / (1024 * 1024)
        issues.append(f"{rel_path}: file size {mb:.2f} MB exceeds 10.00 MB limit")

    if rel_path == SELF_REL_PATH:
        return issues

    # Skip binary blobs for text regex scan
    if b"\x00" in data[:8192]:
        return issues

    text = data.decode("utf-8", errors="replace")
    for line_no, line in enumerate(text.splitlines(), start=1):
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(line):
                issues.append(f"{rel_path}:{line_no}: potential {label} detected!")

        for match in GENERIC_ASSIGN_RE.finditer(line):
            var_name, raw_val = match.group(1), match.group(2)
            if is_placeholder(raw_val):
                continue
            if len(raw_val) >= 16 and shannon_entropy(raw_val) >= 3.3:
                issues.append(
                    f"{rel_path}:{line_no}: suspicious hardcoded secret assigned to '{var_name}' (use .env instead)"
                )

    return issues


def collect_staged_files() -> list[tuple[str, bytes]]:
    res = subprocess.run(
        ["git", "-C", str(ROOT_DIR), "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        capture_output=True,
        text=True,
        check=False,
    )
    items: list[tuple[str, bytes]] = []
    for line in res.stdout.splitlines():
        rel = line.strip()
        if not rel:
            continue
        blob = subprocess.run(
            ["git", "-C", str(ROOT_DIR), "show", f":{rel}"],
            capture_output=True,
            check=False,
        )
        if blob.returncode == 0:
            items.append((rel, blob.stdout))
        else:
            full = ROOT_DIR / rel
            if full.is_file():
                items.append((rel, full.read_bytes()))
    return items


def collect_repo_files() -> list[tuple[str, bytes]]:
    # Uses git ls-files (tracked + untracked non-ignored files) so .gitignore is respected
    res = subprocess.run(
        ["git", "-C", str(ROOT_DIR), "ls-files", "--cached", "--others", "--exclude-standard"],
        capture_output=True,
        text=True,
        check=False,
    )
    items: list[tuple[str, bytes]] = []
    for line in res.stdout.splitlines():
        rel = line.strip()
        if not rel:
            continue
        full = ROOT_DIR / rel
        if full.is_file() and not full.is_symlink():
            items.append((rel, full.read_bytes()))
    return items


def main() -> int:
    parser = argparse.ArgumentParser(description="Secret, API key, junk & bloat guard")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="Scan git staged files")
    mode.add_argument("--all", action="store_true", help="Scan all non-ignored repository files")
    args = parser.parse_args()

    items = collect_staged_files() if args.staged else collect_repo_files()
    scope = "staged" if args.staged else "repository"

    violations: list[str] = []
    for rel_path, content in items:
        violations.extend(check_filename(rel_path))
        violations.extend(scan_bytes(rel_path, content))

    if violations:
        print(f"[secret-guard] BLOCKED — Found {len(violations)} security/hygiene violation(s) in {scope} files:")
        for v in violations:
            print(f"  - {v}")
        print("[secret-guard] Remove secrets/junk or move keys to ignored '.env' before committing/pushing.")
        return 1

    print(f"[secret-guard] PASS — Scanned {len(items)} {scope} file(s); 0 API keys, 0 secrets, 0 junk/bloat files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
