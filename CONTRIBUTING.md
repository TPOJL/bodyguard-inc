# Contributing to BODYGUARD INC.

Welcome! Whether you are a human contributor or an autonomous Gemini/Antigravity agent, every contribution must adhere to **[AGENTS.md](AGENTS.md)**.

---

## Development Setup

1. Clone the repository and initialize hooks:
   ```bash
   ./scripts/setup_env.sh
   ```
2. Install Godot 4.3+ and `gdtoolkit` (`gdlint`) if not already present:
   ```bash
   ./scripts/setup_env.sh --install
   ```
3. Copy `.env.example` to `.env` if you need local overrides (`.env` is gitignored and blocked from commits).

---

## Non-Negotiable Rules

1. **Strict Static GDScript Typing:** Every variable, function parameter, and return type must be explicitly typed (`var x: float = 0.0`, `func foo(a: int) -> void:`).
2. **60 Hz Physics Determinism:** All gameplay, AI, ragdoll forces, and suspicion updates belong in `_physics_process(delta: float)`. `_process()` is strictly visual interpolation & HUD only.
3. **NaN / INF Impulse Guard:** Validate `.is_finite()` and clamp magnitude before applying any force or impulse.
4. **Host Authority:** Never trust clients for VIP state, damage, ragdoll transforms, or suspicion. Every `@rpc("any_peer")` must guard with `if not multiplayer.is_server(): return`.
5. **Solid Wall Collision (`WallColliderGrid`):** Every wall, pillar, table, vendor counter, and locked gate must register in `WallColliderGrid` and pass `wall-collision-bug-hunter`.
6. **Zero Secrets, Junk, or >10 MB Assets:** Never commit API keys, credentials, `.DS_Store`, logs, or oversized binaries.

---

## Before Opening a Pull Request

Run the full quality gate locally and ensure every step passes with zero errors:

```bash
make verify-all
```

This runs:
- `make security` — API key, secret, junk, and asset bloat scan
- `make check` — strict static typing, `gdlint` (`.gdlintrc`), `godot --check-only`, and netcode authority audit
- `make test-unit` — VIP state machine, 52m×136m multi-level E2E, `wall-collision-bug-hunter`, 300-tick ragdoll stability, and voice lip-sync mock
- `make test-mp` — 1 Host + 2 Headless Clients localhost ENet E2E smoke test
- `make test-perf` — 1,000-tick party scene benchmark (`orphan_nodes == 0`)
