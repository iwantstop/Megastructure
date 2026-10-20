extends SceneTree

## Тест горы: в нескольких точках тропы высота земли совпадает с расчётной,
## а поставленный туда герой стоит на ней и не проваливается.

var mountain: Node3D
var player: CharacterBody3D
var frames := 0
var checks := [0.0, 0.3, 0.6, 0.95]
var index := 0


func _initialize() -> void:
	print("MOUNTAIN collision modes: ", ClassDB.class_get_enum_constants("Terrain3D", "CollisionMode"))
	var world := Node3D.new()
	root.add_child(world)
	mountain = load("res://scripts/mountain.gd").new()
	world.add_child(mountain)
	player = load("res://scripts/player.gd").new()
	world.add_child(player)
	_place()


func _place() -> void:
	var xform: Transform3D = Mountain.path_point(checks[index])
	player.global_position = xform.origin + Vector3.UP * 1.0
	player.velocity = Vector3.ZERO
	frames = 0


func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames < 90:
		return false
	var xform: Transform3D = Mountain.path_point(checks[index])
	var ground: float = mountain.terrain.data.get_height(xform.origin)
	print("MOUNTAIN at %.2f: expected=%.1f terrain=%.1f player_y=%.1f on_floor=%s" % [
		checks[index], xform.origin.y, ground, player.global_position.y, player.is_on_floor()])
	index += 1
	if index >= checks.size():
		return true
	_place()
	return false
