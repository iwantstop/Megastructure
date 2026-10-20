extends CanvasLayer

## Экран загрузки с прологом. Чёрный экран, название «Где мой ангел?» — под ним строится мир; потом
## абзацы предыстории по одному медленно проявляются и тают. Каждый держится столько, сколько нужно,
## чтобы прочитать. Последний абзац — «…и бросился вниз.» — остаётся, пока игрок не нажмёт пробел;
## пробел в любой момент пропускает историю. Пока идёт пролог, игра на паузе.

signal title_shown
signal finished

const TITLE := "Где мой ангел?"
const PARAGRAPHS := [
	"В сердце антиутопического города, где небо вечно затянуто свинцовыми тучами, а дождь, падая, мгновенно превращается в ледяную корку на рассвете, живёт бессмертный человек. Город этот — воплощение человеческих пороков: каждый его житель словно оживший символ какого‑либо греха. Меркантильность здесь возведена в культ, эгоизм стал нормой, духовный упадок — обыденностью, а разврат — едва ли не единственной формой общения.",
	"Рекламные билборды горят неугасимым огнём, бросая зловещие отблески на улицы, а с крыш ежечасно срываются те, кто больше не в силах выносить это существование. В этом мире нет места искренности: каждый стремится обмануть другого — ради денег, ради минутного удовольствия, ради самого факта победы над ближним.",
	"Главный герой провёл здесь много лет. Поначалу он пытался выстроить свою жизнь, найти в ней смысл, но чем дольше он оставался в этом городе, тем отчётливее осознавал собственную незначительность. Всё, за что он брался, рушилось; он чувствовал, что находится не там, где должен быть, но не мог ничего изменить — он был не в том месте и не с теми людьми. В его мире не существовало объективности: он даже не знал, что может быть иначе, что за пределами этих улиц и домов есть другая жизнь.",
	"Однажды терпение иссякло. Поднявшись на самую высокую башню, он в последний раз взглянул на небо, затянутое ледяной пеленой, докурил сигарету — и бросился вниз.",
]
const FADE := 1.4
const CHARS_PER_SECOND := 17.0     # спокойное чтение
const TEXT_ALPHA := 0.82

var background: ColorRect
var title: Label
var text: Label
var hint: Label
var index := -1
var shown_for := 0.0
var hold := 0.0
var playing := false
var tween: Tween


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # работает, пока мир на паузе
	background = ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	title = _label(34, Color(0.85, 0.85, 0.85, 0.7))
	title.text = TITLE
	title.modulate.a = 0.0
	text = _label(24, Color(0.88, 0.87, 0.85, TEXT_ALPHA))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.modulate.a = 0.0
	hint = Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -360
	hint.offset_top = -60
	hint.offset_right = -36
	hint.offset_bottom = -30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.3))
	hint.text = "загрузка…"
	background.add_child(hint)
	var t := create_tween()
	t.tween_property(title, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void: title_shown.emit())


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 220
	label.offset_right = -220
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 8)
	background.add_child(label)
	return label


## Мир построен — название тает, начинаются абзацы.
func play_text() -> void:
	playing = true
	hint.text = "пробел — пропустить"
	tween = create_tween()
	tween.tween_property(title, "modulate:a", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_next)


func _process(delta: float) -> void:
	if not playing or index < 0:
		return
	shown_for += delta
	# Абзацы сменяются сами, но последний остаётся на экране — игра начинается только по пробелу.
	if shown_for >= hold and index < PARAGRAPHS.size() - 1:
		_next()


## Пробел — пропустить историю (или начать игру после последнего абзаца).
func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_finish()


## Следующий абзац: прежний тает, новый проявляется.
func _next() -> void:
	shown_for = 0.0
	hold = 1e9  # пока идёт смена — не торопить
	if tween:
		tween.kill()
	tween = create_tween()
	if index >= 0:
		tween.tween_property(text, "modulate:a", 0.0, FADE * 0.7).set_trans(Tween.TRANS_SINE)
	index += 1
	if index == PARAGRAPHS.size() - 1:
		tween.parallel().tween_property(hint, "modulate:a", 0.0, FADE * 0.7)
		tween.tween_callback(func() -> void: hint.text = "пробел — начать")
		tween.tween_property(hint, "modulate:a", 1.0, FADE)
	var paragraph: String = PARAGRAPHS[min(index, PARAGRAPHS.size() - 1)]
	tween.tween_callback(func() -> void: text.text = paragraph)
	tween.tween_property(text, "modulate:a", 1.0, FADE).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		shown_for = 0.0
		hold = 3.0 + paragraph.length() / CHARS_PER_SECOND)


## Конец пролога: текст и подсказка тают, игра снимается с паузы, чёрный экран уходит в падение.
func _finish() -> void:
	playing = false
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(text, "modulate:a", 0.0, FADE * 0.7).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(title, "modulate:a", 0.0, FADE * 0.7)
	tween.parallel().tween_property(hint, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void: finished.emit())
	tween.tween_property(background, "modulate:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)
