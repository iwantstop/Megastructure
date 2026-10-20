extends SceneTree

## Тест: игрок стоит на платформе лифта внизу; лифт должен довезти его до 75 м.
## Запуск: godot --headless --path <проект> -s res://tests/elevator_test.gd

var player: CharacterBody3D
var frames := 0
var max_y := 0.0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	shape.shape = box
	shape.position.y = -1
	ground.add_child(shape)
	world.add_child(ground)

	var lift = load("res://scripts/elevator.gd").new()
	var stops: Array[float] = [0.0, 14.0, 40.0, 75.0]
	lift.setup(stops, 0, StandardMaterial3D.new(), StandardMaterial3D.new())
	world.add_child(lift)

	player = load("res://scripts/player.gd").new()
	player.position = Vector3(0, 0.3, 0)
	world.add_child(player)


func _physics_process(_delta: float) -> bool:
	frames += 1
	max_y = maxf(max_y, player.global_position.y)
	if frames >= 60 * 30:
		print("LIFT RESULT max_y=%.2f" % max_y)
		return true
	return false
