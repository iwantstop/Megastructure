extends SceneTree

## Меню и настройки: предыстория пробелами → главное меню → «Настройки» (громкость меняется и сохраняется) → «Назад»
## → «Начать» (герой на крыше, шагает с края — падение) → Esc: пауза (мир стоит) → «Настройки» → Esc назад →
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
		if prologue and prologue.playing:
			break
		await process_frame
	# Сначала — предыстория: абзацы по пробелу, ещё до меню.
	_check("после загрузки сразу пошла предыстория (до меню)", prologue != null and prologue.playing and prologue.menu == null)
	for i in prologue.PARAGRAPHS.size():
		while not (prologue.index == i and prologue.text.modulate.a > 0.99):
			await process_frame
		await _wait(0.8)
		_key(KEY_SPACE)
	while prologue.menu == null:
		await process_frame
	await _wait(1.2)
	_check("после последнего абзаца — главное меню (без названия)", prologue.menu.modulate.a > 0.9 and not "TITLE" in prologue.get_property_list().map(func(p: Dictionary) -> String: return p.name),
		", ".join(prologue.menu.get_children().map(func(b: Button) -> String: return b.text)))
	await _wait(2.0)
	await _shot("main")
	var intro_node: Node = null
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
			intro_node = c
	var hero: Node3D = get_first_node_in_group("player")
	_check("меню — прямо на кадре: ночь, герой на крыше самой высокой башни, мир живёт", not paused and intro_node.state == intro_node.State.ROOF
		and hero.global_position.y > 755.0 and Game.journey.night > 0.99)
	_key(KEY_ESCAPE)
	await _wait(0.3)
	var pause_node: Node = null
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("pause_menu.gd"):
			pause_node = c
	_check("Esc в главном меню не открывает паузу", not pause_node.open)
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
	# Начать (в пачке с прошлой игры осталось 3 — новая игра даёт полную)
	Progress.cigarettes = 3
	Game.smoke.left_in_pack = 3
	prologue.menu.get_child(0).emit_signal("pressed")
	_check("новая игра — пачка снова полная", Progress.cigarettes == Progress.FULL_PACK and Game.smoke.left_in_pack == Progress.FULL_PACK,
		"%d сигарет" % Game.smoke.left_in_pack)
	await _wait(1.0)
	_check("«Начать игру» — кнопки исчезли, герой разбегается", prologue == null or not is_instance_valid(prologue) or prologue.menu.modulate.a < 0.05)
	_check("…бежит к краю, камера трясётся", intro_node.running and Vector2(hero.velocity.x, hero.velocity.z).length() > 6.0 and hero.fall_shake > 0.2,
		"%.1f м/с" % Vector2(hero.velocity.x, hero.velocity.z).length())
	await _shot("run")
	var fell := false
	for i in 900:
		if intro_node.state == intro_node.State.FALLING:
			fell = true
			break
		await process_frame
	_check("прыгнул с края — падение", fell and intro_node.jumped)
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
	var clock1: float = intro_node.t   # время вступления: падение или машина — на паузе не идёт
	await _wait(1.0)
	_check("Esc — пауза: мир стоит", pause.open and paused and is_equal_approx(intro_node.t, clock1))
	await _shot("pause")
	pause.list.get_child(1).emit_signal("pressed")
	await _wait(0.3)
	_check("из паузы — настройки", pause.settings.visible)
	_key(KEY_ESCAPE)
	await _wait(0.3)
	_check("Esc — из настроек обратно в паузу", not pause.settings.visible and pause.open)
	_key(KEY_ESCAPE)
	await _wait(1.0)
	_check("Esc — игра идёт дальше", not pause.open and not paused and intro_node.t > clock1 + 0.5)
	# Вернуть настройки игрока как были.
	if saved_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.FILE))
	else:
		var f := FileAccess.open(Settings.FILE, FileAccess.WRITE)
		f.store_string(saved_before)
	print("MENU ИТОГ: прошло %d из %d" % [passed, passed + failed])
	quit()
