extends Node3D

## Точка сборки мира: свет, туман, материалы, постройки, манекены, вещи, игрок.
## Поменяй WORLD_SEED — получишь другой мир.

const WORLD_SEED := 1337
const Builder = preload("res://scripts/builder.gd")
const Structures = preload("res://scripts/structures.gd")
const Mannequins = preload("res://scripts/mannequins.gd")
const Props = preload("res://scripts/props.gd")
const CONCRETE_SHADER = preload("res://shaders/concrete.gdshader")
const BODYCAM_SHADER = preload("res://shaders/bodycam.gdshader")

var rng := RandomNumberGenerator.new()
var sky_mat: ProceduralSkyMaterial
var env: Environment
var signal_amber: StandardMaterial3D
var fog_volume: FogVolume
var fog_origin := Vector3(0, 25, -150)
var time := 0.0


func _ready() -> void:
	rng.seed = WORLD_SEED
	var mats := _make_materials()
	_make_environment()
	var sun := _make_sun()
	var bodycam := _make_bodycam()

	var builder := Builder.new()
	var structures := Structures.new(builder, rng, mats)
	structures.build()
	var mannequins := Mannequins.new(builder, rng, mats.plastic, mats.concrete)
	mannequins.populate(structures.streets, structures.plazas)
	builder.finish(self)

	var props := Props.new(rng)
	var vignettes := props.place_all(self, structures)
	_make_window_lights(structures.lights)

	var player := _spawn_player()
	_make_ash(player)
	_make_hint()

	var dream = preload("res://scripts/dream.gd").new()
	dream.setup(sun, sky_mat, vignettes, mats.concrete_dark)
	add_child(dream)
	var presence = preload("res://scripts/presence.gd").new()
	add_child(presence)
	add_child(preload("res://scripts/ambient.gd").new())

	var admin = preload("res://scripts/admin.gd").new()
	admin.setup(player, dream, presence, env, bodycam)
	add_child(admin)


# --- Материалы ---------------------------------------------------------------

func _make_materials() -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	noise_tex.width = 1024
	noise_tex.height = 1024
	noise_tex.generate_mipmaps = true

	var concrete := func(params: Dictionary) -> ShaderMaterial:
		var mat := ShaderMaterial.new()
		mat.shader = CONCRETE_SHADER
		mat.set_shader_parameter("noise_tex", noise_tex)
		for key in params:
			mat.set_shader_parameter(key, params[key])
		return mat

	var plaster := func(color: Color) -> ShaderMaterial:
		return concrete.call({"base_color": color, "streaks": 0.7, "grime": 0.8, "tint_amount": 0.25, "variation": 0.35})
	var brick := func(color: Color) -> ShaderMaterial:
		return concrete.call({"base_color": color, "brick_size": 0.25, "streaks": 0.5, "grime": 0.7, "variation": 0.25})

	signal_amber = _plain(Color(0.25, 0.15, 0.02), 0.4, 0.0)
	signal_amber.emission_enabled = true
	signal_amber.emission = Color(1.0, 0.6, 0.1)

	return {
		"facades": [
			plaster.call(Color(0.68, 0.66, 0.62)), plaster.call(Color(0.6, 0.63, 0.66)),
			plaster.call(Color(0.7, 0.64, 0.55)), plaster.call(Color(0.55, 0.6, 0.55)),
			plaster.call(Color(0.68, 0.58, 0.56)), plaster.call(Color(0.5, 0.5, 0.52)),
			brick.call(Color(0.5, 0.27, 0.2)), brick.call(Color(0.38, 0.25, 0.2)),
			brick.call(Color(0.62, 0.52, 0.38)), brick.call(Color(0.45, 0.3, 0.26)),
		],
		"asphalt": concrete.call({"base_color": Color(0.19, 0.19, 0.2), "variation": 0.35, "grime": 0.0,
			"tint_amount": 0.0, "streaks": 0.0, "puddles": 1.0, "roughness_value": 0.85}),
		"sidewalk": concrete.call({"base_color": Color(0.52, 0.52, 0.51), "panel_size": 1.5, "seam_width": 0.025,
			"seam_dark": 0.35, "grime": 0.6, "puddles": 0.5}),
		"soil": _plain(Color(0.2, 0.18, 0.15), 1.0, 0.0),
		"glass": _plain(Color(0.08, 0.1, 0.12), 0.06, 0.4),
		"glass_lit": _glow(Color(0.35, 0.28, 0.18), Color(1.0, 0.75, 0.45), 0.6),
		"door": _plain(Color(0.22, 0.16, 0.12), 0.7, 0.0),
		"paint": _plain(Color(0.75, 0.74, 0.7), 0.8, 0.0),
		"paint_yellow": _plain(Color(0.7, 0.58, 0.25), 0.8, 0.0),
		"rubber": _plain(Color(0.06, 0.06, 0.06), 0.9, 0.0),
		"bark": _plain(Color(0.17, 0.15, 0.13), 1.0, 0.0),
		"wood_pole": _plain(Color(0.3, 0.25, 0.2), 0.95, 0.0),
		"wire": _plain(Color(0.05, 0.05, 0.05), 0.8, 0.0),
		"hydrant": _plain(Color(0.5, 0.12, 0.08), 0.6, 0.0),
		"fence": _plain(Color(0.35, 0.36, 0.34), 0.7, 0.4),
		"billboard": _plain(Color(0.62, 0.6, 0.55), 0.9, 0.0),
		"signal_off": _plain(Color(0.05, 0.05, 0.05), 0.3, 0.0),
		"signal_amber": signal_amber,
		"car_paints": [
			_plain(Color(0.42, 0.12, 0.1), 0.35, 0.3), _plain(Color(0.65, 0.6, 0.5), 0.4, 0.2),
			_plain(Color(0.35, 0.37, 0.4), 0.35, 0.4), _plain(Color(0.14, 0.18, 0.28), 0.35, 0.3),
			_plain(Color(0.72, 0.72, 0.7), 0.4, 0.2), _plain(Color(0.2, 0.28, 0.22), 0.4, 0.2),
		],
		"signs": [
			_plain(Color(0.45, 0.15, 0.12), 0.7, 0.0), _plain(Color(0.15, 0.25, 0.35), 0.7, 0.0),
			_plain(Color(0.6, 0.55, 0.4), 0.7, 0.0), _plain(Color(0.2, 0.3, 0.2), 0.7, 0.0),
		],
		"awnings": [
			_plain(Color(0.4, 0.15, 0.13), 1.0, 0.0), _plain(Color(0.2, 0.3, 0.28), 1.0, 0.0),
			_plain(Color(0.55, 0.5, 0.42), 1.0, 0.0),
		],
		"concrete": concrete.call({"base_color": Color(0.6, 0.6, 0.62), "streaks": 0.6, "tint_amount": 0.15}),
		"concrete_dark": concrete.call({"base_color": Color(0.38, 0.39, 0.42), "streaks": 0.4, "tint_amount": 0.1,
			"puddles": 0.6}),
		"weathered": concrete.call({"base_color": Color(0.55, 0.54, 0.53), "streaks": 1.0, "tint_amount": 0.35,
			"tint_color": Color(0.6, 0.45, 0.3), "grime": 0.8}),
		"panels": concrete.call({"base_color": Color(0.58, 0.59, 0.61), "panel_size": 2.5, "seam_width": 0.05,
			"seam_dark": 0.45, "streaks": 0.5}),
		"tower_panels": concrete.call({"base_color": Color(0.5, 0.51, 0.54), "panel_size": 6.0, "seam_width": 0.15,
			"seam_dark": 0.5, "streaks": 0.8}),
		"ground": concrete.call({"base_color": Color(0.45, 0.46, 0.48), "panel_size": 5.0, "seam_width": 0.06,
			"seam_dark": 0.35, "grime": 0.0, "variation": 0.45, "tint_amount": 0.25, "tint_color": Color(0.45, 0.5, 0.4),
			"puddles": 1.0}),
		"stone": concrete.call({"base_color": Color(0.3, 0.3, 0.32), "panel_size": 1.2, "seam_width": 0.02,
			"seam_dark": 0.4, "grime": 0.0, "puddles": 1.0}),
		"plaster": concrete.call({"base_color": Color(0.68, 0.66, 0.62), "streaks": 0.7, "grime": 0.8, "tint_amount": 0.25}),
		"plaster_cool": concrete.call({"base_color": Color(0.6, 0.63, 0.66), "streaks": 0.6, "grime": 0.7, "tint_amount": 0.2}),
		"metal": _plain(Color(0.24, 0.25, 0.27), 0.45, 0.6),
		"slit": _plain(Color(0.07, 0.075, 0.08), 0.7, 0.0),
		"plastic": _plain(Color(0.86, 0.85, 0.83), 0.35, 0.0),
	}


func _plain(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _glow(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := _plain(color, 0.3, 0.0)
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat


## Мигающий жёлтый на всех светофорах города и дрейф клочьев тумана.
func _process(delta: float) -> void:
	time += delta
	signal_amber.emission_energy_multiplier = 2.5 if fmod(time, 1.6) < 0.8 else 0.0
	if fog_volume:
		fog_volume.position = fog_origin + Vector3(sin(time * 0.013) * 80.0, 0, cos(time * 0.009) * 80.0)


# --- Небо, туман, свет -------------------------------------------------------

## Пасмурный день в духе Silent Hill, но не белый: серое небо, приглушённые цвета.
## Основной туман — объёмный: рваные клочья, которые медленно дрейфуют по ветру.
func _make_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.5, 0.52, 0.55)
	sky_mat.sky_horizon_color = Color(0.66, 0.67, 0.68)
	sky_mat.ground_horizon_color = Color(0.66, 0.67, 0.68)
	sky_mat.ground_bottom_color = Color(0.55, 0.56, 0.57)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	# Дальний туман. Цвет берётся прямо с неба — так на горизонте нет шва.
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 1.0
	env.fog_height = 40.0
	env.fog_height_density = 0.006
	# Объёмный туман: ровная лёгкая дымка + клочья из FogVolume (см. _make_fog_volume).
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.62, 0.63, 0.65)
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_sky_affect = 1.0
	_make_fog_volume()
	# Мягкий отражённый свет и отражения в лужах.
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.ssil_enabled = true
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.25
	# Чуть приглушённые цвета, но с контрастом.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.12

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## Клочья тумана: большой объём над городом с трёхмерным шумом плотности.
## Внизу гуще, к высоте редеет. Медленно дрейфует (см. _process).
func _make_fog_volume() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.07
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.35, 0.75])
	ramp.colors = PackedColorArray([Color.BLACK, Color.WHITE])
	var density := NoiseTexture3D.new()
	density.width = 64
	density.height = 16
	density.depth = 64
	density.seamless = true
	density.noise = noise
	density.color_ramp = ramp

	var fog := FogMaterial.new()
	fog.density = 0.05
	fog.albedo = Color(0.64, 0.65, 0.67)
	fog.density_texture = density
	fog.height_falloff = 0.04
	fog.edge_fade = 0.2

	fog_volume = FogVolume.new()
	fog_volume.size = Vector3(1600, 60, 1600)
	fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog_volume.material = fog
	fog_volume.position = fog_origin
	add_child(fog_volume)


## Солнце за облаками: мягкие тени, но достаточно сильное, чтобы давать лучи в тумане.
func _make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(0.96, 0.95, 0.92)
	sun.light_energy = 0.6
	sun.light_angular_distance = 3.0
	sun.light_volumetric_fog_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)
	return sun


## Экранный эффект нагрудной камеры поверх всего 3D.
func _make_bodycam() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BODYCAM_SHADER
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)
	return layer


## Медленно падающий пепел вокруг игрока.
func _make_ash(player: Node3D) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(25, 12, 25)
	process.direction = Vector3(0, -1, 0)
	process.spread = 30.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.4
	process.gravity = Vector3(0, -0.25, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 4.0
	process.scale_min = 0.5
	process.scale_max = 1.3

	var flake_mat := StandardMaterial3D.new()
	flake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_mat.albedo_color = Color(0.85, 0.84, 0.82, 0.75)
	var flake := QuadMesh.new()
	flake.size = Vector2(0.035, 0.035)
	flake.material = flake_mat

	var ash := GPUParticles3D.new()
	ash.amount = 2500
	ash.lifetime = 14.0
	ash.preprocess = 14.0
	ash.local_coords = false  # пепел остаётся в мире, а облако следует за игроком
	ash.process_material = process
	ash.draw_pass_1 = flake
	ash.visibility_aabb = AABB(Vector3(-40, -25, -40), Vector3(80, 50, 80))
	ash.position = Vector3(0, 6, 0)
	player.add_child(ash)


## Тёплый свет в некоторых окнах.
func _make_window_lights(points: Array[Vector3]) -> void:
	for p in points:
		var light := OmniLight3D.new()
		light.position = p
		light.light_color = Color(1.0, 0.8, 0.55)
		light.light_energy = 0.8
		light.omni_range = 7.0
		add_child(light)


# --- Игрок и подсказка -------------------------------------------------------

func _spawn_player() -> CharacterBody3D:
	var player: CharacterBody3D = preload("res://scripts/player.gd").new()
	player.position = Vector3(0, 0.2, 25)
	player.rotation.y = 0.0
	add_child(player)
	return player


func _make_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	var label := Label.new()
	label.text = "WASD — идти   Shift — бежать   Space — прыжок   F1 — админ-панель   Esc — освободить мышь"
	label.position = Vector2(30, 30)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	layer.add_child(label)
	add_child(layer)
	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(label, "modulate:a", 0.0, 3.0)
