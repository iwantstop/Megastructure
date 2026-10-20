extends Node

## Демо-прогон для проверки картинки: запуск с `-- --demo` (можно записать видео: --write-movie).
## Игра сама проигрывает весь путь героя за ~2,5 минуты: вступление, город, лифт, уровни,
## край города и бездна, мост, тропа на гору, выход над облаками и финал на вершине.
## Кадры сохраняются в папку screenshots/ рядом с проектом.

var player: CharacterBody3D
var intro: Node
var finale: Node
var points: Array[Vector3] = []
var lifts: Array[Node3D] = []
var real := 0.0  # с самого начала, включая падение
var t := 0.0     # от пробуждения у подножия башни
const FALL := 11.0  # падение, удар и пробуждение
var fall_shots := [1.5, 4.0, 7.0]
var shot_index := 0
var dir_path := ""
var lift: Node3D

# Моменты кадров (секунды).
var shots := [2.0, 5.0, 10.5, 14.5, 21.0, 25.0,
	30.0, 38.0, 46.0, 54.0,
	58.5, 63.5, 65.5,
	69.0, 72.0, 75.0, 78.0,
	82.0, 86.0, 90.0, 94.0, 98.0,
	103.0, 110.0, 118.0, 126.0, 134.0, 142.0, 150.0]


func setup(p_player: CharacterBody3D, p_intro: Node, p_points: Array[Vector3], p_lifts: Array[Node3D], p_finale: Node) -> void:
	player = p_player
	intro = p_intro
	points = p_points
	lifts = p_lifts
	finale = p_finale


func _ready() -> void:
	dir_path = ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir_path)


func _process(delta: float) -> void:
	real += delta
	if not fall_shots.is_empty() and real >= fall_shots[0]:
		fall_shots.pop_front()
		_capture(90 + (3 - fall_shots.size()))  # кадры падения: shot_91..93
	if real < FALL:
		return
	t += delta
	if _passed(6.0):
		intro.skip()  # встаёт
	if t > 10.0 and t < 17.0:
		player.target_yaw += delta * TAU / 7.0  # медленный оборот вокруг себя
	if _passed(17.0):
		player.target_yaw = 0.0  # лицом к городу (и к горе за ним)
		_key(KEY_W, true)
	if _passed(26.0):
		_key(KEY_W, false)

	# Лифт: встаём на ближайшую платформу и едем вверх, осматриваясь.
	if _passed(27.0):
		lift = _nearest_lift()
	if lift and t > 27.0 and t < 56.0:
		player.global_position.x = lift.global_position.x
		player.global_position.z = lift.global_position.z
		if t < 27.2:
			player.global_position.y = lift.global_position.y + 0.3
			player.velocity = Vector3.ZERO
		player.target_yaw += delta * TAU / 30.0
		player.target_pitch = lerpf(player.target_pitch, -0.2, delta)

	# Уровни: площадки 40 и 75 м, взгляд вниз в каньон.
	if _passed(57.0):
		_teleport(40.0, -0.35, 0.0)
	if _passed(62.0):
		_teleport(75.0, -0.6, PI * 0.25)
	if t > 64.0 and t < 66.0:
		player.target_pitch = lerpf(player.target_pitch, 0.15, delta * 2.0)

	# Край города: у самых перил восточного края, взгляд вниз — в бездну.
	if _passed(67.0):
		_place(Vector3(266.5, 0.3, -100), -PI / 2.0, -0.25)
	if t > 70.0 and t < 73.0:
		player.target_pitch = lerpf(player.target_pitch, -1.05, delta * 1.5)
	# Мост над бездной: вперёд на гору, потом оглянуться на город.
	if _passed(73.5):
		_place(Vector3(0, 0.3, -1300), 0.0, 0.05)
	if _passed(77.0):
		_place(Vector3(0, 0.3, -1300), PI, 0.15)

	# Гора: начало тропы, середина, выход над облаками.
	if _passed(80.0):
		_on_path(0.02, 0.05)
	if _passed(84.0):
		_on_path(0.35, 0.0)
	if _passed(88.0):
		_on_path(0.35, -0.5)  # вниз, со стены тропы
	if _passed(92.0):
		_on_path(0.8, 0.05)
	if _passed(96.0):
		_on_path(0.8, 0.1, PI)  # оглянуться — внизу море облаков

	# Финал на вершине.
	if _passed(100.0):
		_place(Mountain.CENTER + Vector3(0, Mountain.PEAK + 0.5, 0), 0.0, 0.0)
		finale.start()

	if shot_index < shots.size() and t >= shots[shot_index]:
		shot_index += 1
		_capture(shot_index)
	if t > 152.0:
		get_tree().quit()


func _passed(moment: float) -> bool:
	return t >= moment and t - get_process_delta_time() < moment


func _nearest_lift() -> Node3D:
	var best: Node3D = null
	for l in lifts:
		if best == null or l.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
			best = l
	return best


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.last_safe = pos
	player.target_yaw = yaw
	player.target_pitch = pitch


## На тропу горы: fraction — доля подъёма, turn — поворот относительно направления тропы.
func _on_path(fraction: float, pitch: float, turn := 0.0) -> void:
	var xform: Transform3D = Mountain.path_point(fraction)
	var forward := -xform.basis.z
	_place(xform.origin + Vector3.UP * 0.5, atan2(-forward.x, -forward.z) + turn, pitch)


## Ставит игрока на ближайшую к центру точку нужного уровня.
func _teleport(level: float, pitch: float, yaw: float) -> void:
	var best := Vector3.INF
	for p in points:
		if absf(p.y - level) < 1.0 and Vector2(p.x, p.z).length() < Vector2(best.x, best.z).length():
			best = p
	if best != Vector3.INF:
		_place(best, yaw, pitch)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _capture(n: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/shot_%02d.png" % [dir_path, n])
