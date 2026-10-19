extends Node

## Демо-прогон для проверки картинки: запуск с `-- --demo`.
## Игра сама проигрывает ~40 секунд: лежит, встаёт, осматривается, идёт к городу,
## потом переносится на уровни 14, 40 и 75 м. Кадры — в папку screenshots/ рядом с проектом.

var player: CharacterBody3D
var intro: Node
var points: Array[Vector3] = []
var t := 0.0
var shots := [2.0, 5.0, 10.5, 12.5, 14.5, 16.5, 21.0, 25.0, 28.0, 30.0, 32.5, 35.5, 38.5, 40.0]
var shot_index := 0
var dir_path := ""


func setup(p_player: CharacterBody3D, p_intro: Node, p_points: Array[Vector3]) -> void:
	player = p_player
	intro = p_intro
	points = p_points


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
	if t > 29.0 and t < 31.0:
		player.target_pitch = lerpf(player.target_pitch, 0.6, delta * 2.0)  # взгляд вверх, на башни

	# Уровни: галерея 14 м, мост 40 м, площадка 75 м.
	if _passed(31.0):
		_teleport(14.0, 0.0)
	if _passed(34.0):
		_teleport(40.0, -0.15)
	if _passed(37.0):
		_teleport(75.0, -0.55)
	if t > 39.0:
		player.target_pitch = lerpf(player.target_pitch, 0.2, delta * 2.0)

	if shot_index < shots.size() and t >= shots[shot_index]:
		shot_index += 1
		_capture(shot_index)
	if t > 41.0:
		get_tree().quit()


func _passed(moment: float) -> bool:
	return t >= moment and t - get_process_delta_time() < moment


## Ставит игрока на ближайшую к центру точку нужного уровня, лицом вдоль улицы.
func _teleport(level: float, pitch: float) -> void:
	var best := Vector3.INF
	for p in points:
		if absf(p.y - level) < 1.0 and Vector2(p.x, p.z).length() < Vector2(best.x, best.z).length():
			best = p
	if best == Vector3.INF:
		return
	player.global_position = best
	player.velocity = Vector3.ZERO
	player.target_yaw = 0.0
	player.target_pitch = pitch


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _capture(n: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/shot_%02d.png" % [dir_path, n])
