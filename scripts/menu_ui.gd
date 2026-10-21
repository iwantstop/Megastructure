class_name MenuUi
extends RefCounted

## Вид меню в стиле игры: только полупрозрачный текст, без плашек и рамок. Пункт под мышью или под
## клавиатурой (стрелки) — ярче. Ползунки — тонкая линия и маленькая точка.

const TEXT := Color(0.88, 0.87, 0.85, 0.62)
const BRIGHT := Color(1.0, 1.0, 1.0, 0.95)
const DIM := Color(0.85, 0.85, 0.85, 0.35)
const FONT := 22

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		_theme.set_stylebox(state, "Button", empty)
	_theme.set_color("font_color", "Button", TEXT)
	_theme.set_color("font_hover_color", "Button", BRIGHT)
	_theme.set_color("font_focus_color", "Button", BRIGHT)
	_theme.set_color("font_pressed_color", "Button", BRIGHT)
	_theme.set_color("font_hover_pressed_color", "Button", BRIGHT)
	_theme.set_font_size("font_size", "Button", FONT)
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_font_size("font_size", "Label", 18)
	# Ползунок: тонкая линия, заполненная часть ярче, точка вместо ручки.
	var line := StyleBoxFlat.new()
	line.bg_color = DIM
	line.content_margin_top = 1
	line.content_margin_bottom = 1
	var filled := line.duplicate()
	filled.bg_color = TEXT
	_theme.set_stylebox("slider", "HSlider", line)
	_theme.set_stylebox("grabber_area", "HSlider", filled)
	_theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	_theme.set_icon("grabber", "HSlider", _dot(14, TEXT))
	_theme.set_icon("grabber_highlight", "HSlider", _dot(14, BRIGHT))
	_theme.set_stylebox("focus", "HSlider", empty)
	_theme.set_stylebox("panel", "ScrollContainer", empty)
	return _theme


static func _dot(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(color, color.a * clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Пункт меню: текст, по нажатию — action.
static func button(parent: Node, text: String, action: Callable, font_size := FONT) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	b.mouse_entered.connect(b.grab_focus)   # мышь и клавиатура подсвечивают одно и то же
	parent.add_child(b)
	return b


## Вертикальный список пунктов по центру экрана, чуть ниже середины.
static func column(parent: Node, top := 120.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.position.y += top
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.theme = theme()
	parent.add_child(box)
	return box
