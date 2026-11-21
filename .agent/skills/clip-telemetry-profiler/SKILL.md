---
name: clip-telemetry-profiler
description: >-
  1,000-tick headless party-scene performance benchmark (VIP + 4 players + 10 NPCs + sniper laser)
  measuring P95/P99 frame times, physics step time, active nodes, and orphan-node leaks.
---

# Clip Telemetry Profiler (`clip-telemetry-profiler`)

Use this skill to guard frame pacing and memory hygiene before shipping any milestone.

## 1. Benchmark Scene Composition
`scripts/profile_party_scene.gd` spawns a deterministic headless party stress scene:
- `1` VIP (`VipStateMachine` + physics proxy)
- `4` Player bodyguards
- `10` Party NPCs / Guards with suspicion tick logic
- `1` Sniper Laser raycast hazard
Simulates **1,000 fixed 60 Hz ticks** and records per-tick timings in milliseconds.

## 2. Hard Performance & Leak Thresholds
- **Orphan Nodes at Teardown:** MUST be `== 0` (hard fail if `orphan_nodes > 0`).
- **Frame-Time P95:** `<= 12.0 ms` (well inside 16.67 ms 60 FPS budget).
- **Frame-Time P99:** `<= 16.67 ms`.
- **Physics Step Average:** `<= 8.0 ms`.

## 3. Usage
```bash
python3 .agent/skills/clip-telemetry-profiler/scripts/run_profiler.py
```
(Automatically executed by `make test-perf`, `make verify-all`, and the `stop` / `pre-push` verification gate.)
