class_name ProceduralTextures
extends RefCounted
## Generates crisp procedural PBR textures (marble veins, red velvet carpet, architectural stone)
## using FastNoiseLite so surfaces have rich depth and localized specular glints with zero bloat.


static func make_marble_floor_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.30)
	mat.metallic = 0.14
	mat.metallic_specular = 0.48
	mat.roughness = 0.42
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.12
	mat.clearcoat_roughness = 0.38
	mat.uv1_scale = Vector3(10.0, 26.0, 1.0)

	var albedo_noise: FastNoiseLite = FastNoiseLite.new()
	albedo_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	albedo_noise.frequency = 0.035
	albedo_noise.fractal_octaves = 4
	albedo_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(0.14, 0.16, 0.22))
	grad.set_color(1, Color(0.32, 0.34, 0.40))
	grad.add_point(0.72, Color(0.20, 0.22, 0.28))

	var albedo_tex: NoiseTexture2D = NoiseTexture2D.new()
	albedo_tex.width = 256
	albedo_tex.height = 256
	albedo_tex.seamless = true
	albedo_tex.noise = albedo_noise
	albedo_tex.color_ramp = grad
	mat.albedo_texture = albedo_tex

	var normal_tex: NoiseTexture2D = NoiseTexture2D.new()
	normal_tex.width = 256
	normal_tex.height = 256
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 1.1
	normal_tex.noise = albedo_noise
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 0.22

	var rough_grad: Gradient = Gradient.new()
	rough_grad.set_color(0, Color(0.28, 0.28, 0.28))
	rough_grad.set_color(1, Color(0.52, 0.52, 0.52))
	var rough_tex: NoiseTexture2D = NoiseTexture2D.new()
	rough_tex.width = 256
	rough_tex.height = 256
	rough_tex.seamless = true
	rough_tex.noise = albedo_noise
	rough_tex.color_ramp = rough_grad
	mat.roughness_texture = rough_tex

	return mat


static func make_velvet_carpet_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.06, 0.11)
	mat.metallic = 0.0
	mat.roughness = 0.88
	mat.uv1_scale = Vector3(4.0, 40.0, 1.0)

	var weave: FastNoiseLite = FastNoiseLite.new()
	weave.noise_type = FastNoiseLite.TYPE_CELLULAR
	weave.frequency = 0.18
	var bump: NoiseTexture2D = NoiseTexture2D.new()
	bump.width = 128
	bump.height = 128
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 1.6
	bump.noise = weave
	mat.normal_enabled = true
	mat.normal_texture = bump
	mat.normal_scale = 0.25
	return mat


static func make_brushed_brass_material() -> StandardMaterial3D:
	## Non-emissive physical brushed gold/brass — catches REAL crisp specular glints without blooming!
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.28)
	mat.metallic = 0.92
	mat.metallic_specular = 0.95
	mat.roughness = 0.22
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.35
	mat.clearcoat_roughness = 0.16
	return mat


static func make_architectural_wall_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.145, 0.19)
	mat.metallic = 0.15
	mat.roughness = 0.48
	return mat
