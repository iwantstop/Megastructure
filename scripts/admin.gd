extends CanvasLayer

## Админ-панель. F1 — открыть/закрыть, F — быстро включить/выключить полёт.

const START := Vector3(4, 0.2, 86)
const BODYCAM_PARAMS := ["distortion", "aberration", "vignette", "grain"]

var bodycam_base := {}   # исходные значения параметров бодикамеры (для регулятора)
var player: CharacterBody3D
var dream: Node
var presence: Node
var env: Environment
var bodycam: CanvasLayer
var journey: Node
var intro: Node
var finale: Node
var seizure: Node
var panel: PanelContainer
var fps_label: Label
var fly_box: CheckBox
var journey_slider: HSlider


func setup(refs: Dictionary) -> void:
	player = refs.player
	dream = refs.dream
	presence = refs.presence
	env = refs.env
	bodycam = refs.bodycam
	journey = refs.journey
	intro = refs.intro
	finale = refs.finale
	seizure = refs.seizure


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

	_button(box, "Пропустить вступление", func() -> void: intro.skip())
	fly_box = _check(box, "Полёт (F)  — Space вверх, Ctrl вниз", func(on: bool) -> void: player.set_flying(on))
	_check(box, "Сквозь стены", func(on: bool) -> void: player.set_noclip(on))
	_check(box, "Эффект бодикамеры", func(on: bool) -> void: bodycam.visible = on).button_pressed = true
	_slider(box, "Бодикамера (линза, зерно, виньетка): 0 — нет, 100 — как задумано", 0, 200, 100, _on_bodycam_strength)
	_slider(box, "Покачивание при ходьбе: 0 — нет, 100 — как задумано", 0, 200, 100, func(v: float) -> void: player.bob_scale = v / 100.0)
	_check(box, "Живопись (мазки и гамма зоны)", _on_paint).button_pressed = true
	_check(box, "Глобальное освещение (тяжёлое)", func(on: bool) -> void: env.sdfgi_enabled = on).button_pressed = true
	_slider(box, "Скорость полёта", 5, 200, player.fly_speed, func(v: float) -> void: player.fly_speed = v)
	_check(box, "Путь героя вручную", _on_manual_journey)
	journey_slider = _slider(box, "Путь: 0 — город, 100 — над облаками", 0, 100, 0, _on_journey_slider)
	_slider(box, "Скорость «сна» (вещи)", 1, 30, 1, func(v: float) -> void: dream.time_scale = v)
	_button(box, "Позвать её", func() -> void: presence.call_now())
	_button(box, "Переставить вещь рядом", func() -> void: dream.shift_vignette())
	_button(box, "Припадок сейчас (на мосту — с переносом)", func() -> void: seizure.trigger_now())
	_button(box, "Подняться на 100 м", _rise)
	_button(box, "Вернуться на старт", _to_start)
	_button(box, "К началу тропы на гору", func() -> void: _teleport(Mountain.path_point(0.0)))
	_button(box, "На тропу над облаками", func() -> void: _teleport(Mountain.path_point(0.85)))
	_button(box, "Финал на вершине", _to_finale)


## Сила бодикамеры: искажение линзы, расслоение цвета, виньетка и зерно — от исходных значений шейдера
## (100% — как задумано, 0% — чистая картинка, 200% — вдвое сильнее).
func _on_bodycam_strength(v: float) -> void:
	var mat := (bodycam.get_child(0) as ColorRect).material as ShaderMaterial
	for param in BODYCAM_PARAMS:
		if not bodycam_base.has(param):
			bodycam_base[param] = mat.get_shader_parameter(param)
			if bodycam_base[param] == null:
				bodycam_base[param] = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), param)
		mat.set_shader_parameter(param, bodycam_base[param] * v / 100.0)


func _on_paint(on: bool) -> void:
	(bodycam.get_child(0) as ColorRect).material.set_shader_parameter("paint", 0.7 if on else 0.0)
	for node in get_tree().get_nodes_in_group("paint_strokes"):
		node.visible = on


## Ставит героя на тропу лицом вперёд по ней.
func _teleport(xform: Transform3D) -> void:
	fly_box.button_pressed = false
	player.global_position = xform.origin + Vector3.UP * 0.5
	player.velocity = Vector3.ZERO
	player.last_safe = player.global_position
	var forward := -xform.basis.z
	player.target_yaw = atan2(-forward.x, -forward.z)
	player.target_pitch = 0.0


func _to_finale() -> void:
	_teleport(Transform3D(Basis.IDENTITY, Mountain.CENTER + Vector3(0, Mountain.PEAK, 0)))
	finale.start()


func _on_manual_journey(on: bool) -> void:
	journey.override = journey_slider.value / 100.0 if on else -1.0


func _on_journey_slider(v: float) -> void:
	if journey.override >= 0.0:
		journey.override = v / 100.0


func _rise() -> void:
	player.position.y += 100
	fly_box.button_pressed = true


func _to_start() -> void:
	fly_box.button_pressed = false
	player.position = START
	player.velocity = Vector3.ZERO


func _process(_delta: float) -> void:
	if panel.visible:
		fps_label.text = "FPS: %d   Высота: %.0f м   Путь: %d%%" % [
			Engine.get_frames_per_second(), player.global_position.y, journey.progress * 100.0]


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


func _slider(box: Container, text: String, min_value: float, max_value: float, value: float, on_change: Callable) -> HSlider:
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
	label.text = "%s: %.0f" % [text, value]
	box.add_child(slider)
	return slider


func _button(box: Container, text: String, on_press: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	box.add_child(button)
