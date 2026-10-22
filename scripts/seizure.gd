extends Node

## Припадки на мосту и у подножия горы. Пока герой идёт к горе, в определённых точках его «накрывает»: резко,
## на 1,2 секунды кадр рвётся помехами и цифровым треском, весь звук мира пропадает — только сердце и звон в ушах
## (стихают за 13 с), на миг — чернота, и он приходит в себя
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
	{"from_height": 428.0, "after_m": 100.0, "to_height": Mountain.PEAK - 40.0, "line": "",
		"story": "Поднявшись выше облаков, я впервые увидел солнце — его лучи, тёплые и живые, коснулись моего измождённого лица."},
]
const PATH_REACH := 15.0    # дальше этого от оси тропы (по горизонтали) — герой не на тропе, м
const DURATION := 1.2
const BLACK_FROM := 0.5     # с этого момента — чернота, в ней перенос
const BLACK_TO := 0.7
const ON_BRIDGE := 16.0     # |x| меньше этого — герой на мосту (весь настил до перил)
const ZONE := 120.0         # ушёл дальше точки больше чем на столько (перенесли) — она пройдена, м
const MIX_RATE := Synth.MIX_RATE
const AFTERSHOCK := 13.0    # за столько секунд после срыва стихают сердце и звон, и возвращается мир
const HEART_DB := 0.0
const RING_DB := -16.0

var player: CharacterBody3D
var screen: ShaderMaterial    # материал экранного эффекта (bodycam.gdshader)
var next_stop := 0
var active := -2              # -2 — нет припадка, -1 — припадок без переноса (из админ-панели), иначе номер точки
var t := 0.0
var jerk := 0.0               # до следующего «срыва» кадра
var level := 0.0
var moved := false
var held := false             # припадок отложен, пока на экране рассказ, — потом не пропускать его
var rng := RandomNumberGenerator.new()
var stops: Array = []         # STOPS с рассчитанными долями тропы

var heart: AudioStreamPlayer   # во время и после припадка — только сердцебиение и звон в ушах
var noise_player: AudioStreamPlayer   # цифровой треск срыва кадра (не глушится вместе с миром)
var noise_playback: AudioStreamGeneratorPlayback
var crush := 0.0              # текущий «битый» отсчёт треска
var crush_hold := 0
var ring: AudioStreamPlayer
var aftershock: Tween


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
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.1
	noise_player = AudioStreamPlayer.new()
	noise_player.stream = generator
	noise_player.volume_db = -4.0
	add_child(noise_player)
	heart = AudioStreamPlayer.new()
	heart.stream = _heartbeat()
	add_child(heart)
	ring = AudioStreamPlayer.new()
	ring.stream = _ringing()
	add_child(ring)


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


## Следующая точка: герой до неё дошёл — пора припадка; но если посреди экрана рассказ (hud.narrate),
## припадок ждёт, пока тот растает, и не пропадает. Если героя перенесли далеко за точку (админ-панель,
## вспышка у пещеры) — она считается пройденной.
func _watch() -> void:
	if next_stop >= stops.size():
		return
	var stop: Dictionary = stops[next_stop]
	if not held and _far_past(stop):
		next_stop += 1
		return
	if _reached(stop):
		held = true
	var narrating := Game.hud != null and Game.hud.narration.modulate.a > 0.01
	if held and not narrating and not player.flying and not player.locked:
		held = false
		_start(next_stop)


## Дошёл до точки: на мосту — до отметки z (и стоит на настиле), на тропе — поднялся до её высоты, стоя на тропе.
func _reached(stop: Dictionary) -> bool:
	var p := player.global_position
	if stop.has("path_at"):
		var spot := Mountain.path_point(stop.path_at).origin
		var on_path := Mountain.path_point(Mountain.fraction_at_height(p.y)).origin
		return p.y >= spot.y - 0.5 and Vector2(p.x - on_path.x, p.z - on_path.z).length() < PATH_REACH
	return p.z <= stop.at and absf(p.x) < ON_BRIDGE


func _far_past(stop: Dictionary) -> bool:
	var p := player.global_position
	if stop.has("path_at"):
		return p.y > Mountain.path_point(stop.path_at).origin.y + 30.0
	return p.z < stop.at - ZONE


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
	if Game.smoke:
		Game.smoke.seizure_hit()  # сигарета гаснет, руки потом дрожат
	_silence_world()
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
	var hud := Game.hud
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


## Весь звук мира разом пропадает — остаются сердцебиение и звон в ушах. За AFTERSHOCK секунд они стихают,
## а мир постепенно возвращается (громкость игрока из настроек при этом не трогается — Settings.duck_db).
func _silence_world() -> void:
	if aftershock:
		aftershock.kill()
	heart.volume_db = HEART_DB
	ring.volume_db = RING_DB
	if not heart.playing:
		heart.play()
		ring.play()
	_duck(-80.0)
	aftershock = create_tween().set_parallel()
	aftershock.tween_method(_duck, -80.0, 0.0, AFTERSHOCK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	aftershock.tween_property(heart, "volume_db", -60.0, AFTERSHOCK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	aftershock.tween_property(ring, "volume_db", -60.0, AFTERSHOCK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	aftershock.chain().tween_callback(func() -> void:
		heart.stop()
		ring.stop())


func _duck(db: float) -> void:
	Settings.duck_db = db
	Settings.apply_audio()


## Сердцебиение: «тук-тук» — глухой низкий удар и второй, потише; учащённое, ~90 ударов в минуту. Петля.
func _heartbeat() -> AudioStreamWAV:
	var beat := 60.0 / 90.0
	var samples := PackedFloat32Array()
	samples.resize(int(MIX_RATE * beat))
	for i in samples.size():
		var t := i / MIX_RATE
		var v := 0.0
		for hit in [[0.0, 1.0, 52.0], [0.26, 0.65, 64.0]]:
			var dt: float = t - hit[0]
			if dt >= 0.0:
				v += hit[1] * sin(TAU * hit[2] * dt) * exp(-dt * 16.0) * minf(dt * 300.0, 1.0)
		samples[i] = v * 0.9
	return Synth.wav_from(samples, true)


## Звон в ушах: тонкий высокий тон с медленным биением. Петля ровно в 1 с — без щелчка на стыке.
func _ringing() -> AudioStreamWAV:
	return Synth.wav(1.0, func(t: float) -> float:
		return (sin(TAU * 6400.0 * t) + 0.6 * sin(TAU * 6403.0 * t)) * 0.18, true)
