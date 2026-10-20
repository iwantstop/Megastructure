extends Node

## Припадки на мосту и у подножия горы. Пока герой идёт к горе, в определённых точках его «накрывает»: резко,
## на 1,2 секунды кадр рвётся помехами и цифровым треском, на миг — чернота, и он приходит в себя
## уже намного ближе к горе. После каждого припадка внизу плавно проступают его мысли.
## Так мост (2 км) проходится за полторы минуты, а переход к финалу становится событием.
## Камеру не трясём (автора укачивает) — всё искажение только экранное.

const STOPS := [
	{"at": -420.0, "to": -1150.0, "line": "Скоро это закончится..."},   # сразу за началом моста (−368)
	{"at": -1300.0, "to": -1800.0, "line": "Возможно именно сегодня..."},
	{"at": -1950.0, "to": -2250.0, "line": "Закроются глаза..."},
	# У подножия горы: подъём скучный и долгий — переносит почти к пещере.
	{"path_at": 0.012, "path_to": Mountain.CAVE_AT - 0.014, "line": ""},
	# Через 100 м после уступа, где ангел исчез («Прости меня...»), — ещё ближе к вершине, и над облаками — солнце.
	# Доли тропы считаются в _ready (from_height + after_m → path_at, to_height → path_to).
	{"from_height": 428.0, "after_m": 110.0, "to_height": Mountain.PEAK - 40.0, "reach": 10.0, "line": "",   # срабатывает за reach до точки — ~100 м
		"story": "Поднявшись выше облаков, он впервые увидел солнце — его лучи, тёплые и живые, коснулись измождённого лица."},
]
const PATH_REACH := 40.0    # насколько близко к точке на тропе надо подойти, м (с запасом — не проскочить)
const DURATION := 1.2
const BLACK_FROM := 0.5     # с этого момента — чернота, в ней перенос
const BLACK_TO := 0.7
const ON_BRIDGE := 16.0     # |x| меньше этого — герой на мосту (весь настил до перил)
const ZONE := 120.0         # припадок срабатывает в этих метрах после точки — бегом не проскочить
const MIX_RATE := 22050.0

var player: CharacterBody3D
var screen: ShaderMaterial    # материал экранного эффекта (bodycam.gdshader)
var next_stop := 0
var active := -2              # -2 — нет припадка, -1 — припадок без переноса (из админ-панели), иначе номер точки
var t := 0.0
var jerk := 0.0               # до следующего «срыва» кадра
var level := 0.0
var moved := false
var prev_z := 0.0
var held := false             # припадок отложен, пока на экране рассказ, — потом не пропускать его
var rng := RandomNumberGenerator.new()
var stops: Array = []         # STOPS с рассчитанными долями тропы

var noise_player: AudioStreamPlayer
var noise_playback: AudioStreamGeneratorPlayback
var crush := 0.0              # текущий «битый» отсчёт треска
var crush_hold := 0


func setup(p_player: CharacterBody3D, p_screen: ShaderMaterial) -> void:
	player = p_player
	screen = p_screen


func _ready() -> void:
	rng.randomize()
	stops = STOPS.duplicate(true)
	for stop in stops:
		if stop.has("from_height"):
			stop.path_at = Mountain.fraction_after(Mountain.fraction_at_height(stop.from_height), stop.after_m)
			stop.path_to = Mountain.fraction_at_height(stop.to_height)
	prev_z = player.global_position.z
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.1
	noise_player = AudioStreamPlayer.new()
	noise_player.stream = generator
	noise_player.volume_db = -4.0
	add_child(noise_player)


func _process(delta: float) -> void:
	if active == -2:
		_watch()
		return
	t += delta
	if t < BLACK_FROM:
		_tear(1.0, delta)
	elif t < BLACK_TO:
		screen.set_shader_parameter("glitch", 0.0)
		screen.set_shader_parameter("glitch_invert", 0.0)
		screen.set_shader_parameter("blackout", 1.0)
		level = 0.0
		if not moved:
			moved = true
			_move()
	elif t < DURATION:
		screen.set_shader_parameter("blackout", 0.0)
		_tear(lerpf(0.9, 0.3, (t - BLACK_TO) / (DURATION - BLACK_TO)), delta)
	else:
		_finish()
		return
	_fill_noise()


## Герой идёт к горе пешком и вошёл в зону точки (ZONE метров за ней) — припадок. Зона, а не линия:
## даже если кадр подвис и герой «перешагнул» линию, припадок не пропадёт. Если героя перенесли
## дальше зоны (админ-панель) — эта точка считается пройденной.
func _watch() -> void:
	var z := player.global_position.z
	# Пока посреди экрана рассказ (hud.narrate) — не перебивать его: припадок подождёт.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.narration.modulate.a > 0.01:
		held = held or (next_stop < stops.size() and stops[next_stop].has("at") and z <= stops[next_stop].at)
		prev_z = z
		return
	if held and next_stop < stops.size() and absf(player.global_position.x) < ON_BRIDGE and not player.locked and not player.flying:
		held = false
		_start(next_stop)
		prev_z = z
		return
	held = false
	if next_stop < stops.size() and not player.flying and not player.locked:
		var stop: Dictionary = stops[next_stop]
		if stop.has("path_at"):
			# Точка на тропе горы: подошёл к ней — припадок; уже выше — считается пройденной.
			var spot := Mountain.path_point(stop.path_at).origin
			var p := player.global_position
			if p.y > spot.y + 30.0:
				next_stop += 1
			elif Vector2(p.x - spot.x, p.z - spot.z).length() < stop.get("reach", PATH_REACH) and absf(p.y - spot.y) < 12.0:
				_start(next_stop)
		elif z < stop.at - ZONE:
			next_stop += 1
		elif z <= stop.at and prev_z - z < 5.0 and absf(player.global_position.x) < ON_BRIDGE:
			_start(next_stop)
	prev_z = z


## Из админ-панели: следующий припадок прямо сейчас (на мосту — с переносом, иначе только эффект).
func trigger_now() -> void:
	if active != -2:
		return
	var on_bridge := absf(player.global_position.x) < ON_BRIDGE and next_stop < stops.size()
	_start(next_stop if on_bridge else -1)


func _start(index: int) -> void:
	active = index
	t = 0.0
	jerk = 0.0
	moved = false
	player.locked = true
	var smoke := get_tree().get_first_node_in_group("smoke")
	if smoke:
		smoke.seizure_hit()  # сигарета гаснет, руки потом дрожат
	noise_player.play()
	noise_playback = noise_player.get_stream_playback()


## Кадр рвётся рывками: сила и «рисунок» помех меняются скачками, один короткий негатив за припадок.
func _tear(strength: float, delta: float) -> void:
	jerk -= delta
	if jerk <= 0.0:
		jerk = rng.randf_range(0.04, 0.09)
		level = strength * rng.randf_range(0.55, 1.0)
		screen.set_shader_parameter("glitch_seed", rng.randf() * 100.0)
	screen.set_shader_parameter("glitch", level)
	var flash := 1.0 if t > 0.22 and t < 0.3 else 0.0
	screen.set_shader_parameter("glitch_invert", flash)


## Перенос в черноте: на настил моста ближе к горе, лицом к ней.
func _move() -> void:
	if active < 0:
		return
	var stop: Dictionary = stops[active]
	# Вперёд, но не назад (если, пока ждал рассказа, ушёл дальше точки переноса).
	var spot := Vector3(clampf(player.global_position.x, -9.0, 9.0), 0.3, minf(stop.get("to", 0.0), player.global_position.z))
	var yaw := 0.0
	if stop.has("path_to"):
		var on_path := Mountain.path_point(stop.path_to)
		var forward := -on_path.basis.z
		spot = on_path.origin + Vector3.UP * 0.3
		yaw = atan2(-forward.x, -forward.z)   # лицом вверх по тропе
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.last_safe = spot
	player.rotation.y = yaw
	player.target_yaw = yaw


func _finish() -> void:
	screen.set_shader_parameter("glitch", 0.0)
	screen.set_shader_parameter("glitch_invert", 0.0)
	screen.set_shader_parameter("blackout", 0.0)
	noise_player.stop()
	player.locked = false
	var line: String = stops[active].line if active >= 0 else stops[mini(next_stop, stops.size() - 1)].line
	var story: String = stops[active].get("story", "") if active >= 0 else ""
	if active >= 0:
		next_stop = active + 1
	active = -2
	prev_z = player.global_position.z
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and line != "":
		hud.say(line)
	if hud and story != "":
		hud.narrate(story)


## Цифровой треск: шум с «залипанием» отсчётов (как битый сигнал), в черноте — тишина.
func _fill_noise() -> void:
	if noise_playback == null:
		return
	var silent := t >= BLACK_FROM and t < BLACK_TO
	for frame in noise_playback.get_frames_available():
		if crush_hold <= 0:
			crush = (rng.randf() * 2.0 - 1.0) * (0.0 if silent else level)
			crush_hold = rng.randi_range(4, 60)
		crush_hold -= 1
		noise_playback.push_frame(Vector2(crush, crush) * 0.6)
