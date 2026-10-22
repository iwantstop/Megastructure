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
const STROKES_SHADER = preload("res://shaders/paint_strokes.gdshader")
const FACADE_SHADER = preload("res://shaders/facade.gdshader")
const HOLOGRAM_SHADER = preload("res://shaders/hologram.gdshader")
const SIGN_WORDS := ["БАР", "ОТЕЛЬ", "ЛЮБОВЬ", "ДЕНЬГИ", "НОЧЬ", "СОН", "КЛУБ", "ЕДА", "24 ЧАСА", "ЗАЙМЫ", "РАЙ"]

## Режим запуска: "" — обычная игра; "demo", "bench", "map" — скриптовые режимы (-- --demo и т. п.).
var mode := ""
var under_test := false     # запущен тестом (-s): ни пролога, ни лишнего
var rng := RandomNumberGenerator.new()
var sky_mat: ProceduralSkyMaterial
var env: Environment
var signal_amber: StandardMaterial3D
var fog_volume: FogVolume
var fog_origin := Vector3(0, 10, -150)
var searchlights: Array[SpotLight3D] = []
var lifts: Array[Node3D] = []
var _last_mark := 0
var _build_time := 0
var time := 0.0
var built := false
var shared_noise: NoiseTexture2D
var neon: Array[StandardMaterial3D] = []
var neon_energy: Array[float] = []
var beacon: StandardMaterial3D
var holograms: Array[Node3D] = []
var ad_glows := {}   # цвет рекламы -> материал светящегося фона

const AD_TEXTS := [
	"КУПИ СЕБЕ СЧАСТЬЕ", "БОЛЬШЕ. ЕЩЁ. СЕЙЧАС.", "ТЫ ЗАСЛУЖИВАЕШЬ ВСЁ", "ЛЮБОВЬ 24/7",
	"ДОВЕРЯЙ ТОЛЬКО СЕБЕ", "ПОБЕДИ БЛИЖНЕГО", "ЗАБУДЬ", "КРЕДИТ НА ЖИЗНЬ",
	"БУДЬ ЛУЧШЕ ДРУГИХ", "ВОЗЬМИ ВСЁ", "НИКТО НЕ УЗНАЕТ", "НАСЛАЖДАЙСЯ",
]
const AD_GLOW := 1.8          # яркость светящегося фона рекламы: мягкий ореол в тумане, но текст читается
const AD_TEXT_GLOW := 1.8     # светящийся текст на тёмных экранах (было ×3 — расплывался)
const LOADING_TITLE: String = preload("res://scripts/prologue.gd").TITLE
const NEON_COLORS := [
	Color(1.0, 0.1, 0.55), Color(0.1, 0.85, 1.0), Color(1.0, 0.15, 0.1),
	Color(1.0, 0.55, 0.1), Color(0.6, 0.2, 1.0), Color(0.9, 0.95, 1.0),
]


## Экран загрузки: мир строится несколько секунд — пусть это время будет чёрным экраном
## с названием истории, а не заставкой движка. Потом экран тает прямо в падение.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for m in ["demo", "bench", "map"]:
		if "--" + m in args:
			mode = m
	under_test = "-s" in OS.get_cmdline_args() or "--script" in OS.get_cmdline_args()
	# Пролог — только в настоящей игре: в скриптовых режимах (демо, бенчмарк, карта) и тестах его нет.
	var with_prologue := (mode == "" and not under_test) or "--prologue" in args   # --prologue — тест пролога
	if with_prologue:
		var prologue = preload("res://scripts/prologue.gd").new()
		add_child(prologue)
		await prologue.title_shown        # название проявилось — теперь можно надолго занять поток постройкой
		_build()
		built = true
		get_tree().paused = true           # падение не начинается, пока не дочитан пролог
		prologue.show_menu()   # главное меню; «Начать» — пролог
		await prologue.finished
		get_tree().paused = false
		return
	var loading := _make_loading_screen()
	# Дать кадру с экраном загрузки отрисоваться: постройка мира займёт главный поток.
	await get_tree().process_frame
	await get_tree().process_frame
	_build()
	built = true
	var tween := create_tween()
	tween.tween_property(loading.get_child(0), "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(loading.queue_free)


func _make_loading_screen() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var root := ScreenText.black(layer)
	ScreenText.center(root, LOADING_TITLE, 30, Color(0.85, 0.85, 0.85, 0.6))
	ScreenText.corner_hint(root, "загрузка…")
	add_child(layer)
	return layer


func _build() -> void:
	rng.seed = WORLD_SEED
	Game.clear()
	Game.world = self
	Progress.load_saved(not under_test or "--persist" in OS.get_cmdline_user_args())   # пачка сигарет — с прошлого раза
	_last_mark = Time.get_ticks_msec()  # время постройки — с этого момента, без запуска движка и пролога
	preload("res://scripts/soundscape.gd").make_buses()  # шины звука — до всех, кто в них играет
	var mats := _make_materials()
	_make_environment()
	var sun := _make_sun()
	Game.sun = sun  # финал: солнце взрывается за ангелом
	var bodycam := _make_bodycam()
	Game.env = env
	Game.bodycam_mat = bodycam.get_child(0).material

	_mark("материалы и окружение")

	var builder := Builder.new()
	var structures := Structures.new(builder, rng, mats)
	structures.build()
	_mark("генерация построек")
	var mannequins := Mannequins.new(builder, rng, mats.concrete)
	mannequins.populate(structures.streets, structures.plazas, structures.decks, Structures.L1, structures.has_floor)
	builder.finish(self)
	_mark("сборка меша и коллизий")
	var crowd = preload("res://scripts/crowd.gd").new()
	add_child(crowd)
	crowd.setup(mannequins.figures, mats.plastic)
	_mark("манекены")
	_make_elevators(structures.elevators, mats)

	var props := Props.new(rng)
	var vignettes := props.place_all(self, structures)
	for v in vignettes:
		for g in v.find_children("*", "GeometryInstance3D", true, false):
			_limit_range(g, 150.0)
	_make_window_lights(structures.lights)
	_mark("лифты, вещи, свет")

	var player := _spawn_player()
	Game.player = player
	_make_paint_strokes(player.camera)
	var smoke = preload("res://scripts/smoke.gd").new()  # сигареты «в руках» — перед камерой
	smoke.setup(player)
	player.camera.add_child(smoke)
	Game.smoke = smoke
	var rain := _make_rain(player)
	_make_ads(structures.ads)
	_make_signs(structures.signs)
	_make_holograms(structures.open_hubs, Structures.L1)
	var traffic = preload("res://scripts/traffic.gd").new()
	traffic.setup(structures.streets, rng)
	add_child(traffic)
	_make_searchlights()
	var mountain = preload("res://scripts/mountain.gd").new()
	add_child(mountain)
	var features = preload("res://scripts/mountain_features.gd").new()  # уступы, пещера, квартира, костёр
	features.setup(player)
	add_child(features)
	Game.mountain_features = features
	_mark("гора")
	var clouds_mat := _make_clouds()

	var dream = preload("res://scripts/dream.gd").new()
	dream.setup(vignettes)
	add_child(dream)
	var presence = preload("res://scripts/presence.gd").new()
	add_child(presence)
	Game.presence = presence
	add_child(preload("res://scripts/creature.gd").new())   # существо у перил моста
	add_child(preload("res://scripts/bench_spot.gd").new())  # скамейка и торшер у перил моста
	var ad_voices = preload("res://scripts/ad_voices.gd").new()   # билборды иногда говорят фразами из пролога
	ad_voices.setup(structures.ads)
	add_child(ad_voices)
	var falls = preload("res://scripts/falls.gd").new()
	falls.setup(structures.roofs)
	add_child(falls)

	var journey = preload("res://scripts/journey.gd").new()
	journey.setup({"player": player, "sun": sun, "sky": sky_mat, "env": env, "rain": rain,
		"bodycam_mat": bodycam.get_child(0).material, "fog": fog_volume.material, "clouds_mat": clouds_mat})
	add_child(journey)
	Game.journey = journey
	var soundscape = preload("res://scripts/soundscape.gd").new()  # звук мира по зонам, шаги, музыка
	soundscape.setup(player, journey)
	add_child(soundscape)
	var intro = preload("res://scripts/intro.gd").new()
	intro.setup(player)
	add_child(intro)
	add_child(preload("res://scripts/bandages.gd").new())
	var finale = preload("res://scripts/finale.gd").new()
	finale.setup(player)
	add_child(finale)

	var scripted := mode != ""
	var seizure = preload("res://scripts/seizure.gd").new()
	seizure.setup(player, bodycam.get_child(0).material)
	if not scripted:
		add_child(seizure)  # в демо и бенчмарке героя переносят скриптом — припадки помешали бы
		var flashback = preload("res://scripts/flashback.gd").new()  # выход из пещеры: падение с небоскрёба
		flashback.setup(player, bodycam.get_child(0).material)
		add_child(flashback)

	var admin = preload("res://scripts/admin.gd").new()
	admin.setup({"player": player, "dream": dream, "presence": presence, "env": env, "bodycam": bodycam,
		"journey": journey, "intro": intro, "finale": finale, "seizure": seizure})
	if not scripted:
		add_child(admin)  # в демо и бенчмарке панель не нужна: случайное F1 не испортит запись
	if mode != "bench" and mode != "map":
		Game.hud = preload("res://scripts/hud.gd").new()
		add_child(Game.hud)
		add_child(preload("res://scripts/photos.gd").new())   # C — снимок бодикамерой (в финале — на слайдах)  # задание и субтитры; в демо — тоже, для видеоотчёта

	Settings.load_saved()   # громкость, мышь, камера, качество — как выбрал игрок
	Settings.apply()
	if not scripted:
		add_child(preload("res://scripts/pause_menu.gd").new())   # Esc — пауза и настройки
	_mark("всё остальное")

	if mode == "map":
		add_child(preload("res://scripts/map.gd").new())
	if mode == "bench":
		var bench = preload("res://scripts/bench.gd").new()
		bench.setup(player, intro)
		add_child(bench)
	if mode == "demo":
		var demo = preload("res://scripts/demo.gd").new()
		demo.setup(player, intro, structures.access_points, lifts, finale)
		add_child(demo)


## Пишет в лог, сколько занял очередной этап постройки мира.
func _mark(stage: String) -> void:
	var now := Time.get_ticks_msec()
	_build_time += now - _last_mark
	print("[мир] %s: %d мс (всего %d мс)" % [stage, now - _last_mark, _build_time])
	_last_mark = now


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
	shared_noise = noise_tex

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

	signal_amber = Shapes.mat(Color(0.25, 0.15, 0.02), 0.4, 0.0)
	signal_amber.emission_enabled = true
	signal_amber.emission = Color(1.0, 0.6, 0.1)
	beacon = Shapes.glow(Color(0.3, 0.02, 0.02), Color(1.0, 0.05, 0.03), 4.0)
	# Неон: тёмная подложка и сильное свечение (у «неосвещаемых» материалов Godot свечение не рисует).
	for c in NEON_COLORS:
		neon.append(Shapes.glow(c * 0.15, c, 6.0))
		neon_energy.append(6.0)

	# Фасады небоскрёбов: окна рисует шейдер. Разный шаг окон, рёбра, доля горящих окон.
	var facade := func(wall: Color, cell: Vector2, window: Vector2, fins: float, lit: float) -> ShaderMaterial:
		var mat := ShaderMaterial.new()
		mat.shader = FACADE_SHADER
		mat.set_shader_parameter("noise_tex", noise_tex)
		mat.set_shader_parameter("wall_color", wall)
		mat.set_shader_parameter("cell", cell)
		mat.set_shader_parameter("window", window)
		mat.set_shader_parameter("fin_every", fins)
		mat.set_shader_parameter("lit_chance", lit)
		return mat

	# Аркологии и стены колодцев: окна по всей высоте, в том числе ниже уровня города.
	var arcology := func(wall: Color, cell: Vector2, window: Vector2, fins: float, lit: float) -> ShaderMaterial:
		var mat: ShaderMaterial = facade.call(wall, cell, window, fins, lit)
		mat.set_shader_parameter("ground_floor", -10000.0)
		return mat

	return {
		"neon": neon,
		"beacon": beacon,
		"lamp_warm": Shapes.glow(Color(0.4, 0.3, 0.2), Color(1.0, 0.75, 0.45), 3.0),
		"arcology": [
			arcology.call(Color(0.3, 0.31, 0.33), Vector2(1.6, 3.2), Vector2(0.6, 0.5), 5.0, 0.3),
			arcology.call(Color(0.22, 0.23, 0.26), Vector2(1.2, 3.2), Vector2(0.7, 0.6), 0.0, 0.25),
			arcology.call(Color(0.36, 0.33, 0.3), Vector2(2.0, 3.2), Vector2(0.55, 0.45), 4.0, 0.35),
		],
		"facades": [
			facade.call(Color(0.46, 0.47, 0.48), Vector2(1.8, 3.2), Vector2(0.6, 0.5), 0.0, 0.22),
			facade.call(Color(0.34, 0.35, 0.37), Vector2(1.2, 3.2), Vector2(0.7, 0.62), 4.0, 0.18),
			facade.call(Color(0.52, 0.49, 0.45), Vector2(1.6, 3.2), Vector2(0.5, 0.45), 0.0, 0.25),
			facade.call(Color(0.3, 0.32, 0.35), Vector2(1.0, 3.2), Vector2(0.75, 0.7), 6.0, 0.15),
			facade.call(Color(0.48, 0.42, 0.38), Vector2(2.2, 3.2), Vector2(0.55, 0.5), 3.0, 0.2),
			facade.call(Color(0.4, 0.43, 0.46), Vector2(1.4, 3.2), Vector2(0.8, 0.3), 0.0, 0.3),
		],
		"house_facades": [
			plaster.call(Color(0.68, 0.66, 0.62)), plaster.call(Color(0.6, 0.63, 0.66)),
			plaster.call(Color(0.7, 0.64, 0.55)), plaster.call(Color(0.55, 0.6, 0.55)),
			plaster.call(Color(0.68, 0.58, 0.56)), plaster.call(Color(0.5, 0.5, 0.52)),
			brick.call(Color(0.5, 0.27, 0.2)), brick.call(Color(0.38, 0.25, 0.2)),
			brick.call(Color(0.62, 0.52, 0.38)), brick.call(Color(0.45, 0.3, 0.26)),
		],
		"asphalt": concrete.call({"base_color": Color(0.19, 0.19, 0.2), "variation": 0.35, "grime": 0.0,
			"tint_amount": 0.0, "streaks": 0.0, "puddles": 1.4, "roughness_value": 0.35}),  # мокрый, в ледяной корке
		"sidewalk": concrete.call({"base_color": Color(0.5, 0.5, 0.5), "panel_size": 1.5, "seam_width": 0.025,
			"seam_dark": 0.35, "grime": 0.6, "puddles": 1.0, "roughness_value": 0.5}),
		"soil": Shapes.mat(Color(0.2, 0.18, 0.15), 1.0, 0.0),
		"glass": Shapes.mat(Color(0.08, 0.1, 0.12), 0.06, 0.4),
		"glass_lit": Shapes.glow(Color(0.35, 0.28, 0.18), Color(1.0, 0.75, 0.45), 0.6),
		"door": Shapes.mat(Color(0.22, 0.16, 0.12), 0.7, 0.0),
		"paint": Shapes.mat(Color(0.75, 0.74, 0.7), 0.8, 0.0),
		"paint_yellow": Shapes.mat(Color(0.7, 0.58, 0.25), 0.8, 0.0),
		"rubber": Shapes.mat(Color(0.06, 0.06, 0.06), 0.9, 0.0),
		"bark": Shapes.mat(Color(0.17, 0.15, 0.13), 1.0, 0.0),
		"wood_pole": Shapes.mat(Color(0.3, 0.25, 0.2), 0.95, 0.0),
		"wire": Shapes.mat(Color(0.05, 0.05, 0.05), 0.8, 0.0),
		"hydrant": Shapes.mat(Color(0.5, 0.12, 0.08), 0.6, 0.0),
		"fence": Shapes.mat(Color(0.35, 0.36, 0.34), 0.7, 0.4),
		"billboard": Shapes.mat(Color(0.62, 0.6, 0.55), 0.9, 0.0),
		"signal_off": Shapes.mat(Color(0.05, 0.05, 0.05), 0.3, 0.0),
		"signal_amber": signal_amber,
		"car_paints": [
			Shapes.mat(Color(0.42, 0.12, 0.1), 0.35, 0.3), Shapes.mat(Color(0.65, 0.6, 0.5), 0.4, 0.2),
			Shapes.mat(Color(0.35, 0.37, 0.4), 0.35, 0.4), Shapes.mat(Color(0.14, 0.18, 0.28), 0.35, 0.3),
			Shapes.mat(Color(0.72, 0.72, 0.7), 0.4, 0.2), Shapes.mat(Color(0.2, 0.28, 0.22), 0.4, 0.2),
		],
		"signs": [
			Shapes.mat(Color(0.45, 0.15, 0.12), 0.7, 0.0), Shapes.mat(Color(0.15, 0.25, 0.35), 0.7, 0.0),
			Shapes.mat(Color(0.6, 0.55, 0.4), 0.7, 0.0), Shapes.mat(Color(0.2, 0.3, 0.2), 0.7, 0.0),
		],
		"awnings": [
			Shapes.mat(Color(0.4, 0.15, 0.13), 1.0, 0.0), Shapes.mat(Color(0.2, 0.3, 0.28), 1.0, 0.0),
			Shapes.mat(Color(0.55, 0.5, 0.42), 1.0, 0.0),
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
		"metal": Shapes.mat(Color(0.24, 0.25, 0.27), 0.45, 0.6),
		"slit": Shapes.mat(Color(0.07, 0.075, 0.08), 0.7, 0.0),
		"plastic": Shapes.mat(Color(0.86, 0.85, 0.83), 0.35, 0.0),
	}


## Мигающий жёлтый на всех светофорах, мерцание неона и дрейф клочьев тумана.
func _process(delta: float) -> void:
	if not built:
		return  # мир ещё строится под экраном загрузки
	time += delta
	signal_amber.emission_energy_multiplier = 2.5 if fmod(time, 1.6) < 0.8 else 0.0
	beacon.emission_energy_multiplier = 5.0 if fmod(time, 2.0) < 0.25 else 0.3  # огни на шпилях
	for h in holograms:
		h.rotate_y(delta * 0.15)
	for i in searchlights.size():
		var a := time * 0.12 + i * 1.7
		searchlights[i].rotation = Vector3(deg_to_rad(55.0 + 15.0 * sin(time * 0.2 + i)), a, 0)
	for i in neon.size():
		if randf() < 0.004:
			neon[i].emission_energy_multiplier = neon_energy[i] * 0.15  # короткий сбой
		else:
			neon[i].emission_energy_multiplier = lerpf(neon[i].emission_energy_multiplier, neon_energy[i], 0.3)
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
	# Внизу, в бездне, туман сгущается до сплошного моря.
	env.fog_height = -15.0
	env.fog_height_density = 0.03
	# Объёмный туман: ровная дымка + клочья из FogVolume (см. _make_fog_volume).
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.007  # реже, чтобы вдали был виден масштаб; густые клочья — в FogVolume
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
	env.glow_intensity = 0.8  # неон, фары и огни расплываются в тумане — мягкое киношное свечение
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	for level in [3, 4, 5]:  # широкие слои свечения — ореол вокруг огней, а не только «жёсткая» кайма
		env.set_glow_level(level, 1.0)
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
	fog.density = 0.08
	fog.albedo = Color(0.64, 0.65, 0.67)
	fog.density_texture = density
	fog.height_falloff = 0.04
	fog.edge_fade = 0.2

	fog_volume = FogVolume.new()
	fog_volume.size = Vector3(1600, 120, 1600)  # от бездны под краем города до крыш галерей
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


## Мазки кисти на поверхностях мира: полноэкранный квадрат перед камерой (shaders/paint_strokes.gdshader).
## Группа "paint_strokes" — админ-панель включает и выключает его вместе с живописью.
func _make_paint_strokes(camera: Camera3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = STROKES_SHADER
	var pass_node := MeshInstance3D.new()
	pass_node.mesh = quad
	pass_node.material_override = mat
	pass_node.extra_cull_margin = 16384.0  # квадрат рисуется всегда — он «на экране», а не в мире
	pass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pass_node.add_to_group("paint_strokes")
	camera.add_child(pass_node)


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


## Холодный дождь вокруг игрока. Под крышами не идёт — капли гаснут о верхние поверхности.
func _make_rain(player: Node3D) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(18, 1, 18)
	process.direction = Vector3(0.08, -1, 0.03)
	process.spread = 2.0
	process.initial_velocity_min = 20.0
	process.initial_velocity_max = 24.0
	process.gravity = Vector3.ZERO
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.albedo_color = Color(0.75, 0.8, 0.85, 0.1)
	drop_mat.proximity_fade_enabled = true  # капли у самой камеры растворяются, а не висят палками
	drop_mat.proximity_fade_distance = 1.0
	drop_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	drop_mat.distance_fade_min_distance = 0.5
	drop_mat.distance_fade_max_distance = 3.0
	var drop := QuadMesh.new()
	drop.size = Vector2(0.006, 0.45)
	drop.material = drop_mat

	var rain := GPUParticles3D.new()
	rain.amount = 9000
	rain.lifetime = 0.9
	rain.preprocess = 1.0
	rain.local_coords = false  # капли остаются в мире, а облако следует за игроком
	rain.process_material = process
	rain.draw_pass_1 = drop
	rain.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 40, 50))
	rain.position = Vector3(0, 14, 0)
	player.add_child(rain)

	var roofs := GPUParticlesCollisionHeightField3D.new()
	roofs.size = Vector3(44, 60, 44)
	roofs.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	roofs.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	roofs.follow_camera_enabled = true
	add_child(roofs)
	return rain


## Прожекторы по краям города шарят лучами по туману и тучам.
func _make_searchlights() -> void:
	var spots := [Vector3(-260, 2, -360), Vector3(260, 2, -360), Vector3(-260, 2, 140), Vector3(260, 2, 140),
		Vector3(-120, 2, -360), Vector3(120, 2, 140)]
	for p in spots:
		var light := SpotLight3D.new()
		light.position = p
		light.light_color = Color(0.85, 0.9, 1.0)
		light.light_energy = 40.0
		light.light_volumetric_fog_energy = 4.0
		light.spot_range = 700.0
		light.spot_angle = 3.5
		light.spot_attenuation = 0.5
		add_child(light)
		searchlights.append(light)


## Лифты в башнях доступа. Стартуют с разных остановок, чтобы не ездить синхронно.
## На каждом уровне у шахты — створка: красная и закрытая, пока платформы нет; зелёная и открытая, когда она тут.
func _make_elevators(list: Array[Dictionary], mats: Dictionary) -> void:
	var red := Shapes.glow(Color(0.3, 0.02, 0.02), Color(1.0, 0.1, 0.05), 3.0)
	var green := Shapes.glow(Color(0.02, 0.3, 0.05), Color(0.2, 1.0, 0.3), 3.0)
	var bar := BoxMesh.new()
	bar.size = Vector3(1.6, 0.06, 0.06)
	var gate_shape := BoxShape3D.new()
	gate_shape.size = Vector3(1.6, 1.1, 0.1)
	for e in list:
		var lift = preload("res://scripts/elevator.gd").new()
		var stops: Array[float] = e.stops
		var gates: Array[Dictionary] = []
		gates.append({})  # на земле створки нет
		for p in e.gates:
			var body := StaticBody3D.new()
			body.position = p
			var collision := CollisionShape3D.new()
			collision.shape = gate_shape
			collision.position.y = 0.55
			body.add_child(collision)
			var light := MeshInstance3D.new()
			light.mesh = bar
			light.position.y = 1.05
			body.add_child(light)
			add_child(body)
			gates.append({"shape": collision, "light": light})
		lift.setup(stops, rng.randi() % stops.size(), mats.metal, _pick_neon())
		lift.set_gates(gates, red, green)
		var pos: Vector3 = e.pos
		lift.position = Vector3(pos.x, 0, pos.z)
		add_child(lift)
		lifts.append(lift)


func _pick_neon() -> Material:
	return neon[rng.randi() % neon.size()]


## Вертикальные вывески поперёк улицы: светящаяся полоса и слово по буквам сверху вниз, с обеих сторон.
func _make_signs(spots: Array[Dictionary]) -> void:
	for spot in spots:
		var xform: Transform3D = spot.xform
		var size: Vector2 = spot.size
		var k := rng.randi() % NEON_COLORS.size()
		var word: String = SIGN_WORDS[rng.randi() % SIGN_WORDS.size()]
		var letters := "\n".join(word.split(""))
		for side in [0.0, PI]:
			var face := xform.rotated_local(Vector3.UP, side).translated_local(Vector3(0, 0, 0.2 if side > 0 else 0.0))
			var quad := QuadMesh.new()
			quad.size = size
			var panel := MeshInstance3D.new()
			panel.mesh = quad
			panel.material_override = neon[k]
			panel.transform = face
			_limit_range(panel, 220.0)
			add_child(panel)
			var label := Label3D.new()
			label.text = letters
			label.font_size = 96
			label.shaded = false
			label.line_spacing = -20
			label.pixel_size = minf(size.x * 0.75 / 96.0, size.y * 0.9 / (word.length() * 96.0))
			label.modulate = Color(0.02, 0.02, 0.02)
			label.transform = face.translated_local(Vector3(0, 0, 0.02))
			_limit_range(label, 220.0)
			add_child(label)


## Огромные голограммы над перекрёстками: медленно вращаются, светятся сквозь дождь.
## Каждую проецирует аппарат на площадке-хабе (deck_y) — от него вверх идёт слабый луч света,
## поэтому голограмма не «висит в воздухе».
func _make_holograms(points: Array[Vector2], deck_y: float) -> void:
	var picks := points.duplicate()
	picks.shuffle()
	for i in mini(8, picks.size()):
		var p: Vector2 = picks[i]
		var color: Color = NEON_COLORS[rng.randi() % NEON_COLORS.size()]
		var mat := ShaderMaterial.new()
		mat.shader = HOLOGRAM_SHADER
		mat.set_shader_parameter("color", color)
		var root := Node3D.new()
		root.position = Vector3(p.x, rng.randf_range(35, 70), p.y)
		add_child(root)
		_hologram_projector(Vector3(p.x, deck_y, p.y), root.position.y, color)

		var shape := MeshInstance3D.new()
		if i % 2 == 0:
			var quad := QuadMesh.new()
			quad.size = Vector2(16, 26)
			shape.mesh = quad
			var label := Label3D.new()
			var text: String = AD_TEXTS[rng.randi() % AD_TEXTS.size()]
			label.text = text.replace(" ", "\n")
			label.font_size = 128
			label.shaded = false
			label.double_sided = true
			label.pixel_size = 0.03
			label.modulate = color * 2.5
			label.transparency = 0.2
			root.add_child(label)
		else:
			var torus := TorusMesh.new()
			torus.inner_radius = 8
			torus.outer_radius = 10
			shape.mesh = torus
			shape.rotation.x = PI / 2.0
		shape.material_override = mat
		root.add_child(shape)
		holograms.append(root)


## Проектор голограммы на хабе: тёмная тумба со светящимся кольцом и луч света вверх до голограммы.
func _hologram_projector(base: Vector3, top_y: float, color: Color) -> void:
	var body := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = 1.1
	drum.bottom_radius = 1.4
	drum.height = 1.2
	body.mesh = drum
	body.material_override = Shapes.mat(Color(0.06, 0.06, 0.07), 0.4, 0.6)
	body.position = base + Vector3.UP * 0.6
	add_child(body)
	var lens := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.7
	ring.outer_radius = 0.95
	lens.mesh = ring
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 4.0
	lens.material_override = glow
	lens.position = base + Vector3.UP * 1.22
	add_child(lens)
	# Луч: расширяется кверху, едва заметный — как пыль в свете проектора.
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = HOLOGRAM_SHADER
	beam_mat.set_shader_parameter("color", color)
	beam_mat.set_shader_parameter("intensity", 0.35)
	var cone := CylinderMesh.new()
	var height := top_y - 13.0 - (base.y + 1.2)  # до нижнего края голограммы
	cone.top_radius = 6.0
	cone.bottom_radius = 0.7
	cone.height = height
	cone.cap_top = false
	cone.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = beam_mat
	beam.position = base + Vector3.UP * (1.2 + height / 2.0)
	add_child(beam)


## Горящие билборды: светящиеся панели с лозунгами, мерцают, освещают мокрые улицы.
func _make_ads(spots: Array[Dictionary]) -> void:
	var dark := Shapes.mat(Color(0.03, 0.03, 0.035), 0.4, 0.0)
	var lights_left := 28
	for ad in spots:
		var xform: Transform3D = ad.xform
		var size: Vector2 = ad.size
		var k := rng.randi() % NEON_COLORS.size()
		var color: Color = NEON_COLORS[k]
		var bright_panel := rng.randf() < 0.5  # либо светящийся фон с тёмным текстом, либо наоборот

		var quad := QuadMesh.new()
		quad.size = size
		var panel := MeshInstance3D.new()
		panel.mesh = quad
		panel.material_override = _ad_glow(k) if bright_panel else dark
		panel.transform = xform
		_limit_range(panel, 450.0 if size.x < 12.0 else 0.0)
		add_child(panel)

		var text: String = AD_TEXTS[rng.randi() % AD_TEXTS.size()]
		var label := Label3D.new()
		label.text = text
		label.font_size = 96
		label.outline_size = 0
		label.shaded = false
		label.double_sided = false
		label.pixel_size = minf(size.x * 0.85 / (text.length() * 96 * 0.62), size.y * 0.5 / 96.0)
		label.modulate = Color(0.02, 0.02, 0.02) if bright_panel else color * AD_TEXT_GLOW
		label.transform = xform.translated_local(Vector3(0, 0, 0.03))
		_limit_range(label, 450.0 if size.x < 12.0 else 0.0)
		add_child(label)

		# Цветной отсвет на улицу — только у невысоких вывесок, чтобы не перегружать сцену.
		if lights_left > 0 and xform.origin.y < 90.0:
			var light := OmniLight3D.new()
			light.light_color = color
			light.light_energy = 2.5
			light.omni_range = clampf(size.x * 2.5, 15.0, 40.0)
			_fade_light(light)
			light.transform = xform.translated_local(Vector3(0, -size.y * 0.3, 4.0))
			add_child(light)
			lights_left -= 1


## Светящийся фон рекламы: мягче неона (у того свечение ×6 — в тумане экран раздувало в белое пятно и тёмный
## текст на нём было не прочитать). Один материал на цвет.
func _ad_glow(k: int) -> StandardMaterial3D:
	if not ad_glows.has(k):
		var color: Color = NEON_COLORS[k]
		ad_glows[k] = Shapes.glow(color * 0.35, color, AD_GLOW)
	return ad_glows[k]


## Слой свинцовых туч над всем миром.
func _make_clouds() -> ShaderMaterial:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(30000, 30000)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/clouds.gdshader")
	mat.set_shader_parameter("noise_tex", shared_noise)
	var clouds := MeshInstance3D.new()
	clouds.mesh = mesh
	clouds.material_override = mat
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.position = Vector3(0, 420, 0)
	add_child(clouds)
	return mat


## Тёплый свет в некоторых окнах.
func _make_window_lights(points: Array[Vector3]) -> void:
	for p in points:
		var light := OmniLight3D.new()
		light.position = p
		light.light_color = Color(1.0, 0.8, 0.55)
		light.light_energy = 0.8
		light.omni_range = 7.0
		_fade_light(light)
		add_child(light)


# --- Игрок -------------------------------------------------------

func _spawn_player() -> CharacterBody3D:
	var player: CharacterBody3D = preload("res://scripts/player.gd").new()
	player.position = Structures.HERO_SPOT  # у подножия самой высокой башни
	add_child(player)
	return player


## Не рисовать объект дальше distance метров (0 — без ограничения); у края — плавное исчезновение.
func _limit_range(node: GeometryInstance3D, distance: float) -> void:
	if distance <= 0.0:
		return
	node.visibility_range_end = distance
	node.visibility_range_end_margin = distance * 0.1
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # плавное проявление делает объект прозрачным — дорого; границу прячет туман


## Фонарь гаснет вдали: дальше ~130 м его свет не считается.
func _fade_light(light: Light3D) -> void:
	light.distance_fade_enabled = true
	light.distance_fade_begin = 100.0
	light.distance_fade_length = 30.0
