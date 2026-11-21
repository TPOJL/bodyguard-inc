# BODYGUARD INC. — Core Agent Constitution (`AGENTS.md`)

This document defines the **non-negotiable engineering laws** for Gemini / Antigravity autonomous agents and human contributors working on **BODYGUARD INC.** (2–4 player co-op physics chaos game built on **Godot 4.3+** with strict static GDScript typing).

Every feature, refactor, or bugfix MUST obey these rules. Violating any rule fails CI, blocks Git hooks, and prevents milestone completion.

---

## 1. Security, Anti-Leak & Code Hygiene
- **Zero Secrets in Git:** NEVER commit API keys, tokens, `.env` files, private keys (`*.pem`, `*.key`), `export_presets.cfg`, `steam_appid.txt`, or credentials. Store local secrets in `.env` (gitignored) and document safe placeholders in `.env.example`. Enforced automatically by `scripts/secret_guard.py` on `pre-commit`, `pre-push`, `make security`, and GitHub Actions CI.
- **Zero Junk or Bloat:** Never commit OS/IDE artifacts (`.DS_Store`, `Thumbs.db`, `.vscode/`, `logs/`, `*.tmp`, `*.bak`) or binary assets > 10 MB.
- **Zero Untyped GDScript:** Every variable, function parameter, and return type MUST have explicit static type annotations (e.g., `var suspicion: float = 0.0`, `func apply_impulse(force: Vector3) -> void:`). `project.godot` treats `untyped_declaration` as a hard error.
- **Zero Orphan Nodes:** Every dynamically allocated `Node` must be added to the scene tree and freed cleanly (`queue_free()` / `free()`). Orphan node count MUST be `0` at shutdown.

---

## 2. Determinism & Physics Safety
- **Fixed 60 Hz Simulation:** All gameplay state mutations, VIP AI decisions, ragdoll forces, grab/carry spring-dampers, and suspicion calculations MUST run exclusively inside `_physics_process(delta: float) -> void` at `physics_ticks_per_second = 60`.
- **Visual Interpolation Separation:** `_process(delta: float) -> void` is strictly reserved for cosmetic interpolation, camera smoothing, UI/HUD updates, and jaw-mesh rendering. Never mutate authoritative gameplay or physics state in `_process`.
- **`NaN` / `INF` Impulse Guard (Mandatory):** Before applying any impulse, force, torque, or transform to a `RigidBody3D`, `PhysicalBone3D`, or joint:
  1. Validate `force.is_finite()` (reject `NAN` and `INF`).
  2. Clamp impulse magnitude to a safe physical ceiling (`MAX_SAFE_IMPULSE`, default `150.0` N·s unless overridden by a tuned profile).
  3. Validate resulting `global_transform.origin.is_finite()` and joint angular velocity bounds.
- **No Unbounded Spring Explosions:** Grab/carry springs must always include velocity damping (`F = k * x - c * v`) and force clamping.

---

## 3. Multiplayer Authority Matrix (Host-Authoritative P2P)
Transport uses a P2P abstraction (`src/core/network_transport.gd`) supporting **ENet localhost** (for headless E2E tests without Steam) and **SteamMultiplayerPeer** (for production).

| System / State | Authoritative Owner | Client Permission | Sync Strategy |
| :--- | :--- | :--- | :--- |
| **VIP AI & Pathing** | **Host (`peer_id == 1`)** | Read-only | Replicated state enum + target |
| **VIP Alive / Corpse / Exposed State** | **Host (`peer_id == 1`)** | Read-only | Reliable RPC broadcast from Host |
| **Ragdoll Physics & Bone Transforms** | **Host (`peer_id == 1`)** | Read-only (visual interpolation) | Unreliable quantized root + key limbs (<= 20 Hz) |
| **Suspicion Meter & Guard Alertness** | **Host (`peer_id == 1`)** | Read-only | Reliable delta/threshold sync |
| **Economy / Quota / Score** | **Host (`peer_id == 1`)** | Read-only | Reliable event sync |
| **Player Input Intents** | Client -> Host | Send intent only (`move_dir`, `grab_pressed`, `push_pressed`) | Unreliable input packet validated on Host |
| **Proximity Voice RMS** | Client -> Host | Send clamped `float` in `[0.0, 1.0]` only | Unreliable 15–20 Hz float; Host validates sender & range |

### RPC Security Laws (Enforced by `multiplayer-netcode-guard`)
1. Every `@rpc("any_peer", ...)` handler MUST check `if not multiplayer.is_server(): return` before mutating authoritative state.
2. Never accept raw damage, `set_vip_dead`, `set_suspicion`, or raw world transforms from a client peer.
3. Always verify `multiplayer.get_remote_sender_id()` matches the entity owned by that peer and clamp numeric inputs (`clampf(rms, 0.0, 1.0)`).
4. Never broadcast full 60-bone ragdoll hierarchies at 60 Hz; stay within the bandwidth budget defined in `.agent/skills/multiplayer-netcode-guard/SKILL.md`.

---

## 4. Test-Driven Game Loop & Verification Gate
No mechanic is considered **"done"** until ALL gates pass with zero secrets, zero engine errors, zero script errors, and zero orphan nodes:

1. **Security & Static Analysis (`make check`)**: `secret_guard.py`, strict GDScript type-check, linter, and `multiplayer-netcode-guard` audit.
2. **Unit & Physics Stability (`make test-unit`)**: VIP state machine, suspicion math, voice lip-sync mock, and 300-tick ragdoll impulse stability tests.
3. **Headless Co-op Smoke (`make test-mp`)**: Simultaneous **1 Host + 2 Headless Clients** on localhost ENet executing scripted bot inputs (move, grab, push, voice RMS) with zero `SCRIPT ERROR`, `ERROR:`, desync, or timeout.
4. **Performance & Leak Benchmark (`make test-perf`)**: 1,000-tick headless party scene (VIP + 4 players + 10 NPCs + sniper laser) verifying P95/P99 frame times and `orphan_nodes == 0`.

Run `make verify-all` before declaring any milestone complete.

---

## 5. Available Antigravity / Gemini Skills (`.agent/skills/`)
Consult the relevant skill before modifying its domain:
- `wall-collision-bug-hunter` — Solid wall, column, furniture, locked gate, and projectile anti-clipping collision auditor.
- `ragdoll-physics-tuner` — Active ragdoll joint limits, grab spring-damper math, corpse tuning, 300-tick stability test.
- `multiplayer-netcode-guard` — Host-authoritative RPC patterns, ragdoll bandwidth budgeting, static security audit.
- `headless-coop-playtester` — 1 Host + 2 Clients localhost ENet orchestrator and log failure detector.
- `voice-lipsync-mock` — Proximity voice & `MockAudioInput` driver for corpse jaw lip-sync and guard reaction testing.
- `clip-telemetry-profiler` — 1,000-tick party scene benchmark, P95/P99 latency, and orphan-node leak detection.
