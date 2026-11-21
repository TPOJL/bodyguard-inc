class_name LootPickup
extends Node3D
## Interactive farmable loot & keycards scattered across the Penthouse Gala.
## Types: TIP_ENVELOPE ($350), BRIEFCASE ($900), CHAMPAGNE_RESTOCK (+1 Bottle + $200), SECURITY_KEYCARD.

enum LootType {
	TIP_ENVELOPE,
	BRIEFCASE,
	CHAMPAGNE_RESTOCK,
	SECURITY_KEYCARD,
}

const PICKUP_RADIUS: float = 1.85

var loot_type: LootType = LootType.TIP_ENVELOPE
var cash_value: int = 350
var title: String = "VIP Tip"
var collected: bool = false

var _mesh_pivot: Node3D = null
var _label: Label3D = null
var _clock: float = 0.0


func configure_loot(l_type: LootType, pos: Vector3) -> void:
	loot_type = l_type
	position = pos
	collected = false
	match loot_type:
		LootType.TIP_ENVELOPE:
			cash_value = 350
			title = "💵 +$350 Tip"
		LootType.BRIEFCASE:
			cash_value = 900
			title = "💼 +$900 Briefcase"
		LootType.CHAMPAGNE_RESTOCK:
			cash_value = 200
			title = "🍾 +1 Decoy Bottle"
		LootType.SECURITY_KEYCARD:
			cash_value = 600
			title = "🗝️ GOLD KEYCARD (Unlocks Sky-Bridge Gate!)"
	_build_visuals()


func check_pickup(collector_pos: Vector3) -> bool:
	if collected or not collector_pos.is_finite():
		return false
	if position.distance_to(collector_pos) <= PICKUP_RADIUS:
		collected = true
		visible = false
		return true
	return false


func update_visuals(delta: float) -> void:
	if collected or _mesh_pivot == null or not is_finite(delta):
		return
	_clock += delta
	_mesh_pivot.rotation.y += delta * 2.1
	_mesh_pivot.position.y = 0.65 + sin(_clock * 3.4) * 0.14


func _build_visuals() -> void:
	for child: Node in get_children():
		child.free()
	if DisplayServer.get_name() == "headless":
		return

	_mesh_pivot = Node3D.new()
	_mesh_pivot.position = Vector3(0.0, 0.65, 0.0)
	add_child(_mesh_pivot)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.metallic = 0.85
	mat.roughness = 0.18
	mat.clearcoat_enabled = true

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	match loot_type:
		LootType.TIP_ENVELOPE:
			mat.albedo_color = Color(0.28, 0.88, 0.42)
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(0.45, 0.25, 0.12)
			mesh_inst.mesh = b
		LootType.BRIEFCASE:
			mat.albedo_color = Color(0.92, 0.74, 0.24)
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(0.58, 0.42, 0.20)
			mesh_inst.mesh = b
		LootType.CHAMPAGNE_RESTOCK:
			mat.albedo_color = Color(0.22, 0.78, 0.92)
			var c: CylinderMesh = CylinderMesh.new()
			c.top_radius = 0.07
			c.bottom_radius = 0.14
			c.height = 0.56
			mesh_inst.mesh = c
		LootType.SECURITY_KEYCARD:
			mat.albedo_color = Color(1.0, 0.84, 0.22)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.78, 0.18)
			mat.emission_energy_multiplier = 1.6
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(0.52, 0.34, 0.06)
			mesh_inst.mesh = b

	mesh_inst.material_override = mat
	_mesh_pivot.add_child(mesh_inst)

	# Subtle ground marker ring
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.56
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.04, 0.0)
	var rmat: StandardMaterial3D = StandardMaterial3D.new()
	rmat.albedo_color = mat.albedo_color
	rmat.roughness = 0.3
	ring.material_override = rmat
	add_child(ring)

	_label = Label3D.new()
	_label.position = Vector3(0.0, 1.55, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 20
	_label.outline_size = 7
	_label.text = title
	_label.modulate = mat.albedo_color.lightened(0.25)
	add_child(_label)
