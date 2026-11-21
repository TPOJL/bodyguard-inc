---
name: multiplayer-netcode-guard
description: >-
  Host-authoritative RPC security patterns, ragdoll bone bandwidth budgeting,
  Steam-to-ENet P2P abstraction, and automated static security auditing for BODYGUARD INC.
---

# Multiplayer Netcode Guard (`multiplayer-netcode-guard`)

Use this skill before writing or reviewing any `@rpc` method, multiplayer synchronizer, or P2P transport code.

## 1. Host-Authoritative RPC Rules
1. **Host Owns Truth:** Peer `1` (`multiplayer.is_server()`) owns VIP AI, VIP Alive/Corpse/Exposed state, ragdoll physics, suspicion meter, and quota/score.
2. **Every `@rpc("any_peer", ...)` Must Guard Authority:**
   ```gdscript
   @rpc("any_peer", "unreliable_ordered")
   func submit_player_intent(move_dir: Vector2, grab_pressed: bool, voice_rms: float) -> void:
       if not multiplayer.is_server():
           return
       var sender_id: int = multiplayer.get_remote_sender_id()
       var safe_dir: Vector2 = move_dir.limit_length(1.0) if move_dir.is_finite() else Vector2.ZERO
       var safe_rms: float = clampf(voice_rms, 0.0, 1.0) if is_finite(voice_rms) else 0.0
       _apply_validated_intent(sender_id, safe_dir, grab_pressed, safe_rms)
   ```
3. **Never Trust Client State Mutations:** Forbidden client-callable RPCs include `set_vip_dead`, `apply_vip_damage`, `set_suspicion`, `set_score`, or `set_ragdoll_transform`.
4. **Authority-Only Broadcasts:** Host-to-client state sync uses `@rpc("authority", "call_local", "reliable")` (events) or `@rpc("authority", "unreliable_ordered")` (snapshots).

## 2. Ragdoll Bandwidth Budget
Never sync 60 bones at 60 Hz!
- **Sync Rate:** `<= 20 Hz` (every 3rd physics tick) via `unreliable_ordered`.
- **Bone Subset (7 key nodes max):** Root/Pelvis (`Vector3` + quantized `Quaternion`) + Head, LeftHand, RightHand, LeftFoot, RightFoot, JawAngle (`uint8` quantized `0..255`).
- **Target Budget:** `< 8 KB/s` per connected client (~120 bytes/snapshot × 20 Hz = 2.4 KB/s).
- **Client Interpolation:** Clients smoothly slerp/lerp visual skeleton bones in `_process()` toward the latest host snapshot.

## 3. Steam-to-ENet P2P Abstraction
Use `src/core/network_transport.gd`:
- In headless tests / CI: `TransportMode.ENET_LOCALHOST` (`ENetMultiplayerPeer` on `127.0.0.1`).
- In Steam builds: `TransportMode.STEAM_P2P` (swapped behind the same interface without touching gameplay code).

## 4. Automated Static Audit
Run the netcode security scanner (also executed in `make check` and `.githooks/pre-commit`):

```bash
python3 .agent/skills/multiplayer-netcode-guard/scripts/audit_netcode.py
```
