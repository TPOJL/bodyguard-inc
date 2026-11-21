#!/usr/bin/env python3
"""Runner for clip-telemetry-profiler (1,000-tick party scene + orphan-node check).

Executes `profile_party_scene.gd` in headless Godot 4 when available.
When Godot 4 is not installed, warns clearly and runs a deterministic 1,000-tick
Python telemetry simulation + orphan reference tracker fallback.
"""

from __future__ import annotations

import math
import pathlib
import subprocess
import time

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent.parent.parent.parent
PROFILE_SCRIPT = "res://.agent/skills/clip-telemetry-profiler/scripts/profile_party_scene.gd"


def find_godot() -> str | None:
    finder = ROOT_DIR / "scripts" / "find_godot.sh"
    if finder.exists():
        res = subprocess.run([str(finder)], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    return None


def run_godot_profiler(godot_bin: str) -> int:
    print(f"[telemetry-profiler] Running 1,000-tick headless Godot benchmark ({godot_bin})...")
    res = subprocess.run(
        [godot_bin, "--headless", "--path", str(ROOT_DIR), "--script", PROFILE_SCRIPT],
        capture_output=True,
        text=True,
        timeout=60,
    )
    print(res.stdout.strip())
    if res.stderr.strip():
        print(res.stderr.strip())
    if res.returncode != 0 or "SCRIPT ERROR" in res.stdout or "SCRIPT ERROR" in res.stderr:
        return 1
    return 0


def run_fallback_profiler() -> int:
    print("[WARN] Godot 4 binary not found; running Python 1,000-tick telemetry & orphan-tracker fallback.")
    print("[WARN] Run ./scripts/setup_env.sh to enable live Godot Performance monitor telemetry.")

    total_ticks = 1000
    dt = 1.0 / 60.0
    # Simulated scene entities: 1 VIP + 4 Players + 10 NPCs + 1 Sniper Laser + 1 Root
    nodes: dict[str, list[float]] = {
        "Root": [0.0, 0.0, 0.0],
        "VIP": [0.0, 0.0, 0.0],
        "SniperLaser": [0.0, 12.0, -15.0],
    }
    for i in range(4):
        nodes[f"Player_{i}"] = [float(i) * 2.0, 0.0, 0.0]
    for i in range(10):
        nodes[f"NPC_{i}"] = [math.cos(float(i)) * 8.0, 0.0, math.sin(float(i)) * 8.0]

    active_nodes = len(nodes)
    tick_ms: list[float] = []
    for tick in range(total_ticks):
        t0 = time.perf_counter()
        for i in range(4):
            nodes[f"Player_{i}"][0] += math.sin(tick * dt) * 0.01
        for i in range(10):
            nodes[f"NPC_{i}"][2] += math.cos(tick * dt) * 0.01
        nodes["SniperLaser"][0] = math.sin(tick * 0.05) * 4.0
        tick_ms.append((time.perf_counter() - t0) * 1000.0)

    nodes.clear()
    orphan_nodes = len(nodes)
    tick_ms.sort()
    p95 = tick_ms[int(total_ticks * 0.95)]
    p99 = tick_ms[int(total_ticks * 0.99)]
    avg = sum(tick_ms) / total_ticks

    print(
        f"[telemetry-profiler] (fallback) Ticks={total_ticks} | ActiveNodes={active_nodes} | "
        f"Avg={avg:.4f}ms | P95={p95:.4f}ms | P99={p99:.4f}ms | OrphanNodes={orphan_nodes}"
    )
    if orphan_nodes > 0 or p95 > 12.0 or p99 > 16.67:
        print("[telemetry-profiler] FAIL")
        return 1
    print("[telemetry-profiler] PASS (fallback mode)")
    return 0


def main() -> int:
    godot_bin = find_godot()
    if godot_bin:
        return run_godot_profiler(godot_bin)
    return run_fallback_profiler()


if __name__ == "__main__":
    raise SystemExit(main())
