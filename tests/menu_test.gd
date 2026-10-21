extends SceneTree

## Меню и настройки: главное меню на экране названия → «Настройки» (громкость меняется и сохраняется) → «Назад»
## → «Начать» (пролог пошёл) → пролог пробелами → падение → Esc: пауза (мир стоит) → «Настройки» → Esc назад →
## Esc: игра идёт. Снимки — screenshots/menu_*.png. Настройки игрока в конце возвращаются как были.
## Запуск (с окном): godot --path . -s tests/menu_test.gd -- --prologue

var world: Node
var passed := 0
var failed := 0
var saved_before := ""


func _initialize() -> void:
	var file := FileAccess.open(Settings.FILE, FileAccess.READ)
	if file:
		saved_before = file.get_as_text()
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("MENU %s %s%s" % ["✔" if ok else "✘", name, (" — " + detail) if detail else ""])


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/menu_%s.png" % name)


func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func _run() -> void:
	var prologue: Node = null
	for i in 3000:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("prologue.gd"):
				prologue = c
		if prologue and prologue.menu:
			break
		await process_frame
	await _wait(1.2)
	_check("главное меню под названием", prologue != null and prologue.menu != null and prologue.menu.modulate.a > 0.9,
		", ".join(prologue.menu.get_children().map(func(b: Button) -> String: return b.text)))
	await _shot("main")
	_check("игра на паузе, пока в меню", paused)
	# Настройки
	prologue.menu.get_child(1).emit_signal("pressed")
	await _wait(0.5)
	await _shot("settings")
	_check("настройки открываются", prologue.settings.visible and not prologue.menu.visible)
	Settings.set_value("master", 0.5)
	var bus := AudioServer.get_bus_index("Master")
	_check("громкость меняется сразу", absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.1, "%.1f дБ" % AudioServer.get_bus_volume_db(bus))
	var cfg := ConfigFile.new()
	cfg.load(Settings.FILE)
	_check("и сохраняется в файл", is_equal_approx(cfg.get_value("settings", "master", 1.0), 0.5))
	_key(KEY_ESCAPE)
	await _wait(0.3)
	_check("Esc — назад в меню", not prologue.settings.visible and prologue.menu.visible)
	# Начать
	prologue.menu.get_child(0).emit_signal("pressed")
	await _wait(3.5)
	_check("«Начать» — пролог пошёл", prologue.playing and prologue.index == 0)
	for i in prologue.PARAGRAPHS.size():
		while not (prologue.index == i and prologue.text.modulate.a > 0.99):
			await process_frame
		await _wait(0.8)
		_key(KEY_SPACE)
	var player: Node3D = null
	for i in 600:
		player = get_first_node_in_group("player")
		if player and not paused:
			break
		await process_frame
	await _wait(2.0)
	# Пауза
	var pause: Node = null
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("pause_menu.gd"):
			pause = c
	_key(KEY_ESCAPE)
	await _wait(0.3)
	var y1: float = player.global_position.y
	await _wait(1.0)
	_check("Esc — пауза: мир стоит", pause.open and paused and is_equal_approx(player.global_position.y, y1))
	await _shot("pause")
	pause.list.get_child(1).emit_signal("pressed")
	await _wait(0.3)
	_check("из паузы — настройки", pause.settings.visible)
	_key(KEY_ESCAPE)
	await _wait(0.3)
	_check("Esc — из настроек обратно в паузу", not pause.settings.visible and pause.open)
	_key(KEY_ESCAPE)
	await _wait(1.0)
	_check("Esc — игра идёт дальше", not pause.open and not paused and player.global_position.y < y1 - 1.0)
	# Вернуть настройки игрока как были.
	if saved_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.FILE))
	else:
		var f := FileAccess.open(Settings.FILE, FileAccess.WRITE)
		f.store_string(saved_before)
	print("MENU ИТОГ: прошло %d из %d" % [passed, passed + failed])
	quit()
