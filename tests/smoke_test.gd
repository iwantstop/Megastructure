extends SceneTree

## Курение: T — пачка и сигарета, T — чиркнуть (пока не загорится), держать T — затяжка, отпустить — выдох.
## Запуск: godot --headless --path <проект> -s res://tests/smoke_test.gd

var world: Node
var player: CharacterBody3D
var smoke: Node
var stage := 0
var t := 0.0
var strikes := 0
var paper_before := 0.0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _key(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
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
			var hud := get_first_node_in_group("hud")
			print("SMOKE hint=\"", hud.smoke_hint.text, "\"")
			_key(true)
			_key(false)
			stage = 2
			t = 0.0
		2:
			if smoke.state == smoke.State.WAIT_STRIKE:
				print("SMOKE took cigarette in %.1fs, left_in_pack=%d" % [t, smoke.left_in_pack])
				stage = 3
				t = 0.0
			elif t > 10.0:
				print("SMOKE FAIL: no WAIT_STRIKE, state=", smoke.state)
				return true
		3:
			if smoke.state == smoke.State.WAIT_STRIKE and t > 0.4:
				strikes += 1
				_key(true)
				_key(false)
				t = 0.0
			elif smoke.state == smoke.State.SMOKING:
				print("SMOKE lit after %d strikes" % strikes)
				paper_before = smoke.paper_len
				_key(true)
				stage = 4
				t = 0.0
			elif strikes > 30:
				print("SMOKE FAIL: never lit")
				return true
		4:
			if t > 2.0:
				print("SMOKE puff: puff_amount=%.2f glow=%.2f burned=%.4fm stream=%s" % [smoke.puff_amount, smoke.glow, paper_before - smoke.paper_len, smoke.stream.emitting])
				_key(false)
				stage = 5
				t = 0.0
		5:
			if t > 1.5:
				print("SMOKE after release: puff_amount=%.2f exhale=%s state=%d" % [smoke.puff_amount, smoke.exhale.emitting, smoke.state])
				return true
	return false
