extends SceneTree

## Снимки рук: пачка в левой, зажигалка, сигарета в правой, затяжка; потом припадок гасит сигарету
## и руки дрожат — прикурить снова по T. Запуск с окном: godot --path <проект> -s res://tests/hands_view.gd

var world: Node
var player: CharacterBody3D
var smoke: Node
var frame := 0
var stage := 0
var t := 0.0
var strikes := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _key(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/hands_%s.png" % name)
	print("HANDS shot ", name, " state=", smoke.State.keys()[smoke.state])


func _process(delta: float) -> bool:
	frame += 1
	t += delta
	match stage:
		0:
			if frame < 5:
				return false
			player = get_first_node_in_group("player")
			smoke = get_first_node_in_group("smoke")
			for c in world.get_children():
				if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
					c.skip()
			stage = 1
		1:
			if player.locked:
				return false
			player.global_position = Vector3(6, 0.3, 40)   # на улице города, лицом вдоль неё
			player.target_yaw = 0.0
			player.rotation.y = 0.0
			player.target_pitch = -0.05
			_key(true)
			_key(false)
			stage = 2
			t = 0.0
		2:
			if t > 1.4:
				_shot("pack")
				stage = 3
		3:
			if smoke.state == smoke.State.WAIT_STRIKE:
				_shot("lighter")
				stage = 4
				t = 0.0
		4:
			if smoke.state == smoke.State.WAIT_STRIKE and t > 0.4:
				_key(true)
				_key(false)
				t = 0.0
				strikes += 1
			elif smoke.state == smoke.State.LIGHTING and t > 1.0:
				_shot("lighting")
				stage = 5
		5:
			if smoke.state == smoke.State.SMOKING:
				t = 0.0
				stage = 6
		6:
			if t > 1.0:
				_shot("rest")
				_key(true)
				stage = 7
				t = 0.0
		7:
			if t > 1.6:
				_shot("puff")
				_key(false)
				stage = 8
				t = 0.0
		8:
			if t > 2.0:
				smoke.seizure_hit()
				print("HANDS after seizure_hit: state=", smoke.State.keys()[smoke.state], " tremor=", smoke.tremor, " ember=", smoke.ember.visible)
				stage = 9
				t = 0.0
		9:
			if t > 0.7:
				_shot("tremor")
				_key(true)
				_key(false)
				stage = 10
				t = 0.0
		10:
			if smoke.state == smoke.State.WAIT_STRIKE:
				print("HANDS relight: lighter is out again")
				return true
			if t > 8.0:
				print("HANDS FAIL relight, state=", smoke.State.keys()[smoke.state])
				return true
	return false
