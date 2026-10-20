extends RefCounted

## Манекены на улицах: будто люди шли по своим делам и застыли.
## Здесь только решаем, где кто стоит и в какой позе; сами фигуры (модель манекена
## из библиотеки анимаций, застывшая в кадре анимации) создаёт crowd.gd.

const Builder = preload("res://scripts/builder.gd")

# Позы: анимация и доля её длины, на которой фигура застыла (-1 — случайный момент).
const WALKING := [
	{"anim": "Walk", "at": -1.0},
	{"anim": "Walk_Formal", "at": -1.0},
	{"anim": "Jog_Fwd", "at": -1.0},
]
const STANDING := [
	{"anim": "Idle", "at": -1.0},
	{"anim": "Idle_Talking", "at": -1.0},
	{"anim": "Interact", "at": 0.5},
	{"anim": "Push", "at": 0.4},
	{"anim": "Crouch_Idle", "at": -1.0},
	{"anim": "Fixing_Kneeling", "at": -1.0},
	{"anim": "Dance", "at": -1.0},
	{"anim": "PickUp_Table", "at": 0.45},
	{"anim": "Sitting_Idle", "at": -1.0, "sit": true},
]
const LOOKING_UP := [
	{"anim": "Spell_Simple_Idle", "at": -1.0},
	{"anim": "Idle", "at": -1.0},
]

var b: Builder
var rng: RandomNumberGenerator
var seat_mat: Material
var placed: Array[Vector2] = []
var floor_check: Callable  # есть ли пол в точке (над колодцами — нет)

## Итог: кого где поставить. {pos, yaw, anim, at}
var figures: Array[Dictionary] = []


func _init(builder: Builder, random: RandomNumberGenerator, concrete: Material) -> void:
	b = builder
	rng = random
	seat_mat = concrete


## Расставляет манекены по улицам, по галереям второго уровня, по бульвару и на площадях.
func populate(streets: Array[Vector4], plazas: Array[Vector2], decks: Array[Vector4], deck_y: float, has_floor: Callable) -> void:
	floor_check = has_floor
	for i in mini(30, decks.size()):
		var s: Vector4 = decks[rng.randi() % decks.size()]
		var a := Vector2(s.x, s.y)
		var c := Vector2(s.z, s.w)
		var dir := (c - a).normalized()
		var p := a.lerp(c, rng.randf_range(0.15, 0.85))
		var yaw := atan2(-dir.x, -dir.y) + (PI if rng.randf() < 0.5 else 0.0)
		if not _is_taken(p, 1.5):
			placed.append(p)
			_figure(Vector3(p.x, deck_y, p.y), yaw, _any_pose())

	for i in 90:
		var s: Vector4 = streets[rng.randi() % streets.size()]
		var a := Vector2(s.x, s.y)
		var c := Vector2(s.z, s.w)
		var dir := (c - a).normalized()
		# Больше половины — на тротуарах, остальные застыли посреди дороги.
		var on_sidewalk := rng.randf() < 0.6
		var lateral := rng.randf_range(4.5, 5.7) if on_sidewalk else rng.randf_range(0.5, 3.0)
		if rng.randf() < 0.5:
			lateral = -lateral
		var p := a.lerp(c, rng.randf()) + Vector2(-dir.y, dir.x) * lateral
		if absf(p.x) < 14.0:
			continue
		var yaw := atan2(-dir.x, -dir.y) + (PI if rng.randf() < 0.5 else 0.0)
		_place(p, yaw, 0.15 if on_sidewalk else 0.0)

	# Бульвар между колоннами.
	for i in 10:
		var p := Vector2(rng.randf_range(-6, 6), rng.randf_range(-350, 0))
		if p.distance_to(Vector2(0, -170)) < 4.0:
			continue  # не загораживать столик
		_place(p, rng.randf_range(-0.4, 0.4) + (PI if rng.randf() < 0.3 else 0.0))

	# Небольшие группы на площадях: все смотрят в одну сторону.
	for plaza in plazas:
		var look := rng.randf() * TAU
		for k in rng.randi_range(2, 5):
			var p := plaza + Vector2(rng.randf_range(-13, 13), rng.randf_range(-13, 13))
			if _is_taken(p, 1.2) or p.distance_to(plaza) < 6.5:
				continue
			placed.append(p)
			_figure(Vector3(p.x, 0.17, p.y), look + rng.randf_range(-0.3, 0.3), LOOKING_UP[rng.randi() % LOOKING_UP.size()])


func _place(p: Vector2, yaw: float, y := 0.0) -> void:
	if _is_taken(p, 1.5) or not floor_check.call(p):
		return
	placed.append(p)
	if rng.randf() < 0.15:
		# Пара, идущая рядом в ногу.
		var right := Vector2(cos(yaw), -sin(yaw)) * 0.35
		var pose: Dictionary = {"anim": "Walk_Formal", "at": rng.randf()}
		_figure(Vector3(p.x - right.x, y, p.y - right.y), yaw, pose)
		_figure(Vector3(p.x + right.x, y, p.y + right.y), yaw, pose)
	else:
		_figure(Vector3(p.x, y, p.y), yaw, _any_pose())


func _any_pose() -> Dictionary:
	return WALKING[rng.randi() % WALKING.size()] if rng.randf() < 0.55 else STANDING[rng.randi() % STANDING.size()]


func _is_taken(p: Vector2, r: float) -> bool:
	for q in placed:
		if p.distance_to(q) < r:
			return true
	return false


func _figure(pos: Vector3, yaw: float, pose: Dictionary) -> void:
	var at: float = pose.at
	figures.append({
		"pos": pos,
		"yaw": yaw,
		"anim": pose.anim,
		"at": rng.randf() if at < 0.0 else at,
	})
	var root := Transform3D(Basis(Vector3.UP, yaw), pos)
	if pose.get("sit", false):
		# Сиденье по замеру позы Sitting_Idle: таз на 0,54 м и в 0,33 м позади центра фигуры,
		# снизу у таза ~0,42 м. Плита чуть ниже — 0,40 м, от колен назад за таз, на двух ножках.
		b.box(root * Vector3(0, 0.38, 0.24), Vector3(0.62, 0.04, 0.56), seat_mat, root.basis)
		for side in [-0.26, 0.26]:
			b.box(root * Vector3(side, 0.18, 0.24), Vector3(0.06, 0.36, 0.5), seat_mat, root.basis, false)
	else:
		b.collider_box(root * Vector3(0, 0.9, 0), Vector3(0.5, 1.8, 0.4), root.basis)
