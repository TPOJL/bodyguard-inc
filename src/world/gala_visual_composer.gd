class_name GalaVisualComposer
extends RefCounted
## Builds the massive 52m x 136m Multi-Theme Penthouse Estate & Registers EVERY Solid Wall,
## Pillar, Banquet Table, Vendor Booth, and Locked Laser Gate into WallColliderGrid!

const ProceduralTexturesLib := preload("res://src/world/procedural_textures.gd")
const WallColliderGridLib := preload("res://src/world/wall_collider_grid.gd")

const SUBTLE_POSTFX_SHADER: String = """
shader_type canvas_item;

uniform float danger_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float flash_burst : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float vig = smoothstep(0.48, 0.94, dist) * 0.30;
	float edge = smoothstep(0.40, 0.86, dist);
	vec3 danger_col = vec3(0.85, 0.10, 0.14) * edge * danger_pulse * 0.40;
	vec3 flash_col = vec3(1.0, 0.95, 0.84) * flash_burst * 0.18;
	vec3 rgb = mix(vec3(0.01, 0.015, 0.03), danger_col + flash_col, clamp(length(danger_col + flash_col) * 2.2, 0.0, 1.0));
	float alpha = clamp(vig + length(danger_col) + flash_burst * 0.16, 0.0, 0.50);
	COLOR = vec4(rgb, alpha);
}
"""


static func build_hdr_environment(parent: Node3D, theme_cfg: Dictionary) -> Dictionary:
	## Returns {"env_root": Node3D, "flare_mat": ShaderMaterial} for clean level theme reloads.
	var env_root: Node3D = Node3D.new()
	env_root.name = "ThemeEnvironmentRoot"
	parent.add_child(env_root)

	if DisplayServer.get_name() == "headless":
		return {"env_root": env_root, "flare_mat": null}

	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()

	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme_cfg["sky_top"]
	sky_mat.sky_horizon_color = theme_cfg["sky_horizon"]
	sky_mat.ground_bottom_color = Color(0.03, 0.04, 0.08)
	sky_mat.ground_horizon_color = Color(0.12, 0.12, 0.18)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.72
	env.ambient_light_energy = 0.88

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.04
	env.tonemap_white = 8.0

	# Tasteful, Crisp HDR Glints ("Норм Блики") — ZERO blinding whiteout!
	env.glow_enabled = true
	env.set_glow_level(0, false)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	env.set_glow_level(4, false)
	env.set_glow_level(5, false)
	env.glow_intensity = 0.28
	env.glow_strength = 0.64
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.45
	env.glow_hdr_scale = 1.15

	env.ssr_enabled = true
	env.ssr_max_steps = 40
	env.ssr_fade_in = 0.22
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.22

	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.6

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08

	env_node.environment = env
	env_root.add_child(env_node)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-56.0, 26.0, 0.0)
	key_light.light_color = theme_cfg["key_color"]
	key_light.light_energy = 0.96
	key_light.light_specular = 0.44
	key_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.6
	env_root.add_child(key_light)

	var rim_light: DirectionalLight3D = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-48.0, 58.0, 0.0)
	rim_light.light_color = theme_cfg["rim_color"]
	rim_light.light_energy = 0.48
	rim_light.light_specular = 0.42
	rim_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	env_root.add_child(rim_light)

	var fx_layer: CanvasLayer = CanvasLayer.new()
	fx_layer.layer = 0
	env_root.add_child(fx_layer)
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = SUBTLE_POSTFX_SHADER
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = shader
	rect.material = smat
	fx_layer.add_child(rect)

	return {"env_root": env_root, "flare_mat": smat}


static func build_estate_architecture(
	parent: Node3D,
	wall_grid: WallColliderGridLib,
	theme_cfg: Dictionary,
	vendor_pos: Vector3,
	press_pos: Vector3,
	auction_pos: Vector3,
	gate_z: float,
	extraction_pos: Vector3,
	extraction_radius: float
) -> Dictionary:
	## Registers ALL solid colliders (works in headless tests too!) AND builds 3D architecture.
	wall_grid.clear()

	var arch_root: Node3D = Node3D.new()
	arch_root.name = "PenthouseEstateArch"
	parent.add_child(arch_root)

	var gate_root: Node3D = Node3D.new()
	gate_root.name = "LaserSecurityGate"
	gate_root.position = Vector3(0.0, 0.0, gate_z)
	arch_root.add_child(gate_root)

	# --- 1. REGISTER SOLID COLLIDERS (ALWAYS runs in headless & windowed!) ---
	# Solid vendor counter footprint so nobody walks through Big Tony's booth
	wall_grid.add_box(vendor_pos.x, vendor_pos.z + 0.3, 4.1, 2.0, "vendor_booth", false)

	# 3 Architectural Zone Archway Wing Walls (wide 12m center portal; solid side wings!)
	var archway_zs: Array[float] = [42.0, 14.0, -18.0, -48.0]
	for az: float in archway_zs:
		wall_grid.add_box(-16.0, az, 18.0, 1.1, "zone_wall_west", false)
		wall_grid.add_box(16.0, az, 18.0, 1.1, "zone_wall_east", false)

	# Solid Laser Security Gate across center portal at gate_z (blocks when locked!)
	wall_grid.add_box(0.0, gate_z, 50.0, 1.1, "security_laser_gate", true)

	# 16 Grand Marble Columns (solid circular colliders r = 0.72)
	var col_zs: Array[float] = [52.0, 34.0, 22.0, 4.0, -10.0, -28.0, -40.0, -56.0]
	for cz: float in col_zs:
		wall_grid.add_circle(-19.5, cz, 0.72, "marble_column")
		wall_grid.add_circle(19.5, cz, 0.72, "marble_column")

	# 10 Solid Banquet Lounge Tables (circular colliders r = 1.45)
	var table_spots: Array[Vector3] = [
		Vector3(-14.5, 0.0, 32.0),
		Vector3(14.5, 0.0, 32.0),
		Vector3(-15.5, 0.0, 22.0),
		Vector3(15.5, 0.0, 22.0),
		Vector3(-14.5, 0.0, 5.0),
		Vector3(14.5, 0.0, 5.0),
		Vector3(-15.5, 0.0, -9.0),
		Vector3(15.5, 0.0, -12.0),
		Vector3(-14.5, 0.0, -35.0),
		Vector3(14.5, 0.0, -35.0),
	]
	for tp: Vector3 in table_spots:
		wall_grid.add_circle(tp.x, tp.z, 1.45, "banquet_table")

	# Solid Armored Limousine chassis behind extraction pad
	wall_grid.add_box(extraction_pos.x, extraction_pos.z - 4.2, 8.6, 2.8, "armored_limo", false)

	if DisplayServer.get_name() == "headless":
		return {"arch_root": arch_root, "gate_root": gate_root}

	# --- 2. BUILD RICH 3D VISUAL ARCHITECTURE ---
	var marble_mat: StandardMaterial3D = ProceduralTexturesLib.make_marble_floor_material()
	marble_mat.albedo_color = theme_cfg["marble_tint"]
	var carpet_mat: StandardMaterial3D = ProceduralTexturesLib.make_velvet_carpet_material()
	carpet_mat.albedo_color = theme_cfg["carpet_color"]
	var brass_mat: StandardMaterial3D = ProceduralTexturesLib.make_brushed_brass_material()
	var wall_mat: StandardMaterial3D = ProceduralTexturesLib.make_architectural_wall_material()
	var accent_col: Color = theme_cfg["accent_color"]

	# Massive 52m x 136m Veined Marble Floor (z = +62 .. -74)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(52.0, 0.5, 136.0)
	floor_mesh.mesh = fbox
	floor_mesh.position = Vector3(0.0, -0.25, -6.0)
	floor_mesh.material_override = marble_mat
	arch_root.add_child(floor_mesh)

	# Wide 5.8m Royal Velvet Carpet Runway + Non-Emissive Brushed Brass Trim
	var carpet: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(5.8, 0.04, 122.0)
	carpet.mesh = cbox
	carpet.position = Vector3(0.0, 0.02, -4.0)
	carpet.material_override = carpet_mat
	arch_root.add_child(carpet)

	for side_x: float in [-3.02, 3.02]:
		var trim: MeshInstance3D = MeshInstance3D.new()
		var tbox: BoxMesh = BoxMesh.new()
		tbox.size = Vector3(0.16, 0.045, 122.0)
		trim.mesh = tbox
		trim.position = Vector3(side_x, 0.022, -4.0)
		trim.material_override = brass_mat
		arch_root.add_child(trim)

	# Perimeter Glass Railings + Distant City Skyline
	_build_skyline_and_railings(arch_root, brass_mat, accent_col)

	# Render Archway Wing Walls matching WallColliderGrid exact coordinates
	for az: float in archway_zs:
		_build_zone_archway(arch_root, az, wall_mat, brass_mat, accent_col)

	# Render 16 Marble Columns & Side-Wing Chandeliers (positioned at x=+-10 so they NEVER block Follow Camera!)
	for cz: float in col_zs:
		_build_column(arch_root, Vector3(-19.5, 0.0, cz), wall_mat, brass_mat)
		_build_column(arch_root, Vector3(19.5, 0.0, cz), wall_mat, brass_mat)
		_build_chandelier(arch_root, Vector3(-10.5, 8.6, cz), brass_mat, accent_col)
		_build_chandelier(arch_root, Vector3(10.5, 8.6, cz), brass_mat, accent_col)

	# Objective Stages
	_build_objective_stage(arch_root, press_pos, "📸 PRESS PHOTO-OP STAGE (Hold VIP 3.5s)", Color(0.28, 0.84, 1.0), brass_mat)
	_build_objective_stage(arch_root, auction_pos, "🎤 CHARITY AUCTION PODIUM (Hold VIP 4.0s)", accent_col, brass_mat)

	# Banquet Tables + Chairs
	_build_banquet_tables(arch_root, table_spots, brass_mat, wall_mat)

	# Laser Security Gate Visuals
	_build_laser_gate_visuals(gate_root, brass_mat)

	# Armored Limousine + Rooftop Escape Helicopter on Helipad
	_build_extraction_plaza(arch_root, extraction_pos, extraction_radius, brass_mat)

	return {"arch_root": arch_root, "gate_root": gate_root}


static func _build_skyline_and_railings(parent: Node3D, brass_mat: StandardMaterial3D, accent_col: Color) -> void:
	var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.45, 0.68, 0.88, 0.22)
	glass_mat.roughness = 0.08

	for side_x: float in [-25.4, 25.4]:
		var glass: MeshInstance3D = MeshInstance3D.new()
		var gbox: BoxMesh = BoxMesh.new()
		gbox.size = Vector3(0.14, 1.15, 134.0)
		glass.mesh = gbox
		glass.position = Vector3(side_x, 0.6, -6.0)
		glass.material_override = glass_mat
		parent.add_child(glass)

		var rail: MeshInstance3D = MeshInstance3D.new()
		var rbox: BoxMesh = BoxMesh.new()
		rbox.size = Vector3(0.26, 0.10, 134.0)
		rail.mesh = rbox
		rail.position = Vector3(side_x, 1.22, -6.0)
		rail.material_override = brass_mat
		parent.add_child(rail)

	# South Low Glass Railing (never blocks camera!)
	var srail: MeshInstance3D = MeshInstance3D.new()
	var srbox: BoxMesh = BoxMesh.new()
	srbox.size = Vector3(51.0, 0.12, 0.24)
	srail.mesh = srbox
	srail.position = Vector3(0.0, 1.12, 61.2)
	srail.material_override = brass_mat
	parent.add_child(srail)

	# Surrounding City Skyline Silhouettes
	var tower_mat: StandardMaterial3D = StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.035, 0.045, 0.085)
	tower_mat.roughness = 0.6

	var beacon_mat: StandardMaterial3D = StandardMaterial3D.new()
	beacon_mat.albedo_color = accent_col
	beacon_mat.emission_enabled = true
	beacon_mat.emission = accent_col
	beacon_mat.emission_energy_multiplier = 1.6

	var towers: Array[Vector4] = [
		Vector4(-42.0, 26.0, -50.0, 12.0),
		Vector4(-40.0, 32.0, 0.0, 11.0),
		Vector4(-44.0, 20.0, 44.0, 12.0),
		Vector4(42.0, 28.0, -52.0, 12.0),
		Vector4(44.0, 24.0, 6.0, 11.0),
		Vector4(40.0, 30.0, 48.0, 12.0),
		Vector4(-16.0, 34.0, -96.0, 14.0),
		Vector4(16.0, 28.0, -94.0, 12.0),
	]
	for spec: Vector4 in towers:
		var bldg: MeshInstance3D = MeshInstance3D.new()
		var bbox: BoxMesh = BoxMesh.new()
		bbox.size = Vector3(spec.w, spec.y, spec.w)
		bldg.mesh = bbox
		bldg.position = Vector3(spec.x, spec.y * 0.5 - 14.0, spec.z)
		bldg.material_override = tower_mat
		parent.add_child(bldg)

		var beacon: MeshInstance3D = MeshInstance3D.new()
		var bsph: SphereMesh = SphereMesh.new()
		bsph.radius = 0.40
		beacon.mesh = bsph
		beacon.position = Vector3(spec.x, spec.y - 13.6, spec.z)
		beacon.material_override = beacon_mat
		parent.add_child(beacon)


static func _build_zone_archway(
	parent: Node3D,
	z_pos: float,
	wall_mat: StandardMaterial3D,
	brass_mat: StandardMaterial3D,
	accent_col: Color
) -> void:
	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = accent_col
	neon_mat.emission_enabled = true
	neon_mat.emission = accent_col
	neon_mat.emission_energy_multiplier = 1.35

	# Solid low architectural divider walls (2.8m tall) + grand twin portal obelisks (ZERO overhead camera occlusion!)
	for side_x: float in [-16.0, 16.0]:
		var wing: MeshInstance3D = MeshInstance3D.new()
		var wbox: BoxMesh = BoxMesh.new()
		wbox.size = Vector3(18.0, 2.7, 1.0)
		wing.mesh = wbox
		wing.position = Vector3(side_x, 1.35, z_pos)
		wing.material_override = wall_mat
		parent.add_child(wing)

		var accent_bar: MeshInstance3D = MeshInstance3D.new()
		var abox: BoxMesh = BoxMesh.new()
		abox.size = Vector3(17.8, 0.10, 1.08)
		accent_bar.mesh = abox
		accent_bar.position = Vector3(side_x, 2.72, z_pos)
		accent_bar.material_override = neon_mat
		parent.add_child(accent_bar)

	# Twin Brass-Capped Portal Pillars framing the 14m open runway
	for px: float in [-7.1, 7.1]:
		var obelisk: MeshInstance3D = MeshInstance3D.new()
		var obox: BoxMesh = BoxMesh.new()
		obox.size = Vector3(0.85, 3.6, 1.15)
		obelisk.mesh = obox
		obelisk.position = Vector3(px, 1.8, z_pos)
		obelisk.material_override = brass_mat
		parent.add_child(obelisk)

	# Glowing Floor Threshold Line across portal entrance
	var thresh: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(13.6, 0.05, 0.26)
	thresh.mesh = tbox
	thresh.position = Vector3(0.0, 0.025, z_pos)
	thresh.material_override = neon_mat
	parent.add_child(thresh)


static func _build_column(parent: Node3D, pos: Vector3, wall_mat: StandardMaterial3D, brass_mat: StandardMaterial3D) -> void:
	var pillar: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.58
	cyl.bottom_radius = 0.68
	cyl.height = 8.0
	pillar.mesh = cyl
	pillar.position = pos + Vector3(0.0, 4.0, 0.0)
	pillar.material_override = wall_mat
	parent.add_child(pillar)

	var collar: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.60
	torus.outer_radius = 0.74
	collar.mesh = torus
	collar.position = pos + Vector3(0.0, 1.9, 0.0)
	collar.material_override = brass_mat
	parent.add_child(collar)


static func _build_chandelier(parent: Node3D, pos: Vector3, brass_mat: StandardMaterial3D, accent_col: Color) -> void:
	var chand: Node3D = Node3D.new()
	chand.position = pos
	parent.add_child(chand)

	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = accent_col.lightened(0.45)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = accent_col.lightened(0.25)
	bulb_mat.emission_energy_multiplier = 1.75

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.2
	torus.outer_radius = 1.38
	ring.mesh = torus
	ring.material_override = brass_mat
	chand.add_child(ring)

	for i: int in range(6):
		var ang: float = float(i) * (TAU / 6.0)
		var crystal: MeshInstance3D = MeshInstance3D.new()
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = 0.14
		crystal.mesh = sph
		crystal.position = Vector3(cos(ang) * 1.28, -0.18, sin(ang) * 1.28)
		crystal.material_override = bulb_mat
		chand.add_child(crystal)

	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.90, 0.75)
	light.light_energy = 1.65
	light.light_specular = 0.9
	light.omni_range = 20.0
	chand.add_child(light)


static func _build_objective_stage(
	parent: Node3D,
	pos: Vector3,
	title: String,
	accent: Color,
	brass_mat: StandardMaterial3D
) -> void:
	var stage: Node3D = Node3D.new()
	stage.position = pos
	parent.add_child(stage)

	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = accent
	ring_mat.emission_enabled = true
	ring_mat.emission = accent
	ring_mat.emission_energy_multiplier = 1.4

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 2.6
	torus.outer_radius = 2.82
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.06, 0.0)
	ring.material_override = ring_mat
	stage.add_child(ring)

	var podium: MeshInstance3D = MeshInstance3D.new()
	var pbox: BoxMesh = BoxMesh.new()
	pbox.size = Vector3(1.05, 1.15, 0.58)
	podium.mesh = pbox
	podium.position = Vector3(0.0, 0.58, -1.8)
	podium.material_override = brass_mat
	stage.add_child(podium)

	var lbl: Label3D = Label3D.new()
	lbl.position = Vector3(0.0, 2.85, -1.6)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 24
	lbl.outline_size = 8
	lbl.text = title
	lbl.modulate = accent.lightened(0.2)
	stage.add_child(lbl)


static func _build_banquet_tables(
	parent: Node3D,
	spots: Array[Vector3],
	brass_mat: StandardMaterial3D,
	wall_mat: StandardMaterial3D
) -> void:
	var cloth_mat: StandardMaterial3D = StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.18, 0.20, 0.28)
	cloth_mat.roughness = 0.72

	for p: Vector3 in spots:
		var tbl: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.3
		cyl.height = 0.96
		tbl.mesh = cyl
		tbl.position = p + Vector3(0.0, 0.48, 0.0)
		tbl.material_override = cloth_mat
		parent.add_child(tbl)

		var rim: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 1.35
		torus.outer_radius = 1.44
		rim.mesh = torus
		rim.position = p + Vector3(0.0, 0.97, 0.0)
		rim.material_override = brass_mat
		parent.add_child(rim)

		var vase: MeshInstance3D = MeshInstance3D.new()
		var vcyl: CylinderMesh = CylinderMesh.new()
		vcyl.top_radius = 0.14
		vcyl.bottom_radius = 0.22
		vcyl.height = 0.44
		vase.mesh = vcyl
		vase.position = p + Vector3(0.0, 1.18, 0.0)
		vase.material_override = wall_mat
		parent.add_child(vase)


static func _build_laser_gate_visuals(gate_root: Node3D, brass_mat: StandardMaterial3D) -> void:
	var laser_mat: StandardMaterial3D = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(1.0, 0.14, 0.20)
	laser_mat.emission_enabled = true
	laser_mat.emission = Color(1.0, 0.12, 0.18)
	laser_mat.emission_energy_multiplier = 2.0

	for side_x: float in [-6.8, 6.8]:
		var pylon: MeshInstance3D = MeshInstance3D.new()
		var pbox: BoxMesh = BoxMesh.new()
		pbox.size = Vector3(0.65, 3.0, 0.65)
		pylon.mesh = pbox
		pylon.position = Vector3(side_x, 1.5, 0.0)
		pylon.material_override = brass_mat
		gate_root.add_child(pylon)

	for h_idx: int in range(3):
		var beam: MeshInstance3D = MeshInstance3D.new()
		var bbox: BoxMesh = BoxMesh.new()
		bbox.size = Vector3(13.6, 0.09, 0.09)
		beam.mesh = bbox
		beam.position = Vector3(0.0, 0.55 + float(h_idx) * 0.78, 0.0)
		beam.material_override = laser_mat
		gate_root.add_child(beam)

	var lbl: Label3D = Label3D.new()
	lbl.position = Vector3(0.0, 3.3, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 24
	lbl.outline_size = 8
	lbl.text = "🔒 SOLID LASER GATE — GRAB GOLD KEYCARD IN EAST VAULT!"
	lbl.modulate = Color(1.0, 0.32, 0.32)
	gate_root.add_child(lbl)


static func _build_extraction_plaza(
	parent: Node3D,
	extraction_pos: Vector3,
	extraction_radius: float,
	brass_mat: StandardMaterial3D
) -> void:
	var pad_mat: StandardMaterial3D = StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.18, 0.95, 0.56)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.14, 0.85, 0.48)
	pad_mat.emission_energy_multiplier = 1.5

	var pad_ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = extraction_radius - 0.16
	torus.outer_radius = extraction_radius
	pad_ring.mesh = torus
	pad_ring.position = extraction_pos + Vector3(0.0, 0.06, 0.0)
	pad_ring.material_override = pad_mat
	parent.add_child(pad_ring)

	# Detailed Armored Stretch Limousine (chassis, tinted cabin, 4 alloy wheels, xenon lights)
	var limo_root: Node3D = Node3D.new()
	limo_root.position = extraction_pos + Vector3(0.0, 0.0, -4.2)
	parent.add_child(limo_root)

	var limo_paint: StandardMaterial3D = StandardMaterial3D.new()
	limo_paint.albedo_color = Color(0.04, 0.05, 0.08)
	limo_paint.metallic = 0.85
	limo_paint.roughness = 0.16
	limo_paint.clearcoat_enabled = true
	limo_paint.clearcoat = 0.75

	var chassis: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(8.4, 0.95, 2.5)
	chassis.mesh = cbox
	chassis.position = Vector3(0.0, 0.78, 0.0)
	chassis.material_override = limo_paint
	limo_root.add_child(chassis)

	var cabin: MeshInstance3D = MeshInstance3D.new()
	var kbox: BoxMesh = BoxMesh.new()
	kbox.size = Vector3(5.4, 0.76, 2.15)
	cabin.mesh = kbox
	cabin.position = Vector3(0.0, 1.56, 0.0)
	cabin.material_override = limo_paint
	limo_root.add_child(cabin)

	var trim: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(8.5, 0.09, 2.56)
	trim.mesh = tbox
	trim.position = Vector3(0.0, 0.88, 0.0)
	trim.material_override = brass_mat
	limo_root.add_child(trim)

	# 4 Wheels with Brass Rims
	var tire_mat: StandardMaterial3D = StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.06, 0.06, 0.07)
	tire_mat.roughness = 0.8
	for wx: float in [-2.8, 2.8]:
		for wz: float in [-1.25, 1.25]:
			var wh: MeshInstance3D = MeshInstance3D.new()
			var wcyl: CylinderMesh = CylinderMesh.new()
			wcyl.top_radius = 0.42
			wcyl.bottom_radius = 0.42
			wcyl.height = 0.24
			wh.mesh = wcyl
			wh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			wh.position = Vector3(wx, 0.42, wz)
			wh.material_override = tire_mat
			limo_root.add_child(wh)

	var xenon_mat: StandardMaterial3D = StandardMaterial3D.new()
	xenon_mat.albedo_color = Color(0.88, 0.96, 1.0)
	xenon_mat.emission_enabled = true
	xenon_mat.emission = Color(0.75, 0.92, 1.0)
	xenon_mat.emission_energy_multiplier = 2.0

	for z_hl: float in [-0.82, 0.82]:
		var hl: MeshInstance3D = MeshInstance3D.new()
		var hsph: SphereMesh = SphereMesh.new()
		hsph.radius = 0.20
		hl.mesh = hsph
		hl.position = Vector3(4.22, 0.82, z_hl)
		hl.material_override = xenon_mat
		limo_root.add_child(hl)

	var lbl: Label3D = Label3D.new()
	lbl.position = Vector3(0.0, 3.1, 2.2)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 26
	lbl.outline_size = 8
	lbl.text = "🚘 ARMORED LIMO EXTRACTION (HOLD 5.0s -> NEXT LEVEL!)"
	lbl.modulate = Color(0.32, 1.0, 0.65)
	limo_root.add_child(lbl)
