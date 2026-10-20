extends SceneTree

## Вступление: после падения герой лежит, через 4 с всплывает подсказка, встаёт только по W.
## Запуск: godot --headless --path <проект> -s res://tests/intro_test.gd

var world: Node
var intro: Node
var player: CharacterBody3D
var lying_t := -1.0
var pressed := false


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _physics_process(delta: float) -> bool:
	if intro == null:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				intro = c
		player = get_first_node_in_group("player")
		return false
	if intro.state < intro.State.LYING:
		return false
	lying_t += delta if lying_t >= 0.0 else 1.0 + delta
	lying_t = maxf(lying_t, 0.0)
	for check in [2.0, 6.0, 20.0]:
		if lying_t >= check and lying_t - delta < check:
			print("INTRO t=", check, " state=", intro.State.keys()[intro.state], " hint_alpha=", snappedf(intro.hint.modulate.a, 0.01), " locked=", player.locked, " lying=", snappedf(player.lying, 0.01))
	if lying_t >= 20.0 and not pressed:
		pressed = true
		var key := InputEventKey.new()
		key.physical_keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key)
	if lying_t >= 27.0:
		print("INTRO after W: state=", intro.State.keys()[intro.state], " locked=", player.locked, " lying=", snappedf(player.lying, 0.01))
		return true
	return false
