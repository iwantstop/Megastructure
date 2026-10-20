extends Node3D

## Ангел героя: тёмный силуэт стройной девушки с каре. Она всегда вдалеке, всегда молчит,
## и стоит только в стороне горы — будто зовёт туда. Появляется, лишь когда смотришь к горе.
## Если подойти ближе — тихо растворяется. Чем дольше идёшь, тем чаще она появляется.

const MOUNTAIN := Vector3(0, 0, -2870)
const LOOK_CONE := 0.9  # радиан: насколько взгляд должен быть направлен к горе
const GONE_ABOVE := 380.0  # выше облаков ангела больше нет — его никогда и не было
const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")

const FIRST_APPEAR := 45.0   # секунд до первого появления
const VANISH_DISTANCE := 28.0
const LIFETIME := 60.0       # сколько она стоит, если к ней не идти
const FADE_TIME := 2.5

var figure: Node3D
var anim: AnimationPlayer
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
		var dist := figure.global_position.distance_to(player.global_position)
		var gone := player.global_position.y > GONE_ABOVE
		if not fading and (dist < VANISH_DISTANCE or visible_time > LIFETIME or gone):
			_fade_out()
	elif player.global_position.y < GONE_ABOVE:
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
	anim.play("Idle")  # стоит и дышит
	anim.seek(rng.randf() * anim.current_animation_length, true)
	mat.albedo_color.a = 0.0
	create_tween().tween_property(mat, "albedo_color:a", 1.0, FADE_TIME)


## Уходит прочь — дальше от героя — и растворяется на ходу.
func _fade_out() -> void:
	fading = true
	anim.play("Walk", 0.5)
	var away := -figure.global_transform.basis.z
	var tween := create_tween().set_parallel()
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE_TIME)
	tween.tween_property(figure, "global_position", figure.global_position + away * 3.0, FADE_TIME)
	tween.chain().tween_callback(_on_faded)


func _on_faded() -> void:
	figure.visible = false
	fading = false
	var k := clampf(elapsed / 1200.0, 0.0, 1.0)
	timer = rng.randf_range(lerpf(60, 30, k), lerpf(120, 60, k))


# --- Силуэт ------------------------------------------------------------------

## Модель манекена из библиотеки анимаций: стройнее и чуть ниже, вся — тёмный силуэт.
## Каре и юбка прикреплены к костям головы и таза, поэтому двигаются вместе с ней.
func _build_figure() -> Node3D:
	var root := Node3D.new()
	var body: Node3D = MODEL.instantiate()
	body.rotation.y = PI  # модель смотрит в +Z, а у нас «вперёд» — это -Z
	body.scale = Vector3(0.86, 0.95, 0.82)
	root.add_child(body)
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mat
	anim = body.find_child("AnimationPlayer", true, false)
	for looped in ["Idle", "Walk"]:
		anim.get_animation(looped).loop_mode = Animation.LOOP_LINEAR

	var skeleton: Skeleton3D = body.find_child("Skeleton3D", true, false)
	var head := _attach(skeleton, "DEF-head")
	_part(head, _sphere(0.118), Vector3(0, 0.13, -0.01))                       # макушка
	_part(head, _cone(0.118, 0.13, 0.15), Vector3(0, 0.07, -0.012))            # ровный срез каре
	var hips := _attach(skeleton, "DEF-hips")
	_part(hips, _cone(0.13, 0.24, 0.5), Vector3(0, -0.22, 0), Vector3(1, 1, 0.8))  # юбка до колен
	return root


func _attach(skeleton: Skeleton3D, bone: String) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	return attachment


func _part(root: Node3D, mesh: Mesh, pos: Vector3, size_scale := Vector3.ONE) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = pos
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
