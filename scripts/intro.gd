extends Node

const Structures = preload("res://scripts/structures.gd")

## Вступление.
## 0. Новая игра (from_roof): ночь, герой стоит на крыше самой высокой башни — там же, куда возвращает финал
##    (петля); поверх кадра — главное меню. «Начать игру» — он разбегается (тряска) и прыгает с края;
##    короткая тьма — и он уже падает.
## 1. Падение: герой уже сорвался с крыши самой высокой башни и летит вниз на спине,
##    глядя вверх, на удаляющуюся крышу. В ушах — нарастающий рёв ветра. Как падение с крыши в Mirror's Edge
##    Catalyst: тело медленно заваливается, голова плавно оборачивается к земле и обратно, ветер мелко треплет
##    кадр, обзор с разгоном шире.
## 2. На высоте ~200 м под ним пролетает летающая машина — он пробивает ей крышу. Дальше — вид из салона
##    (crash_car.gd): дыра над головой, тревожная лампа, сигнализация, машина по спирали падает к подножию башни.
## 3. Удар о землю: тьма, глухой удар, тишина. Во тьме проступает текст (STORY) — ждёт пробел.
## 4. Тьма спадает: он лежит у подножия башни и смотрит в сторону горы, чуть выше неё; рядом горит машина.
##    Мимо пробегают крысы.
##    Сначала он просто лежит (LIE_TIME), потом всплывает подсказка «W — подняться».
##    Встаёт он только по нажатию W — сам не поднимается. Осмотреться можно мышью.

const GET_UP_TIME := 4.5
const LIE_TIME := 4.0                # сколько он лежит, прежде чем всплывёт подсказка
const HINT_RISE := 14.0              # подсказка всплывает снизу на столько пикселей
const HINT_ALPHA := 0.7              # как и задание, и субтитры — полупрозрачная, без обводки
const GROUND := Structures.HERO_SPOT  # где герой лежит после падения — у подножия самой высокой башни
const FALL_FROM := 380.0             # с какой высоты начинается падение (крыша — на 760 м)
const STORY := "Я лежал на земле, глядя в ледяные тучи, а мимо моего тела сновали крысы. В этот момент пришло осознание: даже умереть мне не дано — так же, как и обрести счастье в городе, ставшем моей тюрьмой."
const LOOK_ABOVE_PEAK := 4.0         # после пробуждения взгляд — на гору и на столько градусов выше вершины
const RUN_FROM_Z := 113.0            # откуда разбегается (край крыши — z = 95)
const ROOF_EDGE_Z := 95.4
const RUN_SPEED := 9.0               # разбег, м/с
const RUN_SHAKE := 0.45              # тряска камеры на разбеге
const JUMP_UP := 4.0                 # прыжок с края
const HATCH := Vector3(6.0, 760.2, 121.0)   # люк позади героя — через него он поднялся на крышу
const EDGE_LOOK := Vector3(4.0, 755.0, 95.0)   # куда смотреть на край крыши (и чуть в провал)
const SIGN_SIZE := Vector2(30.0, 12.0)       # «НАСЛАЖДАЙСЯ» — билборд на фасаде, под краем крыши (между карнизами
const SIGN_AT := Vector3(4.0, 730.0, 93.6)    # 710 и 750 м), прямо над тем, кто падает
const DOG_TILT := deg_to_rad(20.0)
const STARS_R := 5000.0              # звёзды — на сфере этого радиуса вокруг крыши   # «Настройки» — голова набок, вопросительно
const CLOUDS_ABOVE := 830.0          # пока он на крыше — облака над ним (потолок), потом — на своё место
const FALL_GRAVITY := 20.0           # с крыши — непрерывно, без склейки, поэтому быстрее обычного
const FALL_CAP := 85.0
const JUMP_FOG := 2.5                # с разбега город тонет в тумане (время всему подгрузиться, пока он падает)…
const FOG_CLEARS := Vector2(480.0, 330.0)   # …и туман редеет, пока он пролетает эти высоты, — к машине обычный
const STEER_TO := Vector2(4.0, 86.0) # в падении его сносит к подножию — туда, где под ним машина

enum State { ROOF, FALLING, CAR, BLACKOUT, STORY, LYING, HINT, GETTING_UP, DONE }

var player: CharacterBody3D
var layer: CanvasLayer
var fade: ColorRect
var hint: Label
var story: Label
var story_hint: Label
var black_tween: Tween
var panic_target := Vector2.ZERO
var panic_jerk := 0.0
var state := State.FALLING
var from_roof := false               # новая игра: начать на крыше (world.gd), иначе — сразу падение
var step_tween: Tween                # прыжок с края: тьма — и падение
var running := false
var stars: MultiMeshInstance3D       # звёзды ночного неба во вступлении
var fall_fx := 0.0                   # 0..1 — помехи, тёмные края и приближение в падении с крыши
var glitch_jerk := 0.0
var vignette_base := -1.0
var rain: AudioStreamPlayer          # в меню: тихий шелест дождя и капли по крыше
var breath: AudioStreamPlayer        # на крыше, у края, — частое сбивчивое дыхание: страшно прыгать
var jumped := false
var t := 0.0
var rat_mat := StandardMaterial3D.new()
var car: Node3D                      # летающая машина, в которую он падает (crash_car.gd)
var looked_down := false

var wind := Synth.WindRoar.new()


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	if from_roof:
		_stand_on_roof()
	else:
		player.fall_on_back(GROUND + Vector3.UP * FALL_FROM, 20.0)
	player.last_safe = GROUND

	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	fade = ScreenText.black(layer)
	create_tween().tween_property(fade, "color:a", 0.0, 1.5)

	hint = Label.new()
	hint.text = "W — подняться"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -150 + HINT_RISE
	hint.offset_bottom = -90 + HINT_RISE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 26)
	hint.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, HINT_ALPHA))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.modulate.a = 0.0
	layer.add_child(hint)

	rat_mat.albedo_color = Color(0.08, 0.07, 0.07)
	rat_mat.roughness = 0.6

	add_child(wind)
	wind.start()
	if from_roof:
		wind.fill(0.12)   # на крыше — ровный высотный ветер
	car = preload("res://scripts/crash_car.gd").new()
	player.get_parent().add_child.call_deferred(car)
	car.crashed.connect(_impact)


func _process(delta: float) -> void:
	t += delta
	match state:
		State.ROOF:
			if running:
				_run_on_roof(delta)
		State.FALLING:
			var speed := -player.velocity.y
			if from_roof:   # сносит к подножию башни — туда, где под ним пролетит машина
				var p := player.global_position
				var thick := clampf(inverse_lerp(FOG_CLEARS.y, FOG_CLEARS.x, p.y), 0.0, 1.0)
				_jump_fog(JUMP_FOG * smoothstep(0.0, 1.0, thick), delta)
				_fall_fx(delta)
				var steer := (STEER_TO - Vector2(p.x, p.z)) * 0.9
				steer = steer.limit_length(9.0)
				player.velocity.x = steer.x
				player.velocity.z = steer.y
			player.fall_shake = clampf(speed / 50.0, 0.0, 1.0) * 0.5   # лёгкая дрожь; главное движение — panic
			_panic(clampf(0.35 + speed / 55.0, 0.0, 1.0), delta)
			wind.fill(clampf(speed / 55.0, 0.15, 1.0))
			# Машина подлетает так, чтобы оказаться под ним к удару; долетел до её крыши — он в салоне.
			var above: float = player.global_position.y - (car.IMPACT.y + car.ROOF)
			if car.is_inside_tree():
				car.approach(above / maxf(speed, 1.0))
				if above / maxf(speed, 1.0) < 1.4 and not looked_down:
					# Последний миг: голова запрокидывается — он видит под собой летящую на него крышу машины.
					looked_down = true
					panic_target = Vector2.ZERO
					panic_jerk = 10.0
					create_tween().tween_property(player, "target_pitch", -PI / 2.0 - player.LIE_PITCH + 0.15, 0.45) 						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				if above <= 0.0:
					_into_car()
			if player.is_on_floor():
				_impact()
		State.CAR:
			if from_roof:
				_jump_fog(0.0, delta)
			wind.fill(clampf(0.55 + car.s * 0.45, 0.0, 1.0))   # в дыру в крыше ревёт ветер
		State.LYING:
			if t > LIE_TIME:
				_show_hint()


## Подняться — только новым нажатием W, когда подсказка уже появилась
## (зажатая заранее клавиша не считается).
func _unhandled_input(event: InputEvent) -> void:
	if state == State.STORY and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_end_story()
		return
	if state == State.HINT and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_W:
		_get_up()


## Подсказка аккуратно всплывает снизу и проявляется.
func _show_hint() -> void:
	state = State.HINT
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(hint, "modulate:a", 1.0, 1.6)
	tween.tween_property(hint, "offset_top", hint.offset_top - HINT_RISE, 1.6)
	tween.tween_property(hint, "offset_bottom", hint.offset_bottom - HINT_RISE, 1.6)


## Паника: голова плавно, но настойчиво оборачивается — то вниз, к несущейся навстречу земле, то в стороны
## (новый взгляд раз в 0,9–1,6 с, поворот ~0,5 с, без рывков); заваливание, ветер и обзор — в player.panic.
func _panic(level: float, delta: float) -> void:
	player.panic = level
	panic_jerk -= delta
	if panic_jerk <= 0.0:
		panic_jerk = randf_range(0.9, 1.6)
		var down := randf() < 0.5   # через раз — взгляд вниз, к земле (лёжа на спине «вниз» — это за голову)
		panic_target = Vector2(randf_range(-0.5, 0.5), randf_range(-0.6, -0.3) if down else randf_range(-0.15, 0.2)) * level
	player.panic_look = player.panic_look.lerp(panic_target, 1.0 - exp(-4.5 * delta))


## Новая игра: ночь, стоит на крыше в нескольких шагах от края, лицом к городу; ждёт «Начать игру» (меню
## поверх этого кадра — prologue.gd). Управления нет, оглядеться — тоже (мышь — у меню).
func _stand_on_roof() -> void:
	state = State.ROOF
	t = 0.0
	player.locked = true
	player.lying = 0.0
	player.global_position = Vector3(Structures.ROOF_SPOT.x, Structures.ROOF_SPOT.y, RUN_FROM_Z)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0   # -Z — к краю, над городом
	player.target_yaw = 0.0
	player.target_pitch = -0.05
	player.head.rotation.x = player.target_pitch
	player.look_smoothing_scale = 0.6   # в меню голова поворачивается плавнее
	_build_hatch()
	_build_railing()
	_build_puddles()
	_build_stars()
	_build_wet_roof()
	_build_enjoy_sign()
	if Game.clouds:
		Game.clouds.position.y = CLOUDS_ABOVE
	breath = AudioStreamPlayer.new()
	breath.stream = _scared_breath()
	breath.volume_db = -14.0
	rain = AudioStreamPlayer.new()
	rain.stream = _rain_on_roof()
	rain.volume_db = -14.0
	rain.bus = &"Ambience"
	add_child(rain)
	rain.play()
	add_child(breath)
	breath.play()


## Перила по краю крыши. Там, где он побежит (x≈4), они проломлены: стойка завалена наружу, концы поручней
## загнуты в пропасть, кусок поручня валяется на крыше. Только вид — без коллизии.
func _build_railing() -> void:
	var rail := Node3D.new()
	player.get_parent().add_child(rail)
	rail.global_position = Vector3(Structures.TALLEST_TOWER.x, Structures.TALLEST_HEIGHT, Structures.TALLEST_TOWER.z)
	var metal := Shapes.mat(Color(0.14, 0.14, 0.15), 0.35, 0.8)
	var half := 22.6
	var front := ROOF_EDGE_Z - Structures.TALLEST_TOWER.z   # передний край (к городу), в координатах rail
	# Стороны: [от, до] по краю; на переднем — два куска с проломом посередине.
	var gap := Vector2(1.6 - Structures.TALLEST_TOWER.x, 6.6 - Structures.TALLEST_TOWER.x)
	var runs := [
		[Vector3(-half, 0, front), Vector3(gap.x, 0, front)], [Vector3(gap.y, 0, front), Vector3(half, 0, front)],
		[Vector3(-half, 0, -front), Vector3(half, 0, -front)],
		[Vector3(-half, 0, front), Vector3(-half, 0, -front)], [Vector3(half, 0, front), Vector3(half, 0, -front)],
	]
	for r in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var length := a.distance_to(b)
		var along := (b - a) / length
		var posts := maxi(int(length / 2.3), 1)
		for k in posts + 1:
			Shapes.box(rail, Vector3(0.07, 1.1, 0.07), a + along * (length * k / posts) + Vector3.UP * 0.55, metal)
		for h in [0.55, 1.07]:
			var bar := Shapes.box(rail, Vector3(0.05, 0.05, length) if absf(along.x) < 0.5 else Vector3(length, 0.05, 0.05),
				(a + b) / 2.0 + Vector3.UP * h, metal)
	# Пролом: загнутые наружу обрывки поручней, заваленная стойка, кусок на крыше.
	for side in [gap.x, gap.y]:
		var dir := 1.0 if side == gap.x else -1.0
		for h in [0.55, 1.07]:
			var stub := Shapes.box(rail, Vector3(1.3, 0.05, 0.05), Vector3(side + dir * 0.55, h, front - 0.35), metal)
			stub.rotation = Vector3(0, dir * 0.6, -dir * 0.25)
	var bent := Shapes.box(rail, Vector3(0.07, 1.1, 0.07), Vector3(gap.x + 1.4, 0.4, front - 0.5), metal)
	bent.rotation = Vector3(-1.0, 0, 0.2)   # стойка завалилась в пропасть
	var piece := Shapes.box(rail, Vector3(2.2, 0.05, 0.05), Vector3(gap.y - 1.2, 0.03, front + 1.8), metal)
	piece.rotation.y = 0.5


## Лужи и ручьи: тёмная вода-зеркало пятнами по крыше и тонкие струйки к краю.
func _build_puddles() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.02, 0.022, 0.028)
	water.roughness = 0.03
	water.metallic = 0.15
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var roof := Node3D.new()
	player.get_parent().add_child(roof)
	roof.global_position = Vector3(Structures.TALLEST_TOWER.x, Structures.TALLEST_HEIGHT + 0.025, Structures.TALLEST_TOWER.z)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	for i in 34:
		var at := Vector3(rng.randf_range(-21, 21), 0, rng.randf_range(-21, 21))
		if at.distance_to(HATCH - roof.global_position) < 2.0:
			continue
		# Лужа — несколько пересекающихся овалов: край неровный.
		for k in rng.randi_range(2, 4):
			var blob := Shapes.node(roof, disc, at + Vector3(rng.randf_range(-0.8, 0.8), 0.001 * k, rng.randf_range(-0.8, 0.8)), water, false,
				Vector3(rng.randf_range(0.5, 2.4), 1.0, rng.randf_range(0.4, 1.6)))
			blob.rotation.y = rng.randf() * TAU
	for i in 9:   # ручьи — тонкие струйки по уклону к краю
		var from := Vector3(rng.randf_range(-18, 18), 0.002, rng.randf_range(-15, 12))
		var to := Vector3(from.x + rng.randf_range(-3, 3), 0.002, -22.0)
		var mid := (from + to) / 2.0 + Vector3(rng.randf_range(-1.5, 1.5), 0, 0)
		for seg in [[from, mid], [mid, to]]:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var strip := Shapes.box(roof, Vector3(rng.randf_range(0.1, 0.22), 0.006, a.distance_to(b)), (a + b) / 2.0, water, false)
			strip.rotation.y = atan2(b.x - a.x, b.z - a.z)


## Звёзды: россыпь неярких точек по небу (в просветах ночных туч), туман их не гасит.
func _build_stars() -> void:
	var star := StandardMaterial3D.new()   # точка-шарик: ровный свет, туман не гасит
	star.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star.disable_fog = true
	star.vertex_color_use_as_albedo = true
	var quad := SphereMesh.new()
	quad.radius = 0.5
	quad.height = 1.0
	quad.radial_segments = 6
	quad.rings = 3
	quad.material = star
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1000
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var centre := Structures.ROOF_SPOT
	for i in mm.instance_count:
		var yaw := rng.randf() * TAU
		var up := asin(rng.randf_range(0.08, 1.0))   # над горизонтом, гуще у зенита не надо — равномерно по небу
		var dir := Vector3(cos(up) * sin(yaw), sin(up), cos(up) * cos(yaw))
		var size := rng.randf_range(8.0, 15.0) * (1.7 if rng.randf() < 0.05 else 1.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), centre + dir * STARS_R))
		var b := rng.randf_range(0.35, 0.8)
		mm.set_instance_color(i, Color(0.85 * b, 0.9 * b, 1.0 * b, 1.0))
	stars = MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_parent().add_child(stars)


## Мокрая крыша: тёмная глянцевая плёнка воды по всей крыше, с лужами (там глаже — отражения, SSR).
func _build_wet_roof() -> void:
	var puddles := NoiseTexture2D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	puddles.noise = noise
	puddles.width = 512
	puddles.height = 512
	puddles.seamless = true
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.1, 0.11, 0.13, 0.3)   # почти прозрачная: бетон виден, блестит вода
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic = 0.4
	water.roughness = 0.12
	water.roughness_texture = puddles   # пятна: где-то лужа как зеркало, где-то просто мокрый бетон
	water.uv1_scale = Vector3(3, 3, 3)
	var film := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(45.0, 45.0)
	film.mesh = plane
	film.material_override = water
	film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_parent().add_child(film)
	film.global_position = Vector3(Structures.TALLEST_TOWER.x, Structures.TALLEST_HEIGHT + 0.02, Structures.TALLEST_TOWER.z)


## Дождь по крыше: ровный тихий шелест и редкие крупные капли (по металлу люка, по лужам); петля 6 с.
func _rain_on_roof() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(Synth.MIX_RATE * 6.0))
	var lp := 0.0
	var hp := 0.0
	var drop := 0.0
	var drop_f := 0.0
	var phase := 0.0
	for i in samples.size():
		var n := randf() * 2.0 - 1.0
		lp += (n - lp) * 0.5
		hp += (lp - hp) * 0.05
		var hiss := (lp - hp) * 0.35   # шелест: без гула и без резкого шипения
		if randf() < 0.0005:   # капля: мягкий «плюх» — низко, с коротким подъёмом тона, как капля в лужу
			drop = randf_range(0.2, 0.5)
			drop_f = randf_range(280.0, 650.0)
		phase += TAU * drop_f / Synth.MIX_RATE
		drop_f *= 1.00004   # тон чуть растёт — пузырёк
		drop *= 0.9975
		samples[i] = hiss + sin(phase) * drop * 0.5
	return Synth.wav_from(samples, true)


## Люк в крыше позади: бортик, откинутая крышка, изнутри — тёплый свет лестницы.
func _build_hatch() -> void:
	var hatch := Node3D.new()
	player.get_parent().add_child(hatch)
	hatch.global_position = HATCH
	var metal := Shapes.mat(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	for side in [-1.0, 1.0]:
		Shapes.box(hatch, Vector3(0.12, 0.5, 1.6), Vector3(side * 0.8, 0.25, 0), metal)
		Shapes.box(hatch, Vector3(1.6, 0.5, 0.12), Vector3(0, 0.25, side * 0.8), metal)
	var glow := Shapes.glow(Color(0.3, 0.2, 0.1), Color(1.0, 0.7, 0.4), 1.6)
	Shapes.box(hatch, Vector3(1.48, 0.02, 1.48), Vector3(0, 0.05, 0), glow, false)   # свет из глубины
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.5, 0.8)
	lid.rotation.x = 1.15   # откинута назад
	hatch.add_child(lid)
	Shapes.box(lid, Vector3(1.6, 0.08, 1.6), Vector3(0, 0, -0.8), metal)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.position = Vector3(0, 0.4, 0)
	hatch.add_child(light)


## «НАСЛАЖДАЙСЯ»: обычный билборд на фасаде, на 30 м ниже края, с которого он прыгнет, — лицом наружу.
## Светящийся фиолетовый экран, чёрные буквы. С крыши его не видно; видно — падая на спине, глядя вверх.
func _build_enjoy_sign() -> void:
	var sign := Node3D.new()
	player.get_parent().add_child(sign)
	sign.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), SIGN_AT)   # экран (+Z) — к -Z, наружу
	var frame := Shapes.mat(Color(0.05, 0.05, 0.06), 0.5, 0.6)
	Shapes.box(sign, Vector3(SIGN_SIZE.x + 0.8, SIGN_SIZE.y + 0.8, 1.2), Vector3(0, 0, -0.65), frame)   # короб до стены
	var screen := Shapes.glow(Color(0.3, 0.08, 0.5), Color(0.55, 0.15, 1.0), 4.0)
	Shapes.box(sign, Vector3(SIGN_SIZE.x, SIGN_SIZE.y, 0.05), Vector3(0, 0, 0.0), screen, false)
	var text := Label3D.new()
	text.text = "НАСЛАЖДАЙСЯ"
	text.font_size = 220
	text.pixel_size = 0.02
	text.modulate = Color(0.0, 0.0, 0.0)
	text.outline_size = 0
	text.shaded = false
	text.double_sided = false
	text.position = Vector3(0, 0, 0.1)
	sign.add_child(text)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.25, 1.0)
	light.light_energy = 2.5
	light.omni_range = 26.0
	light.position = Vector3(0, -4.0, 5.0)
	sign.add_child(light)


## Главное меню: куда смотрит герой, пока мышь над пунктом. «start» — на край, с которого прыгнет;
## «settings» — на край, голова вопросительно набок; «exit» — оборачивается на люк; «» — просто стоит.
func menu_hover(kind: String) -> void:
	if state != State.ROOF or running:
		return
	var eye := player.global_position + Vector3.UP * 1.6
	var at := eye + Vector3(0, -0.8, -20.0)   # «Начать новую игру» и без наведения — просто на город, с края
	player.head_tilt = DOG_TILT if kind == "settings" else 0.0
	match kind:
		"exit":
			at = HATCH + Vector3.UP * 0.3
		"settings":
			at = EDGE_LOOK
	var to := at - eye
	var yaw := atan2(-to.x, -to.z)
	player.target_yaw = player.target_yaw + angle_difference(player.target_yaw, yaw)
	player.target_pitch = atan2(to.y, Vector2(to.x, to.z).length())


## «Начать игру»: разбегается к краю — шаги, камера трясётся.
func start_game() -> void:
	if state != State.ROOF or running:
		return
	running = true
	player.look_locked = true          # пока бежит и прыгает — мышь не крутит голову
	player.look_smoothing_scale = 1.0
	player.head_tilt = 0.0
	player.target_yaw = player.target_yaw + angle_difference(player.target_yaw, 0.0)   # к краю
	player.target_pitch = -0.05
	player.scripted_run = Vector2(0, -1)
	player.scripted_speed = RUN_SPEED
	if breath:   # рванул — дыхание и дождь тонут в шагах и ветре
		create_tween().tween_property(breath, "volume_db", -40.0, 1.6)
		create_tween().tween_property(rain, "volume_db", -40.0, 2.5)


func _run_on_roof(delta: float) -> void:
	player.fall_shake = move_toward(player.fall_shake, RUN_SHAKE, delta * 0.8)   # тряска нарастает с разбегом
	_jump_fog(JUMP_FOG, delta)
	var p := player.global_position
	if not jumped and p.z <= ROOF_EDGE_Z + 0.6:
		# Край — прыжок вперёд, взгляд вниз, в провал улиц.
		jumped = true
		player.velocity.y = JUMP_UP
		create_tween().tween_property(player, "target_pitch", -0.95, 0.7).set_trans(Tween.TRANS_SINE)
	if jumped and p.y < Structures.ROOF_SPOT.y - 1.5 and step_tween == null:
		# Сорвался с края — без склеек: тело заваливается на спину, взгляд уходит вверх, на удаляющуюся
		# крышу; дальше — то же падение (паника, ветер, машина), просто с самой крыши.
		state = State.FALLING
		player.scripted_run = Vector2.ZERO
		player.look_locked = false
		player.gravity = FALL_GRAVITY
		player.fall_cap = FALL_CAP
		step_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
		step_tween.tween_property(player, "lying", 1.0, 1.2)
		step_tween.tween_property(player, "target_yaw", player.target_yaw + PI, 1.2)
		step_tween.tween_property(player, "target_pitch", 0.0, 1.2)


## Пробил крышу машины: короткая тьма от удара — и он уже в салоне (дальше — машина, crash_car.gd).
## Сам герой ждёт на земле, у подножия башни: там он очнётся.
func _into_car() -> void:
	state = State.CAR
	_end_fall_fx()
	player.end_fall()
	player.global_position = GROUND
	player.velocity = Vector3.ZERO
	fade.color = Color(1, 1, 1, 0.9)   # вспышка удара
	var flash := create_tween()
	flash.tween_property(fade, "color:a", 0.0, 0.25)
	flash.tween_callback(func() -> void: fade.color = Color(0, 0, 0, 0))
	car.begin()


## Удар о землю: ветер обрывается, тьма и глухой удар, потом он приходит в себя.
func _impact() -> void:
	if state != State.FALLING and state != State.CAR:
		return
	_restore_world()
	state = State.BLACKOUT
	player.end_fall()
	player.global_position = GROUND
	wind.stop()
	fade.color.a = 1.0
	Synth.play_once(self, _thud_sound(), 4.0)
	_make_story()
	black_tween = create_tween()
	black_tween.tween_interval(2.0)
	black_tween.tween_callback(func() -> void: state = State.STORY)
	black_tween.tween_property(story, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	black_tween.tween_property(story_hint, "modulate:a", 1.0, 0.8)


## Текст во тьме — как пролог: по центру, полупрозрачный, «пробел — дальше» внизу справа.
func _make_story() -> void:
	story = ScreenText.center(layer, STORY, 24, Color(0.88, 0.87, 0.85, 0.82))
	story.modulate.a = 0.0
	story_hint = ScreenText.corner_hint(layer, "пробел — дальше")
	story_hint.modulate.a = 0.0


## Пробел: текст тает, тьма спадает — он лежит и смотрит на гору.
func _end_story() -> void:
	state = State.BLACKOUT
	if black_tween:
		black_tween.kill()
	black_tween = create_tween()
	black_tween.tween_property(story, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	black_tween.parallel().tween_property(story_hint, "modulate:a", 0.0, 0.5)
	black_tween.tween_callback(_wake_up)
	black_tween.tween_property(fade, "color:a", 0.0, 4.0).set_trans(Tween.TRANS_SINE)


func _wake_up() -> void:
	state = State.LYING
	t = 0.0
	_look_at_mountain()
	for i in 12:
		_rat(i)


## Лёжа камера и так запрокинута вверх (player.lying) — подбираем наклон головы так, чтобы взгляд
## шёл на вершину горы и чуть выше.
func _look_at_mountain() -> void:
	var to_peak := Mountain.CENTER + Vector3.UP * Mountain.PEAK - player.global_position
	var yaw := atan2(-to_peak.x, -to_peak.z)
	var up := atan2(to_peak.y, Vector2(to_peak.x, to_peak.z).length()) + deg_to_rad(LOOK_ABOVE_PEAK)
	player.rotation.y = yaw
	player.target_yaw = yaw
	player.target_pitch = up - player.LIE_PITCH * player.lying
	player.head.rotation.x = player.target_pitch


func _get_up() -> void:
	state = State.GETTING_UP
	create_tween().tween_property(hint, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_SINE)  # плавно тает, пока он встаёт
	var tween := create_tween()
	tween.tween_property(player, "lying", 0.0, GET_UP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Пока встаёт, голова поднимается вместе с ним: взгляд остаётся на горе, а не уходит в землю.
	tween.parallel().tween_property(player, "target_pitch", 0.05, GET_UP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish)


func _finish() -> void:
	state = State.DONE
	player.locked = false
	layer.queue_free()


## Из админ-панели, демо и бенчмарка: сразу на землю и встать.
func skip() -> void:
	if state >= State.GETTING_UP:
		return
	if black_tween:
		black_tween.kill()
	if step_tween:
		step_tween.kill()
	if story:
		story.modulate.a = 0.0
		story_hint.modulate.a = 0.0
	if state == State.FALLING or state == State.CAR or state == State.ROOF:
		player.flying = false
		player.scripted_run = Vector2.ZERO
		_restore_world()
		wind.stop()
		player.end_fall()
		player.global_position = GROUND
		player.velocity = Vector3.ZERO
		state = State.BLACKOUT   # чтобы удар машины о землю уже не запускал тьму
	if car:
		car.wreck_now()   # машина уже лежит рядом и горит
	fade.color.a = 0.0
	_get_up()


## Падение с крыши: кадр мелко рвётся помехами (иногда — срыв сильнее), края темнеют, обзор чуть уже.
func _fall_fx(delta: float) -> void:
	fall_fx = minf(fall_fx + delta / 1.5, 1.0)
	var mat := Game.bodycam_mat
	if mat == null:
		return
	glitch_jerk -= delta
	if glitch_jerk <= 0.0:
		glitch_jerk = randf_range(0.05, 0.12)
		var burst := randf() < 0.12   # изредка — срыв посильнее
		mat.set_shader_parameter("glitch", (randf_range(0.25, 0.5) if burst else randf_range(0.03, 0.1)) * fall_fx)
		mat.set_shader_parameter("glitch_seed", randf() * 100.0)
	if vignette_base < 0.0:
		vignette_base = mat.get_shader_parameter("vignette")
	mat.set_shader_parameter("vignette", lerpf(vignette_base, vignette_base * 2.6 + 0.4, fall_fx))
	player.fov_zoom = 9.0 * fall_fx


func _end_fall_fx() -> void:
	if fall_fx > 0.0 and Game.bodycam_mat:   # помехи, тёмные края и приближение — прочь
		Game.bodycam_mat.set_shader_parameter("glitch", 0.0)
		Game.bodycam_mat.set_shader_parameter("vignette", vignette_base)
	fall_fx = 0.0
	player.fov_zoom = 0.0


## Туман прыжка: плавно к нужной густоте (journey.fog_boost — им же сгущается туман на скамейке).
func _jump_fog(target: float, delta: float) -> void:
	if Game.journey:
		Game.journey.fog_boost = lerpf(Game.journey.fog_boost, target, 1.0 - exp(-2.0 * delta))


## Под тьмой после удара: утро обычного города — облака на своём месте, ночь кончилась, падение — как у всех.
func _restore_world() -> void:
	_end_fall_fx()
	if stars:
		stars.queue_free()   # ночь кончилась
		stars = null
	player.look_locked = false
	player.look_smoothing_scale = 1.0
	if Game.journey:
		Game.journey.night = 0.0
		Game.journey.fog_boost = 0.0
	if Game.clouds:
		Game.clouds.position.y = preload("res://scripts/world.gd").CLOUDS_Y
	if breath:
		breath.stop()
		rain.stop()
	player.gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	player.fall_cap = player.MAX_FALL_SPEED
	player.head_tilt = 0.0


## Страх перед прыжком: частые неровные вдохи и выдохи с дрожью, петля ~5 с (несколько вдохов разной длины).
func _scared_breath() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(Synth.MIX_RATE * 5.2))
	# (начало, длина, вдох ли, громкость) — вдохи короткие и рваные, выдохи дрожат
	var breaths := [[0.0, 0.42, true, 0.8], [0.5, 0.6, false, 0.6], [1.25, 0.35, true, 0.9], [1.65, 0.7, false, 0.55],
		[2.5, 0.3, true, 0.7], [2.85, 0.25, true, 0.85], [3.2, 0.9, false, 0.65], [4.3, 0.45, true, 0.75], [4.8, 0.35, false, 0.5]]
	# Дыхание — не шум, а воздух через рот: узкая резонансная полоса (вдох выше, ~1,3 кГц; выдох ниже, ~0,8 кГц),
	# мягкие края, без низа и без резкого верха.
	var low := 0.0
	var band := 0.0
	for i in samples.size():
		var time := i / Synth.MIX_RATE
		var v := 0.0
		var centre := 0.0
		for b in breaths:
			var x: float = (time - float(b[0])) / float(b[1])
			if x < 0.0 or x > 1.0:
				continue
			var inhale: bool = b[2]
			var env: float = pow(sin(PI * x), 2.0) if inhale else pow(sin(PI * pow(x, 0.6)), 1.5) * (1.0 - x * 0.3)
			var shiver: float = 1.0 if inhale else 0.8 + 0.2 * sin(TAU * 9.0 * time)   # выдох дрожит
			v += env * shiver * float(b[3])
			centre = 1300.0 if inhale else 800.0
		if centre == 0.0:
			centre = 1000.0
		var f := 2.0 * sin(PI * centre / Synth.MIX_RATE)
		var high := (randf() * 2.0 - 1.0) - low - 0.55 * band
		band += f * high
		low += f * band
		samples[i] = band * v * 0.55
	return Synth.wav_from(samples, true)


## Глухой удар: низкий гул, быстро затухающий, с хрустом шума в начале.
func _thud_sound() -> AudioStreamWAV:
	return Synth.wav(1.2, func(time: float) -> float:
		var body := sin(TAU * 48.0 * time) * exp(-time * 4.0)
		var crack := (randf() * 2.0 - 1.0) * exp(-time * 30.0) * 0.5
		return (body + crack) * 0.9)


## Крыса пробегает мимо лежащего героя.
func _rat(i: int) -> void:
	var rat := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.05
	capsule.height = 0.24
	body.mesh = capsule
	body.material_override = rat_mat
	body.rotation.x = PI / 2.0
	body.position.y = 0.05
	rat.add_child(body)
	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.004
	tail_mesh.bottom_radius = 0.01
	tail_mesh.height = 0.2
	tail.mesh = tail_mesh
	tail.material_override = rat_mat
	tail.rotation.x = PI / 2.0 - 0.15
	tail.position = Vector3(0, 0.03, 0.2)
	rat.add_child(tail)
	player.get_parent().add_child(rat)

	# Путь: из темноты сбоку, мимо героя, и дальше.
	var origin := player.global_position
	var side := -1.0 if i % 2 == 0 else 1.0
	var from := origin + Vector3(side * 6.0, 0, randf_range(-3, 3))
	var past := origin + Vector3(side * -0.2, 0, randf_range(-1.2, 1.2))
	var to := origin + Vector3(side * -7.0, 0, randf_range(-4, 4))
	rat.position = from
	rat.look_at(past, Vector3.UP)
	rat.visible = false
	var tween := create_tween()
	tween.tween_interval(2.0 + i * randf_range(1.5, 3.0))
	tween.tween_callback(func() -> void: rat.visible = true)
	tween.tween_property(rat, "position", past, randf_range(1.2, 2.0))
	tween.tween_callback(func() -> void: rat.look_at(to, Vector3.UP))
	tween.tween_property(rat, "position", to, randf_range(1.5, 2.5))
	tween.tween_callback(rat.queue_free)
