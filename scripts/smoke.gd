class_name Smoke
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
## 7. Q — выбросить окурок: он летит вперёд, кувыркаясь, тлеет и дымит; у края моста можно смотреть, как он
##    падает в бездну (как сам герой когда-то). У перил моста с сигаретой в руке — подсказка «Выбросить окурок - Q».
## Руки в перчатках (fp_hands.gd, пока выключены): правая держит сигарету, левая — пачку, потом зажигалку.
## Припадок (seizure.gd) гасит сигарету — T, чтобы прикурить снова, — и после него руки
## дрожат, дрожь медленно стихает; пока дрожат, зажигалка загорается хуже.

enum State { IDLE, TAKING, WAIT_STRIKE, LIGHTING, SMOKING, UNLIT, BUSY }

const PACK_SIZE := 10
const STRIKE_CHANCE := 0.5
const SHOW_HANDS := false         # руки выключены: ждём модель рук с костями (код рук готов — fp_hands.gd)
const TREMOR_TIME := 120.0        # за столько секунд дрожь после припадка стихает
const FILTER_LEN := 0.025
const PAPER_LEN := 0.058
const PAPER_MIN := 0.006           # догорело — дальше только фильтр
const CIG_R := 0.0039
const BURN_IDLE := 0.0006          # м/с — тлеет сама по себе
const BURN_PUFF := 0.006           # м/с — во время затяжки
const PUFF_MAX := 3.0              # дольше этого затяжка не «копится» для выдоха
const THROW_HINT := "Выбросить окурок - Q"
const BUTT_LIFE := 30.0            # столько секунд брошенный окурок живёт (падает в бездну), с

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
var left_in_pack := PACK_SIZE   # с прошлого круга и прошлого запуска — пачка не пополняется (Progress)
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
var hands: RefCounted              # руки (fp_hands.gd) — пока выключены, см. SHOW_HANDS
var right_holds := false           # правая рука держит сигарету
var thumb_flick := 0.0             # 0..1 — большой палец чиркает колёсико
var tremor := 0.0                  # 0..1 — дрожь рук после припадка
var throw_hint_shown := false
var butt: RigidBody3D              # последний брошенный окурок (для тестов)

var snd: Dictionary = {}
var crackle: AudioStreamPlayer


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	rng.randomize()
	add_to_group("smoke")
	left_in_pack = Progress.cigarettes
	_build_pack()
	_build_cigarette()
	_build_lighter()
	if SHOW_HANDS:
		hands = preload("res://scripts/fp_hands.gd").new(self)
	_build_smoke()
	_build_sounds()
	pack.visible = false
	cig.visible = false
	lighter.visible = false


# --- Управление ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_Q and event.pressed and not event.echo:
		if (state == State.SMOKING or state == State.UNLIT) and not player.locked:
			throw_butt()
			get_viewport().set_input_as_handled()
		return
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
	if hands:
		hands.update(delta)
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
	_update_throw_hint()
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
			if Game.hud:
				Game.hud.say("Пусто", 1.0, 0.6, 1.0))
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
	Progress.set_cigarettes(left_in_pack)
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


## Q: окурок летит вперёд и вверх, кувыркаясь; дальше — сам, по законам физики. Тлеющий — светится и дымит.
func throw_butt() -> void:
	var lit := state == State.SMOKING
	state = State.BUSY
	puffing = false
	crackle.stop()
	right_holds = false
	_play("rustle", -6.0)
	butt = RigidBody3D.new()
	butt.mass = 0.01
	butt.continuous_cd = true
	# Окурок появляется у самой камеры, внутри капсулы героя: со своим слоем он не толкает героя назад,
	# но падает на пол, мост и землю (слой мира — 1).
	butt.collision_layer = 2
	butt.collision_mask = 1
	butt.add_collision_exception_with(player)
	butt.linear_damp = 0.05
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.006
	capsule.height = 0.07
	shape.shape = capsule
	shape.rotation.x = PI / 2.0
	butt.add_child(shape)
	var copy: Node3D = cig.duplicate()
	copy.position = Vector3.ZERO
	copy.rotation = Vector3.ZERO
	copy.scale = Vector3.ONE * 1.6     # чуть крупнее, чтобы в полёте его было видно
	butt.add_child(copy)
	for trail in copy.find_children("*", "GPUParticles3D", true, false):
		trail.emitting = lit   # тлеющий — тянет за собой струйку дыма
	for light in copy.find_children("*", "OmniLight3D", true, false):
		light.visible = lit
		light.light_energy = 0.6
		light.omni_range = 1.2
	player.get_parent().add_child(butt)   # в мир: окурок больше не «в руках»
	butt.global_transform = cig.global_transform
	var cam := get_viewport().get_camera_3d()
	var forward := -cam.global_transform.basis.z
	butt.linear_velocity = forward * 6.0 + Vector3.UP * 2.5 + Vector3(player.velocity.x, 0, player.velocity.z)
	butt.angular_velocity = Vector3(rng.randf_range(-14, 14), rng.randf_range(-6, 6), rng.randf_range(-14, 14))
	var thrown := butt
	get_tree().create_timer(BUTT_LIFE).timeout.connect(func() -> void:
		if is_instance_valid(thrown):
			thrown.queue_free())
	cig.visible = false
	stream.emitting = false
	glow = 0.0
	state = State.IDLE


## У перил моста с сигаретой в руке — подсказка «Выбросить окурок - Q» (один раз за игру).
func _update_throw_hint() -> void:
	if throw_hint_shown or Game.hud == null:
		return
	var p := player.global_position
	var at_edge := absf(p.x) > 9.0 and p.z < -368.0 and p.z > -2350.0 and p.y < 2.0
	if at_edge and (state == State.SMOKING or state == State.UNLIT):
		throw_hint_shown = true
		Game.hud.action_hint(THROW_HINT, true)
		get_tree().create_timer(5.0).timeout.connect(func() -> void: Game.hud.action_hint(THROW_HINT, false))


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


# --- Модели ----------------------------------------------------------------------

## Вещи «в руках» — у самой камеры: теней не отбрасывают.
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	return Shapes.box(parent, size, pos, mat, false)


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, segments := 12) -> MeshInstance3D:
	return Shapes.cylinder(parent, radius, radius, height, pos, mat, segments, 1, false)


## Пачка 55×85×22 мм: тёмная, с белой полосой, без марки. Сверху откидная крышка на заднем ребре.
## Внутри — 10 сигарет фильтрами вверх (видны, когда крышка открыта).
func _build_pack() -> void:
	pack = Node3D.new()
	add_child(pack)
	var dark := Shapes.mat(Color(0.12, 0.1, 0.1), 0.6)
	var band := Shapes.mat(Color(0.75, 0.73, 0.7), 0.5)
	var filter := Shapes.mat(Color(0.78, 0.55, 0.32), 0.8)
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
	var filter_mat := Shapes.mat(Color(0.8, 0.56, 0.3), 0.85)
	var paper_mat := Shapes.mat(Color(0.93, 0.92, 0.88), 0.9)
	paper_mat.emission_enabled = true
	paper_mat.emission = Color(0.9, 0.9, 0.88)
	paper_mat.emission_energy_multiplier = 0.06  # чтобы в тёмном городе бумагу было видно
	var f := _cyl(cig, CIG_R, FILTER_LEN, Vector3(0, 0, -FILTER_LEN / 2.0), filter_mat)
	f.rotation.x = PI / 2.0
	paper = _cyl(cig, CIG_R, 1.0, Vector3.ZERO, paper_mat)
	paper.rotation.x = PI / 2.0
	ember_mat = Shapes.mat(Color(0.25, 0.06, 0.02), 0.9)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.32, 0.06)
	ember = _cyl(cig, CIG_R * 0.98, 0.0024, Vector3.ZERO, ember_mat)
	ember.rotation.x = PI / 2.0
	ash = _cyl(cig, CIG_R * 0.92, 0.002, Vector3.ZERO, Shapes.mat(Color(0.45, 0.44, 0.42), 1.0))
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
	var chrome := Shapes.mat(Color(0.72, 0.72, 0.74), 0.28, 1.0)
	var insert := Shapes.mat(Color(0.55, 0.55, 0.56), 0.35, 1.0)
	var wheel := Shapes.mat(Color(0.3, 0.3, 0.3), 0.5, 1.0)
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


func _smoke_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Shapes.soft_dot()  # мягкая круглая «дымка»
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
	crackle.stream = Synth.wav(2.0, func(t: float) -> float:
		var click := (_noise() * 0.8) if randf() < 0.004 else 0.0
		return click + _soft_noise() * 0.12, true)
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
	return Synth.wav(seconds, sample)


func _play(sound: String, volume_db := 0.0) -> void:
	Synth.play_once(self, snd[sound], volume_db - 4.0)
