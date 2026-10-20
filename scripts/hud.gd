extends CanvasLayer

## Экранный текст поверх игры:
## - задание в левом верхнем углу — полупрозрачный текст «Уходи отсюда», без плашки и обводки. Виден, когда герой
##   встаёт после падения, потом тает; снова появляется, пока зажат Tab;
## - субтитры внизу по центру — медленно проявляются и медленно тают (их зовёт ангел).

const TASK := "Уходи отсюда"
const TASK_AT_START := 7.0     # сколько задание висит после того, как герой встал, с
const TASK_SHOW := 0.45       # Tab: плавное появление, с
const TASK_HIDE := 0.6        # Tab отпущен: плавное исчезание, с
const TASK_POS := Vector2(28, 28)
const TASK_SLIDE := 12.0      # текст слегка выезжает слева и уезжает обратно, px
const TEXT_ALPHA := 0.7       # текст полупрозрачный, без обводки и тени
const SUB_FADE_IN := 2.2
const SUB_HOLD := 2.5
const SUB_FADE_OUT := 2.5

var player: CharacterBody3D
var task: PanelContainer
var subtitle: Label
var task_tween: Tween
var sub_tween: Tween
var shown_at_start := false
var tab_held := false


func _ready() -> void:
	layer = 3
	add_to_group("hud")

	task = PanelContainer.new()
	task.position = TASK_POS - Vector2(TASK_SLIDE, 0)
	task.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task.add_theme_stylebox_override("panel", StyleBoxEmpty.new())  # только текст, без плашки
	var text := Label.new()
	text.text = TASK
	text.add_theme_font_size_override("font_size", 22)
	text.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9, TEXT_ALPHA))
	task.add_child(text)
	task.modulate.a = 0.0
	add_child(task)

	subtitle = Label.new()
	subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_top = -150
	subtitle.offset_bottom = -90
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, TEXT_ALPHA))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.modulate.a = 0.0
	add_child(subtitle)


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return
	# В самом начале: как только герой встал после падения.
	if not shown_at_start and not player.locked:
		shown_at_start = true
		task_tween = _new_task_tween()
		_task_step(task_tween, true, 1.5)
		task_tween.chain().tween_interval(TASK_AT_START)
		task_tween.chain()
		_task_step(task_tween, false, 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_TAB and not event.echo:
		if event.pressed and not tab_held:
			tab_held = true
			_task_step(_new_task_tween(), true, TASK_SHOW)
		elif not event.pressed and tab_held:
			tab_held = false
			_task_step(_new_task_tween(), false, TASK_HIDE)
		get_viewport().set_input_as_handled()


## Новая анимация плашки — прежняя (если ещё идёт) обрывается там, где была.
func _new_task_tween() -> Tween:
	if task_tween:
		task_tween.kill()
	task_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return task_tween


## Шаг анимации: текст проявляется и чуть выезжает вправо — или растаять и уехать обратно.
func _task_step(tween: Tween, appear: bool, time: float) -> void:
	var x := TASK_POS.x if appear else TASK_POS.x - TASK_SLIDE
	tween.tween_property(task, "modulate:a", 1.0 if appear else 0.0, time)
	tween.tween_property(task, "position:x", x, time)


## Субтитр внизу экрана: медленно проявляется, держится и медленно тает.
func say(line: String) -> void:
	if sub_tween:
		sub_tween.kill()
	subtitle.text = line
	sub_tween = create_tween()
	sub_tween.tween_property(subtitle, "modulate:a", 1.0, SUB_FADE_IN).set_trans(Tween.TRANS_SINE)
	sub_tween.tween_interval(SUB_HOLD)
	sub_tween.tween_property(subtitle, "modulate:a", 0.0, SUB_FADE_OUT).set_trans(Tween.TRANS_SINE)
