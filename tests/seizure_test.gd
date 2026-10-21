extends SceneTree

## Припадки на мосту: герой бежит от города к горе. Для каждого припадка — где сработал, куда перенёс,
## сколько длился, стоит ли герой потом на настиле, какой субтитр. Потом — финал: субтитр «Это... Всё я».
## Запуск (с окном): godot --path <проект> -s res://tests/seizure_test.gd

const START := Vector3(0, 0.5, -380)

var world: Node
var player: CharacterBody3D
var seizure: Node
var finale: Node
var hud: Node
var stage := 0
var t := 0.0
var run_time := 0.0
var fit_from := Vector3.ZERO
var fit_time := 0.0
var in_fit := false
var check_floor := -1.0
var fits := 0
var sub_first := -1
var sub_last := -1
var narrated := false
var look_check := 0.0
var looked_forward := false


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


## Смотрит ли камера в сторону точки (в пределах 25°).
func _facing(point: Vector3) -> bool:
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var to: Vector3 = point - player.global_position
	return absf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(to.x, to.z)))) < 25.0


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
				return false
			player = get_first_node_in_group("player")
			seizure = _find("seizure.gd")
			finale = _find("finale.gd")
			hud = get_first_node_in_group("hud")
			_find("intro.gd").skip()
			stage = 1
		1:
			if player.locked:
				return false
			player.global_position = START
			player.velocity = Vector3.ZERO
			player.rotation.y = 0.0
			player.target_yaw = 0.0
			print("FIT task=\"", hud.task.get_child(0).text, "\"")
			_key(KEY_W, true)
			_key(KEY_SHIFT, true)
			stage = 2
			t = 0.0
		2:
			run_time += delta
			if not player.locked:
				player.target_yaw = 0.0
			var busy: bool = seizure.active != -2
			if busy and not in_fit:
				in_fit = true
				fit_time = 0.0
				fit_from = player.global_position
				print("FIT start: narration alpha=%.2f text=%s" % [hud.narration.modulate.a, hud.narration.text.substr(0, 12)])
			if in_fit:
				fit_time += delta
			if in_fit and not busy:
				in_fit = false
				fits += 1
				check_floor = 0.4
				print("FIT #%d at z=%.0f -> z=%.0f  duration=%.2fs  locked_after=%s" % [fits, fit_from.z, player.global_position.z, fit_time, player.locked])
			if check_floor > 0.0:
				check_floor -= delta
				if check_floor <= 0.0:
					print("FIT   on_floor=%s y=%.2f subtitle=\"%s\"" % [player.is_on_floor(), player.global_position.y, hud.subtitle.text])
			if hud.narration.modulate.a > 0.99 and not narrated and hud.narration.text.begins_with("Чем"):
				narrated = true
				look_check = 4.0
				print("FIT narration at z=%.0f path=%.0f%%: \"%s...\"" % [player.global_position.z, _find("journey.gd").progress * 100.0, hud.narration.text.substr(0, 40)])
			if look_check > 0.0:
				look_check -= delta
				if look_check <= 0.0:
					print("FIT looking back: locked=%s speed=%.1f facing city=%s" % [player.locked, Vector2(player.velocity.x, player.velocity.z).length(), _facing(Vector3(0, 0, -150))])
			if narrated and not looked_forward and not player.locked and hud.narration.modulate.a < 0.01:
				looked_forward = true
				print("FIT text gone: locked=%s facing mountain=%s" % [player.locked, _facing(Mountain.CENTER)])
			if player.global_position.z <= -2350.0 or run_time > 400.0:
				print("FIT reached mountain: time=%.0fs fits=%d" % [run_time, fits])
				_key(KEY_W, false)
				_key(KEY_SHIFT, false)
				player.global_position = Mountain.CENTER + Vector3(0, Mountain.PEAK + 0.5, 0)
				player.velocity = Vector3.ZERO
				stage = 3
				t = 0.0
		3:
			if t < 1.0:
				return false
			finale.start()
			stage = 4
			t = 0.0
		4:
			if hud.subtitle.modulate.a > 0.99:
				var now := Time.get_ticks_msec()
				if sub_first < 0:
					sub_first = now
				sub_last = now
			if t > 12.0:
				print("FIT finale subtitle=\"%s\" fully_visible=%.1fs" % [hud.subtitle.text, (sub_last - sub_first) / 1000.0])
				return true
	return false
