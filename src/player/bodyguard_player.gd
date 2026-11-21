class_name BodyguardPlayer
extends Node3D
## High-Detail Sculpted Secret Service Bodyguard & Co-op AI Partner Controller.
## Resolves solid collisions against WallColliderGrid at 60 Hz (zero wall clipping!).

const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const CharacterRigBuilderLib := preload("res://src/world/character_rig_builder.gd")

const MOVE_SPEED: float = 6.9
const SPRINT_SPEED: float = 9.8
const CARRY_MOVE_SPEED: float = 4.9
const GRAB_RANGE: float = 3.0
const SHOVE_RANGE: float = 3.6
const SHOVE_IMPULSE_MAG: float = 120.0
const SHOVE_COOLDOWN_SEC: float = 0.55
const BODY_RADIUS: float = 0.48

var peer_id: int = 1
var is_ai_partner: bool = false
var ai_assist_enabled: bool = false

# Upgradeable stats (driven by AgencyProgression)
var carry_speed_mult: float = 1.0
var grab_range_bonus: float = 0.0
var sprint_speed_mult: float = 1.0
var stamina_regen_mult: float = 1.0
var security_gate_locked: bool = false
var security_gate_z: float = -22.0
var wall_grid: RefCounted = null

# Authoritative 60 Hz state
var velocity: Vector3 = Vector3.ZERO
var facing_yaw_rad: float = PI
var is_grabbing_vip: bool = false
var is_sprinting: bool = false
var stamina: float = 100.0
var current_voice_rms: float = 0.0
var _shove_cooldown: float = 0.0
var _intent_move_dir: Vector2 = Vector2.ZERO
var _intent_grab: bool = false
var _weapon_flash_timer: float = 0.0
var _last_shot_cryo: bool = false

# Visual nodes (_process only)
var _visual_root: Node3D = null
var _tether_beam: MeshInstance3D = null
var _voice_ring: MeshInstance3D = null
var _left_arm: Node3D = null
var _right_arm: Node3D = null
var _left_leg: Node3D = null
var _right_leg: Node3D = null
var _weapon_glow_mat: StandardMaterial3D = null
var _anim_clock: float = 0.0


func _ready() -> void:
	_build_visual_mesh()


func set_player_intent(move_dir: Vector2, grab_held: bool, voice_rms: float, sprint_held: bool = false) -> void:
	_intent_move_dir = move_dir.limit_length(1.0) if move_dir.is_finite() else Vector2.ZERO
	_intent_grab = grab_held
	current_voice_rms = clampf(voice_rms, 0.0, 1.0) if is_finite(voice_rms) else 0.0
	is_sprinting = sprint_held and (_intent_move_dir.length_squared() > 0.01)


func notify_weapon_fired(is_cryo: bool) -> void:
	_weapon_flash_timer = 0.22
	_last_shot_cryo = is_cryo


func get_aim_direction() -> Vector3:
	return Vector3(sin(facing_yaw_rad), 0.0, cos(facing_yaw_rad)).normalized()


func step_bodyguard_physics(delta: float, vip: Node3D, extraction_goal: Vector3) -> void:
	if not is_finite(delta) or delta <= 0.0 or vip == null:
		return
	if _shove_cooldown > 0.0:
		_shove_cooldown = maxf(0.0, _shove_cooldown - delta)
	if _weapon_flash_timer > 0.0:
		_weapon_flash_timer = maxf(0.0, _weapon_flash_timer - delta)

	if is_ai_partner:
		_compute_ai_partner_intent(vip, extraction_goal)

	if is_sprinting and stamina > 2.0:
		stamina = maxf(0.0, stamina - delta * 26.0)
	else:
		is_sprinting = false
		stamina = minf(100.0, stamina + delta * (24.0 * stamina_regen_mult))

	var max_spd: float = (CARRY_MOVE_SPEED * carry_speed_mult) if is_grabbing_vip else ((SPRINT_SPEED * sprint_speed_mult) if is_sprinting else MOVE_SPEED)
	var wish_vel: Vector3 = Vector3(_intent_move_dir.x, 0.0, _intent_move_dir.y) * max_spd
	velocity = velocity.lerp(wish_vel, clampf(delta * 15.0, 0.0, 1.0))
	if not velocity.is_finite():
		velocity = Vector3.ZERO

	var next_pos: Vector3 = position + velocity * delta
	next_pos.y = 0.0
	if wall_grid != null:
		next_pos = wall_grid.call("resolve_position", next_pos, BODY_RADIUS, security_gate_locked)
	else:
		next_pos.x = clampf(next_pos.x, -24.0, 24.0)
		var min_z_b: float = (security_gate_z + 1.0) if security_gate_locked else -70.0
		next_pos.z = clampf(next_pos.z, min_z_b, 60.0)
	position = next_pos

	if Vector2(velocity.x, velocity.z).length() > 0.15:
		facing_yaw_rad = atan2(velocity.x, velocity.z)

	var dist_to_vip: float = position.distance_to(vip.position)
	is_grabbing_vip = _intent_grab and (dist_to_vip <= (GRAB_RANGE + grab_range_bonus))


func try_shove_vip(vip: Node3D) -> Vector3:
	if vip == null or _shove_cooldown > 0.0:
		return Vector3.ZERO
	var diff: Vector3 = vip.position - position
	diff.y = 0.0
	var dist: float = diff.length()
	if dist > SHOVE_RANGE:
		return Vector3.ZERO
	_shove_cooldown = SHOVE_COOLDOWN_SEC
	var dir: Vector3 = diff.normalized() if dist > 0.05 else get_aim_direction()
	return RagdollPhysicsLib.sanitize_vector3(dir * SHOVE_IMPULSE_MAG, SHOVE_IMPULSE_MAG)


func get_grab_anchor_world_pos(slot_index: int) -> Vector3:
	var side_offset: float = -0.68 if (slot_index % 2 == 0) else 0.68
	return position + Vector3(side_offset, 0.0, 0.35)


func _compute_ai_partner_intent(vip: Node3D, extraction_goal: Vector3) -> void:
	if not ai_assist_enabled:
		_intent_move_dir = Vector2.ZERO
		_intent_grab = false
		current_voice_rms = 0.0
		return

	var partner_target_offset: Vector3 = vip.position + Vector3(0.85, 0.0, 0.0)
	var to_vip: Vector3 = partner_target_offset - position
	to_vip.y = 0.0
	var dist: float = to_vip.length()

	if dist > 1.35:
		var d: Vector3 = to_vip.normalized()
		_intent_move_dir = Vector2(d.x, d.z)
		_intent_grab = dist <= (GRAB_RANGE + grab_range_bonus)
	else:
		_intent_grab = true
		var to_goal: Vector3 = extraction_goal - vip.position
		to_goal.y = 0.0
		if to_goal.length() > 0.8:
			var gd: Vector3 = to_goal.normalized()
			_intent_move_dir = Vector2(gd.x, gd.z) * 0.78
		else:
			_intent_move_dir = Vector2.ZERO


func update_visuals(vip_pos: Vector3) -> void:
	if _visual_root == null:
		return
	_anim_clock += 0.016
	_visual_root.rotation.y = facing_yaw_rad

	var spd: float = Vector2(velocity.x, velocity.z).length()
	if _left_arm != null and _right_arm != null:
		if is_grabbing_vip:
			_left_arm.rotation.x = deg_to_rad(-65.0)
			_right_arm.rotation.x = deg_to_rad(-65.0)
		elif _weapon_flash_timer > 0.0:
			_right_arm.rotation.x = deg_to_rad(-88.0)
			_left_arm.rotation.x = sin(_anim_clock * 9.0) * minf(spd * 0.2, 0.6)
		else:
			_left_arm.rotation.x = sin(_anim_clock * 9.5) * minf(spd * 0.16, 0.65)
			_right_arm.rotation.x = deg_to_rad(-32.0) - sin(_anim_clock * 9.5) * minf(spd * 0.10, 0.35)

	if _left_leg != null and _right_leg != null:
		_left_leg.rotation.x = -sin(_anim_clock * 9.5) * minf(spd * 0.18, 0.72)
		_right_leg.rotation.x = sin(_anim_clock * 9.5) * minf(spd * 0.18, 0.72)

	if _weapon_glow_mat != null:
		var w_col: Color = Color(0.25, 0.94, 1.0) if _last_shot_cryo else Color(1.0, 0.72, 0.20)
		_weapon_glow_mat.albedo_color = w_col
		_weapon_glow_mat.emission = w_col
		_weapon_glow_mat.emission_energy_multiplier = 2.4 if _weapon_flash_timer > 0.0 else 1.2

	if _tether_beam != null:
		_tether_beam.visible = is_grabbing_vip
		if is_grabbing_vip:
			var mid: Vector3 = (position + vip_pos) * 0.5 + Vector3(0.0, 1.05, 0.0)
			_tether_beam.global_position = mid
			var span: float = maxf(0.2, position.distance_to(vip_pos))
			_tether_beam.scale = Vector3(1.0, 1.0, span)
			if position.distance_squared_to(vip_pos) > 0.01:
				_tether_beam.look_at(vip_pos + Vector3(0.0, 1.05, 0.0), Vector3.UP)

	if _voice_ring != null:
		_voice_ring.visible = current_voice_rms >= 0.08
		var s: float = 1.0 + current_voice_rms * 2.2
		_voice_ring.scale = Vector3(s, 1.0, s)


func _build_visual_mesh() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BodyguardVisual"
	add_child(_visual_root)
	if DisplayServer.get_name() == "headless":
		return

	var suit_c: Color = Color(0.11, 0.15, 0.24) if not is_ai_partner else Color(0.12, 0.24, 0.18)
	var tie_c: Color = Color(0.22, 0.85, 1.0) if not is_ai_partner else Color(0.28, 0.95, 0.55)
	var hair_c: Color = Color(0.09, 0.08, 0.07) if not is_ai_partner else Color(0.26, 0.18, 0.12)

	var rig: Dictionary = CharacterRigBuilderLib.build_sculpted_bodyguard(_visual_root, suit_c, tie_c, hair_c)
	_left_arm = rig["left_arm"]
	_right_arm = rig["right_arm"]
	_left_leg = rig["left_leg"]
	_right_leg = rig["right_leg"]
	_weapon_glow_mat = rig["weapon_glow_mat"]

	# Grab spring tether beam
	_tether_beam = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.08, 0.08, 1.0)
	_tether_beam.mesh = beam_box
	_tether_beam.material_override = CharacterRigBuilderLib.make_material(
		Color(0.25, 0.92, 1.0), 0.2, 0.2, 0.0, Color(0.25, 0.92, 1.0), 1.4
	)
	_tether_beam.visible = false
	add_child(_tether_beam)

	# Proximity voice wave ring
	_voice_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.58
	ring_mesh.outer_radius = 0.68
	_voice_ring.mesh = ring_mesh
	_voice_ring.position = Vector3(0.0, 0.12, 0.0)
	_voice_ring.material_override = CharacterRigBuilderLib.make_material(
		Color(0.25, 1.0, 0.58), 0.2, 0.2, 0.0, Color(0.25, 1.0, 0.58), 1.3
	)
	_voice_ring.visible = false
	add_child(_voice_ring)
