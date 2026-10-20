extends Node

## Карта мира: запуск с `-- --map`. Строит мир, снимает его строго сверху ортогональной
## камерой (без тумана, туч, дождя и экранных эффектов) и сохраняет снимки в screenshots/:
## map_world.png — весь мир, map_city.png — город крупно. Потом выходит.

const SHOTS := [
	{"file": "map_world.png", "center": Vector2(0, -1100), "size": 5600.0, "pixels": 4096},
	{"file": "map_city.png", "center": Vector2(0, -110), "size": 620.0, "pixels": 3072},
]

var viewport: SubViewport
var camera: Camera3D
var index := 0
var wait := 0


func _ready() -> void:
	_clean_scene()
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.near = 1.0
	camera.far = 6000.0
	camera.environment = _clear_sky()
	viewport.add_child(camera)
	camera.current = true
	# Ландшафт строит детализацию вокруг камеры — пусть это будет камера карты.
	for terrain in get_tree().root.find_children("*", "Terrain3D", true, false):
		terrain.set_camera(camera)
	_setup_shot()


func _process(_delta: float) -> void:
	wait += 1
	if wait < 20:
		return
	var shot: Dictionary = SHOTS[index]
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	viewport.get_texture().get_image().save_png("%s/%s" % [dir, shot.file])
	print("[map] saved ", shot.file)
	index += 1
	if index >= SHOTS.size():
		get_tree().quit()
		return
	_setup_shot()


func _setup_shot() -> void:
	var shot: Dictionary = SHOTS[index]
	viewport.size = Vector2i(shot.pixels, shot.pixels)
	camera.size = shot.size
	camera.global_position = Vector3(shot.center.x, 3000, shot.center.y)
	wait = 0


## Убираем всё, что мешает смотреть сверху: тучи, клочья тумана, дождь, экранные слои.
func _clean_scene() -> void:
	var root := get_tree().root
	for node in root.find_children("*", "FogVolume", true, false):
		node.visible = false
	for node in root.find_children("*", "GPUParticles3D", true, false):
		node.visible = false
	for node in root.find_children("*", "CanvasLayer", true, false):
		node.visible = false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = node.material_override
		if mat is ShaderMaterial and mat.shader and mat.shader.resource_path.ends_with("clouds.gdshader"):
			node.visible = false


func _clear_sky() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.08)  # бездна — почти чёрная
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.76, 0.8)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	return env
