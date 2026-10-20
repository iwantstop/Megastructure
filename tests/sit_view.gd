extends SceneTree

## Снимок сидящего манекена на сиденье сбоку и спереди-сбоку — проверить, что он не проваливается.
## Запуск с окном: godot --path <проект> -s res://tests/sit_view.gd

const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")
const Builder = preload("res://scripts/builder.gd")
const Mannequins = preload("res://scripts/mannequins.gd")

var cam: Camera3D
var frame := 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)

	var b := Builder.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.45)
	var rng := RandomNumberGenerator.new()
	var man := Mannequins.new(b, rng, mat)
	man._figure(Vector3.ZERO, 0.0, {"anim": "Sitting_Idle", "at": 0.3, "sit": true})
	b.finish(world)
	var crowd = preload("res://scripts/crowd.gd").new()
	world.add_child(crowd)
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.85, 0.8, 0.75)
	crowd.setup(man.figures, plastic)

	cam = Camera3D.new()
	world.add_child(cam)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		cam.look_at_from_position(Vector3(2.2, 0.6, 0.2), Vector3(0, 0.45, 0.1))
	if frame == 10:
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/sit_side.png")
		cam.look_at_from_position(Vector3(-1.4, 1.0, -1.6), Vector3(0, 0.45, 0.1))
	if frame == 15:
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/sit_front.png")
		return true
	return false
