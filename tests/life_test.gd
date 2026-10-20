extends SceneTree

## Проверка: манекены застыли, ангел появляется в кадре и уходит к цели, субтитр и задание (Tab).
## Запуск: godot --headless --path <проект> -s res://tests/life_test.gd

var world: Node
var crowd: Node
var presence: Node
var hud: Node
var player: CharacterBody3D
var t := 0.0
var stage := 0
var angel_start: Vector3


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _tab(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_TAB
	key.pressed = pressed
	Input.parse_input_event(key)


func _physics_process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
				return false
			crowd = _find("crowd.gd")
			presence = _find("presence.gd")
			hud = get_first_node_in_group("hud")
			player = get_first_node_in_group("player")
			_find("intro.gd").skip()
			var playing := 0
			for p in crowd.find_children("*", "AnimationPlayer", true, false):
				if p.is_playing():
					playing += 1
			print("LIFE figures=", crowd.get_child_count(), " animations_playing=", playing)
			stage = 1
			t = 0.0
		1:
			if player.locked:
				return false
			player.target_yaw = 0.3
			player.target_pitch = 0.0
			if t < 2.0:
				return false
			presence.call_now()
			stage = 2
			t = 0.0
		2:
			if t < 3.0 and not presence.figure.visible:
				return false
			var cam := root.get_viewport().get_camera_3d()
			var fig: Node3D = presence.figure
			print("LIFE angel visible=", fig.visible, " dist=", snappedf(fig.global_position.distance_to(player.global_position), 0.1),
				" in_view=", cam.is_position_in_frustum(fig.global_position + Vector3.UP))
			angel_start = fig.global_position
			stage = 3
			t = 0.0
		3:
			if t < 8.0:
				return false
			var goal: Vector3 = presence._waypoint()
			print("LIFE angel closer_to_goal=", snappedf(angel_start.distance_to(goal) - presence.figure.global_position.distance_to(goal), 0.1), "m")
			print("LIFE noticed=", presence.noticed, " subtitle=\"", hud.subtitle.text, "\"")
			stage = 4
			t = 0.0
		4:
			if t < 12.0:
				return false
			print("LIFE before tab task_alpha=", snappedf(hud.task.modulate.a, 0.01))
			_tab(true)
			stage = 5
			t = 0.0
		5:
			if t < 1.0:
				return false
			print("LIFE tab held task_alpha=", snappedf(hud.task.modulate.a, 0.01), " x=", hud.task.position.x)
			_tab(false)
			stage = 6
			t = 0.0
		6:
			if t < 1.0:
				return false
			print("LIFE tab released task_alpha=", snappedf(hud.task.modulate.a, 0.01), " x=", hud.task.position.x)
			return true
	return false
