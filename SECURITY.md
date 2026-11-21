# Security Policy

## Automated Anti-Leak & Secret Protection

**BODYGUARD INC.** enforces multi-layered automated protection to prevent API keys, tokens, credentials, private keys, and repository junk from ever reaching GitHub:

1. **Gitignore Shield ([`.gitignore`](.gitignore)):** Blocks `.env*`, private keys (`*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`), keystores, `*credentials*.json`, Godot `export_presets.cfg`, `steam_appid.txt`, logs, and OS/IDE metadata.
2. **Active Secret & Bloat Scanner ([`scripts/secret_guard.py`](scripts/secret_guard.py)):**
   - Runs automatically on every `git commit` (`.githooks/pre-commit`) scanning staged index blobs.
   - Runs automatically on every `git push` (`.githooks/pre-push`), `make security`, `make check`, and GitHub Actions CI.
   - Detects Google/Gemini keys, GitHub PATs, OpenAI/Anthropic keys, AWS keys, Stripe keys, Slack/Telegram tokens, Discord webhooks, PEM private keys, DB URLs with passwords, high-entropy secret assignments, forbidden junk files, and assets > 10 MB.
3. **Multiplayer Netcode Authority Audit ([`audit_netcode.py`](.agent/skills/multiplayer-netcode-guard/scripts/audit_netcode.py)):**
   - Prevents client-trusted RPC exploits (`@rpc("any_peer")` without `multiplayer.is_server()` guard or forbidden state mutation RPCs).

---

## Handling Secrets Safely

- Store local API keys or Steam IDs exclusively in a local `.env` file (never tracked).
- Document required variable names with dummy placeholders in [`.env.example`](.env.example).
- If a real secret is ever accidentally exposed, **revoke and rotate the key immediately** before cleaning Git history.

---

## Reporting a Vulnerability

If you discover a security issue, RPC authority bypass, or leaked credential, please open a **GitHub Security Advisory** or contact the repository maintainer privately rather than posting exploit details publicly.
