extends RefCounted

## Руки героя от первого лица для курения (smoke.gd). Сейчас выключены (smoke.SHOW_HANDS): ждём модель рук
## с костями. Руки — из модели манекена (CC0, по 3 кости на палец): каждая рука — отдельный экземпляр модели,
## у которого шейдер fp_arm.gdshader оставляет только эту руку (перчатка + рукав). Пальцы выставляются
## в позу под предмет, а сам экземпляр ставится так, чтобы предмет оказался в нужном месте кисти.
## Правая держит сигарету между указательным и средним; левая — пачку, потом зажигалку в кулаке
## (большой палец чиркает колёсико); когда держать нечего — рука плавно уходит вниз из кадра.

const ARM_MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")
const ARM_SHADER := preload("res://shaders/fp_arm.gdshader")
const HAND_AWAY := Vector3(0, -0.35, 0.05)        # куда рука уходит из кадра
const FINGERS := ["f_index", "f_middle", "f_ring", "f_pinky"]
# Сгиб суставов (рад, 01/02/03) для каждого хвата: указательный, средний, безымянный, мизинец, большой.
const POSE_CIG := [[0.15, 0.2, 0.1], [0.12, 0.2, 0.1], [1.2, 1.4, 0.9], [1.3, 1.4, 0.9], [0.35, 0.5, 0.4]]
const POSE_PACK := [[0.9, 0.9, 0.6], [0.95, 0.9, 0.6], [1.0, 0.9, 0.6], [1.05, 0.9, 0.6], [0.15, 0.25, 0.2]]
const POSE_LIGHTER := [[1.25, 1.3, 0.9], [1.3, 1.35, 0.9], [1.35, 1.35, 0.9], [1.4, 1.35, 0.9], [0.0, 0.15, 0.1]]


class Arm:
	var root: Node3D
	var skeleton: Skeleton3D
	var side: String               # "R" / "L"
	var hand_rest: Transform3D     # кость кисти в пространстве модели (исходная поза)
	var finger_dir: Vector3        # вдоль пальцев, в пространстве кисти
	var back_dir: Vector3          # тыльная сторона ладони, в пространстве кисти
	var pose: Array = []
	var flick := 0.0


var smoke                         # smoke.gd: сигарета, пачка, зажигалка и что сейчас в руках
var arm_r: Arm                     # правая — держит сигарету
var arm_l: Arm                     # левая — пачку, потом зажигалку


func _init(p_smoke: Node) -> void:
	smoke = p_smoke
	arm_r = _build_arm(true)
	arm_l = _build_arm(false)


## Рука: экземпляр манекена, видна только она (перчатка и рукав до плеча).
func _build_arm(right: bool) -> Arm:
	var arm := Arm.new()
	arm.side = "R" if right else "L"
	arm.root = Node3D.new()
	smoke.add_child(arm.root)
	var body: Node3D = ARM_MODEL.instantiate()
	arm.root.add_child(body)
	var mat := ShaderMaterial.new()
	mat.shader = ARM_SHADER
	mat.set_shader_parameter("side", 1.0 if right else -1.0)
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.extra_cull_margin = 2.0
	var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	if anim:
		anim.stop()
	arm.skeleton = body.find_child("Skeleton3D", true, false)
	var hand := arm.skeleton.find_bone("DEF-hand." + arm.side)
	arm.hand_rest = arm.skeleton.get_bone_global_rest(hand)
	# В Т-позе пальцы смотрят от тела вдоль X, тыльная сторона — вверх.
	var outward := Vector3(-1, 0, 0) if right else Vector3(1, 0, 0)
	arm.finger_dir = (arm.hand_rest.basis.inverse() * outward).normalized()
	arm.back_dir = (arm.hand_rest.basis.inverse() * Vector3.UP).normalized()
	arm.root.visible = false
	return arm


## Сгибает пальцы: для каждой кости — поворот вокруг её оси X (к ладони).
func _set_pose(arm: Arm, pose: Array, flick := 0.0) -> void:
	if arm.pose == pose and is_equal_approx(arm.flick, flick):
		return
	arm.pose = pose
	arm.flick = flick
	for f in 5:
		var base: String = "DEF-thumb" if f == 4 else "DEF-" + FINGERS[f]
		for j in 3:
			var bone := arm.skeleton.find_bone("%s.%02d.%s" % [base, j + 1, arm.side])
			if bone < 0:
				continue
			var bend: float = pose[f][j]
			if f == 4:
				bend += flick * 0.6
			if arm.side == "L":
				bend = -bend  # у левой руки кости зеркальные — сгиб к ладони в другую сторону
			arm.skeleton.set_bone_pose_rotation(bone, arm.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, bend))


## Где поставить экземпляр модели, чтобы точка кисти grip_point (в пространстве модели) оказалась в target,
## пальцы смотрели вдоль fingers, а тыльная сторона ладони — в back.
func _arm_transform(arm: Arm, grip_point: Vector3, target: Vector3, fingers: Vector3, back: Vector3) -> Transform3D:
	var f := fingers.normalized()
	var b := (back - f * back.dot(f)).normalized()
	var want := Basis(f, b, f.cross(b))
	var have := Basis(arm.finger_dir, arm.back_dir, arm.finger_dir.cross(arm.back_dir))
	var hand_basis := want * have.inverse()                      # кисть: её оси в пространстве камеры
	var root_basis := hand_basis * arm.hand_rest.basis.inverse()  # весь экземпляр модели
	return Transform3D(root_basis, target - root_basis * grip_point)


func _bone_pos(arm: Arm, bone_name: String) -> Vector3:
	return arm.skeleton.get_bone_global_pose(arm.skeleton.find_bone(bone_name + "." + arm.side)).origin


## Руки следуют за тем, что держат; когда держать нечего — плавно уходят вниз из кадра.
func update(delta: float) -> void:
	# Правая: сигарета между указательным и средним (в средних фалангах), пальцы вдоль сигареты.
	var right_goal = null
	if smoke.right_holds and smoke.cig.visible:
		_set_pose(arm_r, POSE_CIG)
		var between := (_bone_pos(arm_r, "DEF-f_index.02") + _bone_pos(arm_r, "DEF-f_middle.02")) / 2.0
		right_goal = _arm_transform(arm_r, between, smoke.cig.transform * Vector3(0, 0, -0.012),
			smoke.cig.basis * Vector3(0.08, -0.25, -1.0), smoke.cig.basis * Vector3.UP)
	_follow(arm_r, right_goal, delta)
	# Левая: пачка или зажигалка в ладони снизу, ладонью вверх, пальцы обхватывают предмет.
	var left_goal = null
	var item: Node3D = null
	if smoke.pack.visible:
		item = smoke.pack
		_set_pose(arm_l, POSE_PACK)
	elif smoke.lighter.visible and smoke.lighter_mats[0].albedo_color.a > 0.6:
		item = smoke.lighter
		_set_pose(arm_l, POSE_LIGHTER, smoke.thumb_flick)
	if item:
		var palm := _bone_pos(arm_l, "DEF-hand") * 0.4 + _bone_pos(arm_l, "DEF-f_middle.01") * 0.6
		var bottom := -0.045 if item == smoke.pack else -0.042
		left_goal = _arm_transform(arm_l, palm + arm_l.hand_rest.basis * (-arm_l.back_dir) * 0.02,
			item.transform * Vector3(0, bottom, 0.004), item.basis * Vector3(0.25, 0.35, -1.0), item.basis * Vector3.DOWN)
	_follow(arm_l, left_goal, delta)


func _follow(arm: Arm, goal: Variant, delta: float) -> void:
	if goal != null:
		var g: Transform3D = goal
		if not arm.root.visible:
			arm.root.transform = g.translated(HAND_AWAY)  # появляется снизу, а не возникает на месте
			arm.root.visible = true
		arm.root.transform = arm.root.transform.interpolate_with(g, clampf(delta * 12.0, 0.0, 1.0))
	elif arm.root.visible:
		arm.root.position = arm.root.position.move_toward(arm.root.position + HAND_AWAY, delta * 0.45)
		if arm.root.position.y < -0.35:
			arm.root.visible = false
