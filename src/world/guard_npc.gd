class_name GuardNpc
extends Node3D
## Gala Security Guard / Paparazzi NPC with Volumetric Spotlight Cone,
## Decoy Bottle Distraction State, Paparazzi Flash Strobe & Voice-Bluff Inspection.

const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")

const PATROL_SPEED: float = 2.7
const INSPECTION_RADIUS: float = 4.6
const UNPROPPED_CORPSE_PENALTY_PER_SEC: float = 34.0
const ALIVE_DECAY_PER_SEC: float = -8.0

var guard_title: String = "Gala Guard"
var waypoints: Array[Vector3] = []
var current_waypoint_idx: int = 0
var is_inspecting_vip: bool = false
var last_inspection_bark: String = "Patrolling..."

# Decoy Champagne Bottle distraction state
var distracted_timer: float = 0.0
var distraction_target: Vector3 = Vector3.ZERO
var paparazzi_flash_pulse: float = 0.0
var _flash_cooldown: float = 0.0

var _ring_mat: StandardMaterial3D = null
var _visual_root: Node3D = null
var _spotlight: SpotLight3D = null
var _overhead_label: Label3D = null


func _ready() -> void:
	_build_visuals()


func configure_patrol(title: String, points: Array[Vector3]) -> void:
	guard_title = title
	waypoints = points
	current_waypoint_idx = 0
	if waypoints.size() > 0:
		position = waypoints[0]


func trigger_bottle_distraction(bottle_pos: Vector3, radius: float = 7.5, duration: float = 4.5) -> bool:
	if not bottle_pos.is_finite():
		return false
	if position.distance_to(bottle_pos) <= radius:
		distracted_timer = maxf(distracted_timer, duration)
		distraction_target = bottle_pos
		is_inspecting_vip = false
		return true
	return false


func stun_with_taser(duration: float) -> void:
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
	## Runs at 60 Hz on Host. Returns suspicion delta for this physics tick.
	if not is_finite(delta) or delta <= 0.0:
		return 0.0

	paparazzi_flash_pulse = maxf(0.0, paparazzi_flash_pulse - delta * 3.2)
	if _flash_cooldown > 0.0:
		_flash_cooldown = maxf(0.0, _flash_cooldown - delta)

	# 1. Check Decoy Champagne Bottle distraction
	if distracted_timer > 0.0:
		distracted_timer = maxf(0.0, distracted_timer - delta)
		is_inspecting_vip = false
		var to_bottle: Vector3 = distraction_target - position
		to_bottle.y = 0.0
		if to_bottle.length() > 0.75:
			var bdir: Vector3 = to_bottle.normalized()
			position += bdir * (PATROL_SPEED * 0.85) * delta
			if _visual_root != null:
				_visual_root.rotation.y = atan2(bdir.x, bdir.z)
		last_inspection_bark = "%s: '🍾 What smashed over there?! Checking champagne spill!'" % guard_title
		return -6.0 * delta

	var dist_to_vip: float = position.distance_to(vip_pos)
	is_inspecting_vip = dist_to_vip <= INSPECTION_RADIUS

	if not is_inspecting_vip:
		_step_patrol_movement(delta)
		last_inspection_bark = "%s: Patrolling gala floor." % guard_title
		return 0.0

	# Face the VIP while inspecting
	var to_vip: Vector3 = vip_pos - position
	to_vip.y = 0.0
	if to_vip.length() > 0.1 and _visual_root != null:
		_visual_root.rotation.y = atan2(to_vip.x, to_vip.z)

	# Paparazzi camera flash burst when inspecting
	if _flash_cooldown <= 0.0 and guard_title.contains("Paparazzi"):
		paparazzi_flash_pulse = 1.0
		_flash_cooldown = 1.8

	if vip_is_alive:
		last_inspection_bark = "%s: 'Evening, Mr. VIP! Everything looks normal.'" % guard_title
		return ALIVE_DECAY_PER_SEC * delta

	if vip_is_corpse:
		if vip_grabber_count <= 0:
			last_inspection_bark = "%s: '🚨 MAN DOWN! THE VIP IS COLLAPSED ON THE FLOOR!!'" % guard_title
			return UNPROPPED_CORPSE_PENALTY_PER_SEC * delta

		var rate: float = AudioInputDriverLib.evaluate_guard_suspicion_delta(voice_rms, true)
		if rate < 0.0:
			last_inspection_bark = "%s: '✓ Haha, great speech Mr. VIP! (Bluff working! -Suspicion)'" % guard_title
		elif voice_rms > 0.80:
			last_inspection_bark = "%s: '⚠️ Why is the VIP screaming?! Something is wrong!'" % guard_title
		else:
			last_inspection_bark = "%s: '❓ Sir? Why aren't you talking?! Hold [V] or throw Decoy [Q]!'" % guard_title
		return rate * delta

	return 0.0


func update_guard_visuals() -> void:
	if _ring_mat == null:
		return
	if distracted_timer > 0.0:
		_ring_mat.albedo_color = Color(0.25, 0.90, 1.0)
	elif is_inspecting_vip:
		_ring_mat.albedo_color = Color(1.0, 0.22, 0.15)
	else:
		_ring_mat.albedo_color = Color(0.95, 0.78, 0.18)

	if _spotlight != null:
		if paparazzi_flash_pulse > 0.1:
			_spotlight.light_color = Color(1.0, 0.96, 0.88)
			_spotlight.light_energy = 2.0 + paparazzi_flash_pulse * 4.5
		elif distracted_timer > 0.0:
			_spotlight.light_color = Color(0.3, 0.90, 1.0)
			_spotlight.light_energy = 1.6
		elif is_inspecting_vip:
			_spotlight.light_color = Color(1.0, 0.25, 0.20)
			_spotlight.light_energy = 2.4
		else:
			_spotlight.light_color = Color(1.0, 0.90, 0.68)
			_spotlight.light_energy = 1.6

	if _overhead_label != null:
		if distracted_timer > 0.0:
			_overhead_label.text = "🍾 %s [DISTRACTED %.1fs]" % [guard_title, distracted_timer]
			_overhead_label.modulate = Color(0.3, 0.95, 1.0)
		elif is_inspecting_vip:
			_overhead_label.text = "👁️ %s [INSPECTING VIP!]" % guard_title
			_overhead_label.modulate = Color(1.0, 0.35, 0.25)
		else:
			_overhead_label.text = "👮 %s" % guard_title
			_overhead_label.modulate = Color(0.95, 0.85, 0.55)


func _step_patrol_movement(delta: float) -> void:
	if waypoints.is_empty():
		return
	var target: Vector3 = waypoints[current_waypoint_idx]
	var diff: Vector3 = target - position
	diff.y = 0.0
	if diff.length() <= 0.35:
		current_waypoint_idx = (current_waypoint_idx + 1) % waypoints.size()
		return
	var dir: Vector3 = diff.normalized()
	position += dir * PATROL_SPEED * delta
	if _visual_root != null:
		_visual_root.rotation.y = atan2(dir.x, dir.z)


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "GuardVisual"
	add_child(_visual_root)
	if DisplayServer.get_name() == "headless":
		return

	# Guard Officer Suit Jacket
	var body: MeshInstance3D = MeshInstance3D.new()
	var bbox: BoxMesh = BoxMesh.new()
	bbox.size = Vector3(0.62, 0.96, 0.36)
	body.mesh = bbox
	body.position = Vector3(0.0, 1.02, 0.0)
	var guard_mat: StandardMaterial3D = StandardMaterial3D.new()
	guard_mat.albedo_color = Color(0.45, 0.09, 0.14)
	guard_mat.metallic = 0.35
	guard_mat.roughness = 0.28
	guard_mat.clearcoat_enabled = true
	body.material_override = guard_mat
	_visual_root.add_child(body)

	# Gold Officer Chest Badge
	var badge: MeshInstance3D = MeshInstance3D.new()
	var bsph: SphereMesh = SphereMesh.new()
	bsph.radius = 0.08
	badge.mesh = bsph
	badge.position = Vector3(-0.16, 1.26, 0.19)
	var gold_mat: StandardMaterial3D = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(1.0, 0.82, 0.25)
	gold_mat.metallic = 0.95
	gold_mat.roughness = 0.08
	gold_mat.emission_enabled = true
	gold_mat.emission = Color(1.0, 0.78, 0.20)
	badge.material_override = gold_mat
	_visual_root.add_child(badge)

	# Head & Officer Cap Visor
	var head: MeshInstance3D = MeshInstance3D.new()
	var hbox: BoxMesh = BoxMesh.new()
	hbox.size = Vector3(0.38, 0.40, 0.38)
	head.mesh = hbox
	head.position = Vector3(0.0, 1.72, 0.0)
	var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.90, 0.74, 0.62)
	head.material_override = skin_mat
	_visual_root.add_child(head)

	var visor: MeshInstance3D = MeshInstance3D.new()
	var vbox: BoxMesh = BoxMesh.new()
	vbox.size = Vector3(0.46, 0.14, 0.48)
	visor.mesh = vbox
	visor.position = Vector3(0.0, 1.94, 0.06)
	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.08, 0.08, 0.12)
	cap_mat.roughness = 0.15
	visor.material_override = cap_mat
	_visual_root.add_child(visor)

	# Real Volumetric Flashlight / Camera Strobe SpotLight3D Cone
	_spotlight = SpotLight3D.new()
	_spotlight.position = Vector3(0.24, 1.25, 0.28)
	_spotlight.rotation_degrees = Vector3(-16.0, 180.0, 0.0)
	_spotlight.light_color = Color(1.0, 0.90, 0.65)
	_spotlight.light_energy = 3.4
	_spotlight.light_specular = 2.0
	_spotlight.spot_range = 8.5
	_spotlight.spot_angle = 32.0
	_spotlight.shadow_enabled = true
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
	_overhead_label.position = Vector3(0.0, 2.38, 0.0)
	_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.font_size = 24
	_overhead_label.outline_size = 8
	add_child(_overhead_label)
