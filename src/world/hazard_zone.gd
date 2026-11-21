class_name HazardZone
extends Node3D
## Lethal Gala Hazards with HDR Emissive Glare, OmniLights & 3D Warning Billboards.
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
var _hazard_light: OmniLight3D = null
var _label_3d: Label3D = null


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
		var dist_sniper: float = position.distance_to(vip_pos)
		if dist_sniper > radius:
			position.x = sin(_sweep_clock * 1.15) * 5.8
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
	if _zone_mat == null:
		return
	if hazard_type == HazardType.SNIPER_LASER:
		var pulse: float = clampf(sniper_lock_timer / SNIPER_LOCK_THRESHOLD_SEC, 0.0, 1.0)
		_zone_mat.albedo_color = Color(1.0, 0.10, 0.14).lerp(Color(1.0, 0.92, 0.25), pulse)
		if _hazard_light != null:
			_hazard_light.light_energy = 1.6 + pulse * 2.4
		if _label_3d != null:
			if sniper_lock_timer > 0.05:
				_label_3d.text = "🎯 SNIPER LOCKED: %.1fs — SHOVE VIP [F]!" % maxf(0.0, SNIPER_LOCK_THRESHOLD_SEC - sniper_lock_timer)
				_label_3d.modulate = Color(1.0, 0.95, 0.2)
			else:
				_label_3d.text = "🎯 ROOFTOP SNIPER LASER"
				_label_3d.modulate = Color(1.0, 0.28, 0.28)


func _build_hazard_visuals() -> void:
	for child: Node in get_children():
		child.free()
	if DisplayServer.get_name() == "headless":
		return

	_zone_mat = StandardMaterial3D.new()
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius - 0.14
	torus.outer_radius = radius
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.material_override = _zone_mat
	add_child(ring)

	_hazard_light = OmniLight3D.new()
	_hazard_light.position = Vector3(0.0, 1.4, 0.0)
	_hazard_light.omni_range = 7.5
	_hazard_light.light_specular = 2.4
	add_child(_hazard_light)

	_label_3d = Label3D.new()
	_label_3d.position = Vector3(0.0, 2.55, 0.0)
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_3d.font_size = 24
	_label_3d.outline_size = 8
	add_child(_label_3d)

	match hazard_type:
		HazardType.POISON_FOUNTAIN:
			_zone_mat.albedo_color = Color(0.20, 0.92, 0.35)
			_hazard_light.light_color = Color(0.18, 0.92, 0.38)
			_hazard_light.light_energy = 1.65
			_label_3d.text = "☠️ POISON CHAMPAGNE FOUNTAIN"
			_label_3d.modulate = Color(0.3, 1.0, 0.45)

			var fmat: StandardMaterial3D = StandardMaterial3D.new()
			fmat.albedo_color = Color(0.12, 0.78, 0.32)
			fmat.metallic = 0.55
			fmat.roughness = 0.16
			fmat.emission_enabled = true
			fmat.emission = Color(0.10, 0.72, 0.28)
			fmat.emission_energy_multiplier = 1.45

			for tier: int in range(3):
				var bowl: MeshInstance3D = MeshInstance3D.new()
				var tcyl: CylinderMesh = CylinderMesh.new()
				var r: float = 1.15 - float(tier) * 0.30
				tcyl.top_radius = r
				tcyl.bottom_radius = r * 0.65
				tcyl.height = 0.38
				bowl.mesh = tcyl
				bowl.position = Vector3(0.0, 0.45 + float(tier) * 0.58, 0.0)
				bowl.material_override = fmat
				add_child(bowl)

		HazardType.BALCONY_LEDGE:
			_zone_mat.albedo_color = Color(0.95, 0.42, 0.14)
			_hazard_light.light_color = Color(0.95, 0.45, 0.14)
			_hazard_light.light_energy = 1.6
			_label_3d.text = "⚡ HIGH-VOLTAGE BALCONY LEDGE"
			_label_3d.modulate = Color(1.0, 0.55, 0.2)

			var emat: StandardMaterial3D = StandardMaterial3D.new()
			emat.albedo_color = Color(0.95, 0.45, 0.12)
			emat.emission_enabled = true
			emat.emission = Color(0.95, 0.42, 0.10)
			emat.emission_energy_multiplier = 1.5

			var rail: MeshInstance3D = MeshInstance3D.new()
			var rbox: BoxMesh = BoxMesh.new()
			rbox.size = Vector3(radius * 2.0, 0.52, 0.22)
			rail.mesh = rbox
			rail.position = Vector3(0.0, 0.42, 0.0)
			rail.material_override = emat
			add_child(rail)

		HazardType.SNIPER_LASER:
			_zone_mat.albedo_color = Color(1.0, 0.10, 0.15)
			_hazard_light.light_color = Color(1.0, 0.12, 0.16)
			_hazard_light.light_energy = 1.65
			_label_3d.text = "🎯 ROOFTOP SNIPER LASER"
			_label_3d.modulate = Color(1.0, 0.28, 0.28)

			_laser_beam_mesh = MeshInstance3D.new()
			var lcyl: CylinderMesh = CylinderMesh.new()
			lcyl.top_radius = 0.045
			lcyl.bottom_radius = 0.045
			lcyl.height = 15.0
			_laser_beam_mesh.mesh = lcyl
			_laser_beam_mesh.position = Vector3(0.0, 7.2, -3.6)
			_laser_beam_mesh.rotation.x = deg_to_rad(28.0)
			_laser_beam_mesh.material_override = _zone_mat
			add_child(_laser_beam_mesh)
