extends Node3D

## Сигареты. Всё «в руках» — перед камерой (узел — дочерний у камеры героя):
## 1. T — из-за нижнего края выезжает пачка, крышка откидывается, из пачки поднимается сигарета
##    и уходит в нижнюю часть кадра; пачка уезжает. В пачке 10 штук.
## 2. Выезжает зажигалка (как Zippo), крышка со щелчком откидывается.
## 3. T — чиркнуть колёсиком: искры, огонь загорается с вероятностью 50%.
## 4. Пламя подносится к кончику — тот разгорается; зажигалка закрывается и медленно тает.
## 5. Держать T — затяжка: сигарета плавно подносится ближе, кончик разгорается, бумага тлеет,
##    от кончика вьётся тонкая струйка дыма. Отпустить — сигарета плавно возвращается, выдох дымом.
## 6. Догорела до фильтра — окурок улетает вниз. Следующий T — новая сигарета (пока есть в пачке).
## Руки в перчатках: правая держит сигарету между пальцами, левая — пачку, потом зажигалку; рукава уходят
## за край кадра. Припадок (seizure.gd) гасит сигарету — T, чтобы прикурить снова, — и после него руки
## дрожат, дрожь медленно стихает; пока дрожат, зажигалка загорается хуже.

enum State { IDLE, TAKING, WAIT_STRIKE, LIGHTING, SMOKING, UNLIT, BUSY }

const PACK_SIZE := 10
const STRIKE_CHANCE := 0.5
const SHOW_HANDS := false         # руки выключены: ждём модель рук с костями (код рук ниже — готов)
const TREMOR_TIME := 120.0        # за столько секунд дрожь после припадка стихает
const FILTER_LEN := 0.025
const PAPER_LEN := 0.058
const PAPER_MIN := 0.006           # догорело — дальше только фильтр
const CIG_R := 0.0039
const BURN_IDLE := 0.0006          # м/с — тлеет сама по себе
const BURN_PUFF := 0.006           # м/с — во время затяжки
const PUFF_MAX := 3.0              # дольше этого затяжка не «копится» для выдоха
const MIX_RATE := 22050.0

# Где что держится (в координатах камеры: -Z вперёд, +Y вверх, +X вправо).
const REST_POS := Vector3(0.06, -0.095, -0.21)
const REST_ROT := Vector3(0.12, 0.42, -0.25)       # кончик — вперёд и немного влево/вверх
const PUFF_POS := Vector3(0.008, -0.078, -0.075)   # у губ: фильтр за нижним краем кадра
const PUFF_ROT := Vector3(-0.12, 0.08, -0.05)
const HIDDEN_DROP := Vector3(0, -0.25, 0)
const PACK_POS := Vector3(0.05, -0.1, -0.27)
const LIGHTER_POS := Vector3(-0.055, -0.115, -0.25)

var player: CharacterBody3D
var state := State.IDLE
var left_in_pack := PACK_SIZE
var paper_len := PAPER_LEN
var puffing := false
var puff_amount := 0.0             # 0..1 — «приближение» сигареты к губам
var puff_time := 0.0
var glow := 0.0                    # яркость кончика
var rng := RandomNumberGenerator.new()

var pack: Node3D
var pack_lid: Node3D
var pack_slots: Array[MeshInstance3D] = []
var cig: Node3D
var paper: MeshInstance3D
var ember: MeshInstance3D
var ash: MeshInstance3D
var ember_light: OmniLight3D
var ember_mat: StandardMaterial3D
var stream: GPUParticles3D
var exhale: GPUParticles3D
var lighter: Node3D
var lighter_lid: Node3D
var flame: MeshInstance3D
var flame_light: OmniLight3D
var spark: MeshInstance3D
var lighter_mats: Array[StandardMaterial3D] = []
var flame_on := false
var arm_r: Arm                     # правая — держит сигарету
var arm_l: Arm                     # левая — пачку, потом зажигалку
var right_holds := false
var tremor := 0.0                  # 0..1 — дрожь рук после припадка

var snd: Dictionary = {}
var crackle: AudioStreamPlayer


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	rng.randomize()
	add_to_group("smoke")
	_build_pack()
	_build_cigarette()
	_build_lighter()
	if SHOW_HANDS:
		arm_r = _build_arm(true)
		arm_l = _build_arm(false)
	_build_smoke()
	_build_sounds()
	pack.visible = false
	cig.visible = false
	lighter.visible = false


# --- Управление ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.physical_keycode == KEY_T and not event.echo):
		return
	if player.locked or player.flying:
		return
	if event.pressed:
		match state:
			State.IDLE:
				_take_cigarette()
			State.WAIT_STRIKE:
				_strike()
			State.UNLIT:
				state = State.BUSY
				_lighter_out()  # погасла — прикурить снова
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if SHOW_HANDS:
		_hands(delta)
	# Дрожь после припадка: весь «набор в руках» мелко трясётся и медленно успокаивается.
	tremor = move_toward(tremor, 0.0, delta / TREMOR_TIME)
	var ms := Time.get_ticks_msec() * 0.001
	var shake := tremor * tremor
	position = Vector3(sin(ms * 31.0) * sin(ms * 7.3), sin(ms * 27.0 + 1.0) * sin(ms * 5.1), 0.0) * 0.006 * shake
	rotation.z = sin(ms * 23.0) * sin(ms * 3.7) * 0.03 * shake
	if state == State.SMOKING:
		var holding: bool = Input.is_physical_key_pressed(KEY_T) and not player.locked
		if holding and not puffing:
			puffing = true
			puff_time = 0.0
			crackle.play()
		elif not holding and puffing:
			puffing = false
			crackle.stop()
			_exhale()
		if puffing:
			puff_time += delta
		puff_amount = move_toward(puff_amount, 1.0 if puffing else 0.0, delta / (0.7 if puffing else 0.9))
		var k := smoothstep(0.0, 1.0, puff_amount)
		cig.position = REST_POS.lerp(PUFF_POS, k)
		cig.rotation = REST_ROT.lerp(PUFF_ROT, k)
		paper_len -= (BURN_PUFF if puffing else BURN_IDLE) * delta
		_set_paper(paper_len)
		glow = move_toward(glow, 1.0 if puffing else 0.35, delta * (2.5 if puffing else 1.2))
		if paper_len <= PAPER_MIN:
			_throw_away()
	if cig.visible:
		var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.011) * sin(Time.get_ticks_msec() * 0.0037)
		ember_mat.emission_energy_multiplier = lerpf(0.4, 6.0, glow) * flicker
		ember_light.light_energy = lerpf(0.02, 0.35, glow) * flicker
	if flame_on:
		var f := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.02) + 0.08 * sin(Time.get_ticks_msec() * 0.053)
		flame.scale = Vector3(1.0, 2.6 * f, 1.0)
		flame_light.light_energy = 0.9 * f


## Финал и прочие сцены: всё убрать из рук.
func put_away() -> void:
	puffing = false
	crackle.stop()
	state = State.BUSY
	var tween := create_tween().set_parallel()
	for node in [pack, cig, lighter]:
		if node.visible:
			tween.tween_property(node, "position", node.position + HIDDEN_DROP, 0.8).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(func() -> void:
		pack.visible = false
		cig.visible = false
		lighter.visible = false
		right_holds = false
		stream.emitting = false
		state = State.IDLE)


# --- Шаги ----------------------------------------------------------------------

## Пачка выезжает, крышка откидывается, сигарета поднимается и уходит в руку; пачка уезжает.
func _take_cigarette() -> void:
	state = State.BUSY
	pack.visible = true
	pack.position = PACK_POS + HIDDEN_DROP
	pack.rotation = Vector3(0.35, -0.25, 0.05)
	pack_lid.rotation.x = 0.0
	for i in pack_slots.size():
		pack_slots[i].visible = i < left_in_pack
	var tween := create_tween()
	tween.tween_callback(_play.bind("rustle"))
	tween.tween_property(pack, "position", PACK_POS, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_play.bind("pack_open"))
	tween.tween_property(pack_lid, "rotation:x", -2.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if left_in_pack <= 0:
		# Пусто. Герой смотрит в пустую пачку — и убирает её.
		tween.tween_interval(1.0)
		tween.tween_callback(func() -> void:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.say("Пусто", 1.0, 0.6, 1.0))
		tween.tween_property(pack_lid, "rotation:x", 0.0, 0.3)
		tween.tween_property(pack, "position", PACK_POS + HIDDEN_DROP, 0.6).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func() -> void:
			pack.visible = false
			state = State.IDLE)
		return
	tween.tween_interval(0.15)
	tween.tween_callback(_pull_from_pack)


func _pull_from_pack() -> void:
	left_in_pack -= 1
	pack_slots[left_in_pack].visible = false
	# Сигарета появляется на месте взятой — в координатах камеры — и поднимается из пачки.
	var slot: Transform3D = pack.transform * pack_slots[left_in_pack].transform
	var up := slot.basis.y.normalized()
	cig.visible = true
	paper_len = PAPER_LEN
	_set_paper(paper_len)
	glow = 0.0
	ember.visible = false
	ash.visible = false
	ember_light.visible = false
	# Фильтр — у начала узла, а в пачке сигареты стоят фильтром вверх.
	var tip_down := Basis(pack.transform.basis.x, -PI / 2.0) * pack.transform.basis
	cig.transform = Transform3D(tip_down, slot.origin + up * 0.012)
	var lifted := cig.position + up * 0.05
	var tween := create_tween()
	tween.tween_callback(_play.bind("rustle"))
	tween.tween_property(cig, "position", lifted, 0.5).set_trans(Tween.TRANS_SINE)
	tween.set_parallel()
	tween.chain().tween_property(cig, "position", REST_POS, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cig, "rotation", REST_ROT, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pack_lid, "rotation:x", 0.0, 0.35).set_delay(0.3)
	tween.chain().tween_callback(func() -> void: right_holds = true)  # сигарета в руке — рука поднимается снизу
	tween.tween_callback(_play.bind("pack_close"))
	tween.tween_property(pack, "position", PACK_POS + HIDDEN_DROP, 0.6).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(func() -> void: pack.visible = false)
	tween.chain().tween_callback(_lighter_out)


## Зажигалка выезжает слева, крышка со щелчком откидывается — ждём T.
func _lighter_out() -> void:
	lighter.visible = true
	_lighter_alpha(1.0)
	lighter.position = LIGHTER_POS + HIDDEN_DROP
	lighter.rotation = Vector3(0.15, 0.35, 0.1)
	lighter_lid.rotation.z = 0.0
	flame.visible = false
	flame_light.visible = false
	var tween := create_tween()
	tween.tween_property(lighter, "position", LIGHTER_POS, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_play.bind("zippo_open"))
	tween.tween_property(lighter_lid, "rotation:z", -2.3, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: state = State.WAIT_STRIKE)


## Чирк колёсиком: искры, огонь — с вероятностью 50%.
func _strike() -> void:
	state = State.BUSY
	_play("strike")
	spark.visible = true
	spark.scale = Vector3.ONE * rng.randf_range(0.7, 1.3)
	var lit := rng.randf() < STRIKE_CHANCE * (1.0 - 0.5 * tremor)  # дрожат руки — загорается хуже
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: thumb_flick = v, 0.0, 1.0, 0.05)
	tween.parallel().tween_property(lighter, "rotation:x", 0.22, 0.05)
	tween.tween_method(func(v: float) -> void: thumb_flick = v, 1.0, 0.0, 0.12)
	tween.parallel()
	tween.tween_property(lighter, "rotation:x", 0.15, 0.1)
	tween.tween_callback(func() -> void: spark.visible = false)
	if not lit:
		tween.tween_callback(func() -> void: state = State.WAIT_STRIKE)
		return
	tween.tween_callback(_ignite)


func _ignite() -> void:
	_play("ignite")
	flame_on = true
	flame.visible = true
	flame_light.visible = true
	state = State.LIGHTING
	# Пламя — к кончику сигареты: зажигалку ставим так, чтобы верх пламени коснулся кончика.
	var tip := cig.transform * Vector3(0, 0, -(FILTER_LEN + paper_len + 0.002))
	var flame_top := flame.position + Vector3(0, 0.02, 0)
	var target := tip - lighter.transform.basis * flame_top
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(lighter, "position", target, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		ember.visible = true
		ash.visible = true
		ember_light.visible = true
		crackle.play())
	tween.tween_method(func(v: float) -> void: glow = v, 0.0, 1.0, 1.0)  # кончик разгорается
	tween.tween_callback(func() -> void:
		crackle.stop()
		stream.emitting = true)
	# Зажигалка отходит, закрывается и медленно тает.
	tween.tween_property(lighter, "position", LIGHTER_POS, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		flame_on = false
		flame.visible = false
		flame_light.visible = false
		_play("zippo_close"))
	tween.tween_property(lighter_lid, "rotation:z", 0.0, 0.15)
	tween.tween_method(_lighter_alpha, 1.0, 0.0, 1.4)
	tween.tween_callback(func() -> void:
		lighter.visible = false
		state = State.SMOKING)


## Выдох: дым у губ — тем гуще, чем дольше была затяжка.
func _exhale() -> void:
	var strength := clampf(puff_time / PUFF_MAX, 0.25, 1.0)
	_play("exhale", linear_to_db(strength) - 2.0)
	exhale.amount_ratio = strength
	exhale.restart()
	exhale.emitting = true


## Догорела до фильтра — окурок улетает вниз, дым ещё вьётся.
func _throw_away() -> void:
	state = State.BUSY
	puffing = false
	crackle.stop()
	stream.emitting = false
	var tween := create_tween().set_parallel()
	right_holds = false  # пальцы разжались — окурок летит, рука опускается
	tween.tween_property(cig, "position", cig.position + Vector3(0.08, -0.3, -0.1), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(cig, "rotation", cig.rotation + Vector3(2.5, 0.8, 0), 0.6)
	tween.chain().tween_callback(func() -> void:
		cig.visible = false
		state = State.IDLE)


## Припадок: сигарета гаснет (остаётся в руке), руки начинают дрожать.
func seizure_hit() -> void:
	tremor = 1.0
	if state == State.SMOKING:
		puffing = false
		puff_amount = 0.0
		cig.position = REST_POS
		cig.rotation = REST_ROT
		crackle.stop()
		stream.emitting = false
		glow = 0.0
		ember.visible = false
		ember_light.visible = false
		state = State.UNLIT


func _set_paper(length: float) -> void:
	length = maxf(length, PAPER_MIN)
	paper.scale = Vector3(1, length, 1)
	paper.position = Vector3(0, 0, -(FILTER_LEN + length / 2.0))
	ember.position = Vector3(0, 0, -(FILTER_LEN + length + 0.0012))
	ash.position = ember.position + Vector3(0, 0, -0.0022)
	ember_light.position = ember.position + Vector3(0, 0.01, -0.01)
	stream.position = ash.position


func _lighter_alpha(a: float) -> void:
	for mat in lighter_mats:
		mat.albedo_color.a = a


# --- Руки --------------------------------------------------------------------------
# Руки — из модели манекена (CC0, по 3 кости на палец): каждая рука — отдельный экземпляр модели,
# у которого шейдер fp_arm.gdshader оставляет только эту руку (перчатка + рукав). Пальцы выставляются
# в позу под предмет, а сам экземпляр ставится так, чтобы предмет оказался в нужном месте кисти.

const ARM_MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")
const ARM_SHADER := preload("res://shaders/fp_arm.gdshader")
const HAND_AWAY := Vector3(0, -0.35, 0.05)        # куда рука уходит из кадра
const FINGERS := ["f_index", "f_middle", "f_ring", "f_pinky"]
# Сгиб суставов (рад, 01/02/03) для каждого хвата: указательный, средний, безымянный, мизинец, большой.
const POSE_CIG := [[0.15, 0.2, 0.1], [0.12, 0.2, 0.1], [1.2, 1.4, 0.9], [1.3, 1.4, 0.9], [0.35, 0.5, 0.4]]
const POSE_PACK := [[0.9, 0.9, 0.6], [0.95, 0.9, 0.6], [1.0, 0.9, 0.6], [1.05, 0.9, 0.6], [0.15, 0.25, 0.2]]
const POSE_LIGHTER := [[1.25, 1.3, 0.9], [1.3, 1.35, 0.9], [1.35, 1.35, 0.9], [1.4, 1.35, 0.9], [0.0, 0.15, 0.1]]

var thumb_flick := 0.0             # 0..1 — большой палец чиркает колёсико


class Arm:
	var root: Node3D
	var skeleton: Skeleton3D
	var side: String               # "R" / "L"
	var hand_rest: Transform3D     # кость кисти в пространстве модели (исходная поза)
	var finger_dir: Vector3        # вдоль пальцев, в пространстве кисти
	var back_dir: Vector3          # тыльная сторона ладони, в пространстве кисти
	var pose: Array = []
	var flick := 0.0


## Рука: экземпляр манекена, видна только она (перчатка и рукав до плеча).
func _build_arm(right: bool) -> Arm:
	var arm := Arm.new()
	arm.side = "R" if right else "L"
	arm.root = Node3D.new()
	add_child(arm.root)
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
func _hands(delta: float) -> void:
	# Правая: сигарета между указательным и средним (в средних фалангах), пальцы вдоль сигареты.
	var right_goal = null
	if right_holds and cig.visible:
		_set_pose(arm_r, POSE_CIG)
		var between := (_bone_pos(arm_r, "DEF-f_index.02") + _bone_pos(arm_r, "DEF-f_middle.02")) / 2.0
		right_goal = _arm_transform(arm_r, between, cig.transform * Vector3(0, 0, -0.012),
			cig.basis * Vector3(0.08, -0.25, -1.0), cig.basis * Vector3.UP)
	_follow(arm_r, right_goal, delta)
	# Левая: пачка или зажигалка в ладони снизу, ладонью вверх, пальцы обхватывают предмет.
	var left_goal = null
	var item: Node3D = null
	if pack.visible:
		item = pack
		_set_pose(arm_l, POSE_PACK)
	elif lighter.visible and lighter_mats[0].albedo_color.a > 0.6:
		item = lighter
		_set_pose(arm_l, POSE_LIGHTER, thumb_flick)
	if item:
		var palm := _bone_pos(arm_l, "DEF-hand") * 0.4 + _bone_pos(arm_l, "DEF-f_middle.01") * 0.6
		var bottom := -0.045 if item == pack else -0.042
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


# --- Модели ----------------------------------------------------------------------

func _mat(color: Color, roughness := 0.7, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, segments := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## Пачка 55×85×22 мм: тёмная, с белой полосой, без марки. Сверху откидная крышка на заднем ребре.
## Внутри — 10 сигарет фильтрами вверх (видны, когда крышка открыта).
func _build_pack() -> void:
	pack = Node3D.new()
	add_child(pack)
	var dark := _mat(Color(0.12, 0.1, 0.1), 0.6)
	var band := _mat(Color(0.75, 0.73, 0.7), 0.5)
	var filter := _mat(Color(0.78, 0.55, 0.32), 0.8)
	var w := 0.055
	var h := 0.085
	var d := 0.022
	var body_h := h - 0.022
	_box(pack, Vector3(w, body_h, d), Vector3(0, -0.011, 0), dark)
	_box(pack, Vector3(w + 0.0004, 0.012, d + 0.0004), Vector3(0, -0.012, 0), band)
	# Крышка: шарнир на заднем верхнем ребре корпуса; откидывается назад (rotation.x < 0).
	pack_lid = Node3D.new()
	pack_lid.position = Vector3(0, body_h / 2.0 - 0.011, -d / 2.0)
	pack.add_child(pack_lid)
	_box(pack_lid, Vector3(w, 0.022, d), Vector3(0, 0.011, d / 2.0), dark)
	# 10 сигарет: два ряда по 5, торчат фильтрами над корпусом.
	var top := body_h / 2.0 - 0.011
	for row in 2:
		for i in 5:
			var x := (i - 2) * 0.0098
			var z := (row - 0.5) * 0.0086
			pack_slots.append(_cyl(pack, CIG_R, 0.024, Vector3(x, top - 0.008, z), filter, 8))


## Сигарета: узел — у конца фильтра, кончик — в сторону -Z.
func _build_cigarette() -> void:
	cig = Node3D.new()
	add_child(cig)
	var filter_mat := _mat(Color(0.8, 0.56, 0.3), 0.85)
	var paper_mat := _mat(Color(0.93, 0.92, 0.88), 0.9)
	paper_mat.emission_enabled = true
	paper_mat.emission = Color(0.9, 0.9, 0.88)
	paper_mat.emission_energy_multiplier = 0.06  # чтобы в тёмном городе бумагу было видно
	var f := _cyl(cig, CIG_R, FILTER_LEN, Vector3(0, 0, -FILTER_LEN / 2.0), filter_mat)
	f.rotation.x = PI / 2.0
	paper = _cyl(cig, CIG_R, 1.0, Vector3.ZERO, paper_mat)
	paper.rotation.x = PI / 2.0
	ember_mat = _mat(Color(0.25, 0.06, 0.02), 0.9)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.32, 0.06)
	ember = _cyl(cig, CIG_R * 0.98, 0.0024, Vector3.ZERO, ember_mat)
	ember.rotation.x = PI / 2.0
	ash = _cyl(cig, CIG_R * 0.92, 0.002, Vector3.ZERO, _mat(Color(0.45, 0.44, 0.42), 1.0))
	ash.rotation.x = PI / 2.0
	ember_light = OmniLight3D.new()
	ember_light.light_color = Color(1.0, 0.45, 0.15)
	ember_light.omni_range = 0.35
	ember_light.shadow_enabled = false
	cig.add_child(ember_light)


## Зажигалка как Zippo: хромированный корпус, крышка на шарнире справа, ветрозащита с отверстиями,
## колёсико. Пламя — вытянутая светящаяся капля и тёплый свет.
func _build_lighter() -> void:
	lighter = Node3D.new()
	add_child(lighter)
	var chrome := _mat(Color(0.72, 0.72, 0.74), 0.28, 1.0)
	var insert := _mat(Color(0.55, 0.55, 0.56), 0.35, 1.0)
	var wheel := _mat(Color(0.3, 0.3, 0.3), 0.5, 1.0)
	for m in [chrome, insert, wheel]:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # чтобы медленно растаять
		lighter_mats.append(m)
	var w := 0.038
	var h := 0.039
	var d := 0.013
	_box(lighter, Vector3(w, h, d), Vector3(0, -h / 2.0, 0), chrome)
	_box(lighter, Vector3(w * 0.78, 0.016, d * 0.82), Vector3(-0.002, 0.008, 0), insert)  # ветрозащита
	var wheel_node := _cyl(lighter, 0.0045, 0.006, Vector3(0.012, 0.012, 0), wheel, 10)
	wheel_node.rotation.z = PI / 2.0
	lighter_lid = Node3D.new()
	lighter_lid.position = Vector3(w / 2.0, 0.0, 0)
	lighter.add_child(lighter_lid)
	_box(lighter_lid, Vector3(w, 0.018, d), Vector3(-w / 2.0, 0.009, 0), chrome)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(1.0, 0.62, 0.22)
	var sphere := SphereMesh.new()
	sphere.radius = 0.0055
	sphere.height = 0.011
	flame = MeshInstance3D.new()
	flame.mesh = sphere
	flame.material_override = flame_mat
	flame.position = Vector3(-0.002, 0.03, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lighter.add_child(flame)
	flame_light = OmniLight3D.new()
	flame_light.light_color = Color(1.0, 0.6, 0.25)
	flame_light.omni_range = 1.6
	flame_light.position = flame.position
	lighter.add_child(flame_light)
	var spark_mat := flame_mat.duplicate()
	spark_mat.albedo_color = Color(1.0, 0.85, 0.5)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.004
	spark_mesh.height = 0.008
	spark = MeshInstance3D.new()
	spark.mesh = spark_mesh
	spark.material_override = spark_mat
	spark.position = Vector3(0.006, 0.02, 0)
	spark.visible = false
	lighter.add_child(spark)


## Мягкая круглая «дымка» для частиц.
func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _smoke_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _puff_texture()
	m.albedo_color = Color(0.82, 0.83, 0.85, alpha)
	m.vertex_color_use_as_albedo = true
	return m


func _fade_ramp(peak: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 1, 1, peak))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


func _grow_curve(from: float, to: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = to
	c.add_point(Vector2(0, from))
	c.add_point(Vector2(1, to))
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


## Тонкая струйка от кончика и облачко выдоха. Частицы живут в мире — дым остаётся там,
## где его выпустили, и не «приклеен» к камере.
func _build_smoke() -> void:
	var thin := ParticleProcessMaterial.new()
	thin.direction = Vector3(0, 1, 0)
	thin.spread = 4.0
	thin.initial_velocity_min = 0.01
	thin.initial_velocity_max = 0.02
	thin.gravity = Vector3(0, 0.05, 0)
	thin.damping_min = 0.02
	thin.damping_max = 0.05
	thin.turbulence_enabled = true
	thin.turbulence_noise_strength = 0.6
	thin.turbulence_noise_scale = 3.0
	thin.turbulence_influence_min = 0.02
	thin.turbulence_influence_max = 0.05
	thin.scale_min = 1.0
	thin.scale_max = 1.0
	thin.scale_curve = _grow_curve(1.0, 6.0)
	thin.color_ramp = _fade_ramp(0.5)
	var thin_quad := QuadMesh.new()
	thin_quad.size = Vector2(0.006, 0.006)
	thin_quad.material = _smoke_material(0.35)
	stream = GPUParticles3D.new()
	stream.process_material = thin
	stream.draw_pass_1 = thin_quad
	stream.amount = 90
	stream.lifetime = 3.5
	stream.local_coords = false
	stream.emitting = false
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stream.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	cig.add_child(stream)

	var out := ParticleProcessMaterial.new()
	out.direction = Vector3(0, 0.15, -1)
	out.spread = 14.0
	out.initial_velocity_min = 0.5
	out.initial_velocity_max = 0.9
	out.damping_min = 0.9
	out.damping_max = 1.4
	out.gravity = Vector3(0, 0.06, 0)
	out.turbulence_enabled = true
	out.turbulence_noise_strength = 0.8
	out.turbulence_noise_scale = 1.5
	out.turbulence_influence_min = 0.03
	out.turbulence_influence_max = 0.08
	out.scale_curve = _grow_curve(1.0, 9.0)
	out.color_ramp = _fade_ramp(0.35)
	var out_quad := QuadMesh.new()
	out_quad.size = Vector2(0.05, 0.05)
	out_quad.material = _smoke_material(0.3)
	exhale = GPUParticles3D.new()
	exhale.process_material = out
	exhale.draw_pass_1 = out_quad
	exhale.amount = 70
	exhale.lifetime = 3.2
	exhale.one_shot = true
	exhale.explosiveness = 0.0
	exhale.local_coords = false
	exhale.emitting = false
	exhale.position = Vector3(0, -0.06, -0.12)
	exhale.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exhale.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	add_child(exhale)


# --- Звуки (синтез) -----------------------------------------------------------

func _build_sounds() -> void:
	snd = {
		"rustle": _wav(0.35, func(t: float) -> float: return _noise() * 0.25 * exp(-t * 9.0) * (0.6 + 0.4 * sin(t * 90.0))),
		"pack_open": _wav(0.12, func(t: float) -> float: return _noise() * 0.35 * exp(-t * 40.0)),
		"pack_close": _wav(0.1, func(t: float) -> float: return (_noise() * 0.3 + sin(TAU * 220.0 * t) * 0.3) * exp(-t * 50.0)),
		"zippo_open": _wav(0.5, _clink.bind(1.0)),
		"zippo_close": _wav(0.25, func(t: float) -> float: return (sin(TAU * 900.0 * t) * 0.5 + _noise() * 0.4) * exp(-t * 45.0)),
		"strike": _wav(0.22, func(t: float) -> float: return _noise() * 0.6 * exp(-t * 14.0) * (0.5 + 0.5 * sin(t * 700.0))),
		"ignite": _wav(0.6, func(t: float) -> float: return _soft_noise() * 0.7 * minf(t * 20.0, 1.0) * exp(-t * 5.0)),
		"exhale": _wav(1.6, func(t: float) -> float: return _soft_noise() * 0.45 * sin(PI * minf(t / 1.6, 1.0)) ** 2),
	}
	crackle = AudioStreamPlayer.new()
	var loop := _wav(2.0, func(t: float) -> float:
		var click := (_noise() * 0.8) if randf() < 0.004 else 0.0
		return click + _soft_noise() * 0.12)
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(MIX_RATE * 2.0)
	crackle.stream = loop
	crackle.volume_db = -6.0
	add_child(crackle)


var _lp := 0.0


func _noise() -> float:
	return randf() * 2.0 - 1.0


## Шум, смягчённый фильтром: дыхание, шипение огня.
func _soft_noise() -> float:
	_lp += (_noise() - _lp) * 0.08
	return _lp * 3.0


## Знаменитый щелчок Zippo: короткий удар и звонкий металлический призвук.
func _clink(t: float, gain: float) -> float:
	var ring := sin(TAU * 2350.0 * t) * 0.5 + sin(TAU * 3720.0 * t) * 0.3 + sin(TAU * 5600.0 * t) * 0.2
	return gain * (ring * exp(-t * 12.0) * 0.5 + _noise() * exp(-t * 120.0) * 0.6)


func _wav(seconds: float, sample: Callable) -> AudioStreamWAV:
	var length := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		var s := clampf(sample.call(i / MIX_RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.data = data
	return wav


func _play(sound: String, volume_db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = snd[sound]
	p.volume_db = volume_db - 4.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
