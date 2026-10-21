class_name ScreenText
extends RefCounted

## Экранный текст в одном стиле: без плашек и обводки, полупрозрачный.
## - center(): абзац по центру экрана (пролог, текст во тьме после удара, рассказ поверх игры, экран загрузки);
## - corner_hint(): маленькая подсказка внизу справа («пробел — дальше», «загрузка…»);
## - black(): чёрный экран на весь кадр.

const HINT_COLOR := Color(0.85, 0.85, 0.85, 0.3)


## Абзац по центру; margin — поля слева и справа, px. Переносится по словам.
static func center(parent: Node, text: String, font_size: int, color: Color, margin := 220.0) -> Label:
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = margin
	label.offset_right = -margin
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Подсказка мелким бледным текстом внизу справа.
static func corner_hint(parent: Node, text: String) -> Label:
	var hint := Label.new()
	hint.text = text
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -360
	hint.offset_top = -60
	hint.offset_right = -36
	hint.offset_bottom = -30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hint)
	return hint


## Чёрный экран на весь кадр (клики проходят сквозь него).
static func black(parent: Node) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect
