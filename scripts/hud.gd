class_name Hud
extends CanvasLayer

## Экранный текст поверх игры:
## - задание в левом верхнем углу — полупрозрачный текст «Я должен уйти», без плашки и обводки. Виден, когда герой
##   встаёт после падения, потом тает; снова появляется, пока зажат Tab;
## - субтитры внизу по центру — медленно проявляются и медленно тают (их зовёт ангел);
## - после того как герой встал — внизу на 5 секунд подсказка «Закурить - T» (smoke.gd);
## - рассказ (narrate) — абзац истории посреди экрана поверх игры: проявляется, держится, пока его
##   можно прочитать, и тает. Первый — когда отработали подсказки после подъёма (вера в ангела);
##   после него задание меняется на «Я должен найти его».

const TASK := "Я должен уйти"
const TASK_FIND := "Я должен найти его"
const ANGEL_STORY := "В отчаянии родилась вера: некий ангел не даёт ему умереть, даровал способность видеть то, что скрыто от других, — различать добро и зло в мире, где мораль давно утрачена, где за каждым добрым поступком скрывается обман."
const ANGEL_STORY_AT := 11.5  # через столько секунд после подъёма — когда задание и «Закурить - T» уже растаяли
const NARRATE_FADE := 1.8
const NARRATE_CPS := 17.0     # скорость спокойного чтения, знаков в секунду
const TASK_AT_START := 7.0     # сколько задание висит после того, как герой встал, с
const TASK_SHOW := 0.45       # Tab: плавное появление, с
const TASK_HIDE := 0.6        # Tab отпущен: плавное исчезание, с
const TASK_POS := Vector2(28, 28)
const TASK_SLIDE := 12.0      # текст слегка выезжает слева и уезжает обратно, px
const TEXT_ALPHA := 0.7       # текст полупрозрачный, без обводки и тени
const SMOKE_HINT := "Закурить - T"
const SMOKE_HINT_TIME := 5.0  # столько подсказка полностью на экране после того, как герой встал
const SUB_FADE_IN := 2.2
const SUB_HOLD := 2.5
const SUB_FADE_OUT := 2.5

var player: CharacterBody3D
var task: PanelContainer
var subtitle: Label
var narration: Label
var narrate_tween: Tween
var smoke_hint: Label
var action_label: Label
var action_tween: Tween
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

	smoke_hint = Label.new()
	smoke_hint.text = SMOKE_HINT
	smoke_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	smoke_hint.offset_top = -90
	smoke_hint.offset_bottom = -50
	smoke_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	smoke_hint.add_theme_font_size_override("font_size", 22)
	smoke_hint.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, TEXT_ALPHA))
	smoke_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	smoke_hint.modulate.a = 0.0
	add_child(smoke_hint)

	action_label = smoke_hint.duplicate()
	action_label.text = ""
	add_child(action_label)

	narration = ScreenText.center(self, "", 24, Color(0.95, 0.94, 0.92, TEXT_ALPHA), 260.0)
	narration.offset_top = 160    # чуть ниже середины кадра
	narration.modulate.a = 0.0


func _process(_delta: float) -> void:
	if player == null:
		player = Game.player
		return
	# В самом начале: как только герой встал после падения.
	if not shown_at_start and not player.locked:
		shown_at_start = true
		task_tween = _new_task_tween()
		_task_step(task_tween, true, 1.5)
		task_tween.chain().tween_interval(TASK_AT_START)
		task_tween.chain()
		_task_step(task_tween, false, 2.0)
		# Подсказка внизу: 5 секунд полностью на экране, мягко проявляется и тает.
		var hint_tween := create_tween()
		hint_tween.tween_interval(2.0)
		hint_tween.tween_property(smoke_hint, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
		hint_tween.tween_interval(SMOKE_HINT_TIME)
		hint_tween.tween_property(smoke_hint, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
		# Когда подсказки отработали — вера в ангела, и задание меняется.
		var story_tween := create_tween()
		story_tween.tween_interval(ANGEL_STORY_AT)
		story_tween.tween_callback(func() -> void: narrate(ANGEL_STORY, _new_task))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_TAB and not event.echo:
		if event.pressed and not tab_held:
			tab_held = true
			_task_step(_new_task_tween(), true, TASK_SHOW)
		elif not event.pressed and tab_held:
			tab_held = false
			_task_step(_new_task_tween(), false, TASK_HIDE)
		get_viewport().set_input_as_handled()


## Новое задание «Я должен найти его»: показывается так же, как в начале, — проявляется, висит и тает.
func _new_task() -> void:
	(task.get_child(0) as Label).text = TASK_FIND
	if tab_held:
		return
	var tween := _new_task_tween()
	_task_step(tween, true, 1.5)
	tween.chain().tween_interval(TASK_AT_START)
	tween.chain()
	_task_step(tween, false, 2.0)


## Абзац истории посреди экрана: проявляется, держится, сколько нужно на чтение, и тает; потом — done.
func narrate(text: String, done: Callable = Callable()) -> void:
	if narrate_tween:
		narrate_tween.kill()
	narration.text = text
	narration.modulate.a = 0.0
	narrate_tween = create_tween()
	narrate_tween.tween_property(narration, "modulate:a", 1.0, NARRATE_FADE).set_trans(Tween.TRANS_SINE)
	narrate_tween.tween_interval(3.0 + text.length() / NARRATE_CPS)
	narrate_tween.tween_property(narration, "modulate:a", 0.0, NARRATE_FADE).set_trans(Tween.TRANS_SINE)
	if done.is_valid():
		narrate_tween.tween_callback(done)


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


## Подсказка действия внизу («Разжечь костёр - E»): мягко проявляется, пока игрок рядом, и тает, когда отошёл.
func action_hint(text: String, show_it: bool) -> void:
	if action_tween:
		action_tween.kill()
	if show_it:
		action_label.text = text
	action_tween = create_tween()
	action_tween.tween_property(action_label, "modulate:a", 1.0 if show_it else 0.0, 0.5).set_trans(Tween.TRANS_SINE)


## Субтитр внизу экрана: медленно проявляется, держится hold секунд и медленно тает.
func say(line: String, hold := SUB_HOLD, fade_in := SUB_FADE_IN, fade_out := SUB_FADE_OUT) -> void:
	if sub_tween:
		sub_tween.kill()
	subtitle.text = line
	subtitle.visible_characters = -1
	subtitle.modulate.a = 0.0
	sub_tween = create_tween()
	sub_tween.tween_property(subtitle, "modulate:a", 1.0, fade_in).set_trans(Tween.TRANS_SINE)
	sub_tween.tween_interval(hold)
	sub_tween.tween_property(subtitle, "modulate:a", 0.0, fade_out).set_trans(Tween.TRANS_SINE)
