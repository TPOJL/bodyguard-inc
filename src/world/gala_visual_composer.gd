class_name GalaVisualComposer
extends RefCounted
## Tasteful Noir-Luxury Forward+ Environment ("Норм Блики" — ZERO blinding whiteout!),
## Procedural Calacatta Marble PBR Floor, City Skyline, 4-Zone 104m Penthouse Estate,
## Press Photo-Op Stage, Charity Auction Podium, Laser Security Gate & Armored Limousine.

const ProceduralTexturesLib := preload("res://src/world/procedural_textures.gd")

const SUBTLE_POSTFX_SHADER: String = """
shader_type canvas_item;

uniform float danger_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float flash_burst : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);

	// Clean optical lens vignette (never washes out the center!)
	float vig = smoothstep(0.46, 0.92, dist) * 0.32;

	// Localized crimson edge warning only when danger/suspicion is high
	float edge = smoothstep(0.38, 0.84, dist);
	vec3 danger_col = vec3(0.85, 0.10, 0.14) * edge * danger_pulse * 0.42;

	// Restrained warm champagne/camera glint (capped so it NEVER blinds!)
	vec3 flash_col = vec3(1.0, 0.95, 0.84) * flash_burst * 0.20;

	vec3 rgb = mix(vec3(0.01, 0.015, 0.03), danger_col + flash_col, clamp(length(danger_col + flash_col) * 2.2, 0.0, 1.0));
	float alpha = clamp(vig + length(danger_col) + flash_burst * 0.18, 0.0, 0.55);
	COLOR = vec4(rgb, alpha);
}
"""


static func build_hdr_environment(parent: Node3D) -> ShaderMaterial:
	if DisplayServer.get_name() == "headless":
		return null

	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.name = "NoirLuxuryEnvironment"
	var env: Environment = Environment.new()

	# Rich Penthouse Twilight Procedural Sky -> gives metallic gold/brass/limo gorgeous reflections!
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.06, 0.14)
	sky_mat.sky_horizon_color = Color(0.22, 0.18, 0.28)
	sky_mat.ground_bottom_color = Color(0.04, 0.05, 0.09)
	sky_mat.ground_horizon_color = Color(0.14, 0.13, 0.20)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.72
	env.ambient_light_energy = 0.85

	# Balanced ACES Filmic Tonemapping
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.04
	env.tonemap_white = 8.0

	# Tasteful, Controlled Specular Glow & Glints ("Норм Блики") — NO whiteout!
	env.glow_enabled = true
	env.set_glow_level(0, false)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	env.set_glow_level(4, false)
	env.set_glow_level(5, false)
	env.glow_intensity = 0.28
	env.glow_strength = 0.65
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.45
	env.glow_hdr_scale = 1.15

	# Subtle Screen-Space Reflections on procedural marble veins
	env.ssr_enabled = true
	env.ssr_max_steps = 40
	env.ssr_fade_in = 0.22
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.22

	# Grounded Contact Shadows via SSAO
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.6

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08

	env_node.environment = env
	parent.add_child(env_node)

	# Crisp Moonlight Key Light (SKY_MODE_LIGHT_ONLY prevents burning a giant sun disk into the marble floor!)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.name = "MoonlightKey"
	key_light.rotation_degrees = Vector3(-56.0, 26.0, 0.0)
	key_light.light_color = Color(0.88, 0.92, 1.0)
	key_light.light_energy = 0.95
	key_light.light_specular = 0.45
	key_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.6
	parent.add_child(key_light)

	# Warm Penthouse Side-Key Fill (crisp golden glints on brass & suits, zero camera-axis glare blob!)
	var rim_light: DirectionalLight3D = DirectionalLight3D.new()
	rim_light.name = "WarmSpecularRim"
	rim_light.rotation_degrees = Vector3(-48.0, 58.0, 0.0)
	rim_light.light_color = Color(1.0, 0.84, 0.62)
	rim_light.light_energy = 0.48
	rim_light.light_specular = 0.45
	rim_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(rim_light)

	return _build_post_fx_layer(parent)


static func _build_post_fx_layer(parent: Node3D) -> ShaderMaterial:
	var fx_layer: CanvasLayer = CanvasLayer.new()
	fx_layer.name = "PostFXLayer"
	fx_layer.layer = 0
	parent.add_child(fx_layer)

	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = SUBTLE_POSTFX_SHADER
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = shader
	rect.material = smat
	fx_layer.add_child(rect)
	return smat


static func build_estate_architecture(
	parent: Node3D,
	press_pos: Vector3,
	auction_pos: Vector3,
	gate_z: float,
	extraction_pos: Vector3,
	extraction_radius: float
) -> Node3D:
	## Builds the 4-Zone 104m Penthouse Gala Estate. Returns the retractable Laser Security Gate node.
	var gate_root: Node3D = Node3D.new()
	gate_root.name = "LaserSecurityGate"
	gate_root.position = Vector3(0.0, 0.0, gate_z)
	parent.add_child(gate_root)

	if DisplayServer.get_name() == "headless":
		return gate_root

	var arch: Node3D = Node3D.new()
	arch.name = "PenthouseEstateArch"
	parent.add_child(arch)

	var marble_mat: StandardMaterial3D = ProceduralTexturesLib.make_marble_floor_material()
	var carpet_mat: StandardMaterial3D = ProceduralTexturesLib.make_velvet_carpet_material()
	var brass_mat: StandardMaterial3D = ProceduralTexturesLib.make_brushed_brass_material()
	var wall_mat: StandardMaterial3D = ProceduralTexturesLib.make_architectural_wall_material()

	# 1. Main 104m x 32m Procedural Calacatta Marble Floor (z = +50 .. -56)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(32.0, 0.5, 108.0)
	floor_mesh.mesh = fbox
	floor_mesh.position = Vector3(0.0, -0.25, -3.0)
	floor_mesh.material_override = marble_mat
	arch.add_child(floor_mesh)

	# 2. Royal Red Velvet Carpet Runway (high roughness -> rich velvet, ZERO glare!)
	var carpet: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(4.6, 0.04, 96.0)
	carpet.mesh = cbox
	carpet.position = Vector3(0.0, 0.02, -1.0)
	carpet.material_override = carpet_mat
	arch.add_child(carpet)

	# 3. Brushed Physical Brass Floor Trim (NON-emissive -> catches tasteful moving glints!)
	for side_x: float in [-2.42, 2.42]:
		var trim: MeshInstance3D = MeshInstance3D.new()
		var tbox: BoxMesh = BoxMesh.new()
		tbox.size = Vector3(0.14, 0.045, 96.0)
		trim.mesh = tbox
		trim.position = Vector3(side_x, 0.022, -1.0)
		trim.material_override = brass_mat
		arch.add_child(trim)

	# 4. Perimeter Glass Balcony Railings + Distant City Skyline Silhouette
	_build_skyline_and_perimeter(arch, brass_mat, wall_mat)

	# 5. Architectural Zone Archways separating the 4 Estate Zones
	for arch_z: float in [20.0, -8.0, -34.0]:
		_build_zone_archway(arch, arch_z, wall_mat, brass_mat)

	# 6. Fluted Marble Columns & Overhead Chandeliers (warm soft pools, NO glare overload)
	for z_col: float in [40.0, 26.0, 12.0, -2.0, -16.0, -28.0, -40.0]:
		for x_col: float in [-12.5, 12.5]:
			_build_column(arch, Vector3(x_col, 0.0, z_col), wall_mat, brass_mat)
		if int(z_col) % 24 != 0:
			_build_chandelier(arch, Vector3(0.0, 7.8, z_col), brass_mat)

	# 7. Mandatory Objective #1: VIP Press Photo-Op Stage (Zone 1)
	_build_objective_stage(arch, press_pos, "📸 PRESS PHOTO-OP STAGE (Hold VIP 3.5s)", Color(0.28, 0.78, 1.0), brass_mat)

	# 8. Mandatory Objective #2: Charity Auction Podium (Zone 2)
	_build_objective_stage(arch, auction_pos, "🎤 CHARITY AUCTION PODIUM (Hold VIP 4.0s)", Color(1.0, 0.76, 0.24), brass_mat)

	# 9. Banquet Lounge Tables with Subtle Glassware Props
	_build_banquet_tables(arch, brass_mat, wall_mat)

	# 10. Retractable Laser Security Gate (Zone 3 — requires Gold Keycard!)
	_build_laser_gate_visuals(gate_root, brass_mat)

	# 11. Armored Luxury Limousine & Extraction Plaza (Zone 4)
	_build_extraction_limousine(arch, extraction_pos, extraction_radius, brass_mat)

	return gate_root


static func _build_skyline_and_perimeter(parent: Node3D, brass_mat: StandardMaterial3D, wall_mat: StandardMaterial3D) -> void:
	# Low perimeter brass+glass balustrades along east/west edges
	var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.45, 0.65, 0.85, 0.22)
	glass_mat.roughness = 0.08
	glass_mat.metallic = 0.15

	for side_x: float in [-15.2, 15.2]:
		var glass: MeshInstance3D = MeshInstance3D.new()
		var gbox: BoxMesh = BoxMesh.new()
		gbox.size = Vector3(0.14, 1.15, 106.0)
		glass.mesh = gbox
		glass.position = Vector3(side_x, 0.6, -3.0)
		glass.material_override = glass_mat
		parent.add_child(glass)

		var rail: MeshInstance3D = MeshInstance3D.new()
		var rbox: BoxMesh = BoxMesh.new()
		rbox.size = Vector3(0.24, 0.10, 106.0)
		rail.mesh = rbox
		rail.position = Vector3(side_x, 1.22, -3.0)
		rail.material_override = brass_mat
		parent.add_child(rail)

	# Distant Midnight City Skyline Towers around the penthouse
	var tower_mat: StandardMaterial3D = StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.03, 0.04, 0.075)
	tower_mat.roughness = 0.6

	var beacon_mat: StandardMaterial3D = StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(1.0, 0.22, 0.24)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.18, 0.20)
	beacon_mat.emission_energy_multiplier = 1.8

	var skyline_specs: Array[Vector4] = [
		Vector4(-32.0, 18.0, -35.0, 10.0),
		Vector4(-28.0, 26.0, 5.0, 9.0),
		Vector4(-34.0, 15.0, 38.0, 11.0),
		Vector4(30.0, 24.0, -40.0, 10.0),
		Vector4(33.0, 19.0, -5.0, 9.0),
		Vector4(29.0, 28.0, 34.0, 11.0),
		Vector4(-14.0, 30.0, -76.0, 12.0),
		Vector4(12.0, 24.0, -74.0, 10.0),
	]
	for spec: Vector4 in skyline_specs:
		var bldg: MeshInstance3D = MeshInstance3D.new()
		var bbox: BoxMesh = BoxMesh.new()
		bbox.size = Vector3(spec.w, spec.y, spec.w)
		bldg.mesh = bbox
		bldg.position = Vector3(spec.x, spec.y * 0.5 - 12.0, spec.z)
		bldg.material_override = tower_mat
		parent.add_child(bldg)

		var beacon: MeshInstance3D = MeshInstance3D.new()
		var bsph: SphereMesh = SphereMesh.new()
		bsph.radius = 0.35
		beacon.mesh = bsph
		beacon.position = Vector3(spec.x, spec.y - 11.6, spec.z)
		beacon.material_override = beacon_mat
		parent.add_child(beacon)

	# Low glass-and-brass terrace railing behind South spawn (never blocks camera view!)
	var south_glass: MeshInstance3D = MeshInstance3D.new()
	var sgbox: BoxMesh = BoxMesh.new()
	sgbox.size = Vector3(31.0, 1.05, 0.14)
	south_glass.mesh = sgbox
	south_glass.position = Vector3(0.0, 0.55, 51.2)
	south_glass.material_override = glass_mat
	parent.add_child(south_glass)

	var south_rail: MeshInstance3D = MeshInstance3D.new()
	var srbox: BoxMesh = BoxMesh.new()
	srbox.size = Vector3(31.0, 0.10, 0.24)
	south_rail.mesh = srbox
	south_rail.position = Vector3(0.0, 1.12, 51.2)
	south_rail.material_override = brass_mat
	parent.add_child(south_rail)


static func _build_zone_archway(parent: Node3D, z_pos: float, wall_mat: StandardMaterial3D, brass_mat: StandardMaterial3D) -> void:
	# Side wing walls leaving a grand 11m central gala portal
	for side_x: float in [-10.4, 10.4]:
		var wing: MeshInstance3D = MeshInstance3D.new()
		var wbox: BoxMesh = BoxMesh.new()
		wbox.size = Vector3(9.6, 4.6, 0.7)
		wing.mesh = wbox
		wing.position = Vector3(side_x, 2.3, z_pos)
		wing.material_override = wall_mat
		parent.add_child(wing)

	var lintel: MeshInstance3D = MeshInstance3D.new()
	var lbox: BoxMesh = BoxMesh.new()
	lbox.size = Vector3(12.2, 0.75, 0.95)
	lintel.mesh = lbox
	lintel.position = Vector3(0.0, 4.85, z_pos)
	lintel.material_override = brass_mat
	parent.add_child(lintel)


static func _build_column(parent: Node3D, pos: Vector3, wall_mat: StandardMaterial3D, brass_mat: StandardMaterial3D) -> void:
	var pillar: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.52
	cyl.bottom_radius = 0.62
	cyl.height = 7.6
	pillar.mesh = cyl
	pillar.position = pos + Vector3(0.0, 3.8, 0.0)
	pillar.material_override = wall_mat
	parent.add_child(pillar)

	var collar: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.54
	torus.outer_radius = 0.68
	collar.mesh = torus
	collar.position = pos + Vector3(0.0, 1.9, 0.0)
	collar.material_override = brass_mat
	parent.add_child(collar)


static func _build_chandelier(parent: Node3D, pos: Vector3, brass_mat: StandardMaterial3D) -> void:
	var chand: Node3D = Node3D.new()
	chand.position = pos
	parent.add_child(chand)

	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.94, 0.80)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.86, 0.62)
	bulb_mat.emission_energy_multiplier = 1.95

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.15
	torus.outer_radius = 1.32
	ring.mesh = torus
	ring.material_override = brass_mat
	chand.add_child(ring)

	for i: int in range(6):
		var ang: float = float(i) * (TAU / 6.0)
		var crystal: MeshInstance3D = MeshInstance3D.new()
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = 0.14
		crystal.mesh = sph
		crystal.position = Vector3(cos(ang) * 1.22, -0.18, sin(ang) * 1.22)
		crystal.material_override = bulb_mat
		chand.add_child(crystal)

	# Controlled warm overhead pool light (energy 1.75 -> lush highlights, ZERO whiteout!)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.89, 0.72)
	light.light_energy = 1.75
	light.light_specular = 1.2
	light.omni_range = 17.0
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
	ring_mat.emission_energy_multiplier = 1.45

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 2.45
	torus.outer_radius = 2.65
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.06, 0.0)
	ring.material_override = ring_mat
	stage.add_child(ring)

	var podium: MeshInstance3D = MeshInstance3D.new()
	var pbox: BoxMesh = BoxMesh.new()
	pbox.size = Vector3(0.95, 1.15, 0.55)
	podium.mesh = pbox
	podium.position = Vector3(0.0, 0.58, -1.65)
	podium.material_override = brass_mat
	stage.add_child(podium)

	var lbl: Label3D = Label3D.new()
	lbl.position = Vector3(0.0, 2.75, -1.5)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 24
	lbl.outline_size = 8
	lbl.text = title
	lbl.modulate = accent.lightened(0.2)
	stage.add_child(lbl)


static func _build_banquet_tables(parent: Node3D, brass_mat: StandardMaterial3D, wall_mat: StandardMaterial3D) -> void:
	var cloth_mat: StandardMaterial3D = StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.18, 0.20, 0.28)
	cloth_mat.roughness = 0.72

	var spots: Array[Vector3] = [
		Vector3(-10.8, 0.0, 37.5),
		Vector3(10.8, 0.0, 37.5),
		Vector3(-10.8, 0.0, 15.0),
		Vector3(10.8, 0.0, 15.0),
		Vector3(-10.8, 0.0, -3.5),
		Vector3(10.8, 0.0, -10.0),
	]
	for p: Vector3 in spots:
		var tbl: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 1.35
		cyl.bottom_radius = 1.25
		cyl.height = 0.95
		tbl.mesh = cyl
		tbl.position = p + Vector3(0.0, 0.48, 0.0)
		tbl.material_override = cloth_mat
		parent.add_child(tbl)

		var rim: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 1.30
		torus.outer_radius = 1.38
		rim.mesh = torus
		rim.position = p + Vector3(0.0, 0.96, 0.0)
		rim.material_override = brass_mat
		parent.add_child(rim)

		var vase: MeshInstance3D = MeshInstance3D.new()
		var vcyl: CylinderMesh = CylinderMesh.new()
		vcyl.top_radius = 0.12
		vcyl.bottom_radius = 0.20
		vcyl.height = 0.42
		vase.mesh = vcyl
		vase.position = p + Vector3(0.0, 1.16, 0.0)
		vase.material_override = wall_mat
		parent.add_child(vase)


static func _build_laser_gate_visuals(gate_root: Node3D, brass_mat: StandardMaterial3D) -> void:
	var laser_mat: StandardMaterial3D = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(1.0, 0.14, 0.20)
	laser_mat.emission_enabled = true
	laser_mat.emission = Color(1.0, 0.12, 0.18)
	laser_mat.emission_energy_multiplier = 2.0

	for side_x: float in [-5.6, 5.6]:
		var pylon: MeshInstance3D = MeshInstance3D.new()
		var pbox: BoxMesh = BoxMesh.new()
		pbox.size = Vector3(0.55, 2.8, 0.55)
		pylon.mesh = pbox
		pylon.position = Vector3(side_x, 1.4, 0.0)
		pylon.material_override = brass_mat
		gate_root.add_child(pylon)

	for h_idx: int in range(3):
		var beam: MeshInstance3D = MeshInstance3D.new()
		var bbox: BoxMesh = BoxMesh.new()
		bbox.size = Vector3(11.0, 0.08, 0.08)
		beam.mesh = bbox
		beam.position = Vector3(0.0, 0.55 + float(h_idx) * 0.72, 0.0)
		beam.material_override = laser_mat
		gate_root.add_child(beam)

	var lbl: Label3D = Label3D.new()
	lbl.position = Vector3(0.0, 3.1, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 24
	lbl.outline_size = 8
	lbl.text = "🔒 SECURITY LASER GATE — GRAB GOLD KEYCARD IN EAST LOUNGE!"
	lbl.modulate = Color(1.0, 0.32, 0.32)
	gate_root.add_child(lbl)


static func _build_extraction_limousine(
	parent: Node3D,
	extraction_pos: Vector3,
	extraction_radius: float,
	brass_mat: StandardMaterial3D
) -> void:
	var pad_mat: StandardMaterial3D = StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.18, 0.95, 0.56)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.14, 0.85, 0.48)
	pad_mat.emission_energy_multiplier = 1.55

	var pad_ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = extraction_radius - 0.16
	torus.outer_radius = extraction_radius
	pad_ring.mesh = torus
	pad_ring.position = extraction_pos + Vector3(0.0, 0.06, 0.0)
	pad_ring.material_override = pad_mat
	parent.add_child(pad_ring)

	var limo_root: Node3D = Node3D.new()
	limo_root.name = "ArmoredLimousine"
	limo_root.position = extraction_pos + Vector3(0.0, 0.0, -4.0)
	parent.add_child(limo_root)

	var limo_paint: StandardMaterial3D = StandardMaterial3D.new()
	limo_paint.albedo_color = Color(0.04, 0.05, 0.08)
	limo_paint.metallic = 0.88
	limo_paint.roughness = 0.14
	limo_paint.clearcoat_enabled = true
	limo_paint.clearcoat = 0.85
	limo_paint.clearcoat_roughness = 0.08

	var chassis: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(8.2, 1.05, 2.4)
	chassis.mesh = cbox
	chassis.position = Vector3(0.0, 0.72, 0.0)
	chassis.material_override = limo_paint
	limo_root.add_child(chassis)

	var cabin: MeshInstance3D = MeshInstance3D.new()
	var kbox: BoxMesh = BoxMesh.new()
	kbox.size = Vector3(5.4, 0.82, 2.1)
	cabin.mesh = kbox
	cabin.position = Vector3(0.0, 1.52, 0.0)
	cabin.material_override = limo_paint
	limo_root.add_child(cabin)

	var trim: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(8.3, 0.09, 2.46)
	trim.mesh = tbox
	trim.position = Vector3(0.0, 0.85, 0.0)
	trim.material_override = brass_mat
	limo_root.add_child(trim)

	# Tasteful HDR Xenon Headlights (2.2 emission -> crisp lens glint, NO nuclear sun!)
	var xenon_mat: StandardMaterial3D = StandardMaterial3D.new()
	xenon_mat.albedo_color = Color(0.88, 0.96, 1.0)
	xenon_mat.emission_enabled = true
	xenon_mat.emission = Color(0.75, 0.92, 1.0)
	xenon_mat.emission_energy_multiplier = 2.2

	for z_hl: float in [-0.82, 0.82]:
		var hl: MeshInstance3D = MeshInstance3D.new()
		var hsph: SphereMesh = SphereMesh.new()
		hsph.radius = 0.20
		hl.mesh = hsph
		hl.position = Vector3(4.12, 0.82, z_hl)
		hl.material_override = xenon_mat
		limo_root.add_child(hl)

	var lbl: Label3D = Label3D.new()
	lbl.position = Vector3(0.0, 3.0, 2.2)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 26
	lbl.outline_size = 8
	lbl.text = "🚘 ARMORED LIMOUSINE EXTRACTION (HOLD 5.0s)"
	lbl.modulate = Color(0.32, 1.0, 0.65)
	limo_root.add_child(lbl)
