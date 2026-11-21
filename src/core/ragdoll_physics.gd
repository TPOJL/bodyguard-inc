class_name RagdollPhysics
extends RefCounted
## Active Ragdoll & "Weekend at Bernie's" Corpse Physics Math Library.
## Obeys `ragdoll-physics-tuner` laws: 60 Hz deterministic forces, NaN/INF guards,
## critically damped grab springs, and quantized <=20 Hz bone snapshots.

const GRAB_STIFFNESS: float = 280.0
const GRAB_DAMPING: float = 34.0
const MAX_GRAB_FORCE: float = 650.0

const ALIVE_MASS_KG: float = 72.0
const CORPSE_MASS_KG: float = 78.0
const ALIVE_LINEAR_DAMP: float = 0.4
const CORPSE_LINEAR_DAMP: float = 0.9
const ALIVE_ANGULAR_DAMP: float = 1.2
const CORPSE_ANGULAR_DAMP: float = 2.2
const ALIVE_UPRIGHT_STIFFNESS: float = 180.0
const CORPSE_UPRIGHT_STIFFNESS: float = 0.0

const MAX_SAFE_IMPULSE_ALIVE: float = 120.0
const MAX_SAFE_IMPULSE_CORPSE: float = 150.0


static func sanitize_vector3(vec: Vector3, max_length: float = 150.0) -> Vector3:
	if not vec.is_finite():
		return Vector3.ZERO
	if not is_finite(max_length) or max_length <= 0.0:
		return Vector3.ZERO
	return vec.limit_length(max_length)


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


static func compute_upright_tilt_angle(is_alive: bool, grabber_count: int, current_tilt: float, dt: float) -> float:
	if not is_finite(current_tilt) or not is_finite(dt) or dt <= 0.0:
		return 0.0
	var target_tilt: float = 0.0
	var lerp_speed: float = 10.0
	if not is_alive:
		if grabber_count <= 0:
			# Corpse collapses limp onto the floor (~82 degrees tilt)
			target_tilt = deg_to_rad(82.0)
			lerp_speed = 6.5
		elif grabber_count == 1:
			# One bodyguard propping up the corpse: comedic Weekend at Bernie's slouch (~22 deg)
			target_tilt = deg_to_rad(22.0)
			lerp_speed = 8.0
		else:
			# Two+ bodyguards carrying corpse together: nearly upright (~8 deg)
			target_tilt = deg_to_rad(8.0)
			lerp_speed = 12.0
	return lerpf(current_tilt, target_tilt, clampf(dt * lerp_speed, 0.0, 1.0))


static func pack_quantized_snapshot(
	root_pos: Vector3,
	yaw_rad: float,
	tilt_rad: float,
	jaw_angle_deg: float,
	grabber_count: int
) -> PackedByteArray:
	## Packs root transform + key limb state into a compact 22-byte packet (<= 2.4 KB/s @ 20 Hz).
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(22)
	var safe_pos: Vector3 = sanitize_vector3(root_pos, 2000.0)
	buf.encode_float(0, safe_pos.x)
	buf.encode_float(4, safe_pos.y)
	buf.encode_float(8, safe_pos.z)
	buf.encode_float(12, yaw_rad if is_finite(yaw_rad) else 0.0)
	buf.encode_float(16, tilt_rad if is_finite(tilt_rad) else 0.0)
	var jaw_q: int = clampi(int(round((clampf(jaw_angle_deg, 0.0, 42.0) / 42.0) * 255.0)), 0, 255)
	buf.encode_u8(20, jaw_q)
	buf.encode_u8(21, clampi(grabber_count, 0, 4))
	return buf


static func unpack_quantized_snapshot(buf: PackedByteArray) -> Dictionary:
	if buf.size() < 22:
		return {
			"root_pos": Vector3.ZERO,
			"yaw_rad": 0.0,
			"tilt_rad": 0.0,
			"jaw_angle_deg": 0.0,
			"grabber_count": 0,
		}
	var px: float = buf.decode_float(0)
	var py: float = buf.decode_float(4)
	var pz: float = buf.decode_float(8)
	var yaw: float = buf.decode_float(12)
	var tilt: float = buf.decode_float(16)
	var jaw_q: int = buf.decode_u8(20)
	var grabbers: int = buf.decode_u8(21)
	var pos: Vector3 = Vector3(px, py, pz)
	if not pos.is_finite():
		pos = Vector3.ZERO
	return {
		"root_pos": pos,
		"yaw_rad": yaw if is_finite(yaw) else 0.0,
		"tilt_rad": tilt if is_finite(tilt) else 0.0,
		"jaw_angle_deg": (float(jaw_q) / 255.0) * 42.0,
		"grabber_count": grabbers,
	}
