extends CanvasLayer

## Экран загрузки с прологом. Чёрный экран, название «Где мой ангел?» — под ним строится мир; потом под
## названием главное меню («Начать», «Настройки», «Выход»). «Начать» — абзацы предыстории по одному медленно проявляются и тают. Каждый остаётся на экране,
## пока игрок не нажмёт пробел. Пробел — следующий абзац; после последнего — «…и бросился вниз.» —
## пробел начинает игру. Пока идёт пролог, игра на паузе: падение не начинается.

signal title_shown
signal finished

const TITLE := "Где мой ангел?"
const PARAGRAPHS := [
	"В сердце антиутопического города, где небо вечно затянуто свинцовыми тучами, а дождь, падая, мгновенно превращается в ледяную корку на рассвете, живу я — бессмертный человек. Город этот — воплощение человеческих пороков: каждый его житель словно оживший символ какого‑либо греха. Меркантильность здесь возведена в культ, эгоизм стал нормой, духовный упадок — обыденностью, а разврат — едва ли не единственной формой общения.",
	"Рекламные билборды горят неугасимым огнём, бросая зловещие отблески на улицы, а с крыш ежечасно срываются те, кто больше не в силах выносить это существование. В этом мире нет места искренности: каждый стремится обмануть другого — ради денег, ради минутного удовольствия, ради самого факта победы над ближним.",
	"Я провёл тут много лет. Пытался выстроить свою жизнь, найти в ней смысл, но чем дольше остаюсь в этом городе, тем отчётливее осознаю собственную незначительность. Всё, за что я берусь, рушится; я чувствую, что нахожусь не там, где должен быть, но не могу ничего изменить — я не в том месте и не с теми людьми. В моём мире не существует объективности: я даже не знаю, что может быть иначе, что за пределами этих улиц и домов есть другая жизнь.",
	"Однажды терпение иссякло. Я поднялся на самую высокую башню, в последний раз взглянул на небо, затянутое ледяной пеленой, докурил сигарету — и бросился вниз.",
]
const FADE := 1.4
const TEXT_ALPHA := 0.82

var background: ColorRect
var title: Label
var text: Label
var hint: Label
var index := -1
var shown_for := 0.0
var playing := false
var tween: Tween
var menu: VBoxContainer
var settings: Control


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # работает, пока мир на паузе
	background = ScreenText.black(self)
	title = ScreenText.center(background, TITLE, 34, Color(0.85, 0.85, 0.85, 0.7))
	title.modulate.a = 0.0
	text = ScreenText.center(background, "", 24, Color(0.88, 0.87, 0.85, TEXT_ALPHA))
	text.modulate.a = 0.0
	hint = ScreenText.corner_hint(background, "загрузка…")
	var t := create_tween()
	t.tween_property(title, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void: title_shown.emit())


## Мир построен — под названием проявляется главное меню.
func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = MenuUi.column(background, 110.0)
	MenuUi.button(menu, "Начать", _start)
	MenuUi.button(menu, "Настройки", _open_settings)
	MenuUi.button(menu, "Выход", func() -> void: get_tree().quit())
	menu.modulate.a = 0.0
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.hide()
	settings.back.connect(_close_settings)
	background.add_child(settings)
	var fade := create_tween()
	fade.tween_property(hint, "modulate:a", 0.0, 0.6)
	fade.parallel().tween_property(menu, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	menu.get_child(0).grab_focus()


## «Начать»: меню тает — начинается пролог.
func _start() -> void:
	for b in menu.get_children():
		b.disabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var fade := create_tween()
	fade.tween_property(menu, "modulate:a", 0.0, 0.6)
	fade.tween_callback(menu.queue_free)
	hint.modulate.a = 1.0
	play_text()


func _open_settings() -> void:
	menu.hide()
	title.hide()
	settings.open()


func _close_settings() -> void:
	settings.hide()
	menu.show()
	title.show()
	menu.get_child(1).grab_focus()


## «Начать» — название тает, начинаются абзацы.
func play_text() -> void:
	playing = true
	hint.text = "пробел — дальше"
	tween = create_tween()
	tween.tween_property(title, "modulate:a", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_next)


func _process(delta: float) -> void:
	if not playing or index < 0:
		return
	shown_for += delta


## Сам текст не листается: пробел — следующий абзац, пробел на последнем — начало игры (падение).
func _unhandled_input(event: InputEvent) -> void:
	if not playing or index < 0 or shown_for < 0.6:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if index < PARAGRAPHS.size() - 1:
			_next()
		else:
			_finish()


## Следующий абзац: прежний тает, новый проявляется.
func _next() -> void:
	shown_for = 0.0
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
	tween.tween_callback(func() -> void: shown_for = 0.0)


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
