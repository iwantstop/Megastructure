class_name Settings
extends RefCounted

## Настройки игрока: хранятся в user://settings.cfg, применяются сразу и при каждом запуске.
## Звук (общий, музыка, звуки мира), мышь, камера (бодикамера, покачивание, крен), изображение (полный экран,
## вертикальная синхронизация, ограничение FPS, яркость, разрешение 3D) и качество графики (пресеты).
## Меню (menu_ui.gd, settings_panel.gd) только меняет значения и зовёт set_value — дальше всё здесь.

const FILE := "user://settings.cfg"
const QUALITY := ["Низкое", "Среднее", "Высокое"]
const FPS_LIMITS := [0, 30, 60, 120, 144]    # 0 — без ограничения
const BASE_EXPOSURE := 0.95                  # яркость «как задумано» (картинку без просьбы не осветляем)
const BODYCAM_PARAMS := ["distortion", "aberration", "vignette", "grain"]

## Значения по умолчанию (с 22.10.2026: живопись выключена, крен при повороте — на максимум).
const VERSION := 2   # старые сохранения (без версии) один раз получают новый крен по умолчанию
const DEFAULTS := {
	"master": 1.0, "music": 1.0, "world": 1.0,
	"mouse": 1.0, "invert_y": false,
	"bodycam": 1.0, "bob": 1.0, "roll": 3.0, "paint": false,
	"fullscreen": false, "vsync": true, "fps_limit": 0, "brightness": 1.0, "render_scale": 1.0,
	"quality": 2,
}

static var values := DEFAULTS.duplicate()
static var world_fade_db := 0.0              # финал: звук мира стихает поверх громкости игрока
static var duck_db := 0.0                    # припадок: звук мира пропадает и возвращается (seizure.gd)
static var _bodycam_base := {}


static func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS[key])


## Изменить настройку: сразу применить и сохранить.
static func set_value(key: String, value: Variant) -> void:
	values[key] = value
	apply()
	save()


static func load_saved() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		for key in DEFAULTS:
			values[key] = cfg.get_value("settings", key, DEFAULTS[key])
		if cfg.get_value("meta", "version", 1) < VERSION:
			values["roll"] = DEFAULTS["roll"]
	# Для замеров: -- --quality=low|medium|high (бенчмарк), не сохраняется.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			values["quality"] = ["low", "medium", "high"].find(arg.get_slice("=", 1))
	world_fade_db = 0.0
	duck_db = 0.0


static func save() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("settings", key, values[key])
	cfg.set_value("meta", "version", VERSION)
	cfg.save(FILE)


static func reset() -> void:
	values = DEFAULTS.duplicate()
	apply()
	save()


## Применить всё, что уже есть в игре (части берутся из справочника Game; чего ещё нет — пропускается).
static func apply() -> void:
	apply_audio()
	_apply_window()
	_apply_camera()
	_apply_graphics()


static func apply_audio() -> void:
	_bus("Master", get_value("master"), 0.0)
	_bus("Music", get_value("music"), world_fade_db + duck_db)
	for bus in ["Ambience", "Interior", "Steps", "Ads"]:
		_bus(bus, get_value("world"), (world_fade_db if bus == "Ambience" else 0.0) + duck_db)


static func _bus(bus_name: String, volume: float, extra_db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)) + extra_db)


static func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full: bool = get_value("fullscreen")
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and (full or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("fps_limit"))


static func _apply_camera() -> void:
	var player := Game.player
	if player:
		player.mouse_scale = get_value("mouse")
		player.invert_y = get_value("invert_y")
		player.bob_scale = get_value("bob")
		player.turn_roll_scale = get_value("roll")
	set_bodycam_strength(get_value("bodycam"))


## Сила бодикамеры (линза, расслоение цвета, виньетка, зерно) от исходных значений шейдера: 1 — как задумано.
static func set_bodycam_strength(k: float) -> void:
	var mat := Game.bodycam_mat
	if mat == null:
		return
	for param in BODYCAM_PARAMS:
		if not _bodycam_base.has(param):
			var base = mat.get_shader_parameter(param)
			if base == null:
				base = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), param)
			_bodycam_base[param] = base
		mat.set_shader_parameter(param, _bodycam_base[param] * k)


## Качество графики. Высокое — как игра задумана; среднее — без глобального освещения (SDFGI, SSIL);
## низкое — ещё без отражений и затенения, туман грубее, мазки живописи выключены, 3D в 75% разрешения.
static func _apply_graphics() -> void:
	var env := Game.env
	var quality: int = get_value("quality")
	if env:
		env.sdfgi_enabled = quality >= 2
		env.ssil_enabled = quality >= 2
		env.ssr_enabled = quality >= 1
		env.ssao_enabled = quality >= 1
		env.tonemap_exposure = BASE_EXPOSURE * float(get_value("brightness"))
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if quality >= 1 else 40, 64 if quality >= 1 else 32)
	if Game.world:
		for node in Game.world.get_tree().get_nodes_in_group("paint_strokes"):
			node.visible = quality >= 1 and get_value("paint")
	if Game.bodycam_mat:   # живопись: пятна краски (Кувахара) и гамма зоны на экране
		Game.bodycam_mat.set_shader_parameter("paint", 0.7 if get_value("paint") else 0.0)
		var viewport := Game.world.get_viewport()
		var scale: float = get_value("render_scale") * (0.75 if quality == 0 else 1.0)
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if scale >= 0.999 else Viewport.SCALING_3D_MODE_FSR
		viewport.scaling_3d_scale = scale
