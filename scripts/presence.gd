extends Node3D

## Ангел героя: тёмный силуэт стройной девушки с каре. Она молчит и показывает дорогу:
## появляется впереди, в поле зрения, смотрит туда, куда герою идти, — и уходит в ту сторону
## (к выходу из города, по мосту, вверх по тропе). Если подойти ближе — тихо растворяется.
## Выше облаков её больше нет — её никогда и не было.

const Structures = preload("res://scripts/structures.gd")
const GONE_ABOVE := 380.0
const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")

const FIRST_APPEAR := 20.0       # секунд после вступления до первого появления
const INTERVAL := Vector2(15, 30)  # пауза между появлениями, с
const DISTANCE := Vector2(22, 42)  # как далеко от героя она появляется, м (дальше съедает туман)
const VIEW_SPREAD := 0.5         # радиан от центра взгляда — она всегда в кадре
const PAUSE := 2.5               # сколько стоит, прежде чем пойти
const WALK_SPEED := 1.25         # м/с
const LIFETIME := 22.0           # сколько она идёт, если за ней не идти
const VANISH_DISTANCE := 12.0
const FADE_TIME := 1.8
const NOTICE_TIME := 0.8         # столько её надо видеть, чтобы «заметить», с
const NOTICE_CONE := 0.6         # радиан от центра взгляда
const LINES := ["Стой", "Не уходи", "Останься"]

var figure: Node3D
var anim: AnimationPlayer
var mat: StandardMaterial3D
var player: CharacterBody3D
var timer := FIRST_APPEAR
var visible_time := 0.0
var walk_dir := Vector3.FORWARD
var fading := false
var seen_time := 0.0
var noticed := false
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


func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return

	if figure.visible:
		visible_time += delta
		if visible_time > PAUSE:
			if anim.current_animation != "Walk":
				anim.play("Walk", 0.6)
			_walk(delta)
		if not noticed and not fading:
			_watch_for_notice(delta)
		var dist := figure.global_position.distance_to(player.global_position)
		var gone := player.global_position.y > GONE_ABOVE
		if not fading and (dist < VANISH_DISTANCE or visible_time > LIFETIME or gone):
			_fade_out()
	elif player.global_position.y < GONE_ABOVE and not player.locked:
		timer -= delta
		if timer <= 0.0:
			_try_appear()


## Вызов из админ-панели.
func call_now() -> void:
	if not figure.visible:
		timer = 0.0


## Куда герою идти дальше: выход из города на мост → конец моста → тропа вверх.
func _waypoint() -> Vector3:
	var p := player.global_position
	if p.z > Structures.PLATFORM.position.y + 5.0:
		return Vector3(0, 0, Structures.PLATFORM.position.y - 40.0)
	if p.z > Structures.CAUSEWAY_END + 30.0:
		return Vector3(0, 0, Structures.CAUSEWAY_END)
	# На горе — точка тропы чуть выше той, где стоит герой.
	var best := 0.0
	var best_d := INF
	for i in 201:
		var f := i / 200.0
		var d := Mountain.path_point(f).origin.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = f
	return Mountain.path_point(minf(best + 0.02, 1.0)).origin


func _try_appear() -> void:
	timer = 1.0  # если не вышло — пробуем снова через секунду
	var to_goal := _waypoint() - player.global_position
	to_goal.y = 0
	if to_goal.length() < 8.0:
		return
	to_goal = to_goal.normalized()
	var view := -get_viewport().get_camera_3d().global_transform.basis.z
	view.y = 0
	view = view.normalized()

	# Ставим её в кадре, как можно ближе к направлению пути.
	var turn := clampf(view.signed_angle_to(to_goal, Vector3.UP), -VIEW_SPREAD, VIEW_SPREAD)
	var space := get_world_3d().direct_space_state
	for attempt in 8:
		var dir := view.rotated(Vector3.UP, turn + rng.randf_range(-0.12, 0.12))
		var spot := player.global_position + dir * rng.randf_range(DISTANCE.x, DISTANCE.y)
		var feet = _ground(space, spot, 25.0)
		if feet == null:
			continue
		# Не спрятана за постройкой.
		var eye := player.global_position + Vector3.UP * 1.6
		var sight := PhysicsRayQueryParameters3D.create(eye, feet + Vector3.UP * 1.5)
		sight.exclude = [player.get_rid()]
		if not space.intersect_ray(sight).is_empty():
			continue
		_appear(feet, to_goal)
		return


func _appear(feet: Vector3, goal_dir: Vector3) -> void:
	figure.global_position = feet
	walk_dir = goal_dir
	figure.look_at(feet + goal_dir, Vector3.UP)  # смотрит туда, куда идти герою
	figure.visible = true
	visible_time = 0.0
	seen_time = 0.0
	noticed = false
	anim.play("Idle")
	anim.seek(rng.randf() * anim.current_animation_length, true)
	mat.albedo_color.a = 0.0
	create_tween().tween_property(mat, "albedo_color:a", 1.0, FADE_TIME)


## Идёт по дороге к цели, следуя высоте пола; у края или стены просто останавливается.
func _walk(delta: float) -> void:
	var goal := _waypoint() - figure.global_position
	goal.y = 0
	if goal.length() > 2.0:
		walk_dir = walk_dir.slerp(goal.normalized(), clampf(delta * 0.8, 0.0, 1.0)).normalized()
	figure.look_at(figure.global_position + walk_dir, Vector3.UP)
	var space := get_world_3d().direct_space_state
	var next := figure.global_position + walk_dir * WALK_SPEED * delta
	var feet = _ground(space, next, 1.0)
	if feet == null:
		return
	var chest := figure.global_position + Vector3.UP * 1.1
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + walk_dir * 0.8, 1, [player.get_rid()])).is_empty():
		return
	figure.global_position = feet


## Пол под точкой (земля, мост, тропа, галерея) — или null над бездной.
func _ground(space: PhysicsDirectSpaceState3D, spot: Vector3, reach: float) -> Variant:
	var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * reach, spot + Vector3.DOWN * reach)
	down.exclude = [player.get_rid()]
	var hit := space.intersect_ray(down)
	if hit.is_empty() or hit.normal.y < 0.7:
		return null
	return hit.position


## Игрок её заметил — смотрит в её сторону, и между ними ничего нет. Тогда внизу экрана
## медленно проступает просьба героя.
func _watch_for_notice(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var chest := figure.global_position + Vector3.UP * 1.3
	var to_her := (chest - cam.global_position).normalized()
	var view := -cam.global_transform.basis.z
	var looking := view.angle_to(to_her) < NOTICE_CONE and mat.albedo_color.a > 0.5
	if looking:
		var sight := PhysicsRayQueryParameters3D.create(cam.global_position, chest)
		sight.exclude = [player.get_rid()]
		looking = get_world_3d().direct_space_state.intersect_ray(sight).is_empty()
	seen_time = seen_time + delta if looking else 0.0
	if seen_time >= NOTICE_TIME:
		noticed = true
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.say(LINES[rng.randi() % LINES.size()])


## Растворяется на ходу.
func _fade_out() -> void:
	fading = true
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE_TIME)
	tween.tween_callback(_on_faded)


func _on_faded() -> void:
	figure.visible = false
	fading = false
	timer = rng.randf_range(INTERVAL.x, INTERVAL.y)


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
