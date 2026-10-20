extends SceneTree

## Короткий клип для видеоотчёта: герой идёт по мосту, припадок, перенос, субтитр (~12 с).
## Запуск: godot --path <проект> --write-movie clip.avi --fixed-fps 30 -s res://tests/seizure_clip.gd

var world: Node
var player: CharacterBody3D
var stage := 0
var t := 0.0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.3:
				return false
			player = get_first_node_in_group("player")
			for c in world.get_children():
				if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
					c.skip()
			stage = 1
		1:
			if player.locked:
				return false
			player.global_position = Vector3(1.5, 0.3, -630)
			player.velocity = Vector3.ZERO
			player.rotation.y = 0.0
			player.target_yaw = 0.0
			player.target_pitch = 0.02
			stage = 2
			t = 0.0
		2:
			if t > 0.6 and t < 0.7:
				_key(KEY_W, true)
			player.target_yaw = 0.0
			if t > 12.0:
				return true
	return false
