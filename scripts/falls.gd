extends Node3D

## Люди, срывающиеся с крыш (как в прологе: «с крыш ежечасно срываются те, кто больше не в силах…»).
## В случайный момент на крыше впереди, по взгляду, появляется бледная фигура: стоит на краю, шагает — и падает,
## кувыркаясь. Только в городе и только там, где его видно: на краю крыши в кадре, не дальше 45 м, ничем не загорожен.

const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")
const Structures = preload("res://scripts/structures.gd")
const FIRST := Vector2(20.0, 35.0)    # первый раз — через столько секунд игры
const EVERY := Vector2(30.0, 60.0)    # дальше — раз в столько
const DISTANCE := Vector2(15.0, 45.0)       # дальше в городском тумане и за голограммами его не разглядеть
const MIN_ROOF := 18.0                # с низких крыш падение слишком короткое — не успеть заметить
const STAND := 1.5                    # столько он стоит на краю, прежде чем шагнуть

enum State { WAITING, STANDING, FALLING }

var roofs: Array[Dictionary] = []
var figure: Node3D
var state := State.WAITING
var timer := 0.0
var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var rng := RandomNumberGenerator.new()


func setup(p_roofs: Array[Dictionary]) -> void:
	roofs = p_roofs


func _ready() -> void:
	rng.randomize()
	timer = rng.randf_range(FIRST.x, FIRST.y)
	# Бледная фигура, и туман её не перекрашивает: в тумане обычная фигура принимает цвет тумана или тонет
	# в тёмных домах, а эта — бледно-серая, чуть призрачная — видна на любом фоне (как манекены на улицах).
	var silhouette := StandardMaterial3D.new()
	silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette.albedo_color = Color(0.5, 0.5, 0.52)
	silhouette.disable_fog = true
	figure = Node3D.new()
	var body: Node3D = MODEL.instantiate()
	body.rotation.y = PI   # модель смотрит в +Z, «вперёд» у нас — -Z
	figure.add_child(body)
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = silhouette
	var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	anim.play("Idle")
	figure.visible = false
	add_child(figure)


func _process(delta: float) -> void:
	var player := Game.player
	if player == null:
		return
	match state:
		State.WAITING:
			timer -= delta
			if timer <= 0.0:
				timer = 3.0   # не вышло — попробуем чуть позже
				_try_start(player)
		State.STANDING:
			timer -= delta
			if timer <= 0.0:
				state = State.FALLING   # шагнул с края
		State.FALLING:
			velocity.y -= 9.8 * delta
			figure.position += velocity * delta
			figure.rotation += spin * delta
			if figure.position.y < 0.5:
				figure.visible = false
				state = State.WAITING
				timer = rng.randf_range(EVERY.x, EVERY.y)


## Крыша впереди, по центру взгляда, на видном расстоянии и ничем не загороженная.
func _try_start(player: CharacterBody3D) -> void:
	var p := player.global_position
	if roofs.is_empty() or not Structures.PLATFORM.has_point(Vector2(p.x, p.z)) or p.y > 120.0:
		return
	var cam := get_viewport().get_camera_3d()
	var forward := -cam.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state
	# Все крыши, что видны в кадре на нужном расстоянии; первая не загороженная — его.
	var candidates: Array[Dictionary] = []
	for roof in roofs:
		var pos: Vector3 = roof.pos
		var to := pos - p
		to.y = 0
		var dist := to.length()
		if pos.y >= MIN_ROOF and dist > DISTANCE.x and dist < DISTANCE.y and forward.dot(to / dist) > 0.55:
			candidates.append(roof)
	# Ближние — первыми (их лучше видно), но с разбросом, чтобы место каждый раз было новое.
	var order := {}
	for roof in candidates:
		order[roof] = Vector2(roof.pos.x - p.x, roof.pos.z - p.z).length() + rng.randf_range(0.0, 12.0)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order[a] < order[b])
	for roof in candidates:
		var pos: Vector3 = roof.pos
		var to := pos - p
		to.y = 0
		var dist := to.length()
		# Край крыши, обращённый к герою: щупаем пол от середины крыши к герою, пока крыша не кончится.
		var edge := _roof_edge(space, pos, -to / dist)
		if edge == Vector3.INF:
			continue
		if not _seen_whole(space, cam.global_position, edge, player):
			continue   # что-то закрывает голову, плечи или грудь
		if not cam.is_position_in_frustum(edge + Vector3.UP * 1.0):
			continue   # не в кадре
		figure.position = edge
		figure.rotation = Vector3(0, atan2(to.x, to.z), 0)   # лицом наружу, к пустоте (и к герою)
		velocity = -to / dist * 1.4 + Vector3.UP * 0.6
		spin = Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-1.6, 1.6))
		figure.visible = true
		state = State.STANDING
		timer = STAND
		return


## Самая крайняя твёрдая точка крыши по направлению dir от её середины — пол или бортик (парапет) у края:
## там он и стоит, на виду. INF — если крыши там нет. Высоту крыши берём с её поверхности под серединой.
func _roof_edge(space: PhysicsDirectSpaceState3D, center: Vector3, dir: Vector3) -> Vector3:
	var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.UP * 3.0, center + Vector3.DOWN * 6.0))
	if under.is_empty():
		return Vector3.INF
	var floor_y: float = under.position.y
	var last := Vector3.INF
	for k in 160:
		var probe := center + dir * (k * 0.5)
		probe.y = floor_y
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 1.6, probe + Vector3.DOWN * 3.0))
		if hit.is_empty() or hit.position.y < floor_y - 1.5:
			break   # под ногами пусто — край
		if hit.position.y < floor_y + 1.4:
			last = hit.position   # пол крыши или бортик у края (высокие щиты и будки — не опора)
	if last == Vector3.INF:
		return last
	return last - dir * 0.15


## Видно ли его: свободны все лучи — к голове, к плечам слева и справа и к груди (ноги снизу закрывает край крыши).
## Одного луча мало: он проскакивает впритирку мимо колонны, а сама фигура на экране оказывается за ней.
func _seen_whole(space: PhysicsDirectSpaceState3D, eye: Vector3, feet: Vector3, player: CharacterBody3D) -> bool:
	var side := (feet - eye).cross(Vector3.UP).normalized() * 0.6
	for point in [feet + Vector3.UP * 1.7, feet + Vector3.UP * 1.4 + side, feet + Vector3.UP * 1.4 - side,
			feet + Vector3.UP * 1.1]:
		var ray := PhysicsRayQueryParameters3D.create(eye, point)
		ray.exclude = [player.get_rid()]
		if not space.intersect_ray(ray).is_empty():
			return false
	return true
