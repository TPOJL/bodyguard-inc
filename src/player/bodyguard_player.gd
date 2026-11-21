class_name BodyguardPlayer
extends Node3D
## Playable Bodyguard & Co-op AI Partner Controller.
## Supports local player input, remote peer intents, or AI Co-op Partner bot assist.

const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")

const MOVE_SPEED: float = 6.4
const CARRY_MOVE_SPEED: float = 4.8
const GRAB_RANGE: float = 2.85
const SHOVE_RANGE: float = 3.2
const SHOVE_IMPULSE_MAG: float = 115.0
const SHOVE_COOLDOWN_SEC: float = 0.65
const ARENA_HALF_EXTENT_X: float = 13.5
const ARENA_HALF_EXTENT_Z: float = 17.5

var peer_id: int = 1
var is_ai_partner: bool = false
var ai_assist_enabled: bool = true

# Authoritative 60 Hz state
var velocity: Vector3 = Vector3.ZERO
var facing_yaw_rad: float = 0.0
var is_grabbing_vip: bool = false
var current_voice_rms: float = 0.0
var _shove_cooldown: float = 0.0
var _intent_move_dir: Vector2 = Vector2.ZERO
var _intent_grab: bool = false

# Visual nodes (_process only)
var _visual_root: Node3D = null
var _tether_beam: MeshInstance3D = null
var _voice_ring: MeshInstance3D = null


func _ready() -> void:
	_build_visual_mesh()


func set_player_intent(move_dir: Vector2, grab_held: bool, voice_rms: float) -> void:
	_intent_move_dir = move_dir.limit_length(1.0) if move_dir.is_finite() else Vector2.ZERO
	_intent_grab = grab_held
	current_voice_rms = clampf(voice_rms, 0.0, 1.0) if is_finite(voice_rms) else 0.0


func step_bodyguard_physics(delta: float, vip: Node3D, extraction_goal: Vector3) -> void:
	if not is_finite(delta) or delta <= 0.0 or vip == null:
		return
	if _shove_cooldown > 0.0:
		_shove_cooldown = maxf(0.0, _shove_cooldown - delta)

	if is_ai_partner:
		_compute_ai_partner_intent(vip, extraction_goal)

	var max_spd: float = CARRY_MOVE_SPEED if is_grabbing_vip else MOVE_SPEED
	var wish_vel: Vector3 = Vector3(_intent_move_dir.x, 0.0, _intent_move_dir.y) * max_spd
	velocity = velocity.lerp(wish_vel, clampf(delta * 14.0, 0.0, 1.0))
	if not velocity.is_finite():
		velocity = Vector3.ZERO

	position += velocity * delta
	position.x = clampf(position.x, -ARENA_HALF_EXTENT_X, ARENA_HALF_EXTENT_X)
	position.z = clampf(position.z, -ARENA_HALF_EXTENT_Z, ARENA_HALF_EXTENT_Z)
	position.y = 0.0

	if Vector2(velocity.x, velocity.z).length() > 0.15:
		facing_yaw_rad = atan2(velocity.x, velocity.z)

	var dist_to_vip: float = position.distance_to(vip.position)
	is_grabbing_vip = _intent_grab and (dist_to_vip <= GRAB_RANGE)


func try_shove_vip(vip: Node3D) -> Vector3:
	## Returns a safe clamped impulse Vector3 if in range and off cooldown, else Vector3.ZERO.
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
		# Escort VIP toward extraction limousine zone!
		_intent_grab = true
		var to_goal: Vector3 = extraction_goal - vip.position
		to_goal.y = 0.0
		if to_goal.length() > 0.8:
			var gd: Vector3 = to_goal.normalized()
			_intent_move_dir = Vector2(gd.x, gd.z) * 0.75
		else:
			_intent_move_dir = Vector2.ZERO


func update_visuals(vip_pos: Vector3) -> void:
	if _visual_root == null:
		return
	_visual_root.rotation.y = facing_yaw_rad

	if _tether_beam != null:
		_tether_beam.visible = is_grabbing_vip
		if is_grabbing_vip:
			var mid: Vector3 = (position + vip_pos) * 0.5 + Vector3(0.0, 1.0, 0.0)
			_tether_beam.global_position = mid
			var span: float = maxf(0.2, position.distance_to(vip_pos))
			_tether_beam.scale = Vector3(1.0, 1.0, span)
			if position.distance_squared_to(vip_pos) > 0.01:
				_tether_beam.look_at(vip_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)

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

	var suit_color: Color = Color(0.10, 0.14, 0.22) if not is_ai_partner else Color(0.14, 0.24, 0.18)
	var suit_mat: StandardMaterial3D = StandardMaterial3D.new()
	suit_mat.albedo_color = suit_color
	suit_mat.roughness = 0.5

	var body_mesh: MeshInstance3D = MeshInstance3D.new()
	var caps: CapsuleMesh = CapsuleMesh.new()
	caps.radius = 0.36
	caps.height = 1.75
	body_mesh.mesh = caps
	body_mesh.position = Vector3(0.0, 0.90, 0.0)
	body_mesh.material_override = suit_mat
	_visual_root.add_child(body_mesh)

	# Secret Service Sunglasses
	var shades: MeshInstance3D = MeshInstance3D.new()
	var sb: BoxMesh = BoxMesh.new()
	sb.size = Vector3(0.42, 0.10, 0.12)
	shades.mesh = sb
	shades.position = Vector3(0.0, 1.48, 0.32)
	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.05, 0.05, 0.05)
	shades.material_override = dark_mat
	_visual_root.add_child(shades)

	# Grab spring tether beam
	_tether_beam = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.08, 0.08, 1.0)
	_tether_beam.mesh = beam_box
	var beam_mat: StandardMaterial3D = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.25, 0.90, 1.0)
	_tether_beam.material_override = beam_mat
	_tether_beam.visible = false
	add_child(_tether_beam)

	# Proximity voice wave ring
	_voice_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.65
	_voice_ring.mesh = ring_mesh
	_voice_ring.position = Vector3(0.0, 0.15, 0.0)
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.3, 1.0, 0.55)
	_voice_ring.material_override = ring_mat
	_voice_ring.visible = false
	add_child(_voice_ring)
