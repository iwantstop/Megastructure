extends Node

## Демо-прогон для проверки картинки: запуск с `-- --demo`.
## Игра сама проигрывает ~80 секунд: лежит, встаёт, осматривается, идёт к городу,
## едет на лифте с земли на 75 м, смотрит с уровней вниз, выходит к краю города
## и на мост над бездной к горе. Кадры — в папку screenshots/ рядом с проектом.

var player: CharacterBody3D
var intro: Node
var points: Array[Vector3] = []
var lifts: Array[Node3D] = []
var t := 0.0
var shot_index := 0
var dir_path := ""
var lift: Node3D

# Моменты кадров (секунды).
var shots := [2.0, 5.0, 10.5, 12.5, 14.5, 16.5, 21.0, 25.0,
	30.0, 36.0, 42.0, 48.0, 54.0,
	58.5, 60.5, 63.5, 65.5,
	69.0, 71.0, 74.0, 77.0, 80.0]


func setup(p_player: CharacterBody3D, p_intro: Node, p_points: Array[Vector3], p_lifts: Array[Node3D]) -> void:
	player = p_player
	intro = p_intro
	points = p_points
	lifts = p_lifts


func _ready() -> void:
	dir_path = ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir_path)


func _process(delta: float) -> void:
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

	# Край города и мост над бездной к горе.
	if _passed(67.0):
		_place(Vector3(0, 0.3, -372), 0.0, -0.05)
	if _passed(70.0):
		_place(Vector3(10, 0.3, -380), -PI / 2.0, -0.7)  # через перила — вниз, в бездну
	if _passed(73.0):
		_place(Vector3(0, 0.3, -900), 0.0, 0.05)  # на мосту, впереди гора
	if _passed(76.0):
		_place(Vector3(0, 0.3, -900), PI, 0.12)  # оглянуться на город

	if shot_index < shots.size() and t >= shots[shot_index]:
		shot_index += 1
		_capture(shot_index)
	if t > 81.0:
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
	player.target_yaw = yaw
	player.target_pitch = pitch


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
