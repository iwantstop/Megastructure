extends CanvasLayer

## Пауза по Esc: мир стоит, мышь свободна. «Продолжить», «Настройки», «Начать заново», «Выйти из игры».
## Пока идёт пролог (он сам держит игру на паузе), Esc не открывает паузу.

var shade: ColorRect
var list: VBoxContainer
var settings: Control
var open := false


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var title := ScreenText.center(shade, "Пауза", 30, Color(0.85, 0.85, 0.85, 0.7))
	title.offset_bottom = -260
	list = MenuUi.column(shade, 30.0)
	MenuUi.button(list, "Продолжить", close)
	MenuUi.button(list, "Настройки", _show_settings)
	MenuUi.button(list, "Начать заново", _restart)
	MenuUi.button(list, "Выйти из игры", func() -> void: get_tree().quit())
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.hide()
	settings.back.connect(_hide_settings)
	shade.add_child(settings)
	shade.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if open:
		get_viewport().set_input_as_handled()
		close()
	elif not get_tree().paused:   # на паузе от пролога — не наша пауза
		get_viewport().set_input_as_handled()
		_open()


func _open() -> void:
	open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shade.show()
	list.show()
	settings.hide()
	list.get_child(0).grab_focus()


func close() -> void:
	open = false
	shade.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_settings() -> void:
	list.hide()
	settings.open()


func _hide_settings() -> void:
	settings.hide()
	list.show()
	list.get_child(1).grab_focus()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
