---
name: headless-coop-playtester
description: >-
  Headless 1 Host + 2 Clients localhost multiplayer E2E smoke test orchestrator
  with scripted bot inputs and strict log error/desync detection for BODYGUARD INC.
---

# Headless Co-op Playtester (`headless-coop-playtester`)

Use this skill to verify any multiplayer feature end-to-end without human players or Steam running.

## 1. What It Tests
`scripts/run_coop_smoke.py` launches **3 simultaneous headless processes** on `127.0.0.1`:
1. **Host (Peer 1):** Runs authoritative VIP state machine, physics, and intent validation on ENet port `7777` (configurable).
2. **Client Bot 1:** Connects over localhost ENet and executes scripted intents: `move` -> `grab_vip` -> `voice_rms(0.55)`.
3. **Client Bot 2:** Connects over localhost ENet and executes scripted intents: `move` -> `push_vip` -> `voice_rms(0.85)`.

## 2. Failure Conditions (Immediate Non-Zero Exit)
- Any line matching `SCRIPT ERROR`, `ERROR:`, `Parse Error`, or `DESYNC` in Host or Client stdout/stderr.
- Any process exiting with a non-zero return code.
- Connection handshake or simulation exceeding `--timeout` (default `25s`).
- Fewer than 2 clients completing the full scripted intent sequence and clean disconnect.

## 3. Usage
```bash
python3 .agent/skills/headless-coop-playtester/scripts/run_coop_smoke.py --duration 10
```
Logs are saved under `logs/coop_smoke_*.log` for post-mortem inspection.
(Automatically executed by `make test-mp`, `make verify-all`, and the `stop` / `pre-push` verification gate.)
