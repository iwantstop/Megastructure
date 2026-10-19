extends CanvasLayer

## Админ-панель. F1 — открыть/закрыть, F — быстро включить/выключить полёт.

const START := Vector3(0, 0.2, 25)

var player: CharacterBody3D
var dream: Node
var presence: Node
var env: Environment
var bodycam: CanvasLayer
var panel: PanelContainer
var fps_label: Label
var fly_box: CheckBox


func setup(p_player: CharacterBody3D, p_dream: Node, p_presence: Node, p_env: Environment, p_bodycam: CanvasLayer) -> void:
	player = p_player
	dream = p_dream
	presence = p_presence
	env = p_env
	bodycam = p_bodycam


func _ready() -> void:
	layer = 10
	panel = PanelContainer.new()
	panel.position = Vector2(20, 60)
	panel.visible = false
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Админ-панель (F1)"
	box.add_child(title)
	fps_label = Label.new()
	box.add_child(fps_label)

	fly_box = _check(box, "Полёт (F)  — Space вверх, Ctrl вниз", func(on: bool) -> void: player.set_flying(on))
	_check(box, "Сквозь стены", func(on: bool) -> void: player.set_noclip(on))
	_check(box, "Эффект бодикамеры", func(on: bool) -> void: bodycam.visible = on).button_pressed = true
	_check(box, "Глобальное освещение (тяжёлое)", func(on: bool) -> void: env.sdfgi_enabled = on).button_pressed = true
	_slider(box, "Скорость полёта", 5, 200, player.fly_speed, func(v: float) -> void: player.fly_speed = v)
	_slider(box, "Скорость «сна» (закат, вещи, шпиль)", 1, 30, 1, func(v: float) -> void: dream.time_scale = v)
	_button(box, "Позвать её", func() -> void: presence.call_now())
	_button(box, "Переставить вещь рядом", func() -> void: dream.shift_vignette())
	_button(box, "Вырастить шпиль", func() -> void: dream.show_spire())
	_button(box, "Подняться на 100 м", _rise)
	_button(box, "Вернуться на старт", _to_start)


func _rise() -> void:
	player.position.y += 100
	fly_box.button_pressed = true


func _to_start() -> void:
	fly_box.button_pressed = false
	player.position = START
	player.velocity = Vector3.ZERO


func _process(_delta: float) -> void:
	if panel.visible:
		fps_label.text = "FPS: %d   Высота: %.0f м" % [Engine.get_frames_per_second(), player.global_position.y]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F1:
		panel.visible = not panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if panel.visible else Input.MOUSE_MODE_CAPTURED
		if not panel.visible:
			get_viewport().gui_release_focus()
	elif event.physical_keycode == KEY_F:
		fly_box.button_pressed = not fly_box.button_pressed


func _check(box: Container, text: String, on_toggle: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(on_toggle)
	box.add_child(check)
	return check


func _slider(box: Container, text: String, min_value: float, max_value: float, value: float, on_change: Callable) -> void:
	var label := Label.new()
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.value = value
	slider.custom_minimum_size.x = 320
	slider.focus_mode = Control.FOCUS_NONE
	var update := func(v: float) -> void:
		label.text = "%s: %.0f" % [text, v]
		on_change.call(v)
	slider.value_changed.connect(update)
	update.call(value)
	box.add_child(slider)


func _button(box: Container, text: String, on_press: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	box.add_child(button)
