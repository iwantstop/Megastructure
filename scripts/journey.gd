extends Node

## Путь героя. Чем дальше он уходит от города (или чем выше поднимается),
## тем сильнее меняется мир: дождь стихает, холод уходит, краски теплеют,
## тучи редеют. Выше облаков — солнце.

const CITY_CENTER := Vector2(0, -150)
const COLD_TOP := Color(0.36, 0.39, 0.44)
const COLD_HORIZON := Color(0.5, 0.53, 0.57)
const WARM_TOP := Color(0.42, 0.58, 0.82)
const WARM_HORIZON := Color(0.9, 0.8, 0.66)

var override := -1.0  # из админ-панели: 0..1 — задать путь вручную, -1 — по положению игрока
var progress := 0.0

var player: Node3D
var sun: DirectionalLight3D
var sky: ProceduralSkyMaterial
var env: Environment
var rain: GPUParticles3D
var ambient: Node
var bodycam_mat: ShaderMaterial
var fog: FogMaterial
var mountain_mat: ShaderMaterial
var clouds_mat: ShaderMaterial


func setup(refs: Dictionary) -> void:
	player = refs.player
	sun = refs.sun
	sky = refs.sky
	env = refs.env
	rain = refs.rain
	ambient = refs.ambient
	bodycam_mat = refs.bodycam_mat
	fog = refs.fog
	mountain_mat = refs.mountain_mat
	clouds_mat = refs.clouds_mat


func _ready() -> void:
	_apply(0.0)


func _process(delta: float) -> void:
	var p := player.global_position
	var away := smoothstep(320.0, 1800.0, Vector2(p.x, p.z).distance_to(CITY_CENTER))
	var above := smoothstep(300.0, 450.0, p.y)
	var target := maxf(away, above) if override < 0.0 else override
	progress = lerpf(progress, target, clampf(delta * 0.6, 0.0, 1.0))
	_apply(progress)


func _apply(k: float) -> void:
	var dry := smoothstep(0.0, 0.45, k)
	rain.amount_ratio = 1.0 - dry
	ambient.rain_level = 1.0 - dry

	var horizon := COLD_HORIZON.lerp(WARM_HORIZON, k)
	sky.sky_top_color = COLD_TOP.lerp(WARM_TOP, k)
	sky.sky_horizon_color = horizon
	sky.ground_horizon_color = horizon
	sun.light_energy = lerpf(0.45, 1.4, k)
	sun.light_color = Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.88, 0.7), k)

	env.ambient_light_energy = lerpf(0.9, 1.15, k)
	env.volumetric_fog_density = lerpf(0.008, 0.002, k)
	env.adjustment_saturation = lerpf(0.82, 1.05, k)
	fog.density = lerpf(0.05, 0.0, k)
	bodycam_mat.set_shader_parameter("saturation", lerpf(0.85, 1.0, k))
	mountain_mat.set_shader_parameter("haze_color", horizon)
	clouds_mat.set_shader_parameter("under_color", Color(0.28, 0.3, 0.34).lerp(Color(0.62, 0.6, 0.6), k))
	clouds_mat.set_shader_parameter("coverage", lerpf(0.82, 0.45, k))
