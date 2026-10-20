extends SceneTree

## После прощания с ангелом («Прости меня...») — через 100 м по тропе глитч переносит ближе к вершине,
## и посреди экрана — рассказ о солнце. Герой идёт по тропе сам (руль — на точку тропы чуть впереди).
## Печатает: прощание, где сработал глитч (сколько метров после уступа), куда перенёс, рассказ.
## Запуск (с окном): godot --path . -s tests/farewell_jump_test.gd

var world: Node
var player: CharacterBody3D
var seizure: Node
var presence: Node
var hud: Node
var t := 0.0
var stage := 0
var farewell_f := 0.0
var walked := 0.0
var last_pos := Vector3.ZERO
var said_sorry := false
var narr_seen := false
var shots := {}


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


func _shot(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/farewell_%s.png" % name)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
				return false
			player = get_first_node_in_group("player")
			hud = get_first_node_in_group("hud")
			seizure = _find("seizure.gd")
			presence = get_first_node_in_group("presence")
			_find("intro.gd").skip()
			stage = 1
		1:
			if player.locked:
				return false
			# Как после падения-вспышки из пещеры: чуть ниже уступа прощания, все припадки до него пройдены.
			farewell_f = Mountain.fraction_at_height(428.0)
			seizure.next_stop = seizure.stops.size() - 1
			var start := Mountain.path_point(farewell_f - 0.014)
			player.global_position = start.origin + Vector3.UP * 0.5
			player.velocity = Vector3.ZERO
			last_pos = player.global_position
			print("JUMP start at y=%.0f, farewell spot y=%.0f, trigger at path fraction %.4f (farewell %.4f)" % [
				player.global_position.y, Mountain.path_point(farewell_f).origin.y, seizure.stops[-1].path_at, farewell_f])
			_key(KEY_W, true)
			stage = 2
			t = 0.0
		2:
			# Руль: на точку тропы на 0,006 доли впереди ближайшей по высоте.
			var f := Mountain.fraction_at_height(player.global_position.y)
			var aim := Mountain.path_point(minf(f + 0.006, 1.0)).origin - player.global_position
			player.target_yaw = atan2(-aim.x, -aim.z)
			if player.global_position.y > Mountain.path_point(farewell_f).origin.y:
				walked += Vector2(player.global_position.x - last_pos.x, player.global_position.z - last_pos.z).length()
			last_pos = player.global_position
			if not said_sorry and hud.subtitle.text == "Прости меня..." and hud.subtitle.modulate.a > 0.9:
				said_sorry = true
				_shot("sorry")
				print("JUMP angel said \"Прости меня...\" at y=%.0f" % player.global_position.y)
			if seizure.active != -2:
				print("JUMP glitch at y=%.0f, ~%.0f m after the farewell ledge, farewell done=%s" % [
					player.global_position.y, walked, presence.farewell_done])
				_key(KEY_W, false)
				stage = 3
				t = 0.0
			if t > 120.0:
				print("JUMP FAIL: no glitch, y=%.0f" % player.global_position.y)
				return true
		3:
			if seizure.active == -2 and t > 1.5:
				if not narr_seen:
					narr_seen = true
					print("JUMP moved to y=%.0f (peak %.0f), on floor=%s" % [player.global_position.y, Mountain.PEAK, player.is_on_floor()])
			if hud.narration.modulate.a > 0.99:
				_shot("sun")
				print("JUMP narration: \"%s\"" % hud.narration.text)
				return true
			if t > 15.0:
				print("JUMP FAIL: no narration")
				return true
	return false
