class_name GuardNpc
extends Node3D
## High-Detail Sculpted Security Guard / Paparazzi NPC with Scalable HP, Cryo-Freeze State,
## Plasma Damage/Elimination, WallColliderGrid Collision, Spotlight & Voice-Bluff Inspection.

const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")
const CharacterRigBuilderLib := preload("res://src/world/character_rig_builder.gd")

const PATROL_SPEED: float = 2.7
const INSPECTION_RADIUS: float = 4.6
const UNPROPPED_CORPSE_PENALTY_PER_SEC: float = 34.0
const ALIVE_DECAY_PER_SEC: float = -8.0
const GUARD_RADIUS: float = 0.46

var guard_title: String = "Gala Guard"
var waypoints: Array[Vector3] = []
var current_waypoint_idx: int = 0
var is_inspecting_vip: bool = false
var last_inspection_bark: String = "Patrolling..."

# Escalating Level HP & Combat/Freeze state
var max_hp: float = 100.0
var hp: float = 100.0
var is_eliminated: bool = false
var frozen_timer: float = 0.0
var distracted_timer: float = 0.0
var distraction_target: Vector3 = Vector3.ZERO
var paparazzi_flash_pulse: float = 0.0
var speed_multiplier: float = 1.0
var wall_grid: RefCounted = null
var security_gate_locked: bool = false
var _flash_cooldown: float = 0.0

var _ring_mat: StandardMaterial3D = null
var _visual_root: Node3D = null
var _ice_shell: Node3D = null
var _spotlight: SpotLight3D = null
var _overhead_label: Label3D = null
var _left_leg: Node3D = null
var _right_leg: Node3D = null
var _walk_clock: float = 0.0


func _ready() -> void:
	_build_visuals()


func configure_patrol(title: String, points: Array[Vector3], level_max_hp: float = 100.0, spd_mult: float = 1.0) -> void:
	guard_title = title
	waypoints = points
	current_waypoint_idx = 0
	max_hp = maxf(40.0, level_max_hp)
	hp = max_hp
	is_eliminated = false
	frozen_timer = 0.0
	distracted_timer = 0.0
	speed_multiplier = clampf(spd_mult, 0.7, 2.0)
	visible = true
	if waypoints.size() > 0:
		position = waypoints[0]


func apply_weapon_hit(raw_damage: float, freeze_sec: float, shatter_crit_mult: float = 2.0) -> Dictionary:
	if is_eliminated:
		return {"hit": false, "killed": false, "shatter_crit": false, "damage": 0.0}
	var was_frozen: bool = (frozen_timer > 0.0)
	var final_dmg: float = raw_damage
	var is_crit: bool = false
	if freeze_sec > 0.0:
		frozen_timer = maxf(frozen_timer, freeze_sec)
		is_inspecting_vip = false
	elif was_frozen:
		final_dmg = raw_damage * shatter_crit_mult
		is_crit = true

	hp = maxf(0.0, hp - final_dmg)
	if hp <= 0.0:
		is_eliminated = true
		is_inspecting_vip = false
		visible = false
		return {"hit": true, "killed": true, "shatter_crit": is_crit, "damage": final_dmg}
	return {"hit": true, "killed": false, "shatter_crit": is_crit, "damage": final_dmg}


func trigger_bottle_distraction(bottle_pos: Vector3, radius: float = 7.5, duration: float = 4.5) -> bool:
	if is_eliminated or not bottle_pos.is_finite():
		return false
	if position.distance_to(bottle_pos) <= radius:
		distracted_timer = maxf(distracted_timer, duration)
		distraction_target = bottle_pos
		is_inspecting_vip = false
		return true
	return false


func stun_with_taser(duration: float) -> void:
	if is_eliminated:
		return
	distracted_timer = maxf(distracted_timer, duration)
	distraction_target = position
	is_inspecting_vip = false


func step_guard_physics(
	delta: float,
	vip_pos: Vector3,
	vip_is_corpse: bool,
	vip_is_alive: bool,
	vip_grabber_count: int,
	voice_rms: float
) -> float:
	if is_eliminated or not is_finite(delta) or delta <= 0.0:
		return 0.0

	paparazzi_flash_pulse = maxf(0.0, paparazzi_flash_pulse - delta * 3.2)
	if _flash_cooldown > 0.0:
		_flash_cooldown = maxf(0.0, _flash_cooldown - delta)

	# 1. Cryo-Frozen solid in ice -> cannot move or detect corpse!
	if frozen_timer > 0.0:
		frozen_timer = maxf(0.0, frozen_timer - delta)
		is_inspecting_vip = false
		last_inspection_bark = "❄️ %s is FROZEN SOLID (2x Shatter Crit with Plasma [LMB/X]!)" % guard_title
		return 0.0

	# 2. Decoy Bottle / Taser distraction
	if distracted_timer > 0.0:
		distracted_timer = maxf(0.0, distracted_timer - delta)
		is_inspecting_vip = false
		var to_bottle: Vector3 = distraction_target - position
		to_bottle.y = 0.0
		if to_bottle.length() > 0.75:
			var bdir: Vector3 = to_bottle.normalized()
			_move_resolved(bdir * (PATROL_SPEED * 0.85 * speed_multiplier) * delta)
			if _visual_root != null:
				_visual_root.rotation.y = atan2(bdir.x, bdir.z)
		last_inspection_bark = "%s: '🍾 Investigating distraction!'" % guard_title
		return -6.0 * delta

	var dist_to_vip: float = position.distance_to(vip_pos)
	is_inspecting_vip = dist_to_vip <= INSPECTION_RADIUS

	if not is_inspecting_vip:
		_step_patrol_movement(delta)
		last_inspection_bark = "%s: Patrolling sector." % guard_title
		return 0.0

	var to_vip: Vector3 = vip_pos - position
	to_vip.y = 0.0
	if to_vip.length() > 0.1 and _visual_root != null:
		_visual_root.rotation.y = atan2(to_vip.x, to_vip.z)

	if _flash_cooldown <= 0.0 and guard_title.contains("Paparazzi"):
		paparazzi_flash_pulse = 1.0
		_flash_cooldown = 1.8

	if vip_is_alive:
		last_inspection_bark = "%s: 'Evening, Mr. VIP!'" % guard_title
		return ALIVE_DECAY_PER_SEC * delta

	if vip_is_corpse:
		if vip_grabber_count <= 0:
			last_inspection_bark = "%s: '🚨 VIP IS ON THE FLOOR!!'" % guard_title
			return UNPROPPED_CORPSE_PENALTY_PER_SEC * delta

		var rate: float = AudioInputDriverLib.evaluate_guard_suspicion_delta(voice_rms, true)
		if rate < 0.0:
			last_inspection_bark = "%s: '✓ Great speech Mr. VIP! (-Suspicion)'" % guard_title
		elif voice_rms > 0.80:
			last_inspection_bark = "%s: '⚠️ Why is the VIP screaming?!'" % guard_title
		else:
			last_inspection_bark = "%s: '❓ Hold [V] to talk, Cryo [Z], or Shoot [X]!'" % guard_title
		return rate * delta

	return 0.0


func update_guard_visuals() -> void:
	visible = not is_eliminated
	if is_eliminated or _ring_mat == null:
		return
	_walk_clock += 0.016

	if _ice_shell != null:
		_ice_shell.visible = (frozen_timer > 0.0)

	if _left_leg != null and _right_leg != null:
		if frozen_timer <= 0.0 and not is_inspecting_vip:
			_left_leg.rotation.x = sin(_walk_clock * 7.0) * 0.42
			_right_leg.rotation.x = -sin(_walk_clock * 7.0) * 0.42
		else:
			_left_leg.rotation.x = 0.0
			_right_leg.rotation.x = 0.0

	if frozen_timer > 0.0:
		_ring_mat.albedo_color = Color(0.32, 0.94, 1.0)
	elif distracted_timer > 0.0:
		_ring_mat.albedo_color = Color(0.25, 0.82, 1.0)
	elif is_inspecting_vip:
		_ring_mat.albedo_color = Color(1.0, 0.22, 0.15)
	else:
		_ring_mat.albedo_color = Color(0.95, 0.78, 0.18)

	if _spotlight != null:
		if frozen_timer > 0.0:
			_spotlight.light_energy = 0.4
		elif paparazzi_flash_pulse > 0.1:
			_spotlight.light_color = Color(1.0, 0.96, 0.88)
			_spotlight.light_energy = 2.0 + paparazzi_flash_pulse * 4.2
		elif is_inspecting_vip:
			_spotlight.light_color = Color(1.0, 0.25, 0.20)
			_spotlight.light_energy = 2.4
		else:
			_spotlight.light_color = Color(1.0, 0.90, 0.68)
			_spotlight.light_energy = 1.6

	if _overhead_label != null:
		var hp_str: String = "[%.0f/%.0f HP]" % [hp, max_hp]
		if frozen_timer > 0.0:
			_overhead_label.text = "❄️ %s FROZEN %.1fs %s" % [guard_title, frozen_timer, hp_str]
			_overhead_label.modulate = Color(0.42, 0.96, 1.0)
		elif distracted_timer > 0.0:
			_overhead_label.text = "🍾 %s [STUN %.1fs] %s" % [guard_title, distracted_timer, hp_str]
			_overhead_label.modulate = Color(0.3, 0.90, 1.0)
		elif is_inspecting_vip:
			_overhead_label.text = "👁️ %s %s" % [guard_title, hp_str]
			_overhead_label.modulate = Color(1.0, 0.35, 0.25)
		else:
			_overhead_label.text = "👮 %s %s" % [guard_title, hp_str]
			_overhead_label.modulate = Color(0.95, 0.85, 0.55)


func _move_resolved(delta_vec: Vector3) -> void:
	var next_pos: Vector3 = position + delta_vec
	next_pos.y = 0.0
	if wall_grid != null:
		next_pos = wall_grid.call("resolve_position", next_pos, GUARD_RADIUS, security_gate_locked)
	position = next_pos


func _step_patrol_movement(delta: float) -> void:
	if waypoints.is_empty():
		return
	var target: Vector3 = waypoints[current_waypoint_idx]
	var diff: Vector3 = target - position
	diff.y = 0.0
	if diff.length() <= 0.45:
		current_waypoint_idx = (current_waypoint_idx + 1) % waypoints.size()
		return
	var dir: Vector3 = diff.normalized()
	_move_resolved(dir * (PATROL_SPEED * speed_multiplier) * delta)
	if _visual_root != null:
		_visual_root.rotation.y = atan2(dir.x, dir.z)


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "GuardVisual"
	add_child(_visual_root)
	if DisplayServer.get_name() == "headless":
		return

	var rig: Dictionary = CharacterRigBuilderLib.build_sculpted_bodyguard(
		_visual_root,
		Color(0.46, 0.09, 0.14),
		Color(0.95, 0.78, 0.24),
		Color(0.10, 0.10, 0.14)
	)
	_left_leg = rig["left_leg"]
	_right_leg = rig["right_leg"]

	# Peaked Officer Cap Visor on top of sculpted head
	var visor: MeshInstance3D = MeshInstance3D.new()
	var vbox: BoxMesh = BoxMesh.new()
	vbox.size = Vector3(0.44, 0.12, 0.46)
	visor.mesh = vbox
	visor.position = Vector3(0.0, 2.02, 0.06)
	visor.material_override = CharacterRigBuilderLib.make_material(Color(0.08, 0.09, 0.14), 0.35, 0.25)
	_visual_root.add_child(visor)

	# Cryo-Freeze Ice Crystal Prison Overlay
	_ice_shell = CharacterRigBuilderLib.build_ice_crystal_shell(self)

	# Volumetric Flashlight SpotLight3D Cone
	_spotlight = SpotLight3D.new()
	_spotlight.position = Vector3(0.24, 1.25, 0.28)
	_spotlight.rotation_degrees = Vector3(-16.0, 180.0, 0.0)
	_spotlight.light_color = Color(1.0, 0.90, 0.68)
	_spotlight.light_energy = 1.6
	_spotlight.light_specular = 0.8
	_spotlight.spot_range = 8.5
	_spotlight.spot_angle = 32.0
	_visual_root.add_child(_spotlight)

	# Inspection Radius Ring on Floor
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = INSPECTION_RADIUS - 0.10
	torus.outer_radius = INSPECTION_RADIUS
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.04, 0.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.95, 0.78, 0.18)
	ring.material_override = _ring_mat
	add_child(ring)

	_overhead_label = Label3D.new()
	_overhead_label.position = Vector3(0.0, 2.45, 0.0)
	_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.font_size = 22
	_overhead_label.outline_size = 8
	add_child(_overhead_label)
