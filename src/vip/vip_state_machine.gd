class_name VipStateMachine
extends Node3D
## Authoritative VIP AI, Active Ragdoll & "Weekend at Bernie's" Corpse Controller.
## Authoritative Owner: Host (peer_id == 1) exclusively.
## Strictly separates 60 Hz `_physics_process` simulation from `_process` visual jaw/limb rendering.

const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")

enum VipState {
	ALIVE,
	CORPSE,
	EXPOSED,
	EXTRACTED,
}

signal state_changed(previous_state: VipState, next_state: VipState)
signal vip_damaged(new_health: float, reason: String)

const MAX_HEALTH: float = 100.0
const MAX_SUSPICION: float = 100.0
const DEFAULT_MAX_IMPULSE: float = 150.0
const SUICIDAL_WALK_SPEED: float = 2.55
const ARENA_HALF_EXTENT_X: float = 13.0
const ARENA_HALF_EXTENT_Z: float = 17.0

const BLUFF_VOICE_LINES: Array[String] = [
	"🎙️ \"I definitely have a pulse, officer! Ha-ha!\"",
	"🎙️ \"Wonderful gala! My bodyguards are just holding my coat!\"",
	"🎙️ \"Tax cuts and free champagne for everyone!\"",
	"🎙️ \"Never felt more alive in my life, chief!\"",
]

var state: VipState = VipState.ALIVE
var health: float = MAX_HEALTH
var suspicion: float = 0.0
var simulation_ticks: int = 0
var managed_by_level: bool = false

# Authoritative 60 Hz physics state
var velocity: Vector3 = Vector3.ZERO
var facing_yaw_rad: float = 0.0
var torso_tilt_rad: float = 0.0
var grabber_count: int = 0
var authoritative_voice_rms: float = 0.0
var suicidal_target: Vector3 = Vector3(5.5, 0.0, 4.0)
var suicidal_whim_label: String = "Poison Champagne Fountain"
var last_death_cause: String = ""

# Visual-only state updated in _process()
var visual_jaw_angle_deg: float = 0.0
var _visual_root: Node3D = null
var _torso_pivot: Node3D = null
var _head_pivot: Node3D = null
var _jaw_pivot: Node3D = null
var _left_arm_pivot: Node3D = null
var _right_arm_pivot: Node3D = null
var _left_leg_pivot: Node3D = null
var _right_leg_pivot: Node3D = null
var _status_halo_mat: StandardMaterial3D = null
var _overhead_label: Label3D = null
var _anim_clock: float = 0.0


func _ready() -> void:
	_build_visual_rig()


func _physics_process(delta: float) -> void:
	if not managed_by_level:
		step_simulation(delta)


func _process(delta: float) -> void:
	# Strictly cosmetic interpolation & jaw mesh rendering (zero gameplay state mutations)
	if not is_finite(delta) or delta <= 0.0:
		return
	_anim_clock += delta
	var target_jaw: float = 0.0
	if state == VipState.CORPSE or state == VipState.ALIVE:
		target_jaw = AudioInputDriverLib.compute_jaw_angle_deg(authoritative_voice_rms)
	visual_jaw_angle_deg = lerpf(visual_jaw_angle_deg, target_jaw, clampf(delta * 24.0, 0.0, 1.0))
	_update_visual_rig(delta)


func step_simulation(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	simulation_ticks += 1

	if state == VipState.CORPSE and suspicion >= MAX_SUSPICION:
		_transition_to(VipState.EXPOSED)
		return

	if state == VipState.EXPOSED or state == VipState.EXTRACTED:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 12.0)
		return

	# Suicidal Low-IQ wandering when ALIVE and not currently held by bodyguards
	if state == VipState.ALIVE and grabber_count <= 0:
		var to_hazard: Vector3 = suicidal_target - position
		to_hazard.y = 0.0
		if to_hazard.length() > 0.35:
			var wish_dir: Vector3 = to_hazard.normalized()
			var wobble: Vector3 = Vector3(
				sin(float(simulation_ticks) * 0.07) * 0.65,
				0.0,
				cos(float(simulation_ticks) * 0.05) * 0.65
			)
			var drive: Vector3 = (wish_dir * SUICIDAL_WALK_SPEED) + wobble
			velocity.x = lerpf(velocity.x, drive.x, clampf(delta * 4.2, 0.0, 1.0))
			velocity.z = lerpf(velocity.z, drive.z, clampf(delta * 4.2, 0.0, 1.0))

	# Apply Alive vs Corpse linear damping from ragdoll-physics-tuner profile
	var damp: float = RagdollPhysicsLib.ALIVE_LINEAR_DAMP if state == VipState.ALIVE else RagdollPhysicsLib.CORPSE_LINEAR_DAMP
	velocity *= maxf(0.0, 1.0 - damp * delta * 4.5)
	velocity.y = 0.0

	if not velocity.is_finite():
		velocity = Vector3.ZERO

	position += velocity * delta
	position.x = clampf(position.x, -ARENA_HALF_EXTENT_X, ARENA_HALF_EXTENT_X)
	position.z = clampf(position.z, -ARENA_HALF_EXTENT_Z, ARENA_HALF_EXTENT_Z)
	position.y = 0.0

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.15:
		facing_yaw_rad = atan2(velocity.x, velocity.z)

	var is_alive_flag: bool = (state == VipState.ALIVE)
	torso_tilt_rad = RagdollPhysicsLib.compute_upright_tilt_angle(is_alive_flag, grabber_count, torso_tilt_rad, delta)


func apply_grab_spring_authoritative(anchor_positions: Array[Vector3], delta: float, is_host: bool) -> void:
	if not is_host or not is_finite(delta) or delta <= 0.0:
		return
	grabber_count = anchor_positions.size()
	if grabber_count == 0:
		return

	var combined_force: Vector3 = Vector3.ZERO
	for anchor: Vector3 in anchor_positions:
		var spring_f: Vector3 = RagdollPhysicsLib.compute_grab_force(anchor, position, velocity)
		combined_force += spring_f

	var mass: float = RagdollPhysicsLib.ALIVE_MASS_KG if state == VipState.ALIVE else RagdollPhysicsLib.CORPSE_MASS_KG
	var accel: Vector3 = combined_force / mass
	accel.y = 0.0
	if accel.is_finite():
		velocity += accel * delta
		velocity = sanitize_impulse(velocity, 10.5)


func apply_shove_impulse_authoritative(raw_impulse: Vector3, is_host: bool) -> void:
	if not is_host:
		return
	var max_imp: float = RagdollPhysicsLib.MAX_SAFE_IMPULSE_ALIVE if state == VipState.ALIVE else RagdollPhysicsLib.MAX_SAFE_IMPULSE_CORPSE
	var safe_imp: Vector3 = sanitize_impulse(raw_impulse, max_imp)
	var mass: float = RagdollPhysicsLib.ALIVE_MASS_KG if state == VipState.ALIVE else RagdollPhysicsLib.CORPSE_MASS_KG
	var dv: Vector3 = safe_imp / mass
	dv.y = 0.0
	if dv.is_finite():
		velocity += dv


func apply_damage_authoritative(amount: float, is_host: bool, reason: String = "Hazard") -> void:
	if not is_host:
		return
	if not is_finite(amount) or amount <= 0.0:
		return
	if state != VipState.ALIVE:
		return
	health = maxf(0.0, health - amount)
	vip_damaged.emit(health, reason)
	if health <= 0.0:
		last_death_cause = reason
		_transition_to(VipState.CORPSE)


func add_suspicion_authoritative(delta_suspicion: float, is_host: bool) -> void:
	if not is_host:
		return
	if not is_finite(delta_suspicion):
		return
	suspicion = clampf(suspicion + delta_suspicion, 0.0, MAX_SUSPICION)
	if state == VipState.CORPSE and suspicion >= MAX_SUSPICION:
		_transition_to(VipState.EXPOSED)


func mark_extracted_authoritative(is_host: bool) -> void:
	if not is_host:
		return
	if state == VipState.ALIVE or state == VipState.CORPSE:
		_transition_to(VipState.EXTRACTED)


func reset_vip_authoritative(spawn_pos: Vector3, is_host: bool) -> void:
	if not is_host:
		return
	position = spawn_pos if spawn_pos.is_finite() else Vector3.ZERO
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	suspicion = 0.0
	grabber_count = 0
	authoritative_voice_rms = 0.0
	torso_tilt_rad = 0.0
	last_death_cause = ""
	_transition_to(VipState.ALIVE)


func sanitize_impulse(raw_impulse: Vector3, max_magnitude: float = DEFAULT_MAX_IMPULSE) -> Vector3:
	if not raw_impulse.is_finite():
		return Vector3.ZERO
	if not is_finite(max_magnitude) or max_magnitude <= 0.0:
		return Vector3.ZERO
	return raw_impulse.limit_length(max_magnitude)


func _transition_to(next_state: VipState) -> void:
	if state == next_state:
		return
	var prev: VipState = state
	state = next_state
	state_changed.emit(prev, next_state)


func _build_visual_rig() -> void:
	var is_headless: bool = (DisplayServer.get_name() == "headless")
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRig"
	add_child(_visual_root)

	_torso_pivot = Node3D.new()
	_torso_pivot.name = "TorsoPivot"
	_torso_pivot.position = Vector3(0.0, 0.92, 0.0)
	_visual_root.add_child(_torso_pivot)

	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.72, 0.0)
	_torso_pivot.add_child(_head_pivot)

	_jaw_pivot = Node3D.new()
	_jaw_pivot.name = "JawPivot"
	_jaw_pivot.position = Vector3(0.0, -0.05, 0.06)
	_head_pivot.add_child(_jaw_pivot)

	# High-Specular Clearcoat Gold Sequined VIP Tuxedo Material ("БЛИКИ")
	var suit_mat: StandardMaterial3D = StandardMaterial3D.new()
	suit_mat.albedo_color = Color(1.0, 0.80, 0.20)
	suit_mat.metallic = 0.92
	suit_mat.metallic_specular = 1.0
	suit_mat.roughness = 0.12
	suit_mat.clearcoat_enabled = true
	suit_mat.clearcoat = 1.0
	suit_mat.clearcoat_roughness = 0.05

	var pants_mat: StandardMaterial3D = StandardMaterial3D.new()
	pants_mat.albedo_color = Color(0.08, 0.08, 0.11)
	pants_mat.metallic = 0.35
	pants_mat.roughness = 0.25

	_left_arm_pivot = _make_limb_node("LeftArm", Vector3(-0.44, 0.34, 0.0), suit_mat, is_headless)
	_right_arm_pivot = _make_limb_node("RightArm", Vector3(0.44, 0.34, 0.0), suit_mat, is_headless)
	_torso_pivot.add_child(_left_arm_pivot)
	_torso_pivot.add_child(_right_arm_pivot)

	_left_leg_pivot = _make_limb_node("LeftLeg", Vector3(-0.18, -0.45, 0.0), pants_mat, is_headless)
	_right_leg_pivot = _make_limb_node("RightLeg", Vector3(0.18, -0.45, 0.0), pants_mat, is_headless)
	_torso_pivot.add_child(_left_leg_pivot)
	_torso_pivot.add_child(_right_leg_pivot)

	_status_halo_mat = StandardMaterial3D.new()
	_status_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_status_halo_mat.albedo_color = Color(0.2, 0.95, 0.4)

	if is_headless:
		return

	# Tuxedo Jacket Torso
	var torso_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.64, 0.95, 0.38)
	torso_mesh.mesh = box
	torso_mesh.material_override = suit_mat
	_torso_pivot.add_child(torso_mesh)

	# White Dress Shirt V-Front & Crimson Silk Bowtie
	var shirt_mat: StandardMaterial3D = StandardMaterial3D.new()
	shirt_mat.albedo_color = Color(0.96, 0.96, 1.0)
	var shirt: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(0.26, 0.55, 0.40)
	shirt.mesh = sbox
	shirt.position = Vector3(0.0, 0.16, 0.0)
	shirt.material_override = shirt_mat
	_torso_pivot.add_child(shirt)

	var bowtie_mat: StandardMaterial3D = StandardMaterial3D.new()
	bowtie_mat.albedo_color = Color(0.92, 0.08, 0.18)
	bowtie_mat.emission_enabled = true
	bowtie_mat.emission = Color(0.55, 0.04, 0.10)
	var bowtie: MeshInstance3D = MeshInstance3D.new()
	var btbox: BoxMesh = BoxMesh.new()
	btbox.size = Vector3(0.22, 0.09, 0.42)
	bowtie.mesh = btbox
	bowtie.position = Vector3(0.0, 0.38, 0.0)
	bowtie.material_override = bowtie_mat
	_torso_pivot.add_child(bowtie)

	# Upper Head & Hair
	var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.96, 0.80, 0.68)
	skin_mat.roughness = 0.45

	var skull_mesh: MeshInstance3D = MeshInstance3D.new()
	var skull_box: BoxMesh = BoxMesh.new()
	skull_box.size = Vector3(0.42, 0.36, 0.42)
	skull_mesh.mesh = skull_box
	skull_mesh.position = Vector3(0.0, 0.13, 0.0)
	skull_mesh.material_override = skin_mat
	_head_pivot.add_child(skull_mesh)

	var hair_mesh: MeshInstance3D = MeshInstance3D.new()
	var hbox: BoxMesh = BoxMesh.new()
	hbox.size = Vector3(0.45, 0.14, 0.46)
	hair_mesh.mesh = hbox
	hair_mesh.position = Vector3(0.0, 0.33, -0.02)
	hair_mesh.material_override = suit_mat
	_head_pivot.add_child(hair_mesh)

	# Reflective Mirror Aviator Sunglasses ("Weekend at Bernie's" shades!)
	var shades_mesh: MeshInstance3D = MeshInstance3D.new()
	var shades_box: BoxMesh = BoxMesh.new()
	shades_box.size = Vector3(0.46, 0.12, 0.12)
	shades_mesh.mesh = shades_box
	shades_mesh.position = Vector3(0.0, 0.16, 0.21)
	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.04, 0.06, 0.10)
	dark_mat.metallic = 0.95
	dark_mat.roughness = 0.04
	dark_mat.clearcoat_enabled = true
	shades_mesh.material_override = dark_mat
	_head_pivot.add_child(shades_mesh)

	# Articulated Lower Jaw + Teeth Strip (rotates open on voice RMS!)
	var jaw_mesh: MeshInstance3D = MeshInstance3D.new()
	var jaw_box: BoxMesh = BoxMesh.new()
	jaw_box.size = Vector3(0.36, 0.14, 0.36)
	jaw_mesh.mesh = jaw_box
	jaw_mesh.position = Vector3(0.0, -0.05, 0.08)
	jaw_mesh.material_override = skin_mat
	_jaw_pivot.add_child(jaw_mesh)

	var teeth_mesh: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(0.28, 0.05, 0.12)
	teeth_mesh.mesh = tbox
	teeth_mesh.position = Vector3(0.0, 0.02, 0.20)
	teeth_mesh.material_override = shirt_mat
	_jaw_pivot.add_child(teeth_mesh)

	# Glowing HDR Halo Ring above VIP
	var halo: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.44
	torus.outer_radius = 0.54
	halo.mesh = torus
	halo.position = Vector3(0.0, 2.38, 0.0)
	halo.material_override = _status_halo_mat
	_visual_root.add_child(halo)

	# 3D Floating Speech / Status Billboard Label
	_overhead_label = Label3D.new()
	_overhead_label.position = Vector3(0.0, 2.75, 0.0)
	_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.font_size = 28
	_overhead_label.outline_size = 10
	_overhead_label.modulate = Color(1.0, 0.95, 0.45)
	add_child(_overhead_label)


func _make_limb_node(limb_name: String, offset: Vector3, mat: StandardMaterial3D, is_headless: bool) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = limb_name
	pivot.position = offset
	if not is_headless:
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var b: BoxMesh = BoxMesh.new()
		b.size = Vector3(0.18, 0.74, 0.18)
		mesh_inst.mesh = b
		mesh_inst.position = Vector3(0.0, -0.32, 0.0)
		mesh_inst.material_override = mat
		pivot.add_child(mesh_inst)
	return pivot


func _update_visual_rig(_delta: float) -> void:
	if _visual_root == null:
		return
	_visual_root.rotation.y = facing_yaw_rad
	if _torso_pivot != null:
		_torso_pivot.rotation.x = torso_tilt_rad
		_torso_pivot.position.y = lerpf(0.92, 0.30, clampf(torso_tilt_rad / deg_to_rad(82.0), 0.0, 1.0))

	if _jaw_pivot != null:
		_jaw_pivot.rotation.x = deg_to_rad(visual_jaw_angle_deg)

	if _head_pivot != null:
		if state == VipState.CORPSE:
			_head_pivot.rotation.z = sin(_anim_clock * 3.4) * 0.32
		else:
			_head_pivot.rotation.z = 0.0

	var spd: float = Vector2(velocity.x, velocity.z).length()
	if _left_arm_pivot != null and _right_arm_pivot != null:
		if state == VipState.CORPSE and grabber_count > 0:
			_left_arm_pivot.rotation.z = deg_to_rad(52.0)
			_right_arm_pivot.rotation.z = deg_to_rad(-52.0)
			_left_arm_pivot.rotation.x = sin(_anim_clock * 7.5) * 0.28
			_right_arm_pivot.rotation.x = -sin(_anim_clock * 7.5) * 0.28
		else:
			_left_arm_pivot.rotation.z = 0.0
			_right_arm_pivot.rotation.z = 0.0
			_left_arm_pivot.rotation.x = sin(_anim_clock * 8.5) * minf(spd * 0.28, 0.75)
			_right_arm_pivot.rotation.x = -sin(_anim_clock * 8.5) * minf(spd * 0.28, 0.75)

	if _left_leg_pivot != null and _right_leg_pivot != null:
		if state == VipState.CORPSE and grabber_count > 0:
			# Comedic Weekend at Bernie's marionette high-step leg kicks!
			_left_leg_pivot.rotation.x = sin(_anim_clock * 11.0) * minf(0.15 + spd * 0.35, 0.95)
			_right_leg_pivot.rotation.x = -sin(_anim_clock * 11.0) * minf(0.15 + spd * 0.35, 0.95)
		else:
			_left_leg_pivot.rotation.x = -sin(_anim_clock * 8.5) * minf(spd * 0.25, 0.65)
			_right_leg_pivot.rotation.x = sin(_anim_clock * 8.5) * minf(spd * 0.25, 0.65)

	if _status_halo_mat != null:
		match state:
			VipState.ALIVE:
				_status_halo_mat.albedo_color = Color(0.2, 1.0, 0.45)
			VipState.CORPSE:
				_status_halo_mat.albedo_color = Color(1.0, 0.62, 0.12)
			VipState.EXPOSED:
				_status_halo_mat.albedo_color = Color(1.0, 0.15, 0.15)
			VipState.EXTRACTED:
				_status_halo_mat.albedo_color = Color(0.25, 0.90, 1.0)

	if _overhead_label != null:
		if state == VipState.CORPSE:
			if authoritative_voice_rms > 0.72:
				_overhead_label.text = "🔊 \"AAAAHHH!! DON'T LOOK AT ME!!\" (Jaw %.0f°)" % visual_jaw_angle_deg
				_overhead_label.modulate = Color(1.0, 0.35, 0.35)
			elif authoritative_voice_rms >= 0.08:
				var line_idx: int = int(_anim_clock / 2.2) % BLUFF_VOICE_LINES.size()
				_overhead_label.text = "%s (Jaw %.0f°)" % [BLUFF_VOICE_LINES[line_idx], visual_jaw_angle_deg]
				_overhead_label.modulate = Color(0.35, 1.0, 0.55)
			elif grabber_count <= 0:
				_overhead_label.text = "💀 VIP CORPSE ON FLOOR! Hold [E] to Prop Up!"
				_overhead_label.modulate = Color(1.0, 0.42, 0.15)
			else:
				_overhead_label.text = "🤐 CORPSE SILENT! Hold [V] to Bluff Guards!"
				_overhead_label.modulate = Color(1.0, 0.78, 0.22)
		elif state == VipState.ALIVE:
			if grabber_count > 0:
				_overhead_label.text = "🤵 VIP ESCORTED -> Drag to North Limousine!"
				_overhead_label.modulate = Color(0.35, 0.95, 1.0)
			else:
				_overhead_label.text = "🤪 VIP: \"Ooh! Heading to %s!\"" % suicidal_whim_label
				_overhead_label.modulate = Color(1.0, 0.92, 0.38)
		elif state == VipState.EXTRACTED:
			_overhead_label.text = "🏆 VIP EXTRACTED ($10,000 EARNED)!"
			_overhead_label.modulate = Color(0.3, 1.0, 0.65)
		else:
			_overhead_label.text = "🚨 BUSTED! COVER BLOWN!"
			_overhead_label.modulate = Color(1.0, 0.2, 0.2)
