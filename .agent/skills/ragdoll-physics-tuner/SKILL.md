---
name: ragdoll-physics-tuner
description: >-
  Active ragdoll joint limits, grab/carry spring-damper math, corpse weight tuning,
  and 300-tick headless stability testing for BODYGUARD INC.
---

# Ragdoll Physics Tuner (`ragdoll-physics-tuner`)

Use this skill whenever tuning VIP ragdoll physics, grab/carry spring-dampers, active-ragdoll posture muscles, or alive-to-corpse transitions.

## 1. Non-Negotiable Physics Rules
- **Fixed 60 Hz Only:** All impulses, spring forces, and joint torque updates run strictly in `_physics_process(delta: float) -> void`.
- **`NaN` / `INF` Impulse Guard:** Every force/impulse MUST pass `force.is_finite()` and be clamped to `MAX_SAFE_IMPULSE` before calling `apply_central_impulse()` or `apply_force()`.
- **Joint Angle Limits:** Never leave `Generic6DOFJoint3D` or `ConeTwistJoint3D` unconstrained on the spine, neck, or shoulders.
  - Neck twist/swing: `±35°`
  - Spine flex/extension: `[-25°, +45°]`
  - Shoulders: `±85°` swing, `±45°` twist
  - Elbows / Knees: hinge `[0°, +135°]` (no hyperextension)

## 2. Grab & Carry Spring-Damper Formula
Use a critically damped PD controller with hard force clamping so two players pulling opposite limbs cannot detonate the solver:

```gdscript
const GRAB_STIFFNESS: float = 280.0
const GRAB_DAMPING: float = 34.0
const MAX_GRAB_FORCE: float = 650.0

static func compute_grab_force(
	target_pos: Vector3,
	limb_pos: Vector3,
	limb_vel: Vector3
) -> Vector3:
	if not (target_pos.is_finite() and limb_pos.is_finite() and limb_vel.is_finite()):
		return Vector3.ZERO
	var displacement: Vector3 = target_pos - limb_pos
	var raw_force: Vector3 = displacement * GRAB_STIFFNESS - limb_vel * GRAB_DAMPING
	if not raw_force.is_finite():
		return Vector3.ZERO
	return raw_force.limit_length(MAX_GRAB_FORCE)
```

## 3. Alive vs. Corpse Weight & Damping Profiles
| Parameter | Alive (Active Ragdoll) | Corpse ("Weekend at Bernie's") |
| :--- | :---: | :---: |
| Total Mass | `72.0 kg` | `78.0 kg` (feels hilariously heavy) |
| Linear Damp | `0.4` | `0.9` |
| Angular Damp | `1.2` | `2.2` |
| Joint Spring Stiffness | `180.0` (upright posture) | `0.0` (completely limp) |
| Max Safe Impulse | `120.0 N·s` | `150.0 N·s` |

## 4. Verification Command
Run the 300-tick stability test (spawns a ragdoll proxy, applies extreme impulses — car hit, player tackle, fall — simulates 300 physics ticks, and asserts zero joint explosions, zero `NaN`/`INF` transforms, and valid alive-to-corpse transition):

```bash
godot --headless --path . --script .agent/skills/ragdoll-physics-tuner/scripts/test_ragdoll_stability.gd
```
(Automatically executed as part of `make test-unit`.)
