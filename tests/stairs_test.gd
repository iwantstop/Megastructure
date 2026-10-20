extends SceneTree

## Тест: игрок перед лестницей дома зажимает W и должен подняться на этаж выше.
## Запуск: godot --headless --path <проект> -s res://tests/stairs_test.gd
## С переменной окружения STAIR2=1 проверяется лестница со 2-го на 3-й этаж.

const Builder = preload("res://scripts/builder.gd")
const Structures = preload("res://scripts/structures.gd")

var player: CharacterBody3D
var frames := 0
var max_y := 0.0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var mat := StandardMaterial3D.new()
	var m := {"facades": [mat], "house_facades": [mat], "concrete_dark": mat, "metal": mat, "ground": mat}
	var builder := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s := Structures.new(builder, rng, m)
	builder.box(Vector3(0, -1, 0), Vector3(200, 2, 200), mat)
	# Дом 9 x 10, 3 этажа, на тротуаре высотой 0.15.
	s._house(Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), 9.0, 10.0, 3)
	builder.finish(world)

	player = load("res://scripts/player.gd").new()
	# Лестница 1-го этажа у левой стены (x = -3.5), 2-го — у правой (x = 3.5); низ — у фасада.
	player.position = Vector3(3.5, 3.4, 4.1) if OS.get_environment("STAIR2") == "1" else Vector3(-3.5, 0.2, 4.1)
	world.add_child(player)


func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	max_y = maxf(max_y, player.global_position.y)
	if frames >= 360:
		print("STAIRS RESULT max_y=%.2f final=%s" % [max_y, player.global_position.snapped(Vector3.ONE * 0.01)])
		return true
	return false
