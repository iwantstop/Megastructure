extends Node3D

## Ангел героя: тёмный силуэт стройной девушки с каре. Она всегда вдалеке, всегда молчит,
## и стоит только в стороне горы — будто зовёт туда. Появляется, лишь когда смотришь к горе.
## Если подойти ближе — тихо растворяется. Чем дольше идёшь, тем чаще она появляется.

const MOUNTAIN := Vector3(0, 0, -4600)
const LOOK_CONE := 0.9  # радиан: насколько взгляд должен быть направлен к горе

const FIRST_APPEAR := 45.0   # секунд до первого появления
const VANISH_DISTANCE := 28.0
const LIFETIME := 60.0       # сколько она стоит, если к ней не идти
const FADE_TIME := 2.5

var figure: Node3D
var mat: StandardMaterial3D
var player: CharacterBody3D
var timer := FIRST_APPEAR
var visible_time := 0.0
var elapsed := 0.0
var fading := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.albedo_color = Color(0.03, 0.03, 0.035, 0.0)
	figure = _build_figure()
	figure.visible = false
	add_child(figure)


func _process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return
	elapsed += delta

	if figure.visible:
		visible_time += delta
		figure.rotation.z = sin(visible_time * 0.7) * 0.01  # еле заметно покачивается
		var dist := figure.global_position.distance_to(player.global_position)
		if not fading and (dist < VANISH_DISTANCE or visible_time > LIFETIME):
			_fade_out()
	else:
		timer -= delta
		if timer <= 0.0:
			_try_appear()


## Вызов из админ-панели.
func call_now() -> void:
	if not figure.visible:
		timer = 0.0


func _try_appear() -> void:
	# Только между героем и горой — и только если он сейчас смотрит в ту сторону.
	var to_mountain := MOUNTAIN - player.global_position
	to_mountain.y = 0
	to_mountain = to_mountain.normalized()
	var view := -get_viewport().get_camera_3d().global_transform.basis.z
	view.y = 0
	if view.normalized().dot(to_mountain) < cos(LOOK_CONE):
		timer = 2.0
		return
	var forward := to_mountain.rotated(Vector3.UP, rng.randf_range(-0.35, 0.35))
	var spot := player.global_position + forward * rng.randf_range(45, 85)  # в густом тумане дальше не видно

	# Луч сверху: она может стоять и на земле, и на крыше, и на мосту.
	var space := get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 40, spot + Vector3.DOWN * 60)
	down.exclude = [player.get_rid()]
	var ground := space.intersect_ray(down)
	if ground.is_empty() or ground.normal.y < 0.9:
		timer = 2.0
		return
	var feet: Vector3 = ground.position

	# Проверяем, что она не спрятана внутри или за постройкой.
	var eye := player.global_position + Vector3.UP * 1.6
	var sight := PhysicsRayQueryParameters3D.create(eye, feet + Vector3.UP * 1.5)
	sight.exclude = [player.get_rid()]
	if not space.intersect_ray(sight).is_empty():
		timer = 2.0
		return

	figure.global_position = feet
	var away := feet - player.global_position
	away.y = 0
	figure.look_at(feet + away, Vector3.UP)  # смотрит вдаль, не на игрока
	figure.visible = true
	visible_time = 0.0
	mat.albedo_color.a = 0.0
	create_tween().tween_property(mat, "albedo_color:a", 1.0, FADE_TIME)


func _fade_out() -> void:
	fading = true
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE_TIME)
	tween.tween_callback(_on_faded)


func _on_faded() -> void:
	figure.visible = false
	fading = false
	var k := clampf(elapsed / 1200.0, 0.0, 1.0)
	timer = rng.randf_range(lerpf(60, 30, k), lerpf(120, 60, k))


# --- Силуэт ------------------------------------------------------------------

func _build_figure() -> Node3D:
	var root := Node3D.new()
	# Ноги.
	_part(root, _capsule(0.055, 0.86), Vector3(-0.07, 0.43, 0), 0.025)
	_part(root, _capsule(0.055, 0.86), Vector3(0.075, 0.43, 0.02), -0.01)
	# Платье до колен, чуть расширяется книзу.
	_part(root, _cone(0.12, 0.21, 0.48), Vector3(0, 0.79, 0), 0.0, Vector3(1, 1, 0.75))
	# Корпус: узкая талия, плечи.
	_part(root, _cone(0.155, 0.105, 0.42), Vector3(0, 1.21, 0), 0.0, Vector3(1, 1, 0.6))
	# Руки вдоль тела.
	_part(root, _capsule(0.035, 0.62), Vector3(-0.175, 1.11, 0), 0.07)
	_part(root, _capsule(0.035, 0.62), Vector3(0.175, 1.11, 0), -0.07)
	# Шея и голова.
	_part(root, _cone(0.035, 0.035, 0.1), Vector3(0, 1.46, 0))
	_part(root, _sphere(0.095), Vector3(0, 1.565, 0), 0.0, Vector3(0.9, 1.1, 1))
	# Каре: макушка и ровно обрезанные волосы до линии подбородка.
	_part(root, _sphere(0.108), Vector3(0, 1.58, 0.012))
	_part(root, _cone(0.106, 0.118, 0.13), Vector3(0, 1.5, 0.015))
	return root


func _part(root: Node3D, mesh: Mesh, pos: Vector3, tilt := 0.0, size_scale := Vector3.ONE) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = pos
	part.rotation.z = tilt
	part.scale = size_scale
	root.add_child(part)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = r
	mesh.height = h
	return mesh


func _cone(r_top: float, r_bottom: float, h: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = h
	return mesh


func _sphere(r: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	return mesh
