extends SceneTree

## Шаги: герой идёт 6 с по городу, потом 6 с по горе — сколько шагов прозвучало и на какой шине.
## Запуск (с окном): godot --path . -s tests/steps_test.gd

var world: Node
var player: CharacterBody3D
var soundscape: Node
var t := 0.0
var stage := 0
var heard := {}
var seen := {}


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(delta: float) -> bool:
	t += delta
	if stage == 0:
		if t < 0.5:
			return false
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("soundscape.gd"):
				soundscape = c
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				c.skip()
		player = get_first_node_in_group("player")
		stage = 1
		return false
	if stage == 1 and not player.locked:
		player.global_position = Vector3(-24, 0.5, -60)   # улица в городе
		player.target_yaw = 0.0
		var key := InputEventKey.new()
		key.physical_keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key)
		stage = 2
		t = 0.0
	if stage >= 2:
		var zone: String = soundscape._zone()
		for p in soundscape.get_children():
			if p is AudioStreamPlayer and p.bus == &"Steps" and not seen.has(p.get_instance_id()):
				seen[p.get_instance_id()] = true
				heard[zone] = heard.get(zone, 0) + 1
	if stage == 2 and t > 6.0:
		player.global_position = Mountain.path_point(0.1).origin + Vector3.UP * 0.5
		var forward := -Mountain.path_point(0.1).basis.z
		player.target_yaw = atan2(-forward.x, -forward.z)
		stage = 3
		t = 0.0
	if stage == 3 and t > 6.0:
		print("STEPS heard: ", heard)
		return true
	return false
