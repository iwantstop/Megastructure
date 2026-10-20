extends SceneTree

## Прохождение для видеоотчёта (~3 мин), как играл бы человек, но со склейками там, где путь длинный:
## падение → лежит → «W — подняться» → город → (склейка) мост с тремя припадками → (склейка) тропа
## над облаками → (склейка) вершина и финал. Припадки, ангел и субтитры — настоящие, из игры.
## Запуск: godot --path <проект> --write-movie play.avi --fixed-fps 30 -s res://tests/play_clip.gd

const CITY_EXIT := Vector3(0, 0.3, -372)

var world: Node
var player: CharacterBody3D
var intro: Node
var finale: Node
var seizure: Node
var stage := 0
var t := 0.0
var total := 0.0
var path_f := 0.56


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _next() -> void:
	stage += 1
	t = 0.0


func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.last_safe = pos
	player.rotation.y = yaw
	player.target_yaw = yaw
	player.target_pitch = 0.0


func _process(delta: float) -> bool:
	t += delta
	total += delta
	match stage:
		0:  # мир построен — берём узлы
			player = get_first_node_in_group("player")
			intro = _find("intro.gd")
			finale = _find("finale.gd")
			seizure = _find("seizure.gd")
			_next()
		1:  # падение, удар, лежит; когда всплыла подсказка — через секунду W
			if intro.state == intro.State.HINT and t > 0.0:
				if t > 1.2:
					_key(KEY_W, true)
					_key(KEY_W, false)
					_next()
			else:
				t = 0.0
		2:  # встаёт; медленно оглядывается на город
			if not player.locked:
				player.target_yaw = lerp_angle(player.target_yaw, 0.0, delta * 0.8)
			if t > 7.0:
				_key(KEY_W, true)
				_key(KEY_SHIFT, true)
				_next()
		3:  # бежит в город, к выходу на мост
			player.target_yaw = 0.0
			player.target_pitch = 0.05 * sin(t * 0.4)
			if t > 22.0:
				_place(CITY_EXIT, 0.0)  # склейка: выход из города на мост
				_next()
		4:  # мост: три припадка сами переносят ближе к горе
			player.target_yaw = 0.0
			if player.global_position.z < -2360.0 or t > 110.0:
				_key(KEY_SHIFT, false)
				var start := Mountain.path_point(path_f)
				var forward := -start.basis.z
				_place(start.origin + Vector3.UP * 0.5, atan2(-forward.x, -forward.z))  # склейка: тропа над облаками
				_next()
		5:  # идёт по тропе над облаками, к солнцу
			path_f += delta * 4.0 / 4000.0
			var ahead := Mountain.path_point(minf(path_f + 0.01, 1.0)).origin - player.global_position
			player.target_yaw = atan2(-ahead.x, -ahead.z)
			if t > 16.0:
				_key(KEY_W, false)
				_place(Mountain.CENTER + Vector3(0, Mountain.PEAK + 0.5, 6.0), 0.0)  # склейка: вершина
				_next()
		6:
			if t > 1.0:
				finale.start()
				_next()
		7:  # финал до темноты
			if t > 34.0:
				print("PLAY done, total=%.0fs" % total)
				return true
	return false
