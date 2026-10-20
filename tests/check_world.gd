extends SceneTree

## Проверка сборки мира без окна: строит main.tscn и печатает, что получилось.
## Запуск: godot --headless --path <проект> -s res://tests/check_world.gd

var frames := 0
var world: Node


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	var vertices := 0
	var surfaces := 0
	var shapes := 0
	for child in world.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh:
			for s in child.mesh.get_surface_count():
				surfaces += 1
				vertices += child.mesh.surface_get_array_len(s)
		elif child is StaticBody3D:
			shapes += child.get_child_count()
	print("CHECK surfaces=", surfaces, " vertices=", vertices, " collision_shapes=", shapes)
	print("CHECK player=", get_first_node_in_group("player") != null)
	return true
