extends SceneTree

## Снимки моста там, куда переносят припадки: видны ли перила и фонари по краям.
## Запуск с окном: godot --path <проект> -s res://tests/rail_view.gd

const SPOTS := [-1150.0, -1800.0, -2250.0]

var world: Node
var player: CharacterBody3D
var frame := 0
var index := 0
var start := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 3:
		player = get_first_node_in_group("player")
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				c.skip()
	if frame < 30 or player.locked:
		start = frame + 1
		return false
	var local := (frame - start) % 40
	if local == 0:
		player.global_position = Vector3(1.5, 0.3, SPOTS[index])
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.target_yaw = 0.0
		player.target_pitch = 0.0
	if local == 39:
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/rail_%d.png" % index)
		index += 1
		if index >= SPOTS.size():
			return true
	return false
