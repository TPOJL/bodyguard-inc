---
name: voice-lipsync-mock
description: >-
  Proximity voice chat abstraction and MockAudioInput driver for deterministic
  corpse jaw lip-sync and guard reaction testing without audio hardware.
---

# Voice Lip-Sync Mock (`voice-lipsync-mock`)

Use this skill when building or testing the "Weekend at Bernie's" proximity voice chat + corpse jaw lip-sync mechanic.

## 1. Architecture (`src/core/audio_input_driver.gd`)
All voice capture goes through `AudioInputDriver`:
- **Production (`DriverMode.MICROPHONE`):** Samples Godot `AudioEffectCapture` RMS, normalizes to `[0.0, 1.0]`, and transmits **only the float RMS** to the Host at `<= 20 Hz`.
- **Headless / Automated Testing (`DriverMode.MOCK`):** `MockAudioInput` injects deterministic synthetic volume envelopes (`SILENCE`, `TALKING`, `SCREAMING`, or custom arrays) with zero audio hardware dependency.

## 2. Corpse Jaw & Guard Reaction Contract
- **Jaw Angle Mapping (Visual Only, `_process`):**
  - `rms < 0.08` (noise gate) -> `jaw_angle_deg = 0.0`
  - `0.08 <= rms <= 0.70` (normal talking) -> `jaw_angle_deg` mapped smoothly to `[5.0°, 28.0°]`
  - `rms > 0.70` (screaming) -> `jaw_angle_deg` clamped to `[28.0°, 42.0°]`
- **Host Guard Suspicion Reaction (`_physics_process`):**
  - If VIP is `CORPSE` and a guard is inspecting within range:
    - `SILENCE` (`rms < 0.08`): Suspicion rises rapidly (`+18.0/s` — "Why isn't the VIP answering?!")
    - `TALKING` (`0.15 <= rms <= 0.65`): Suspicion drops (`-12.0/s` — guard believes VIP is alive and chatting)
    - `SCREAMING` (`rms > 0.80`): Suspicion rises (`+10.0/s` — draws unwanted attention)

## 3. Verification Command
```bash
godot --headless --path . --script .agent/skills/voice-lipsync-mock/scripts/test_voice_lipsync.gd
```
(Automatically executed as part of `make test-unit`.)
