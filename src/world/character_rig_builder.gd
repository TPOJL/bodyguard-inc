class_name CharacterRigBuilder
extends RefCounted
## High-Detail Procedural Sculpted 3D Character Rig Builder for BODYGUARD INC.
## Replaces crude boxes with sculpted capsules, spheres, collars, ties, shoulder pads,
## dress shoes, weapon props, reflective visors, and cryo-freeze crystal shells.


static func make_material(
	col: Color,
	metallic: float = 0.25,
	roughness: float = 0.35,
	clearcoat: float = 0.0,
	emission_col: Color = Color.BLACK,
	emission_energy: float = 0.0
) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	if clearcoat > 0.01:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.16
	if emission_energy > 0.01:
		m.emission_enabled = true
		m.emission = emission_col
		m.emission_energy_multiplier = emission_energy
	return m


static func build_sculpted_bodyguard(
	parent: Node3D,
	suit_col: Color,
	tie_col: Color,
	hair_col: Color
) -> Dictionary:
	## Builds a high-detail articulated Secret Service agent holding a glowing weapon.
	var suit_mat: StandardMaterial3D = make_material(suit_col, 0.32, 0.30, 0.35)
	var pants_mat: StandardMaterial3D = make_material(suit_col.darkened(0.28), 0.15, 0.45)
	var shirt_mat: StandardMaterial3D = make_material(Color(0.95, 0.96, 1.0), 0.05, 0.55)
	var tie_mat: StandardMaterial3D = make_material(tie_col, 0.25, 0.25, 0.3, tie_col, 0.45)
	var skin_mat: StandardMaterial3D = make_material(Color(0.93, 0.77, 0.65), 0.0, 0.50)
	var hair_mat: StandardMaterial3D = make_material(hair_col, 0.1, 0.48)
	var shades_mat: StandardMaterial3D = make_material(Color(0.03, 0.05, 0.08), 0.92, 0.08, 0.7)
	var shoe_mat: StandardMaterial3D = make_material(Color(0.05, 0.05, 0.07), 0.55, 0.18, 0.6)
	var metal_mat: StandardMaterial3D = make_material(Color(0.72, 0.78, 0.85), 0.88, 0.22)

	# Sculpted Tapered Suit Torso + Broad Shoulders
	var torso: MeshInstance3D = MeshInstance3D.new()
	var tcyl: CylinderMesh = CylinderMesh.new()
	tcyl.top_radius = 0.34
	tcyl.bottom_radius = 0.25
	tcyl.height = 0.76
	torso.mesh = tcyl
	torso.position = Vector3(0.0, 1.12, 0.0)
	torso.material_override = suit_mat
	parent.add_child(torso)

	var chest_pad: MeshInstance3D = MeshInstance3D.new()
	var csph: SphereMesh = SphereMesh.new()
	csph.radius = 0.34
	chest_pad.mesh = csph
	chest_pad.scale = Vector3(1.12, 0.55, 0.78)
	chest_pad.position = Vector3(0.0, 1.42, 0.0)
	chest_pad.material_override = suit_mat
	parent.add_child(chest_pad)

	# Dress Shirt V-Collar & Glowing Tactical Tie
	var shirt: MeshInstance3D = MeshInstance3D.new()
	var shbox: BoxMesh = BoxMesh.new()
	shbox.size = Vector3(0.22, 0.48, 0.28)
	shirt.mesh = shbox
	shirt.position = Vector3(0.0, 1.24, 0.16)
	shirt.material_override = shirt_mat
	parent.add_child(shirt)

	var tie: MeshInstance3D = MeshInstance3D.new()
	var tiebox: BoxMesh = BoxMesh.new()
	tiebox.size = Vector3(0.09, 0.46, 0.06)
	tie.mesh = tiebox
	tie.position = Vector3(0.0, 1.21, 0.31)
	tie.material_override = tie_mat
	parent.add_child(tie)

	# Belt + Silver Buckle
	var belt: MeshInstance3D = MeshInstance3D.new()
	var bcyl: CylinderMesh = CylinderMesh.new()
	bcyl.top_radius = 0.265
	bcyl.bottom_radius = 0.265
	bcyl.height = 0.08
	belt.mesh = bcyl
	belt.position = Vector3(0.0, 0.78, 0.0)
	belt.material_override = shoe_mat
	parent.add_child(belt)

	# Sculpted Neck + Smooth Sphere Head + Styled Hair + Wraparound Shades + Earpiece
	var neck: MeshInstance3D = MeshInstance3D.new()
	var ncyl: CylinderMesh = CylinderMesh.new()
	ncyl.top_radius = 0.10
	ncyl.bottom_radius = 0.11
	ncyl.height = 0.16
	neck.mesh = ncyl
	neck.position = Vector3(0.0, 1.56, 0.0)
	neck.material_override = skin_mat
	parent.add_child(neck)

	var head: MeshInstance3D = MeshInstance3D.new()
	var hsph: SphereMesh = SphereMesh.new()
	hsph.radius = 0.23
	head.mesh = hsph
	head.scale = Vector3(0.95, 1.08, 1.0)
	head.position = Vector3(0.0, 1.78, 0.0)
	head.material_override = skin_mat
	parent.add_child(head)

	var hair: MeshInstance3D = MeshInstance3D.new()
	var hair_sph: SphereMesh = SphereMesh.new()
	hair_sph.radius = 0.235
	hair.mesh = hair_sph
	hair.scale = Vector3(1.02, 0.68, 1.06)
	hair.position = Vector3(0.0, 1.90, -0.02)
	hair.material_override = hair_mat
	parent.add_child(hair)

	var shades: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(0.38, 0.095, 0.14)
	shades.mesh = sbox
	shades.position = Vector3(0.0, 1.80, 0.18)
	shades.material_override = shades_mat
	parent.add_child(shades)

	# Glowing Tactical Comms Earpiece on right ear
	var earpiece: MeshInstance3D = MeshInstance3D.new()
	var esph: SphereMesh = SphereMesh.new()
	esph.radius = 0.045
	earpiece.mesh = esph
	earpiece.position = Vector3(0.22, 1.76, 0.02)
	earpiece.material_override = tie_mat
	parent.add_child(earpiece)

	# Articulated Sculpted Arms (Capsule sleeves + hands + Equipped Plasma/Cryo Pistol on right hand!)
	var left_arm: Node3D = _make_sculpted_arm("LeftArm", Vector3(-0.38, 1.40, 0.0), suit_mat, skin_mat)
	var right_arm: Node3D = _make_sculpted_arm("RightArm", Vector3(0.38, 1.40, 0.0), suit_mat, skin_mat)
	parent.add_child(left_arm)
	parent.add_child(right_arm)

	# Equipped Sidearm Pistol in Right Hand (glowing energy core!)
	var weapon_root: Node3D = Node3D.new()
	weapon_root.name = "EquippedWeapon"
	weapon_root.position = Vector3(0.0, -0.58, 0.22)
	right_arm.add_child(weapon_root)

	var barrel: MeshInstance3D = MeshInstance3D.new()
	var barrel_box: BoxMesh = BoxMesh.new()
	barrel_box.size = Vector3(0.09, 0.12, 0.42)
	barrel.mesh = barrel_box
	barrel.material_override = metal_mat
	weapon_root.add_child(barrel)

	var weapon_glow_mat: StandardMaterial3D = make_material(
		Color(0.25, 0.90, 1.0), 0.3, 0.2, 0.0, Color(0.25, 0.90, 1.0), 1.6
	)
	var muzzle: MeshInstance3D = MeshInstance3D.new()
	var mbox: BoxMesh = BoxMesh.new()
	mbox.size = Vector3(0.06, 0.06, 0.36)
	muzzle.mesh = mbox
	muzzle.position = Vector3(0.0, 0.04, 0.06)
	muzzle.material_override = weapon_glow_mat
	weapon_root.add_child(muzzle)

	# Articulated Sculpted Legs + Dress Shoes
	var left_leg: Node3D = _make_sculpted_leg("LeftLeg", Vector3(-0.15, 0.74, 0.0), pants_mat, shoe_mat)
	var right_leg: Node3D = _make_sculpted_leg("RightLeg", Vector3(0.15, 0.74, 0.0), pants_mat, shoe_mat)
	parent.add_child(left_leg)
	parent.add_child(right_leg)

	return {
		"left_arm": left_arm,
		"right_arm": right_arm,
		"left_leg": left_leg,
		"right_leg": right_leg,
		"weapon_glow_mat": weapon_glow_mat,
	}


static func build_ice_crystal_shell(parent: Node3D) -> Node3D:
	## Translucent glowing ice prison shown around frozen Guards / Assassins!
	var ice_root: Node3D = Node3D.new()
	ice_root.name = "CryoIceShell"
	ice_root.visible = false
	parent.add_child(ice_root)

	var ice_mat: StandardMaterial3D = StandardMaterial3D.new()
	ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_mat.albedo_color = Color(0.45, 0.92, 1.0, 0.56)
	ice_mat.metallic = 0.25
	ice_mat.roughness = 0.08
	ice_mat.emission_enabled = true
	ice_mat.emission = Color(0.25, 0.80, 1.0)
	ice_mat.emission_energy_multiplier = 1.15

	var block: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.52
	cyl.bottom_radius = 0.68
	cyl.height = 2.05
	cyl.radial_segments = 6
	block.mesh = cyl
	block.position = Vector3(0.0, 1.02, 0.0)
	block.material_override = ice_mat
	ice_root.add_child(block)
	return ice_root


static func _make_sculpted_arm(
	arm_name: String,
	offset: Vector3,
	sleeve_mat: StandardMaterial3D,
	skin_mat: StandardMaterial3D
) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = arm_name
	pivot.position = offset

	var sleeve: MeshInstance3D = MeshInstance3D.new()
	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = 0.095
	cap.height = 0.62
	sleeve.mesh = cap
	sleeve.position = Vector3(0.0, -0.26, 0.0)
	sleeve.material_override = sleeve_mat
	pivot.add_child(sleeve)

	var hand: MeshInstance3D = MeshInstance3D.new()
	var hsph: SphereMesh = SphereMesh.new()
	hsph.radius = 0.085
	hand.mesh = hsph
	hand.position = Vector3(0.0, -0.58, 0.02)
	hand.material_override = skin_mat
	pivot.add_child(hand)
	return pivot


static func _make_sculpted_leg(
	leg_name: String,
	offset: Vector3,
	pants_mat: StandardMaterial3D,
	shoe_mat: StandardMaterial3D
) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = leg_name
	pivot.position = offset

	var leg: MeshInstance3D = MeshInstance3D.new()
	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = 0.105
	cap.height = 0.72
	leg.mesh = cap
	leg.position = Vector3(0.0, -0.34, 0.0)
	leg.material_override = pants_mat
	pivot.add_child(leg)

	var shoe: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(0.18, 0.12, 0.30)
	shoe.mesh = sbox
	shoe.position = Vector3(0.0, -0.68, 0.06)
	shoe.material_override = shoe_mat
	pivot.add_child(shoe)
	return pivot
