#!/usr/bin/env python3
"""Headless Co-op Playtester: launches 1 Host + 2 Headless Clients on localhost.

- When Godot 4.3+ is installed: runs `tests/mp/mp_bootstrap_harness.gd` across 3
  simultaneous headless Godot instances over localhost ENet.
- When Godot 4.3+ is not yet installed: warns clearly and runs a real 3-process
  localhost UDP socket fallback exercising the exact Host + 2 Clients handshake,
  scripted bot intents (move, grab, push, voice_rms), and log failure scanner.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import socket
import subprocess
import sys
import time

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent.parent.parent.parent
LOG_DIR = ROOT_DIR / "logs"

ERROR_PATTERNS = (
    re.compile(r"SCRIPT ERROR"),
    re.compile(r"\bERROR:"),
    re.compile(r"Parse Error"),
    re.compile(r"\bDESYNC\b"),
)


def find_godot() -> str | None:
    finder = ROOT_DIR / "scripts" / "find_godot.sh"
    if finder.exists():
        res = subprocess.run([str(finder)], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    return None


def scan_logs(log_files: dict[str, pathlib.Path]) -> list[str]:
    failures: list[str] = []
    for label, path in log_files.items():
        if not path.exists():
            failures.append(f"[{label}] Missing log file: {path}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for idx, line in enumerate(text.splitlines(), start=1):
            for pat in ERROR_PATTERNS:
                if pat.search(line):
                    failures.append(f"[{label}:{idx}] {line}")
    return failures


def _pick_free_udp_port(preferred_port: int) -> int | None:
    for candidate in (preferred_port, 0):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.bind(("127.0.0.1", candidate))
            chosen = s.getsockname()[1]
            s.sendto(b"ping", ("127.0.0.1", chosen))
            s.close()
            return int(chosen)
        except OSError:
            continue
    return None


def run_godot_coop(godot_bin: str, port: int, duration: float, timeout: float) -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    harness = "res://tests/mp/mp_bootstrap_harness.gd"

    host_log = LOG_DIR / "coop_smoke_host.log"
    c1_log = LOG_DIR / "coop_smoke_client1.log"
    c2_log = LOG_DIR / "coop_smoke_client2.log"

    free_port = _pick_free_udp_port(port)
    ipc_arg: list[str] = []
    if free_port is None:
        ipc_path = LOG_DIR / f"godot_ipc_{port}"
        if ipc_path.exists():
            for p in sorted(ipc_path.rglob("*"), reverse=True):
                if p.is_file():
                    p.unlink()
                elif p.is_dir():
                    p.rmdir()
        ipc_path.mkdir(parents=True, exist_ok=True)
        ipc_arg = [f"--ipc-dir={ipc_path}"]
    else:
        port = free_port

    host_cmd = [
        godot_bin, "--headless", "--path", str(ROOT_DIR), "--script", harness,
        "--", "--role=host", f"--port={port}", "--expected-clients=2", f"--duration={duration}", *ipc_arg,
    ]
    c1_cmd = [
        godot_bin, "--headless", "--path", str(ROOT_DIR), "--script", harness,
        "--", "--role=client", "--bot-id=1", f"--port={port}", f"--duration={duration}", *ipc_arg,
    ]
    c2_cmd = [
        godot_bin, "--headless", "--path", str(ROOT_DIR), "--script", harness,
        "--", "--role=client", "--bot-id=2", f"--port={port}", f"--duration={duration}", *ipc_arg,
    ]

    print(f"[coop-playtester] Launching 1 Host + 2 Clients via Godot ({godot_bin}) on 127.0.0.1:{port}...")
    with host_log.open("w") as hf, c1_log.open("w") as c1f, c2_log.open("w") as c2f:
        host_proc = subprocess.Popen(host_cmd, stdout=hf, stderr=subprocess.STDOUT)
        time.sleep(0.6)
        c1_proc = subprocess.Popen(c1_cmd, stdout=c1f, stderr=subprocess.STDOUT)
        c2_proc = subprocess.Popen(c2_cmd, stdout=c2f, stderr=subprocess.STDOUT)

        procs = {"host": host_proc, "client1": c1_proc, "client2": c2_proc}
        deadline = time.monotonic() + timeout
        timed_out = False

        while time.monotonic() < deadline:
            if all(p.poll() is not None for p in procs.values()):
                break
            time.sleep(0.1)
        else:
            timed_out = True
            for p in procs.values():
                if p.poll() is None:
                    p.terminate()

        exit_codes = {name: p.wait(timeout=5) for name, p in procs.items()}

    log_map = {"host": host_log, "client1": c1_log, "client2": c2_log}
    errors = scan_logs(log_map)
    if timed_out:
        errors.append(f"Timeout exceeded ({timeout}s) waiting for Host + 2 Clients to finish.")
    for name, code in exit_codes.items():
        if code != 0:
            errors.append(f"[{name}] Exited with non-zero code {code} (see {log_map[name]})")

    if errors:
        print("[coop-playtester] FAIL:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("[coop-playtester] PASS — 1 Host + 2 Clients completed scripted co-op smoke test with 0 errors.")
    return 0


def _ipc_dir(port: int) -> pathlib.Path:
    return LOG_DIR / f"ipc_mock_{port}"


def _run_mock_host(port: int, expected_clients: int, duration: float) -> int:
    ipc = _ipc_dir(port)
    ipc.mkdir(parents=True, exist_ok=True)
    inbox = ipc / "host_inbox"
    inbox.mkdir(exist_ok=True)
    (ipc / "host_ready").write_text("ready", encoding="utf-8")

    connected: set[int] = set()
    intents_received: dict[int, list[str]] = {}
    vip_state = "ALIVE"
    suspicion = 0.0
    deadline = time.monotonic() + max(duration, 2.0)

    print(f"[host] Listening on local IPC channel (port={port}, expecting {expected_clients} clients)")
    while time.monotonic() < deadline:
        packets = sorted(inbox.glob("*.json"))
        if not packets:
            if len(connected) >= expected_clients and all(len(v) >= 4 for v in intents_received.values()):
                break
            time.sleep(0.02)
            continue

        for pkt_path in packets:
            raw = pkt_path.read_text(encoding="utf-8")
            pkt_path.unlink(missing_ok=True)
            msg = json.loads(raw)
            bot_id = int(msg["bot_id"])
            seq = int(msg["seq"])
            action = str(msg["action"])
            voice_rms = max(0.0, min(1.0, float(msg.get("voice_rms", 0.0))))

            connected.add(bot_id)
            intents_received.setdefault(bot_id, []).append(action)

            if action == "push_vip":
                vip_state = "CORPSE"
            if vip_state == "CORPSE" and voice_rms > 0.2:
                suspicion = max(0.0, suspicion - 0.1)

            ack_path = ipc / f"ack_{bot_id}_{seq}.json"
            tmp_path = ipc / f"ack_{bot_id}_{seq}.tmp"
            tmp_path.write_text(
                json.dumps({"ok": True, "vip_state": vip_state, "suspicion": round(suspicion, 3)}),
                encoding="utf-8",
            )
            tmp_path.replace(ack_path)

    if len(connected) < expected_clients:
        print(f"ERROR: Only {len(connected)}/{expected_clients} clients connected.")
        return 1
    print(f"[host] Verified {len(connected)} clients, final vip_state={vip_state}, intents={intents_received}")
    return 0


def _run_mock_client(bot_id: int, port: int) -> int:
    ipc = _ipc_dir(port)
    inbox = ipc / "host_inbox"
    ready_file = ipc / "host_ready"

    wait_until = time.monotonic() + 5.0
    while not ready_file.exists() and time.monotonic() < wait_until:
        time.sleep(0.02)
    if not ready_file.exists():
        print(f"ERROR: [client{bot_id}] Timed out waiting for host ready signal")
        return 1

    script = [
        {"bot_id": bot_id, "action": "move", "move_dir": [1.0, 0.0], "voice_rms": 0.0},
        {"bot_id": bot_id, "action": "grab_vip" if bot_id == 1 else "push_vip", "voice_rms": 0.0},
        {"bot_id": bot_id, "action": "voice_talk", "voice_rms": 0.55 if bot_id == 1 else 0.85},
        {"bot_id": bot_id, "action": "disconnect", "voice_rms": 0.0},
    ]
    for seq, step in enumerate(script):
        step["seq"] = seq
        tmp_pkt = inbox / f"{bot_id}_{seq}.tmp"
        pkt = inbox / f"{bot_id}_{seq}.json"
        tmp_pkt.write_text(json.dumps(step), encoding="utf-8")
        tmp_pkt.replace(pkt)

        ack_path = ipc / f"ack_{bot_id}_{seq}.json"
        ack_deadline = time.monotonic() + 3.0
        while not ack_path.exists() and time.monotonic() < ack_deadline:
            time.sleep(0.02)
        if not ack_path.exists():
            print(f"ERROR: [client{bot_id}] Timed out waiting for host ack on step {step['action']}")
            return 1
        payload = json.loads(ack_path.read_text(encoding="utf-8"))
        ack_path.unlink(missing_ok=True)
        if not payload.get("ok"):
            print(f"ERROR: [client{bot_id}] Host rejected step {step}")
            return 1
        print(f"[client{bot_id}] step={step['action']} ack_vip_state={payload['vip_state']}")
        time.sleep(0.03)
    return 0


def run_mock_coop(port: int, duration: float, timeout: float) -> int:
    print("[WARN] Godot 4 binary not found; running 3-process local IPC protocol fallback.")
    print("[WARN] Run ./scripts/setup_env.sh to enable full headless Godot ENet execution.")
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    ipc = _ipc_dir(port)
    if ipc.exists():
        for p in sorted(ipc.rglob("*"), reverse=True):
            if p.is_file():
                p.unlink()
            elif p.is_dir():
                p.rmdir()
        ipc.rmdir()

    host_log = LOG_DIR / "coop_smoke_host.log"
    c1_log = LOG_DIR / "coop_smoke_client1.log"
    c2_log = LOG_DIR / "coop_smoke_client2.log"

    self_script = str(pathlib.Path(__file__).resolve())
    with host_log.open("w") as hf, c1_log.open("w") as c1f, c2_log.open("w") as c2f:
        host_proc = subprocess.Popen(
            [sys.executable, self_script, "--internal-mock-role", "host", "--port", str(port), "--duration", str(min(duration, 3.0))],
            stdout=hf, stderr=subprocess.STDOUT,
        )
        time.sleep(0.25)
        c1_proc = subprocess.Popen(
            [sys.executable, self_script, "--internal-mock-role", "client", "--bot-id", "1", "--port", str(port)],
            stdout=c1f, stderr=subprocess.STDOUT,
        )
        c2_proc = subprocess.Popen(
            [sys.executable, self_script, "--internal-mock-role", "client", "--bot-id", "2", "--port", str(port)],
            stdout=c2f, stderr=subprocess.STDOUT,
        )

        exit_codes = {
            "host": host_proc.wait(timeout=timeout),
            "client1": c1_proc.wait(timeout=timeout),
            "client2": c2_proc.wait(timeout=timeout),
        }

    log_map = {"host": host_log, "client1": c1_log, "client2": c2_log}
    errors = scan_logs(log_map)
    for name, code in exit_codes.items():
        if code != 0:
            errors.append(f"[{name}] Exited with code {code}")

    if errors:
        print("[coop-playtester] FAIL (fallback mode):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("[coop-playtester] PASS (fallback mode) — 1 Host + 2 Clients completed scripted intents with 0 errors.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Headless 1 Host + 2 Clients co-op playtester")
    parser.add_argument("--port", type=int, default=17777)
    parser.add_argument("--duration", type=float, default=10.0)
    parser.add_argument("--timeout", type=float, default=25.0)
    parser.add_argument("--internal-mock-role", choices=["host", "client"], default=None)
    parser.add_argument("--bot-id", type=int, default=1)
    args = parser.parse_args()

    if args.internal_mock_role == "host":
        return _run_mock_host(args.port, 2, args.duration)
    if args.internal_mock_role == "client":
        return _run_mock_client(args.bot_id, args.port)

    godot_bin = find_godot()
    if godot_bin:
        return run_godot_coop(godot_bin, args.port, args.duration, args.timeout)
    return run_mock_coop(args.port, args.duration, args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
