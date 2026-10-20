extends Node

## Вступление.
## 1. Падение: герой уже сорвался с крыши самой высокой башни и летит вниз на спине,
##    глядя вверх, на удаляющуюся крышу. В ушах — нарастающий рёв ветра.
## 2. Удар о землю: тьма, глухой удар, тишина.
## 3. Он лежит у подножия башни и смотрит на крышу, с которой упал. Мимо пробегают крысы.
##    Сначала он просто лежит (LIE_TIME), потом всплывает подсказка «W — подняться».
##    Встаёт он только по нажатию W — сам не поднимается. Осмотреться можно мышью.

const GET_UP_TIME := 4.5
const LIE_TIME := 4.0                # сколько он лежит, прежде чем всплывёт подсказка
const HINT_RISE := 14.0              # подсказка всплывает снизу на столько пикселей
const HINT_ALPHA := 0.7              # как и задание, и субтитры — полупрозрачная, без обводки
const GROUND := Vector3(4, 0.2, 86)   # где герой лежит после падения
const FALL_FROM := 380.0             # с какой высоты начинается падение (крыша — на 760 м)
const MIX_RATE := 22050.0

enum State { FALLING, BLACKOUT, LYING, HINT, GETTING_UP, DONE }

var player: CharacterBody3D
var layer: CanvasLayer
var fade: ColorRect
var hint: Label
var state := State.FALLING
var t := 0.0
var rat_mat := StandardMaterial3D.new()

var wind: AudioStreamPlayer
var wind_playback: AudioStreamGeneratorPlayback
var wind_lp := 0.0
var wind_lp2 := 0.0
var wind_t := 0.0


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	player.locked = true
	player.lying = 1.0      # летит на спине, лицом вверх — к крыше
	player.rotation.y = PI  # лицом к башне
	player.target_yaw = PI
	player.global_position = GROUND + Vector3.UP * FALL_FROM
	player.last_safe = GROUND
	player.velocity = Vector3(0, -20, 0)

	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
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

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.25
	wind = AudioStreamPlayer.new()
	wind.stream = generator
	add_child(wind)
	wind.play()
	wind_playback = wind.get_stream_playback()


func _process(delta: float) -> void:
	t += delta
	match state:
		State.FALLING:
			var speed := -player.velocity.y
			player.fall_shake = clampf(speed / 50.0, 0.0, 1.0) * 2.5
			_fill_wind(clampf(speed / 55.0, 0.15, 1.0))
			if player.is_on_floor():
				_impact()
		State.LYING:
			if t > LIE_TIME:
				_show_hint()


## Подняться — только новым нажатием W, когда подсказка уже появилась
## (зажатая заранее клавиша не считается).
func _unhandled_input(event: InputEvent) -> void:
	if state == State.HINT and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_W:
		_get_up()


## Подсказка аккуратно всплывает снизу и проявляется.
func _show_hint() -> void:
	state = State.HINT
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(hint, "modulate:a", 1.0, 1.6)
	tween.tween_property(hint, "offset_top", hint.offset_top - HINT_RISE, 1.6)
	tween.tween_property(hint, "offset_bottom", hint.offset_bottom - HINT_RISE, 1.6)


## Рёв ветра: шум, громче и «ярче» с ростом скорости, с порывами.
func _fill_wind(level: float) -> void:
	var bright := lerpf(0.05, 0.35, level)
	for frame in wind_playback.get_frames_available():
		wind_t += 1.0 / MIX_RATE
		wind_lp += (randf() * 2.0 - 1.0 - wind_lp) * bright
		wind_lp2 += (wind_lp - wind_lp2) * bright
		var gust := 0.75 + 0.25 * sin(wind_t * 1.7) * sin(wind_t * 0.6)
		var s := wind_lp2 * level * gust * 2.2
		wind_playback.push_frame(Vector2(s, s * 0.92))


## Удар о землю: ветер обрывается, тьма и глухой удар, потом он приходит в себя.
func _impact() -> void:
	state = State.BLACKOUT
	player.fall_shake = 0.0
	player.global_position = GROUND
	wind.stop()
	fade.color.a = 1.0
	var thud := AudioStreamPlayer.new()
	thud.stream = _thud_sound()
	thud.volume_db = 4.0
	add_child(thud)
	thud.play()
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_callback(_wake_up)
	tween.tween_property(fade, "color:a", 0.0, 5.0).set_trans(Tween.TRANS_SINE)


func _wake_up() -> void:
	state = State.LYING
	t = 0.0
	for i in 12:
		_rat(i)


func _get_up() -> void:
	state = State.GETTING_UP
	create_tween().tween_property(hint, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_SINE)  # плавно тает, пока он встаёт
	var tween := create_tween()
	tween.tween_property(player, "lying", 0.0, GET_UP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish)


func _finish() -> void:
	state = State.DONE
	player.locked = false
	layer.queue_free()


## Из админ-панели, демо и бенчмарка: сразу на землю и встать.
func skip() -> void:
	if state >= State.GETTING_UP:
		return
	if state == State.FALLING:
		wind.stop()
		player.fall_shake = 0.0
		player.global_position = GROUND
		player.velocity = Vector3.ZERO
	fade.color.a = 0.0
	_get_up()


## Глухой удар: низкий гул, быстро затухающий, с хрустом шума в начале.
func _thud_sound() -> AudioStreamWAV:
	var length := int(MIX_RATE * 1.2)
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		var time := i / MIX_RATE
		var body := sin(TAU * 48.0 * time) * exp(-time * 4.0)
		var crack := (randf() * 2.0 - 1.0) * exp(-time * 30.0) * 0.5
		var s := clampf((body + crack) * 0.9, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.data = data
	return wav


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
