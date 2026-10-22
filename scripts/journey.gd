extends Node

## Путь героя. Чем дальше он уходит от города, тем сильнее меняется мир: дождь стихает,
## холод уходит, краски теплеют, тучи редеют. Но настоящее солнце — только выше облаков:
## там оно висит низко над их белым морем, по ту сторону горы от города.

const CITY_CENTER := Vector2(0, -150)
const COLD_TOP := Color(0.36, 0.39, 0.44)
const COLD_HORIZON := Color(0.5, 0.53, 0.57)
const WARM_TOP := Color(0.42, 0.58, 0.82)
const WARM_HORIZON := Color(0.9, 0.8, 0.66)
const AWAY_SHARE := 0.7  # сколько тепла даёт одна только дорога; остальное — выход над облаками
# Гамма кадра по пути (живописный стиль): у каждой зоны свой почти единственный цвет.
const GRADE := [
	[0.0, Color(0.55, 0.68, 0.88)],   # город — холодная сталь
	[0.3, Color(0.68, 0.6, 0.9)],     # мост над бездной — сирень
	[0.62, Color(0.95, 0.74, 0.5)],   # гора под облаками — янтарь
	[1.0, Color(1.0, 0.86, 0.62)],    # над облаками — золото
]

const WARM_STORY := "Чем дальше я уходил от города, тем заметнее менялись краски мира. Дождь прекратился, холод отступил, а воздух стал сухим и тёплым — кровь на грязных бинтах запекалась, образуя корку"
const WARM_STORY_AT := 0.68  # на этой отметке пути (как «Путь» в админ-панели) — рассказ о тепле
const LOOK_BACK_TIME := 2.5  # за столько секунд герой оборачивается к городу и потом обратно к горе
const CITY_VIEW := Vector3(0, 120, -150)   # куда смотреть, оглядываясь: середина города, на уровне башен

var warm_told := false
var fog_boost := 0.0     # 0..1 — туман сгущается (сидит на скамейке на мосту, bench_spot.gd)
var override := -1.0  # из админ-панели: 0..1 — задать путь вручную, -1 — по положению игрока
var progress := 0.0
var sun_pitch_start: float
var sun_yaw_start: float

var player: Node3D
var sun: DirectionalLight3D
var sky: ProceduralSkyMaterial
var env: Environment
var rain: GPUParticles3D
var bodycam_mat: ShaderMaterial
var fog: FogMaterial
var clouds_mat: ShaderMaterial


func setup(refs: Dictionary) -> void:
	player = refs.player
	sun = refs.sun
	sky = refs.sky
	env = refs.env
	rain = refs.rain
	bodycam_mat = refs.bodycam_mat
	fog = refs.fog
	clouds_mat = refs.clouds_mat


func _ready() -> void:
	sun_pitch_start = sun.rotation_degrees.x
	sun_yaw_start = sun.rotation_degrees.y
	_apply(0.0)


func _process(delta: float) -> void:
	var p := player.global_position
	var away := smoothstep(320.0, 1800.0, Vector2(p.x, p.z).distance_to(CITY_CENTER)) * AWAY_SHARE
	var above := smoothstep(330.0, 450.0, p.y)
	var target := maxf(away, above) if override < 0.0 else override
	progress = lerpf(progress, target, clampf(delta * 0.6, 0.0, 1.0))
	if not warm_told and override < 0.0 and progress >= WARM_STORY_AT:
		# Не поверх припадка и не одновременно с субтитром — дождаться, пока тот растает.
		var hud := Game.hud
		if hud and not player.locked and hud.subtitle.modulate.a < 0.01:
			_look_back(hud)
	_apply(progress)


## Рассказ о тепле: герой останавливается и плавно оглядывается на город; пока текст на экране — стоит,
## управления нет. Текст растаял — так же плавно поворачивается обратно к горе, и можно идти дальше.
func _look_back(hud: Hud) -> void:
	warm_told = true
	player.locked = true
	_turn_to(CITY_VIEW)
	hud.narrate(WARM_STORY, func() -> void:
		var back := _turn_to(Mountain.CENTER + Vector3.UP * 150.0)
		back.tween_callback(func() -> void: player.locked = false))


## Плавный поворот взгляда на точку (по кратчайшей стороне).
func _turn_to(point: Vector3) -> Tween:
	var to := point - player.global_position
	var yaw := atan2(-to.x, -to.z)
	var pitch := clampf(atan2(to.y - 1.5, Vector2(to.x, to.z).length()), -0.3, 0.3)
	var from: float = player.target_yaw
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "target_yaw", from + angle_difference(from, yaw), LOOK_BACK_TIME)
	tween.tween_property(player, "target_pitch", pitch, LOOK_BACK_TIME)
	return tween.chain()


func _apply(k: float) -> void:
	var dry := smoothstep(0.0, 0.45, k)
	rain.amount_ratio = 1.0 - dry

	var horizon := COLD_HORIZON.lerp(WARM_HORIZON, k)
	sky.sky_top_color = COLD_TOP.lerp(WARM_TOP, k)
	sky.sky_horizon_color = horizon
	sky.ground_horizon_color = horizon

	# Солнце: под облаками — высоко и бледно; над ними опускается к горизонту прямо перед героем.
	var sunset := smoothstep(AWAY_SHARE, 1.0, k)
	sun.rotation_degrees.x = lerpf(sun_pitch_start, -9.0, sunset)
	sun.rotation_degrees.y = lerpf(sun_yaw_start, 180.0, sunset)
	sun.light_energy = lerpf(0.45, 1.0, k) + sunset * 0.8
	sun.light_color = Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.86, 0.66), k)
	sky.sun_angle_max = lerpf(30.0, 12.0, sunset)

	env.ambient_light_energy = lerpf(0.9, 1.15, k)
	env.volumetric_fog_density = lerpf(0.007, 0.002, k) * (1.0 + fog_boost * 5.0)
	env.fog_density = 0.0012 * (1.0 + fog_boost * 6.0)
	env.adjustment_saturation = lerpf(0.82, 1.05, k)
	fog.density = lerpf(0.08, 0.0, k) * (1.0 + fog_boost * 3.0) + fog_boost * 0.04
	bodycam_mat.set_shader_parameter("saturation", lerpf(0.85, 1.0, k))
	bodycam_mat.set_shader_parameter("grade_tint", _grade(k))
	bodycam_mat.set_shader_parameter("grade_amount", lerpf(0.6, 0.3, smoothstep(AWAY_SHARE, 1.0, k)))  # над облаками — мягче: небо и солнце важнее
	clouds_mat.set_shader_parameter("under_color", Color(0.28, 0.3, 0.34).lerp(Color(0.62, 0.6, 0.6), k))
	clouds_mat.set_shader_parameter("coverage", lerpf(0.82, 0.55, k))


## Цвет гаммы на отрезке пути k (0 — город, 1 — над облаками), плавно между зонами.
func _grade(k: float) -> Color:
	for i in range(1, GRADE.size()):
		if k <= GRADE[i][0]:
			var t := inverse_lerp(GRADE[i - 1][0], GRADE[i][0], k)
			return (GRADE[i - 1][1] as Color).lerp(GRADE[i][1], smoothstep(0.0, 1.0, t))
	return GRADE[-1][1]
