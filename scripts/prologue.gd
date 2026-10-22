extends CanvasLayer

## Экран загрузки с прологом. Чёрный экран, «загрузка…» — строится мир. Потом абзацы предыстории по одному
## медленно проявляются и тают; каждый остаётся на экране, пока игрок не нажмёт пробел (мир на паузе).
## После последнего («…и бросился вниз.») тьма расходится: ночь, герой на крыше самой высокой башни (там же,
## куда возвращает финал, — петля), мир живёт, и прямо на этом кадре — главное меню («Начать игру»,
## «Настройки», «Выход»). «Начать игру» — кнопки тают, и без всяких загрузок он разбегается и прыгает (intro.gd).

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
var text: Label
var hint: Label
var index := -1
var shown_for := 0.0
var playing := false
var tween: Tween
var menu: VBoxContainer
var settings: Control
var ui: Control          # меню и настройки — поверх живого кадра (фон-тьма к тому времени уже растаял)
var shade: ColorRect     # затемнение под настройками


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # работает, пока мир на паузе
	background = ScreenText.black(self)
	text = ScreenText.center(background, "", 24, Color(0.88, 0.87, 0.85, TEXT_ALPHA))
	text.modulate.a = 0.0
	hint = ScreenText.corner_hint(background, "загрузка…")
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.hide()
	ui.add_child(shade)
	var t := create_tween()
	t.tween_interval(0.3)   # дать кадру с «загрузкой» отрисоваться — дальше постройка займёт поток
	t.tween_callback(func() -> void: title_shown.emit())


## Пролог дочитан — проявляется главное меню (поверх ночной крыши).
func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = MenuUi.column(ui, 150.0)
	MenuUi.button(menu, "Начать игру", _start)
	MenuUi.button(menu, "Настройки", _open_settings)
	MenuUi.button(menu, "Выход", func() -> void: get_tree().quit())
	menu.modulate.a = 0.0
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.hide()
	settings.back.connect(_close_settings)
	ui.add_child(settings)
	var fade := create_tween()
	fade.tween_property(menu, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	menu.get_child(0).grab_focus()


## «Начать игру»: новая игра — кнопки тают, игра сразу начинается (разбег и прыжок — intro.gd).
func _start() -> void:
	for b in menu.get_children():
		b.disabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Progress.new_game()   # новая игра — полная пачка
	_finish()


func _open_settings() -> void:
	menu.hide()
	shade.show()
	settings.open()


func _close_settings() -> void:
	settings.hide()
	shade.hide()
	menu.show()
	menu.get_child(1).grab_focus()


## Мир построен — начинаются абзацы.
func play_text() -> void:
	playing = true
	tween = create_tween()
	tween.tween_property(hint, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void: hint.text = "пробел — дальше")
	tween.tween_property(hint, "modulate:a", 1.0, 0.6)
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
			_to_menu()


## Следующий абзац: прежний тает, новый проявляется.
func _next() -> void:
	shown_for = 0.0
	if tween:
		tween.kill()
	tween = create_tween()
	if index >= 0:
		tween.tween_property(text, "modulate:a", 0.0, FADE * 0.7).set_trans(Tween.TRANS_SINE)
	index += 1
	var paragraph: String = PARAGRAPHS[min(index, PARAGRAPHS.size() - 1)]
	tween.tween_callback(func() -> void: text.text = paragraph)
	tween.tween_property(text, "modulate:a", 1.0, FADE).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: shown_for = 0.0)


## Последний абзац дочитан: текст тает, мир снимается с паузы, тьма расходится — ночная крыша и меню.
func _to_menu() -> void:
	playing = false
	add_to_group("main_menu")   # пока меню на экране, Esc не открывает паузу
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(text, "modulate:a", 0.0, FADE * 0.7).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(hint, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void: get_tree().paused = false)
	tween.tween_property(background, "modulate:a", 0.0, 2.5).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_callback(show_menu).set_delay(1.2)


## «Начать игру»: кнопки тают — игра начинается.
func _finish() -> void:
	if tween:
		tween.kill()
	remove_from_group("main_menu")
	tween = create_tween()
	tween.tween_property(menu, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: finished.emit())
	tween.tween_callback(queue_free)
