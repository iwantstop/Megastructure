extends SceneTree

## Видео начала игры: предыстория (слайды по пробелу) → ночная крыша с меню (мышь по пунктам — герой смотрит
## туда) → «Начать новую игру» → разбег, прыжок, туман, «НАСЛАЖДАЙСЯ», падение → пробил крышу машины (стоп).
## Запуск: godot --path . --write-movie start.avi --fixed-fps 30 -s res://tests/start_clip.gd -- --prologue

const SLIDE := 4.0        # столько каждый абзац на экране
const AFTER_CAR := 3.0    # после удара о крышу машины — ещё столько (салон: дым, искры), и стоп

var world: Node


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func _space() -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_SPACE
		k.physical_keycode = KEY_SPACE
		k.pressed = down
		Input.parse_input_event(k)


func _run() -> void:
	var prologue: Node = null
	while prologue == null or not prologue.playing:
		prologue = _find("prologue.gd")
		await process_frame
	for i in prologue.PARAGRAPHS.size():
		while not (prologue.index == i and prologue.text.modulate.a > 0.99):
			await process_frame
		await _wait(SLIDE)
		_space()
	while prologue.menu == null or prologue.menu.modulate.a < 0.99:
		await process_frame
	await _wait(2.5)
	for k in [0, 1, 2, 0]:   # Начать → Настройки (голова набок) → Выход (люк) → снова Начать
		var item: Button = prologue.menu.get_child(k)
		item.emit_signal("mouse_entered")
		await _wait(2.6)
		item.emit_signal("mouse_exited")
	prologue.menu.get_child(0).emit_signal("mouse_entered")
	await _wait(0.6)
	prologue.menu.get_child(0).emit_signal("pressed")
	var intro := _find("intro.gd")
	while intro.state != intro.State.CAR:
		await process_frame
	await _wait(AFTER_CAR)
	quit()
