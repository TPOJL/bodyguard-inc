class_name BodyguardPlayer
extends Node3D
## Playable Bodyguard & Co-op AI Partner Controller.
## Supports Sprint [Shift], Spring Grab [E], Hero Dive-Tackle [F], and Decoy Bottle Throw [Q].

const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")

const MOVE_SPEED: float = 6.6
const SPRINT_SPEED: float = 9.4
const CARRY_MOVE_SPEED: float = 4.6
const GRAB_RANGE: float = 2.95
const SHOVE_RANGE: float = 3.6
const SHOVE_IMPULSE_MAG: float = 120.0
const SHOVE_COOLDOWN_SEC: float = 0.55
const ARENA_HALF_EXTENT_X: float = 14.2
const ARENA_MIN_Z: float = -52.5
const ARENA_MAX_Z: float = 48.5

var peer_id: int = 1
var is_ai_partner: bool = false
var ai_assist_enabled: bool = false

# Upgradeable stats (driven by AgencyProgression)
var carry_speed_mult: float = 1.0
var grab_range_bonus: float = 0.0
var sprint_speed_mult: float = 1.0
var stamina_regen_mult: float = 1.0
var security_gate_locked: bool = false
var security_gate_z: float = -14.0

# Authoritative 60 Hz state
var velocity: Vector3 = Vector3.ZERO
var facing_yaw_rad: float = 0.0
var is_grabbing_vip: bool = false
var is_sprinting: bool = false
var stamina: float = 100.0
var current_voice_rms: float = 0.0
var _shove_cooldown: float = 0.0
var _intent_move_dir: Vector2 = Vector2.ZERO
var _intent_grab: bool = false

# Visual nodes (_process only)
var _visual_root: Node3D = null
var _tether_beam: MeshInstance3D = null
var _voice_ring: MeshInstance3D = null
var _left_arm: Node3D = null
var _right_arm: Node3D = null
var _anim_clock: float = 0.0


func _ready() -> void:
	_build_visual_mesh()


func set_player_intent(move_dir: Vector2, grab_held: bool, voice_rms: float, sprint_held: bool = false) -> void:
	_intent_move_dir = move_dir.limit_length(1.0) if move_dir.is_finite() else Vector2.ZERO
	_intent_grab = grab_held
	current_voice_rms = clampf(voice_rms, 0.0, 1.0) if is_finite(voice_rms) else 0.0
	is_sprinting = sprint_held and (_intent_move_dir.length_squared() > 0.01)


func step_bodyguard_physics(delta: float, vip: Node3D, extraction_goal: Vector3) -> void:
	if not is_finite(delta) or delta <= 0.0 or vip == null:
		return
	if _shove_cooldown > 0.0:
		_shove_cooldown = maxf(0.0, _shove_cooldown - delta)

	if is_ai_partner:
		_compute_ai_partner_intent(vip, extraction_goal)

	if is_sprinting and stamina > 2.0:
		stamina = maxf(0.0, stamina - delta * 28.0)
	else:
		is_sprinting = false
		stamina = minf(100.0, stamina + delta * (22.0 * stamina_regen_mult))

	var max_spd: float = (CARRY_MOVE_SPEED * carry_speed_mult) if is_grabbing_vip else ((SPRINT_SPEED * sprint_speed_mult) if is_sprinting else MOVE_SPEED)
	var wish_vel: Vector3 = Vector3(_intent_move_dir.x, 0.0, _intent_move_dir.y) * max_spd
	velocity = velocity.lerp(wish_vel, clampf(delta * 15.0, 0.0, 1.0))
	if not velocity.is_finite():
		velocity = Vector3.ZERO

	position += velocity * delta
	position.x = clampf(position.x, -ARENA_HALF_EXTENT_X, ARENA_HALF_EXTENT_X)
	var min_z_bound: float = (security_gate_z + 1.0) if security_gate_locked else ARENA_MIN_Z
	position.z = clampf(position.z, min_z_bound, ARENA_MAX_Z)
	position.y = 0.0

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
	var dir: Vector3 = diff.normalized() if dist > 0.05 else Vector3(sin(facing_yaw_rad), 0.0, cos(facing_yaw_rad))
	return RagdollPhysicsLib.sanitize_vector3(dir * SHOVE_IMPULSE_MAG, SHOVE_IMPULSE_MAG)


func get_grab_anchor_world_pos(slot_index: int) -> Vector3:
	var side_offset: float = -0.65 if (slot_index % 2 == 0) else 0.65
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
		_intent_grab = dist <= GRAB_RANGE
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
		else:
			_left_arm.rotation.x = sin(_anim_clock * 9.0) * minf(spd * 0.22, 0.7)
			_right_arm.rotation.x = -sin(_anim_clock * 9.0) * minf(spd * 0.22, 0.7)

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
		var s: float = 1.0 + current_voice_rms * 2.4
		_voice_ring.scale = Vector3(s, 1.0, s)


func _build_visual_mesh() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BodyguardVisual"
	add_child(_visual_root)
	if DisplayServer.get_name() == "headless":
		return

	var suit_color: Color = Color(0.08, 0.11, 0.18) if not is_ai_partner else Color(0.10, 0.20, 0.16)
	var suit_mat: StandardMaterial3D = StandardMaterial3D.new()
	suit_mat.albedo_color = suit_color
	suit_mat.metallic = 0.45
	suit_mat.roughness = 0.22
	suit_mat.clearcoat_enabled = true

	# Tailored Suit Torso
	var torso: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(0.64, 0.96, 0.36)
	torso.mesh = tbox
	torso.position = Vector3(0.0, 1.02, 0.0)
	torso.material_override = suit_mat
	_visual_root.add_child(torso)

	# White Shirt & Crimson Secret Service Tie
	var tie_mat: StandardMaterial3D = StandardMaterial3D.new()
	tie_mat.albedo_color = Color(0.20, 0.78, 1.0) if not is_ai_partner else Color(0.25, 0.95, 0.55)
	tie_mat.emission_enabled = true
	tie_mat.emission = tie_mat.albedo_color * 0.5
	var tie: MeshInstance3D = MeshInstance3D.new()
	var tie_box: BoxMesh = BoxMesh.new()
	tie_box.size = Vector3(0.11, 0.52, 0.38)
	tie.mesh = tie_box
	tie.position = Vector3(0.0, 1.08, 0.0)
	tie.material_override = tie_mat
	_visual_root.add_child(tie)

	# Head & Wraparound Sunglasses
	var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.92, 0.76, 0.64)
	var head: MeshInstance3D = MeshInstance3D.new()
	var hbox: BoxMesh = BoxMesh.new()
	hbox.size = Vector3(0.40, 0.42, 0.40)
	head.mesh = hbox
	head.position = Vector3(0.0, 1.74, 0.0)
	head.material_override = skin_mat
	_visual_root.add_child(head)

	# Stylized Secret Service Hair Crown & Articulated Legs
	var hair_mat: StandardMaterial3D = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.08, 0.07, 0.06) if not is_ai_partner else Color(0.22, 0.16, 0.12)
	hair_mat.roughness = 0.55
	var hair: MeshInstance3D = MeshInstance3D.new()
	var hair_box: BoxMesh = BoxMesh.new()
	hair_box.size = Vector3(0.43, 0.15, 0.44)
	hair.mesh = hair_box
	hair.position = Vector3(0.0, 1.94, -0.02)
	hair.material_override = hair_mat
	_visual_root.add_child(hair)

	for leg_x: float in [-0.17, 0.17]:
		var leg: MeshInstance3D = MeshInstance3D.new()
		var lbox: BoxMesh = BoxMesh.new()
		lbox.size = Vector3(0.20, 0.62, 0.22)
		leg.mesh = lbox
		leg.position = Vector3(leg_x, 0.31, 0.0)
		leg.material_override = suit_mat
		_visual_root.add_child(leg)

	var shades: MeshInstance3D = MeshInstance3D.new()
	var sb: BoxMesh = BoxMesh.new()
	sb.size = Vector3(0.44, 0.11, 0.14)
	shades.mesh = sb
	shades.position = Vector3(0.0, 1.76, 0.18)
	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.03, 0.04, 0.06)
	dark_mat.metallic = 0.95
	dark_mat.roughness = 0.05
	shades.material_override = dark_mat
	_visual_root.add_child(shades)

	# Articulated Arms
	_left_arm = _make_arm("LeftArm", Vector3(-0.42, 1.38, 0.0), suit_mat)
	_right_arm = _make_arm("RightArm", Vector3(0.42, 1.38, 0.0), suit_mat)
	_visual_root.add_child(_left_arm)
	_visual_root.add_child(_right_arm)

	# HDR Glowing Grab Spring Tether Beam
	_tether_beam = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.09, 0.09, 1.0)
	_tether_beam.mesh = beam_box
	var beam_mat: StandardMaterial3D = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.25, 0.95, 1.0)
	_tether_beam.material_override = beam_mat
	_tether_beam.visible = false
	add_child(_tether_beam)

	# Proximity Voice Equalizer Ring
	_voice_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.58
	ring_mesh.outer_radius = 0.70
	_voice_ring.mesh = ring_mesh
	_voice_ring.position = Vector3(0.0, 0.12, 0.0)
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.25, 1.0, 0.58)
	_voice_ring.material_override = ring_mat
	_voice_ring.visible = false
	add_child(_voice_ring)


func _make_arm(arm_name: String, offset: Vector3, mat: StandardMaterial3D) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = arm_name
	pivot.position = offset
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var abox: BoxMesh = BoxMesh.new()
	abox.size = Vector3(0.18, 0.72, 0.18)
	mesh_inst.mesh = abox
	mesh_inst.position = Vector3(0.0, -0.30, 0.0)
	mesh_inst.material_override = mat
	pivot.add_child(mesh_inst)
	return pivot
