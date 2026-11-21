class_name HazardZone
extends Node3D
## Lethal Gala Hazards that the suicidal low-IQ VIP is drawn toward.
## Types: SNIPER_LASER, POISON_FOUNTAIN, BALCONY_LEDGE.

enum HazardType {
	SNIPER_LASER,
	POISON_FOUNTAIN,
	BALCONY_LEDGE,
}

const SNIPER_LOCK_THRESHOLD_SEC: float = 2.0

var hazard_type: HazardType = HazardType.POISON_FOUNTAIN
var hazard_title: String = "Poison Champagne Fountain"
var radius: float = 2.3
var damage_per_sec: float = 42.0
var sniper_lock_timer: float = 0.0
var _sweep_clock: float = 0.0
var _laser_beam_mesh: MeshInstance3D = null
var _zone_mat: StandardMaterial3D = null


func configure_hazard(h_type: HazardType, title: String, pos: Vector3, zone_radius: float) -> void:
	hazard_type = h_type
	hazard_title = title
	position = pos
	radius = zone_radius
	_build_hazard_visuals()


func step_hazard_physics(delta: float, vip_pos: Vector3, vip_is_alive: bool) -> float:
	## Runs at 60 Hz on Host. Returns authoritative damage dealt to VIP this tick.
	if not is_finite(delta) or delta <= 0.0 or not vip_is_alive:
		sniper_lock_timer = 0.0
		return 0.0

	_sweep_clock += delta
	if hazard_type == HazardType.SNIPER_LASER:
		# Sniper laser dot sweeps gently across the red carpet unless locked onto VIP
		var dist_sniper: float = position.distance_to(vip_pos)
		if dist_sniper > radius:
			position.x = sin(_sweep_clock * 1.1) * 5.5
			sniper_lock_timer = maxf(0.0, sniper_lock_timer - delta * 1.5)
			return 0.0
		sniper_lock_timer += delta
		if sniper_lock_timer >= SNIPER_LOCK_THRESHOLD_SEC:
			sniper_lock_timer = 0.0
			return 100.0
		return 0.0

	var dist: float = position.distance_to(vip_pos)
	if dist <= radius:
		if hazard_type == HazardType.BALCONY_LEDGE:
			return 100.0
		return damage_per_sec * delta
	return 0.0


func update_hazard_visuals() -> void:
	if hazard_type == HazardType.SNIPER_LASER and _zone_mat != null:
		var pulse: float = clampf(sniper_lock_timer / SNIPER_LOCK_THRESHOLD_SEC, 0.0, 1.0)
		_zone_mat.albedo_color = Color(1.0, 0.08, 0.08).lerp(Color(1.0, 0.95, 0.2), pulse)


func _build_hazard_visuals() -> void:
	for child: Node in get_children():
		child.free()
	if DisplayServer.get_name() == "headless":
		return

	_zone_mat = StandardMaterial3D.new()
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ring: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.08
	ring.mesh = cyl
	ring.position = Vector3(0.0, 0.04, 0.0)
	ring.material_override = _zone_mat
	add_child(ring)

	match hazard_type:
		HazardType.POISON_FOUNTAIN:
			_zone_mat.albedo_color = Color(0.22, 0.92, 0.25)
			var tower: MeshInstance3D = MeshInstance3D.new()
			var tcyl: CylinderMesh = CylinderMesh.new()
			tcyl.top_radius = 0.45
			tcyl.bottom_radius = 0.95
			tcyl.height = 1.8
			tower.mesh = tcyl
			tower.position = Vector3(0.0, 0.9, 0.0)
			var fmat: StandardMaterial3D = StandardMaterial3D.new()
			fmat.albedo_color = Color(0.15, 0.85, 0.35)
			fmat.emission_enabled = true
			fmat.emission = Color(0.1, 0.65, 0.2)
			tower.material_override = fmat
			add_child(tower)

		HazardType.BALCONY_LEDGE:
			_zone_mat.albedo_color = Color(0.95, 0.35, 0.10)
			var rail: MeshInstance3D = MeshInstance3D.new()
			var rbox: BoxMesh = BoxMesh.new()
			rbox.size = Vector3(radius * 2.0, 0.45, 0.25)
			rail.mesh = rbox
			rail.position = Vector3(0.0, 0.25, 0.0)
			rail.material_override = _zone_mat
			add_child(rail)

		HazardType.SNIPER_LASER:
			_zone_mat.albedo_color = Color(1.0, 0.10, 0.10)
			_laser_beam_mesh = MeshInstance3D.new()
			var lcyl: CylinderMesh = CylinderMesh.new()
			lcyl.top_radius = 0.05
			lcyl.bottom_radius = 0.05
			lcyl.height = 14.0
			_laser_beam_mesh.mesh = lcyl
			_laser_beam_mesh.position = Vector3(0.0, 7.0, -3.5)
			_laser_beam_mesh.rotation.x = deg_to_rad(28.0)
			_laser_beam_mesh.material_override = _zone_mat
			add_child(_laser_beam_mesh)
