class_name VipStateMachine
extends Node3D
## Authoritative VIP AI, Sculpted Active Ragdoll & "Weekend at Bernie's" Corpse Controller.
## Resolves solid collisions via WallColliderGrid at 60 Hz so VIP NEVER clips through walls!

const RagdollPhysicsLib := preload("res://src/core/ragdoll_physics.gd")
const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")
const CharacterRigBuilderLib := preload("res://src/world/character_rig_builder.gd")

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
const SUICIDAL_WALK_SPEED: float = 2.65
const VIP_RADIUS: float = 0.48

const BLUFF_VOICE_LINES: Array[String] = [
	"🎙️ \"I definitely have a pulse, officer! Ha-ha!\"",
	"🎙️ \"Wonderful gala! My bodyguards are just holding my coat!\"",
	"🎙️ \"Tax cuts and free champagne for everyone!\"",
	"🎙️ \"Never felt more alive in my life, chief!\"",
]

var state: VipState = VipState.ALIVE
var max_health: float = MAX_HEALTH
var health: float = MAX_HEALTH
var suspicion: float = 0.0
var simulation_ticks: int = 0
var managed_by_level: bool = false
var wander_speed_multiplier: float = 1.0
var security_gate_locked: bool = false
var security_gate_z: float = -22.0
var wall_grid: RefCounted = null

# Authoritative 60 Hz physics state
var velocity: Vector3 = Vector3.ZERO
var facing_yaw_rad: float = PI
var torso_tilt_rad: float = 0.0
var grabber_count: int = 0
var authoritative_voice_rms: float = 0.0
var suicidal_target: Vector3 = Vector3(8.5, 0.0, 32.0)
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

	if state == VipState.ALIVE and grabber_count <= 0:
		var to_hazard: Vector3 = suicidal_target - position
		to_hazard.y = 0.0
		if to_hazard.length() > 0.35:
			var wish_dir: Vector3 = to_hazard.normalized()
			var wobble: Vector3 = Vector3(
				sin(float(simulation_ticks) * 0.07) * 0.60,
				0.0,
				cos(float(simulation_ticks) * 0.05) * 0.60
			)
			var drive: Vector3 = (wish_dir * (SUICIDAL_WALK_SPEED * wander_speed_multiplier)) + wobble
			velocity.x = lerpf(velocity.x, drive.x, clampf(delta * 4.2, 0.0, 1.0))
			velocity.z = lerpf(velocity.z, drive.z, clampf(delta * 4.2, 0.0, 1.0))

	var damp: float = RagdollPhysicsLib.ALIVE_LINEAR_DAMP if state == VipState.ALIVE else RagdollPhysicsLib.CORPSE_LINEAR_DAMP
	velocity *= maxf(0.0, 1.0 - damp * delta * 4.5)
	velocity.y = 0.0
	if not velocity.is_finite():
		velocity = Vector3.ZERO

	var next_pos: Vector3 = position + velocity * delta
	next_pos.y = 0.0
	if wall_grid != null:
		next_pos = wall_grid.call("resolve_position", next_pos, VIP_RADIUS, security_gate_locked)
	else:
		next_pos.x = clampf(next_pos.x, -24.0, 24.0)
		var min_z_b: float = (security_gate_z + 1.1) if security_gate_locked else -70.0
		next_pos.z = clampf(next_pos.z, min_z_b, 60.0)
	position = next_pos

	if Vector2(velocity.x, velocity.z).length() > 0.15:
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
		combined_force += RagdollPhysicsLib.compute_grab_force(anchor, position, velocity)

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


func reset_vip_authoritative(spawn_pos: Vector3, is_host: bool, new_max_hp: float = MAX_HEALTH) -> void:
	if not is_host:
		return
	position = spawn_pos if spawn_pos.is_finite() else Vector3.ZERO
	velocity = Vector3.ZERO
	max_health = maxf(50.0, new_max_hp)
	health = max_health
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
	_torso_pivot.position = Vector3(0.0, 0.96, 0.0)
	_visual_root.add_child(_torso_pivot)

	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.72, 0.0)
	_torso_pivot.add_child(_head_pivot)

	_jaw_pivot = Node3D.new()
	_jaw_pivot.name = "JawPivot"
	_jaw_pivot.position = Vector3(0.0, -0.06, 0.06)
	_head_pivot.add_child(_jaw_pivot)

	var suit_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.98, 0.78, 0.22), 0.52, 0.24, 0.45)
	var pants_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.08, 0.08, 0.11), 0.25, 0.35)
	var skin_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.96, 0.80, 0.68), 0.0, 0.45)
	var shoe_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.05, 0.05, 0.07), 0.6, 0.16, 0.6)

	_left_arm_pivot = _make_limb("LeftArm", Vector3(-0.39, 0.36, 0.0), suit_mat, skin_mat, is_headless, true)
	_right_arm_pivot = _make_limb("RightArm", Vector3(0.39, 0.36, 0.0), suit_mat, skin_mat, is_headless, true)
	_torso_pivot.add_child(_left_arm_pivot)
	_torso_pivot.add_child(_right_arm_pivot)

	_left_leg_pivot = _make_limb("LeftLeg", Vector3(-0.16, -0.26, 0.0), pants_mat, shoe_mat, is_headless, false)
	_right_leg_pivot = _make_limb("RightLeg", Vector3(0.16, -0.26, 0.0), pants_mat, shoe_mat, is_headless, false)
	_torso_pivot.add_child(_left_leg_pivot)
	_torso_pivot.add_child(_right_leg_pivot)

	_status_halo_mat = CharacterRigBuilderLib.make_material(Color(0.2, 0.95, 0.4), 0.1, 0.2, 0.0, Color(0.2, 0.95, 0.4), 1.1)

	if is_headless:
		return

	# Sculpted Tapered Gold Tuxedo Jacket & Shoulders
	var torso_mesh: MeshInstance3D = MeshInstance3D.new()
	var tcyl: CylinderMesh = CylinderMesh.new()
	tcyl.top_radius = 0.35
	tcyl.bottom_radius = 0.26
	tcyl.height = 0.78
	torso_mesh.mesh = tcyl
	torso_mesh.position = Vector3(0.0, 0.12, 0.0)
	torso_mesh.material_override = suit_mat
	_torso_pivot.add_child(torso_mesh)

	var shoulders: MeshInstance3D = MeshInstance3D.new()
	var ssph: SphereMesh = SphereMesh.new()
	ssph.radius = 0.35
	shoulders.mesh = ssph
	shoulders.scale = Vector3(1.12, 0.52, 0.78)
	shoulders.position = Vector3(0.0, 0.42, 0.0)
	shoulders.material_override = suit_mat
	_torso_pivot.add_child(shoulders)

	# White Shirt Front & Red Silk Bowtie
	var shirt_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.96, 0.96, 1.0), 0.05, 0.55)
	var shirt: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(0.24, 0.48, 0.28)
	shirt.mesh = sbox
	shirt.position = Vector3(0.0, 0.24, 0.16)
	shirt.material_override = shirt_mat
	_torso_pivot.add_child(shirt)

	var bowtie_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.92, 0.10, 0.18), 0.2, 0.3, 0.2, Color(0.75, 0.05, 0.12), 0.5)
	var bowtie: MeshInstance3D = MeshInstance3D.new()
	var btbox: BoxMesh = BoxMesh.new()
	btbox.size = Vector3(0.22, 0.09, 0.08)
	bowtie.mesh = btbox
	bowtie.position = Vector3(0.0, 0.44, 0.30)
	bowtie.material_override = bowtie_mat
	_torso_pivot.add_child(bowtie)

	# Smooth Sculpted Head + Crown Hair + Aviator Sunglasses
	var skull: MeshInstance3D = MeshInstance3D.new()
	var sksph: SphereMesh = SphereMesh.new()
	sksph.radius = 0.235
	skull.mesh = sksph
	skull.scale = Vector3(0.95, 1.02, 1.0)
	skull.position = Vector3(0.0, 0.12, 0.0)
	skull.material_override = skin_mat
	_head_pivot.add_child(skull)

	var hair: MeshInstance3D = MeshInstance3D.new()
	var hsph: SphereMesh = SphereMesh.new()
	hsph.radius = 0.245
	hair.mesh = hsph
	hair.scale = Vector3(1.02, 0.65, 1.08)
	hair.position = Vector3(0.0, 0.25, -0.02)
	hair.material_override = CharacterRigBuilderLib.make_material(Color(0.92, 0.74, 0.28), 0.35, 0.32)
	_head_pivot.add_child(hair)

	var shades: MeshInstance3D = MeshInstance3D.new()
	var shbox: BoxMesh = BoxMesh.new()
	shbox.size = Vector3(0.40, 0.10, 0.14)
	shades.mesh = shbox
	shades.position = Vector3(0.0, 0.14, 0.19)
	shades.material_override = CharacterRigBuilderLib.make_material(Color(0.04, 0.05, 0.09), 0.92, 0.06, 0.7)
	_head_pivot.add_child(shades)

	# Articulated Lower Jaw + Teeth Strip (rotates open on voice RMS!)
	var jaw_mesh: MeshInstance3D = MeshInstance3D.new()
	var jbox: BoxMesh = BoxMesh.new()
	jbox.size = Vector3(0.30, 0.12, 0.30)
	jaw_mesh.mesh = jbox
	jaw_mesh.position = Vector3(0.0, -0.04, 0.07)
	jaw_mesh.material_override = skin_mat
	_jaw_pivot.add_child(jaw_mesh)

	var teeth: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(0.24, 0.045, 0.10)
	teeth.mesh = tbox
	teeth.position = Vector3(0.0, 0.02, 0.17)
	teeth.material_override = shirt_mat
	_jaw_pivot.add_child(teeth)

	# Glowing Halo Ring & Floating 3D Speech Label
	var halo: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.44
	torus.outer_radius = 0.53
	halo.mesh = torus
	halo.position = Vector3(0.0, 2.38, 0.0)
	halo.material_override = _status_halo_mat
	_visual_root.add_child(halo)

	_overhead_label = Label3D.new()
	_overhead_label.position = Vector3(0.0, 2.78, 0.0)
	_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.font_size = 24
	_overhead_label.outline_size = 8
	_overhead_label.modulate = Color(1.0, 0.95, 0.45)
	add_child(_overhead_label)


func _make_limb(
	limb_name: String,
	offset: Vector3,
	mat: StandardMaterial3D,
	end_mat: StandardMaterial3D,
	is_headless: bool,
	is_arm: bool
) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = limb_name
	pivot.position = offset
	if not is_headless:
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var cap: CapsuleMesh = CapsuleMesh.new()
		cap.radius = 0.095 if is_arm else 0.105
		cap.height = 0.62 if is_arm else 0.72
		mesh_inst.mesh = cap
		mesh_inst.position = Vector3(0.0, -0.28 if is_arm else -0.34, 0.0)
		mesh_inst.material_override = mat
		pivot.add_child(mesh_inst)

		var tip: MeshInstance3D = MeshInstance3D.new()
		if is_arm:
			var hs: SphereMesh = SphereMesh.new()
			hs.radius = 0.085
			tip.mesh = hs
			tip.position = Vector3(0.0, -0.58, 0.02)
		else:
			var sb: BoxMesh = BoxMesh.new()
			sb.size = Vector3(0.18, 0.12, 0.30)
			tip.mesh = sb
			tip.position = Vector3(0.0, -0.68, 0.06)
		tip.material_override = end_mat
		pivot.add_child(tip)
	return pivot


func _update_visual_rig(_delta: float) -> void:
	if _visual_root == null:
		return
	_visual_root.rotation.y = facing_yaw_rad
	if _torso_pivot != null:
		_torso_pivot.rotation.x = torso_tilt_rad
		_torso_pivot.position.y = lerpf(0.96, 0.30, clampf(torso_tilt_rad / deg_to_rad(82.0), 0.0, 1.0))

	if _jaw_pivot != null:
		_jaw_pivot.rotation.x = deg_to_rad(visual_jaw_angle_deg)

	if _head_pivot != null:
		_head_pivot.rotation.z = (sin(_anim_clock * 3.4) * 0.32) if state == VipState.CORPSE else 0.0

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
			_left_arm_pivot.rotation.x = sin(_anim_clock * 8.5) * minf(spd * 0.25, 0.72)
			_right_arm_pivot.rotation.x = -sin(_anim_clock * 8.5) * minf(spd * 0.25, 0.72)

	if _left_leg_pivot != null and _right_leg_pivot != null:
		if state == VipState.CORPSE and grabber_count > 0:
			_left_leg_pivot.rotation.x = sin(_anim_clock * 11.0) * minf(0.15 + spd * 0.35, 0.95)
			_right_leg_pivot.rotation.x = -sin(_anim_clock * 11.0) * minf(0.15 + spd * 0.35, 0.95)
		else:
			_left_leg_pivot.rotation.x = -sin(_anim_clock * 8.5) * minf(spd * 0.25, 0.65)
			_right_leg_pivot.rotation.x = sin(_anim_clock * 8.5) * minf(spd * 0.25, 0.65)

	if _status_halo_mat != null:
		var hc: Color = Color(0.2, 1.0, 0.45)
		if state == VipState.CORPSE:
			hc = Color(1.0, 0.62, 0.12)
		elif state == VipState.EXPOSED:
			hc = Color(1.0, 0.15, 0.15)
		elif state == VipState.EXTRACTED:
			hc = Color(0.25, 0.90, 1.0)
		_status_halo_mat.albedo_color = hc
		_status_halo_mat.emission = hc

	if _overhead_label != null:
		if state == VipState.CORPSE:
			if authoritative_voice_rms > 0.72:
				_overhead_label.text = "🔊 \"AAAAHHH!!\" (Jaw %.0f°)" % visual_jaw_angle_deg
				_overhead_label.modulate = Color(1.0, 0.35, 0.35)
			elif authoritative_voice_rms >= 0.08:
				var line_idx: int = int(_anim_clock / 2.2) % BLUFF_VOICE_LINES.size()
				_overhead_label.text = "%s (Jaw %.0f°)" % [BLUFF_VOICE_LINES[line_idx], visual_jaw_angle_deg]
				_overhead_label.modulate = Color(0.35, 1.0, 0.55)
			elif grabber_count <= 0:
				_overhead_label.text = "💀 VIP CORPSE! Hold [E] to Prop Up!"
				_overhead_label.modulate = Color(1.0, 0.42, 0.15)
			else:
				_overhead_label.text = "🤐 CORPSE SILENT! Hold [V] to Bluff!"
				_overhead_label.modulate = Color(1.0, 0.78, 0.22)
		elif state == VipState.ALIVE:
			if grabber_count > 0:
				_overhead_label.text = "🤵 VIP ESCORTED"
				_overhead_label.modulate = Color(0.35, 0.95, 1.0)
			else:
				_overhead_label.text = "🤪 VIP -> %s" % suicidal_whim_label
				_overhead_label.modulate = Color(1.0, 0.92, 0.38)
		elif state == VipState.EXTRACTED:
			_overhead_label.text = "🏆 VIP EXTRACTED!"
			_overhead_label.modulate = Color(0.3, 1.0, 0.65)
		else:
			_overhead_label.text = "🚨 COVER BLOWN!"
			_overhead_label.modulate = Color(1.0, 0.2, 0.2)
