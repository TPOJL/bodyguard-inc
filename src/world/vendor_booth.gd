class_name VendorBooth
extends Node3D
## Starting-Lobby Physical 3D Arms Dealer Booth ("BIG TONY'S BLACK-MARKET ARMORY").
## Players can walk up at the start of every level and press [U] to buy weapons, cryo & buffs.

const CharacterRigBuilderLib := preload("res://src/world/character_rig_builder.gd")

const INTERACT_RADIUS: float = 4.5

var is_player_in_range: bool = false
var _vendor_arm: Node3D = null
var _prompt_label: Label3D = null
var _ring_mat: StandardMaterial3D = null
var _clock: float = 0.0


func configure_booth(pos: Vector3, accent_col: Color) -> void:
	position = pos
	_build_visuals(accent_col)


func check_player_proximity(player_pos: Vector3) -> bool:
	if not player_pos.is_finite():
		is_player_in_range = false
		return false
	is_player_in_range = (position.distance_to(player_pos) <= INTERACT_RADIUS)
	return is_player_in_range


func update_visuals(delta: float) -> void:
	if not is_finite(delta):
		return
	_clock += delta
	if _vendor_arm != null:
		# Big Tony waves enthusiastically when player approaches the counter!
		var wave_amp: float = 0.55 if is_player_in_range else 0.18
		_vendor_arm.rotation.z = deg_to_rad(-135.0) + sin(_clock * 6.5) * wave_amp
	if _prompt_label != null:
		if is_player_in_range:
			_prompt_label.text = "🛒 BIG TONY: \"PRESS [U] FOR GUNS, CRYO & BUFFS!\""
			_prompt_label.modulate = Color(0.32, 1.0, 0.62)
		else:
			_prompt_label.text = "🛒 TONY'S ARMORY SHOP [U]"
			_prompt_label.modulate = Color(1.0, 0.84, 0.30)
	if _ring_mat != null:
		_ring_mat.albedo_color = Color(0.28, 1.0, 0.58) if is_player_in_range else Color(0.95, 0.78, 0.28)


func _build_visuals(accent_col: Color) -> void:
	for child: Node in get_children():
		child.free()
	if DisplayServer.get_name() == "headless":
		return

	var counter_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.10, 0.11, 0.16), 0.45, 0.28, 0.3)
	var brass_mat: StandardMaterial3D = CharacterRigBuilderLib.make_material(Color(0.90, 0.72, 0.28), 0.88, 0.22, 0.35)
	var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.42, 0.82, 1.0, 0.28)
	glass_mat.roughness = 0.08

	# Solid Sales Counter Base (3.8m x 1.2m)
	var counter: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(3.8, 1.05, 1.25)
	counter.mesh = cbox
	counter.position = Vector3(0.0, 0.525, 0.6)
	counter.material_override = counter_mat
	add_child(counter)

	# Glass Showcase Display Top
	var showcase: MeshInstance3D = MeshInstance3D.new()
	var scbox: BoxMesh = BoxMesh.new()
	scbox.size = Vector3(3.6, 0.32, 1.05)
	showcase.mesh = scbox
	showcase.position = Vector3(0.0, 1.21, 0.6)
	showcase.material_override = glass_mat
	add_child(showcase)

	# Glowing Weapon Display Props inside Glass Showcase (Plasma Gold + Cryo Cyan)
	var plasma_prop: MeshInstance3D = MeshInstance3D.new()
	var pbox: BoxMesh = BoxMesh.new()
	pbox.size = Vector3(0.75, 0.14, 0.14)
	plasma_prop.mesh = pbox
	plasma_prop.position = Vector3(-0.9, 1.18, 0.6)
	plasma_prop.material_override = CharacterRigBuilderLib.make_material(Color(1.0, 0.72, 0.20), 0.5, 0.2, 0.0, Color(1.0, 0.68, 0.18), 1.4)
	add_child(plasma_prop)

	var cryo_prop: MeshInstance3D = MeshInstance3D.new()
	var crbox: BoxMesh = BoxMesh.new()
	crbox.size = Vector3(0.95, 0.16, 0.16)
	cryo_prop.mesh = crbox
	cryo_prop.position = Vector3(0.9, 1.18, 0.6)
	cryo_prop.material_override = CharacterRigBuilderLib.make_material(Color(0.25, 0.92, 1.0), 0.5, 0.2, 0.0, Color(0.25, 0.88, 1.0), 1.4)
	add_child(cryo_prop)

	# Canopy Posts & Glowing Sign Bar
	for px: float in [-1.85, 1.85]:
		var post: MeshInstance3D = MeshInstance3D.new()
		var pcyl: CylinderMesh = CylinderMesh.new()
		pcyl.top_radius = 0.08
		pcyl.bottom_radius = 0.09
		pcyl.height = 3.1
		post.mesh = pcyl
		post.position = Vector3(px, 1.55, -0.5)
		post.material_override = brass_mat
		add_child(post)

	var canopy: MeshInstance3D = MeshInstance3D.new()
	var kbox: BoxMesh = BoxMesh.new()
	kbox.size = Vector3(4.3, 0.28, 2.2)
	canopy.mesh = kbox
	canopy.position = Vector3(0.0, 3.12, 0.15)
	canopy.material_override = counter_mat
	add_child(canopy)

	var sign_bar: MeshInstance3D = MeshInstance3D.new()
	var sbbox: BoxMesh = BoxMesh.new()
	sbbox.size = Vector3(3.9, 0.10, 0.10)
	sign_bar.mesh = sbbox
	sign_bar.position = Vector3(0.0, 3.05, 1.24)
	sign_bar.material_override = CharacterRigBuilderLib.make_material(accent_col, 0.2, 0.2, 0.0, accent_col, 1.5)
	add_child(sign_bar)

	# Sculpted Vendor NPC ("Big Tony") behind the counter
	var tony_root: Node3D = Node3D.new()
	tony_root.name = "BigTonyNPC"
	tony_root.position = Vector3(0.0, 0.0, -0.35)
	add_child(tony_root)
	var rig: Dictionary = CharacterRigBuilderLib.build_sculpted_bodyguard(
		tony_root,
		Color(0.42, 0.08, 0.22),
		Color(1.0, 0.80, 0.24),
		Color(0.18, 0.14, 0.12)
	)
	_vendor_arm = rig["right_arm"]

	# Interactive Floor Ring in front of Counter
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 2.15
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.05, 2.2)
	_ring_mat = CharacterRigBuilderLib.make_material(Color(0.95, 0.78, 0.28), 0.3, 0.3, 0.0, Color(0.95, 0.78, 0.28), 0.9)
	ring.material_override = _ring_mat
	add_child(ring)

	_prompt_label = Label3D.new()
	_prompt_label.position = Vector3(0.0, 3.65, 0.4)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.font_size = 26
	_prompt_label.outline_size = 9
	_prompt_label.text = "🛒 TONY'S ARMORY SHOP [U]"
	add_child(_prompt_label)
