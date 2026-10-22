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


## «Начать игру»: разбегается к краю — шаги, камера трясётся.
func start_game() -> void:
	if state != State.ROOF or running:
		return
	running = true
	player.scripted_run = Vector2(0, -1)
	player.scripted_speed = RUN_SPEED


func _run_on_roof(delta: float) -> void:
	player.fall_shake = move_toward(player.fall_shake, RUN_SHAKE, delta * 0.8)   # тряска нарастает с разбегом
	var p := player.global_position
	if not jumped and p.z <= ROOF_EDGE_Z + 0.6:
		# Край — прыжок вперёд, взгляд вниз, в провал улиц.
		jumped = true
		player.velocity.y = JUMP_UP
		create_tween().tween_property(player, "target_pitch", -0.95, 0.7).set_trans(Tween.TRANS_SINE)
	if jumped and p.y < Structures.ROOF_SPOT.y - 6.0 and step_tween == null:
		# Короткая тьма — и он уже летит на спине (дальше — всё как было: падение, машина…).
		player.scripted_run = Vector2.ZERO
		step_tween = create_tween()
		step_tween.tween_property(fade, "color:a", 1.0, 0.15)
		step_tween.tween_callback(func() -> void:
			state = State.FALLING
			player.fall_on_back(GROUND + Vector3.UP * FALL_FROM, 20.0))
		step_tween.tween_property(fade, "color:a", 0.0, 0.4)


## Пробил крышу машины: короткая тьма от удара — и он уже в салоне (дальше — машина, crash_car.gd).
## Сам герой ждёт на земле, у подножия башни: там он очнётся.
func _into_car() -> void:
	state = State.CAR
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
	if Game.journey:
		Game.journey.night = 0.0   # под тьмой: очнётся он уже в обычном городе
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
		if Game.journey:
			Game.journey.night = 0.0
		wind.stop()
		player.end_fall()
		player.global_position = GROUND
		player.velocity = Vector3.ZERO
		state = State.BLACKOUT   # чтобы удар машины о землю уже не запускал тьму
	if car:
		car.wreck_now()   # машина уже лежит рядом и горит
	fade.color.a = 0.0
	_get_up()


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
