class_name GuardNpc
extends Node3D
## Gala Security Guard / Paparazzi NPC with Patrol Waypoints & Corpse Voice-Bluff Inspection.

const AudioInputDriverLib := preload("res://src/core/audio_input_driver.gd")

const PATROL_SPEED: float = 2.6
const INSPECTION_RADIUS: float = 4.6
const UNPROPPED_CORPSE_PENALTY_PER_SEC: float = 34.0
const ALIVE_DECAY_PER_SEC: float = -8.0

var guard_title: String = "Gala Guard"
var waypoints: Array[Vector3] = []
var current_waypoint_idx: int = 0
var is_inspecting_vip: bool = false
var last_inspection_bark: String = "Patrolling..."

var _ring_mat: StandardMaterial3D = null
var _visual_root: Node3D = null


func _ready() -> void:
	_build_visuals()


func configure_patrol(title: String, points: Array[Vector3]) -> void:
	guard_title = title
	waypoints = points
	current_waypoint_idx = 0
	if waypoints.size() > 0:
		position = waypoints[0]


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

	if vip_is_alive:
		last_inspection_bark = "%s: 'Evening, Mr. VIP! Everything looks normal.'" % guard_title
		return ALIVE_DECAY_PER_SEC * delta

	if vip_is_corpse:
		if vip_grabber_count <= 0:
			last_inspection_bark = "%s: 'MAN DOWN! THE VIP IS COLLAPSED ON THE FLOOR!!'" % guard_title
			return UNPROPPED_CORPSE_PENALTY_PER_SEC * delta

		var rate: float = AudioInputDriverLib.evaluate_guard_suspicion_delta(voice_rms, true)
		if rate < 0.0:
			last_inspection_bark = "%s: 'Haha, great point Mr. VIP! (Bluff working! -Suspicion)'" % guard_title
		elif voice_rms > 0.80:
			last_inspection_bark = "%s: 'Why is the VIP screaming?! Something is wrong!'" % guard_title
		else:
			last_inspection_bark = "%s: 'Sir? Why aren't you talking?! Hold [V] to animate his jaw!'" % guard_title
		return rate * delta

	return 0.0


func update_guard_visuals() -> void:
	if _ring_mat == null:
		return
	if is_inspecting_vip:
		_ring_mat.albedo_color = Color(1.0, 0.28, 0.15, 0.85)
	else:
		_ring_mat.albedo_color = Color(0.95, 0.78, 0.18, 0.45)


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

	var body: MeshInstance3D = MeshInstance3D.new()
	var caps: CapsuleMesh = CapsuleMesh.new()
	caps.radius = 0.35
	caps.height = 1.75
	body.mesh = caps
	body.position = Vector3(0.0, 0.90, 0.0)
	var guard_mat: StandardMaterial3D = StandardMaterial3D.new()
	guard_mat.albedo_color = Color(0.55, 0.12, 0.16)
	body.material_override = guard_mat
	_visual_root.add_child(body)

	# Guard Cap Visor
	var visor: MeshInstance3D = MeshInstance3D.new()
	var vbox: BoxMesh = BoxMesh.new()
	vbox.size = Vector3(0.45, 0.12, 0.35)
	visor.mesh = vbox
	visor.position = Vector3(0.0, 1.68, 0.15)
	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.12, 0.12, 0.14)
	visor.material_override = cap_mat
	_visual_root.add_child(visor)

	# Inspection Radius Ring on Floor
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = INSPECTION_RADIUS - 0.12
	torus.outer_radius = INSPECTION_RADIUS
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.05, 0.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.95, 0.78, 0.18)
	ring.material_override = _ring_mat
	add_child(ring)
