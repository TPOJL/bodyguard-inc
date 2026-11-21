class_name GalaVisualComposer
extends RefCounted
## AAA-Stylized Forward+ Visual Environment, HDR Glare/Bloom ("БЛИКИ"), SSR Marble Floor,
## Crystal Chandeliers, Velvet Ropes, Neon Bar, and Armored Extraction Limousine Builder.
## Skips GPU mesh/light allocation automatically when running in `--headless` test mode.

const FLARE_SHADER_CODE: String = """
shader_type canvas_item;

uniform float glare_intensity : hint_range(0.0, 2.0) = 0.65;
uniform float danger_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float flash_burst : hint_range(0.0, 1.0) = 0.0;
uniform float time_sec = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);

	// Anamorphic horizontal cinema lens flare streaks across top chandelier zone
	float streak1 = exp(-abs(uv.y - 0.16) * 42.0) * exp(-abs(uv.x - 0.5) * 2.4) * 0.22;
	float streak2 = exp(-abs(uv.y - 0.22) * 55.0) * exp(-abs(uv.x - 0.28 - sin(time_sec * 0.7) * 0.08) * 4.5) * 0.16;
	float streak3 = exp(-abs(uv.y - 0.22) * 55.0) * exp(-abs(uv.x - 0.72 + cos(time_sec * 0.7) * 0.08) * 4.5) * 0.16;
	vec3 anamorphic = vec3(1.0, 0.86, 0.55) * (streak1 + streak2 + streak3) * glare_intensity;

	// Corner specular lens glints
	float glint = smoothstep(0.55, 0.0, dist) * 0.04 * glare_intensity;
	vec3 col = anamorphic + vec3(0.35, 0.65, 1.0) * glint;

	// Danger red edge pulse when suspicion or sniper lock is high
	float edge = smoothstep(0.32, 0.78, dist);
	col += vec3(0.95, 0.12, 0.18) * edge * danger_pulse * 0.55;

	// Paparazzi / impact white-gold flash glare burst
	col += vec3(1.0, 0.96, 0.85) * flash_burst * 0.75;

	// Subtle cinematic vignette
	float vig = smoothstep(0.45, 0.88, dist) * 0.35;
	float alpha = clamp(length(col) + vig + flash_burst * 0.45, 0.0, 0.78);
	vec3 final_rgb = mix(vec3(0.02, 0.02, 0.05), col / max(alpha, 0.001), clamp(length(col) * 1.6, 0.0, 1.0));
	COLOR = vec4(final_rgb, alpha);
}
"""


static func build_hdr_environment(parent: Node3D) -> ShaderMaterial:
	if DisplayServer.get_name() == "headless":
		return null

	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.name = "ForwardPlusHDREnvironment"
	var env: Environment = Environment.new()

	# Deep night penthouse skyline background
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.34)
	env.ambient_light_energy = 0.85

	# ACES Filmic Tonemapping for rich HDR highlights
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.18
	env.tonemap_white = 6.0

	# HDR Glow, Bloom & Anamorphic Glare ("БЛИКИ")
	env.glow_enabled = true
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, true)
	env.set_glow_level(4, true)
	env.set_glow_level(5, true)
	env.glow_intensity = 1.45
	env.glow_strength = 1.12
	env.glow_bloom = 0.28
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.82
	env.glow_hdr_scale = 1.8

	# Real-time Screen-Space Reflections (SSR) on polished marble floor
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25

	# SSAO + SSIL + SDFGI for realistic contact shadows & bounce light
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.4
	env.ssil_enabled = true
	env.ssil_radius = 3.5
	env.ssil_intensity = 1.1
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.1

	# Volumetric Fog for spotlight beams, sniper laser & glare halos
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.015
	env.volumetric_fog_albedo = Color(0.16, 0.19, 0.30)
	env.volumetric_fog_emission = Color(0.02, 0.03, 0.06)
	env.volumetric_fog_anisotropy = 0.68

	# Color adjustments for crisp contrast & saturation
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.18

	env_node.environment = env

	var cam_attr: CameraAttributesPractical = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 32.0
	cam_attr.dof_blur_far_transition = 14.0
	cam_attr.dof_blur_amount = 0.06
	env_node.camera_attributes = cam_attr
	parent.add_child(env_node)

	# Key Moonlight / Penthouse Skylight DirectionalLight3D
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.name = "PenthouseKeyLight"
	key_light.rotation_degrees = Vector3(-54.0, 32.0, 0.0)
	key_light.light_color = Color(0.85, 0.90, 1.0)
	key_light.light_energy = 1.25
	key_light.light_specular = 1.8
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.5
	parent.add_child(key_light)

	# Warm Rim DirectionalLight3D for dramatic character silhouettes & specular glints
	var rim_light: DirectionalLight3D = DirectionalLight3D.new()
	rim_light.name = "GoldenRimLight"
	rim_light.rotation_degrees = Vector3(-28.0, -145.0, 0.0)
	rim_light.light_color = Color(1.0, 0.78, 0.48)
	rim_light.light_energy = 0.75
	rim_light.light_specular = 2.2
	parent.add_child(rim_light)

	return _build_post_fx_flare_layer(parent)


static func _build_post_fx_flare_layer(parent: Node3D) -> ShaderMaterial:
	var fx_layer: CanvasLayer = CanvasLayer.new()
	fx_layer.name = "AnamorphicFlareLayer"
	fx_layer.layer = 0
	parent.add_child(fx_layer)

	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = FLARE_SHADER_CODE
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = shader
	rect.material = smat
	fx_layer.add_child(rect)
	return smat


static func build_penthouse_architecture(parent: Node3D, extraction_pos: Vector3, extraction_radius: float) -> void:
	if DisplayServer.get_name() == "headless":
		return

	var arch_root: Node3D = Node3D.new()
	arch_root.name = "PenthouseArchitecture"
	parent.add_child(arch_root)

	# 1. Polished Mirror-Reflective Obsidian Marble Floor
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(30.0, 0.4, 38.0)
	floor_mesh.mesh = fbox
	floor_mesh.position = Vector3(0.0, -0.2, 0.0)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.07, 0.08, 0.12)
	floor_mat.metallic = 0.78
	floor_mat.metallic_specular = 0.95
	floor_mat.roughness = 0.11
	floor_mat.clearcoat_enabled = true
	floor_mat.clearcoat = 1.0
	floor_mat.clearcoat_roughness = 0.06
	floor_mesh.material_override = floor_mat
	arch_root.add_child(floor_mesh)

	# 2. Specular Gold Inlay Floor Trim Lines (catch intense HDR glare!)
	var gold_trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	gold_trim_mat.albedo_color = Color(1.0, 0.82, 0.28)
	gold_trim_mat.metallic = 0.96
	gold_trim_mat.roughness = 0.08
	gold_trim_mat.emission_enabled = true
	gold_trim_mat.emission = Color(1.0, 0.75, 0.22)
	gold_trim_mat.emission_energy_multiplier = 1.35

	for side_x: float in [-2.35, 2.35, -9.5, 9.5]:
		var strip: MeshInstance3D = MeshInstance3D.new()
		var sbox: BoxMesh = BoxMesh.new()
		sbox.size = Vector3(0.14, 0.03, 32.0)
		strip.mesh = sbox
		strip.position = Vector3(side_x, 0.015, -1.0)
		strip.material_override = gold_trim_mat
		arch_root.add_child(strip)

	# 3. Royal Red Velvet Carpet Runway
	var carpet: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(4.4, 0.04, 31.0)
	carpet.mesh = cbox
	carpet.position = Vector3(0.0, 0.02, -1.0)
	var carpet_mat: StandardMaterial3D = StandardMaterial3D.new()
	carpet_mat.albedo_color = Color(0.58, 0.05, 0.11)
	carpet_mat.roughness = 0.65
	carpet.material_override = carpet_mat
	arch_root.add_child(carpet)

	# 4. Gold Velvet-Rope Stanchions along the Red Carpet
	var rope_mat: StandardMaterial3D = StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.85, 0.08, 0.16)
	rope_mat.roughness = 0.4

	for z_idx: int in range(-11, 13, 4):
		for x_side: float in [-2.55, 2.55]:
			var post: MeshInstance3D = MeshInstance3D.new()
			var pcyl: CylinderMesh = CylinderMesh.new()
			pcyl.top_radius = 0.06
			pcyl.bottom_radius = 0.08
			pcyl.height = 1.05
			post.mesh = pcyl
			post.position = Vector3(x_side, 0.52, float(z_idx))
			post.material_override = gold_trim_mat
			arch_root.add_child(post)

			var finial: MeshInstance3D = MeshInstance3D.new()
			var fsph: SphereMesh = SphereMesh.new()
			fsph.radius = 0.11
			finial.mesh = fsph
			finial.position = Vector3(x_side, 1.08, float(z_idx))
			finial.material_override = gold_trim_mat
			arch_root.add_child(finial)

	# 5. 10 Grand Marble Columns with Golden Uplights & HDR Glare Crowns
	var col_mat: StandardMaterial3D = StandardMaterial3D.new()
	col_mat.albedo_color = Color(0.14, 0.16, 0.24)
	col_mat.metallic = 0.45
	col_mat.roughness = 0.18
	col_mat.clearcoat_enabled = true

	for z_col: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		for x_col: float in [-11.5, 11.5]:
			var pillar: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.65
			cyl.height = 7.5
			pillar.mesh = cyl
			pillar.position = Vector3(x_col, 3.75, z_col)
			pillar.material_override = col_mat
			arch_root.add_child(pillar)

			var ring_crown: MeshInstance3D = MeshInstance3D.new()
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = 0.58
			torus.outer_radius = 0.75
			ring_crown.mesh = torus
			ring_crown.position = Vector3(x_col, 2.2, z_col)
			ring_crown.material_override = gold_trim_mat
			arch_root.add_child(ring_crown)

	# 6. 3 Overhead HDR Crystal Chandeliers casting warm pools & glare
	for z_chand: float in [-9.0, 0.0, 9.0]:
		_build_crystal_chandelier(arch_root, Vector3(0.0, 7.2, z_chand), gold_trim_mat)

	# 7. VIP Lounge Cocktail Tables & Neon Cyber-Bar
	_build_gala_lounge_props(arch_root, gold_trim_mat)

	# 8. Luxury Armored Extraction Limousine at the North Plaza (with blazing Xenon headlights!)
	_build_extraction_limousine(arch_root, extraction_pos, extraction_radius, gold_trim_mat)


static func _build_crystal_chandelier(parent: Node3D, pos: Vector3, gold_mat: StandardMaterial3D) -> void:
	var chand: Node3D = Node3D.new()
	chand.position = pos
	parent.add_child(chand)

	var crystal_mat: StandardMaterial3D = StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(1.0, 0.92, 0.72)
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(1.0, 0.85, 0.52)
	crystal_mat.emission_energy_multiplier = 4.2

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.25
	torus.outer_radius = 1.45
	ring.mesh = torus
	ring.material_override = gold_mat
	chand.add_child(ring)

	var core: MeshInstance3D = MeshInstance3D.new()
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 0.55
	core.mesh = sph
	core.material_override = crystal_mat
	chand.add_child(core)

	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.88, 0.65)
	light.light_energy = 3.6
	light.light_specular = 2.5
	light.omni_range = 16.0
	light.shadow_enabled = true
	chand.add_child(light)


static func _build_gala_lounge_props(parent: Node3D, gold_mat: StandardMaterial3D) -> void:
	var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.15, 0.85, 1.0)
	glass_mat.metallic = 0.8
	glass_mat.roughness = 0.05
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.10, 0.65, 0.95)
	glass_mat.emission_energy_multiplier = 2.4

	var table_positions: Array[Vector3] = [
		Vector3(-7.2, 0.0, 9.0),
		Vector3(7.2, 0.0, 9.0),
		Vector3(-7.2, 0.0, -2.5),
		Vector3(7.2, 0.0, -2.5),
	]
	for tpos: Vector3 in table_positions:
		var tbl: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 1.15
		cyl.bottom_radius = 0.35
		cyl.height = 1.05
		tbl.mesh = cyl
		tbl.position = tpos + Vector3(0.0, 0.52, 0.0)
		tbl.material_override = gold_mat
		parent.add_child(tbl)

		var centerpiece: MeshInstance3D = MeshInstance3D.new()
		var csph: SphereMesh = SphereMesh.new()
		csph.radius = 0.24
		centerpiece.mesh = csph
		centerpiece.position = tpos + Vector3(0.0, 1.2, 0.0)
		centerpiece.material_override = glass_mat
		parent.add_child(centerpiece)


static func _build_extraction_limousine(
	parent: Node3D,
	extraction_pos: Vector3,
	extraction_radius: float,
	gold_mat: StandardMaterial3D
) -> void:
	# Glowing Holographic Extraction Zone Ring
	var pad_mat: StandardMaterial3D = StandardMaterial3D.new()
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.albedo_color = Color(0.15, 1.0, 0.62)

	var pad_ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = extraction_radius - 0.18
	torus.outer_radius = extraction_radius
	pad_ring.mesh = torus
	pad_ring.position = extraction_pos + Vector3(0.0, 0.06, 0.0)
	pad_ring.material_override = pad_mat
	parent.add_child(pad_ring)

	# Stretch Armored Limousine parked right behind the extraction zone
	var limo_root: Node3D = Node3D.new()
	limo_root.name = "ArmoredLimousine"
	limo_root.position = extraction_pos + Vector3(0.0, 0.0, -3.4)
	parent.add_child(limo_root)

	var limo_paint: StandardMaterial3D = StandardMaterial3D.new()
	limo_paint.albedo_color = Color(0.04, 0.05, 0.08)
	limo_paint.metallic = 0.92
	limo_paint.roughness = 0.07
	limo_paint.clearcoat_enabled = true
	limo_paint.clearcoat = 1.0
	limo_paint.clearcoat_roughness = 0.04

	var chassis: MeshInstance3D = MeshInstance3D.new()
	var cbox: BoxMesh = BoxMesh.new()
	cbox.size = Vector3(7.8, 1.05, 2.35)
	chassis.mesh = cbox
	chassis.position = Vector3(0.0, 0.72, 0.0)
	chassis.material_override = limo_paint
	limo_root.add_child(chassis)

	var cabin: MeshInstance3D = MeshInstance3D.new()
	var kbox: BoxMesh = BoxMesh.new()
	kbox.size = Vector3(5.2, 0.82, 2.05)
	cabin.mesh = kbox
	cabin.position = Vector3(0.0, 1.52, 0.0)
	cabin.material_override = limo_paint
	limo_root.add_child(cabin)

	# Gold Hood Ornament & Trim Strip
	var trim: MeshInstance3D = MeshInstance3D.new()
	var tbox: BoxMesh = BoxMesh.new()
	tbox.size = Vector3(7.9, 0.08, 2.42)
	trim.mesh = tbox
	trim.position = Vector3(0.0, 0.85, 0.0)
	trim.material_override = gold_mat
	limo_root.add_child(trim)

	# Blazing HDR Xenon Headlights + Volumetric SpotLight3D Beams ("БЛИКИ")
	var xenon_mat: StandardMaterial3D = StandardMaterial3D.new()
	xenon_mat.albedo_color = Color(0.85, 0.96, 1.0)
	xenon_mat.emission_enabled = true
	xenon_mat.emission = Color(0.75, 0.92, 1.0)
	xenon_mat.emission_energy_multiplier = 8.5

	for z_hl: float in [-0.82, 0.82]:
		var hl: MeshInstance3D = MeshInstance3D.new()
		var hsph: SphereMesh = SphereMesh.new()
		hsph.radius = 0.22
		hl.mesh = hsph
		hl.position = Vector3(3.92, 0.82, z_hl)
		hl.material_override = xenon_mat
		limo_root.add_child(hl)

	var spot: SpotLight3D = SpotLight3D.new()
	spot.position = Vector3(0.0, 1.8, 1.4)
	spot.rotation_degrees = Vector3(-15.0, 180.0, 0.0)
	spot.light_color = Color(0.45, 1.0, 0.78)
	spot.light_energy = 5.5
	spot.spot_range = 14.0
	spot.spot_angle = 42.0
	limo_root.add_child(spot)
