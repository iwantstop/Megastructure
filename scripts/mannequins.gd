extends RefCounted

## Манекены на улицах: будто люди шли по своим делам и застыли.
## Каждый собирается из капсул по простому «скелету» и вклеивается в общий меш.

const Builder = preload("res://scripts/builder.gd")

# Углы в градусах. arm: (вперёд/назад, в сторону). leg/knee: вперёд/назад.
const WALK_A := {"leg_l": 22, "knee_l": -8, "leg_r": -18, "knee_r": -30,
	"arm_l": Vector2(-22, 4), "arm_r": Vector2(24, 4), "elbow_l": 8, "elbow_r": 22, "lean": -4}
const WALK_B := {"leg_l": -18, "knee_l": -30, "leg_r": 22, "knee_r": -8,
	"arm_l": Vector2(24, 4), "arm_r": Vector2(-22, 4), "elbow_l": 22, "elbow_r": 8, "lean": -4}
const POSES := [
	WALK_A,
	WALK_B,
	# Остановился и смотрит вверх.
	{"head": Vector3(30, 10, 0), "arm_l": Vector2(0, 5), "arm_r": Vector2(0, 5), "leg_l": 3, "leg_r": -3},
	# Показывает куда-то в небо.
	{"head": Vector3(25, 0, 0), "arm_r": Vector2(150, 8), "arm_l": Vector2(0, 5), "leg_l": 4, "leg_r": -2},
	# Опустил голову.
	{"head": Vector3(-35, 0, 0), "lean": -8, "arm_l": Vector2(8, 4), "arm_r": Vector2(8, 4), "elbow_l": 20, "elbow_r": 20},
	# Оглянулся на ходу.
	{"twist": 20, "head": Vector3(0, 65, 0), "leg_l": 18, "knee_l": -6, "leg_r": -14, "knee_r": -24,
		"arm_l": Vector2(-10, 6), "arm_r": Vector2(12, 6)},
	# Руки прижаты к груди.
	{"arm_l": Vector2(35, 15), "arm_r": Vector2(35, 15), "elbow_l": 110, "elbow_r": 110, "head": Vector3(-10, 0, 0)},
	# Тянется вперёд, будто хотел кого-то догнать.
	{"arm_r": Vector2(80, 0), "elbow_r": 10, "lean": -6, "leg_l": 20, "knee_l": -6, "leg_r": -16, "knee_r": -28,
		"arm_l": Vector2(-15, 5)},
	# Сидит на бетонном блоке.
	{"sit": true, "leg_l": 90, "leg_r": 84, "knee_l": -90, "knee_r": -84, "arm_l": Vector2(30, 5), "arm_r": Vector2(30, 5),
		"elbow_l": 40, "elbow_r": 40, "lean": -10, "head": Vector3(-15, 0, 0)},
]

var b: Builder
var rng: RandomNumberGenerator
var plastic: Material
var seat_mat: Material
var placed: Array[Vector2] = []
var floor_check: Callable  # есть ли пол в точке (над колодцами — нет)

var torso := _capsule(0.15, 0.5)
var hips := _capsule(0.14, 0.3)
var neck := _capsule(0.045, 0.12)
var head := _sphere(0.1)
var upper_arm := _capsule(0.045, 0.3)
var forearm := _capsule(0.04, 0.28)
var hand := _sphere(0.045)
var thigh := _capsule(0.07, 0.46)
var shin := _capsule(0.055, 0.46)
var foot := BoxMesh.new()


func _init(builder: Builder, random: RandomNumberGenerator, plastic_mat: Material, concrete: Material) -> void:
	b = builder
	rng = random
	plastic = plastic_mat
	seat_mat = concrete
	foot.size = Vector3(0.09, 0.06, 0.24)


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
			_figure(Vector3(p.x, deck_y, p.y), yaw, POSES[rng.randi() % POSES.size()])

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
			_figure(Vector3(p.x, 0.17, p.y), look + rng.randf_range(-0.3, 0.3), POSES[2 + rng.randi() % 2])


func _place(p: Vector2, yaw: float, y := 0.0) -> void:
	if _is_taken(p, 1.5) or not floor_check.call(p):
		return
	placed.append(p)
	if rng.randf() < 0.15:
		# Пара, держащаяся за руки.
		var right := Vector2(cos(yaw), -sin(yaw)) * 0.3
		var left_pose := WALK_A.duplicate()
		left_pose["arm_r"] = Vector2(5, 18)
		var right_pose := WALK_A.duplicate()
		right_pose["arm_l"] = Vector2(5, 18)
		_figure(Vector3(p.x - right.x, y, p.y - right.y), yaw, left_pose)
		_figure(Vector3(p.x + right.x, y, p.y + right.y), yaw, right_pose)
	else:
		_figure(Vector3(p.x, y, p.y), yaw, POSES[rng.randi() % POSES.size()])


func _is_taken(p: Vector2, r: float) -> bool:
	for q in placed:
		if p.distance_to(q) < r:
			return true
	return false


func _figure(pos: Vector3, yaw: float, pose: Dictionary) -> void:
	var root := Transform3D(Basis(Vector3.UP, yaw), pos)
	var leg := [_deg(pose, "leg_l"), _deg(pose, "leg_r")]
	var knee := [_deg(pose, "knee_l"), _deg(pose, "knee_r")]
	var arm: Array = [pose.get("arm_l", Vector2.ZERO), pose.get("arm_r", Vector2.ZERO)]
	var elbow := [_deg(pose, "elbow_l"), _deg(pose, "elbow_r")]
	var head_rot: Vector3 = pose.get("head", Vector3.ZERO)

	# Таз ставим на такой высоте, чтобы нижняя нога касалась земли.
	var pelvis_y := 0.05 + maxf(_leg_extent(leg[0], knee[0]), _leg_extent(leg[1], knee[1]))
	var pelvis := root * Transform3D(Basis.IDENTITY, Vector3(0, pelvis_y, 0))
	b.part(hips, pelvis * Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(1, 1, 0.7)), Vector3.ZERO), plastic)

	var spine := pelvis * Transform3D(Basis.from_euler(Vector3(_deg(pose, "lean"), _deg(pose, "twist"), 0)), Vector3(0, 0.05, 0))
	b.part(torso, spine * Transform3D(Basis.from_scale(Vector3(1, 1, 0.62)), Vector3(0, 0.24, 0)), plastic)
	var neck_t := spine * Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0))
	b.part(neck, neck_t * Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), plastic)
	var head_t := neck_t * Transform3D(Basis.from_euler(head_rot * (PI / 180.0)), Vector3(0, 0.06, 0))
	b.part(head, head_t * Transform3D(Basis.from_scale(Vector3(0.85, 1.12, 0.95)), Vector3(0, 0.1, 0)), plastic)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var a: Vector2 = arm[i] * (PI / 180.0)
		var shoulder := spine * Transform3D(Basis.from_euler(Vector3(a.x, 0, a.y * side)), Vector3(side * 0.19, 0.42, 0))
		b.part(upper_arm, shoulder * Transform3D(Basis.IDENTITY, Vector3(0, -0.15, 0)), plastic)
		var elbow_t := shoulder * Transform3D(Basis(Vector3.RIGHT, elbow[i]), Vector3(0, -0.3, 0))
		b.part(forearm, elbow_t * Transform3D(Basis.IDENTITY, Vector3(0, -0.14, 0)), plastic)
		b.part(hand, elbow_t * Transform3D(Basis.from_scale(Vector3(0.7, 1.2, 0.5)), Vector3(0, -0.31, 0)), plastic)

		var hip := pelvis * Transform3D(Basis(Vector3.RIGHT, leg[i]), Vector3(side * 0.09, -0.02, 0))
		b.part(thigh, hip * Transform3D(Basis.IDENTITY, Vector3(0, -0.23, 0)), plastic)
		var knee_t := hip * Transform3D(Basis(Vector3.RIGHT, knee[i]), Vector3(0, -0.46, 0))
		b.part(shin, knee_t * Transform3D(Basis.IDENTITY, Vector3(0, -0.23, 0)), plastic)
		b.part(foot, knee_t * Transform3D(Basis.IDENTITY, Vector3(0, -0.48, -0.06)), plastic)

	if pose.get("sit", false):
		var seat_h := pelvis_y - 0.1
		b.box(root * Vector3(0, seat_h / 2.0, -0.1), Vector3(0.7, seat_h, 0.6), seat_mat, root.basis)
	else:
		b.collider_box(root * Vector3(0, 0.9, 0), Vector3(0.5, 1.8, 0.4), root.basis)


## Насколько нога (бедро + голень + стопа) вытянута вниз от тазобедренного сустава.
func _leg_extent(hip_angle: float, knee_angle: float) -> float:
	return 0.02 + 0.46 * cos(hip_angle) + 0.48 * cos(hip_angle + knee_angle) + 0.03


func _deg(pose: Dictionary, key: String) -> float:
	return deg_to_rad(float(pose.get(key, 0.0)))


func _capsule(r: float, h: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = r
	mesh.height = h
	mesh.radial_segments = 12
	mesh.rings = 4
	return mesh


func _sphere(r: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh
