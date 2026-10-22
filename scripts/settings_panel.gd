extends Control

## Экран настроек (из главного меню и из паузы): звук, управление, камера, изображение.
## Всё меняется сразу и сохраняется (settings.gd). Esc или «Назад» — вернуться.

signal back

var rows: VBoxContainer
var first: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuUi.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var title := Label.new()
	title.text = "Настройки"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_top = 60
	title.add_theme_font_size_override("font_size", 30)
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 130
	scroll.offset_bottom = -110
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	center.add_child(rows)

	_header("Звук")
	_slider("Общая громкость", "master", 0.0, 1.0)
	_slider("Музыка", "music", 0.0, 1.0)
	_slider("Звуки мира и шаги", "world", 0.0, 1.0)
	_header("Управление")
	_slider("Чувствительность мыши", "mouse", 0.25, 2.5)
	_toggle("Инверсия мыши по вертикали", "invert_y")
	_header("Камера")
	_slider("Бодикамера: линза, зерно, виньетка", "bodycam", 0.0, 2.0)
	_slider("Покачивание при ходьбе", "bob", 0.0, 2.0)
	_slider("Крен при повороте", "roll", 0.0, 3.0)
	_header("Изображение")
	_choice("Качество графики", "quality", Settings.QUALITY)
	_toggle("Живописный стиль", "paint")
	_slider("Разрешение 3D", "render_scale", 0.5, 1.0)
	_slider("Яркость", "brightness", 0.7, 1.3)
	_toggle("Полный экран", "fullscreen")
	_toggle("Вертикальная синхронизация", "vsync")
	var limits: Array = []
	for fps in Settings.FPS_LIMITS:
		limits.append("нет" if fps == 0 else str(fps))
	_choice("Ограничение FPS", "fps_limit", limits, Settings.FPS_LIMITS)

	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.offset_top = -90
	bottom.offset_bottom = -50
	bottom.add_theme_constant_override("separation", 60)
	add_child(bottom)
	MenuUi.button(bottom, "Сбросить", _reset)
	MenuUi.button(bottom, "Назад", func() -> void: back.emit())


func open() -> void:
	show()
	if first:
		first.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back.emit()


func _reset() -> void:
	Settings.reset()
	for row in rows.get_children():
		if row.has_meta("refresh"):
			row.get_meta("refresh").call()


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MenuUi.DIM)
	label.add_theme_font_size_override("font_size", 16)
	if rows.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		rows.add_child(gap)
	rows.add_child(label)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 380
	row.add_child(label)
	rows.add_child(row)
	return row


## Ползунок: значение показывается в процентах.
func _slider(text: String, key: String, low: float, high: float) -> void:
	var row := _row(text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(280, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 70
	row.add_child(value)
	var refresh := func() -> void:
		slider.set_value_no_signal(Settings.get_value(key))
		value.text = "%d%%" % roundi(slider.value * 100.0)
	refresh.call()
	slider.value_changed.connect(func(v: float) -> void:
		value.text = "%d%%" % roundi(v * 100.0)
		Settings.set_value(key, v))
	row.set_meta("refresh", refresh)
	if first == null:
		first = slider


## Вкл/выкл.
func _toggle(text: String, key: String) -> void:
	var row := _row(text)
	var b := MenuUi.button(row, "", func() -> void: pass, 18)
	var refresh := func() -> void: b.text = "вкл" if Settings.get_value(key) else "выкл"
	refresh.call()
	b.pressed.connect(func() -> void:
		Settings.set_value(key, not Settings.get_value(key))
		refresh.call())
	row.set_meta("refresh", refresh)


## Выбор из списка: нажатие (или стрелки влево/вправо) — следующий вариант.
func _choice(text: String, key: String, names: Array, values: Array = []) -> void:
	var row := _row(text)
	var b := MenuUi.button(row, "", func() -> void: pass, 18)
	var vals: Array = values if not values.is_empty() else range(names.size())
	var refresh := func() -> void:
		var i := vals.find(Settings.get_value(key))
		b.text = "‹  %s  ›" % names[maxi(i, 0)]
	var shift := func(step: int) -> void:
		var i := vals.find(Settings.get_value(key))
		Settings.set_value(key, vals[posmod(i + step, vals.size())])
		refresh.call()
	refresh.call()
	b.pressed.connect(func() -> void: shift.call(1))
	b.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_right"):
			shift.call(1)
			b.accept_event()
		elif event.is_action_pressed("ui_left"):
			shift.call(-1)
			b.accept_event())
	row.set_meta("refresh", refresh)
