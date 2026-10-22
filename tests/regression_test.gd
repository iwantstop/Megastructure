extends SceneTree

## Регрессия: вся игра по порядку, как играет человек, — каждая механика проверяется, итог «прошло X из Y».
## Пролог → падение → тьма → подъём → задание и подсказки → курение → рассказ об ангеле → Tab → шаги в городе,
## манекены, ангел-проводник → мост: припадки, сигарета гаснет, оглядывание на город → подножие: глитч к пещере →
## костёр → пещера и вспышка-падение → прощание, плач, глитч к вершине, рассказ о солнце, бинты → финал: слова,
## ангел «25-м кадром», вспышка солнца, слайды → снова на крыше. Плюс регуляторы админ-панели.
## Между участками героя переносят (это проверка механик, а не поиска дороги), но сами участки он проходит ногами.
## Запуск (с окном): godot --path . -s tests/regression_test.gd -- --prologue
## Итог — в консоли и в tests/regression_playthrough.txt (строка «ИТОГ»). Всё вместе — tests/run_regression.bat.

const LINES := ["Стой", "Не уходи", "Останься"]
const SEIZURE_LINES := ["Скоро это закончится...", "Возможно именно сегодня...", "Закроются глаза..."]

var world: Node
var player: CharacterBody3D
var hud: Node
var smoke: Node
var presence: Node
var intro: Node
var finale: Node
var seizure: Node
var journey: Node
var flashback: Node
var bandages: Node
var admin: Node
var passed := 0
var failed := 0
var report: PackedStringArray = []
var steer_to = null        # куда герой идёт сам (Vector3) — или null
var steer_path := false     # идти вверх по тропе горы


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


# --- Помощники -----------------------------------------------------------------

func _check(name: String, ok: bool, detail := "") -> void:
	var line := "%s %s%s" % ["✔" if ok else "✘", name, (" — " + detail) if detail != "" else ""]
	if ok:
		passed += 1
	else:
		failed += 1
	report.append(line)
	print("REG ", line)


func _section(title: String) -> void:
	report.append("\n== " + title)
	print("REG == ", title)


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


## Ждёт, пока условие станет верным (или выйдет время). Возвращает, дождался ли.
func _until(condition: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if condition.call():
			return true
		await process_frame
		left -= root.get_process_delta_time() if root.get_process_delta_time() > 0.0 else 0.016
	return condition.call()


func _place(pos: Vector3, look_at := Vector3.INF) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.last_safe = pos
	if look_at != Vector3.INF:
		var to := look_at - pos
		player.rotation.y = atan2(-to.x, -to.z)
		player.target_yaw = player.rotation.y
	player.target_pitch = 0.0


func _yaw_error_to(point: Vector3) -> float:
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var to := point - player.global_position
	return absf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(to.x, to.z))))


## Каждый кадр: если задано — рулим героем к точке или вверх по тропе.
func _process(_delta: float) -> bool:
	if player and not player.locked:
		var aim = steer_to
		if steer_path:
			var f := Mountain.fraction_at_height(player.global_position.y)
			aim = Mountain.path_point(minf(f + 0.006, 1.0)).origin
		if aim != null:
			var to: Vector3 = aim - player.global_position
			player.target_yaw = atan2(-to.x, -to.z)
	return false


func _steps_heard(seconds: float) -> int:
	var soundscape := _find("soundscape.gd")
	var seen := {}
	var left := seconds
	while left > 0.0:
		for p in soundscape.get_children():
			if p is AudioStreamPlayer and p.bus == &"Steps":
				seen[p.get_instance_id()] = true
		await process_frame
		left -= root.get_process_delta_time()
	return seen.size()


# --- Сценарий ------------------------------------------------------------------

func _run() -> void:
	await process_frame
	await _prologue()
	player = get_first_node_in_group("player")
	hud = get_first_node_in_group("hud")
	smoke = get_first_node_in_group("smoke")
	presence = get_first_node_in_group("presence")
	intro = _find("intro.gd")
	finale = _find("finale.gd")
	seizure = _find("seizure.gd")
	journey = _find("journey.gd")
	flashback = _find("flashback.gd")
	bandages = _find("bandages.gd")
	admin = _find("admin.gd")
	await _fall_and_wake()
	await _first_minutes()
	await _city()
	await _bridge()
	await _mountain_base()
	await _cave()
	await _farewell()
	await _finale()
	_admin()
	_finish()


func _prologue() -> void:
	_section("Пролог")
	# (лямбда видит копию локальной переменной — поэтому ищем обычным циклом)
	var prologue: Node = null
	for k in 300:
		prologue = _find("prologue.gd")
		if prologue:
			break
		await process_frame
	_check("пролог показан", prologue != null)
	if prologue == null:
		return
	var hero: Node3D = null
	for k in 3000:
		hero = get_first_node_in_group("player")
		if hero:
			break
		await process_frame
	# Предыстория — сразу после загрузки, до меню; каждый слайд ждёт пробела.
	for i in prologue.PARAGRAPHS.size():
		var shown := await _until(func() -> bool: return prologue.index == i and prologue.text.modulate.a > 0.99, 30.0)
		await _wait(2.0)
		_check("слайд %d стоит без пробела (меню ещё нет)" % (i + 1), shown and prologue.index == i and prologue.menu == null)
		_tap(KEY_SPACE)
	var menu_ready := await _until(func() -> bool: return prologue.menu != null and prologue.menu.modulate.a > 0.9, 20.0)
	_check("после предыстории — главное меню: «Начать», «Настройки», «Выход»", menu_ready and prologue.menu.get_child_count() == 3)
	var intro_node := _find("intro.gd")
	_check("меню — на кадре ночной крыши, мир живёт", not paused and intro_node.state == intro_node.State.ROOF
		and hero.global_position.y > 755.0 and Game.journey.night > 0.99)
	prologue.menu.get_child(0).emit_signal("pressed")   # «Начать игру»
	var ran := await _until(func() -> bool: return intro_node.running and Vector2(hero.velocity.x, hero.velocity.z).length() > 6.0, 3.0)
	_check("«Начать игру» — разбегается по крыше, камера трясётся", ran and hero.fall_shake > 0.1)
	var stepped := await _until(func() -> bool: return intro_node.state == intro_node.State.FALLING, 12.0)
	var y0: float = hero.global_position.y
	await _wait(2.0)
	_check("прыгнул с края — падение", stepped and y0 - hero.global_position.y > 20.0, "пролетел %.0f м за 2 с" % (y0 - hero.global_position.y))


func _fall_and_wake() -> void:
	_section("Падение и пробуждение")
	var max_fov := 0.0
	var max_speed := 0.0      # скорость поворота головы, рад/с (раньше рывки давали ~11)
	var hitches := 0
	var last_look: Vector2 = player.panic_look
	while intro.state == intro.State.FALLING:
		await process_frame
		if intro.state != intro.State.FALLING:
			break   # кадр удара: взгляд сбрасывается под чёрным экраном — это не рывок
		var dt := root.get_process_delta_time()
		max_fov = maxf(max_fov, player.camera.fov)
		if dt > 0.0 and dt < 0.05:
			max_speed = maxf(max_speed, (player.panic_look - last_look).length() / dt)
		elif dt >= 0.05:
			hitches += 1      # подвисший кадр: в нём «скачок» — от задержки кадра, а не от рывка головы
		last_look = player.panic_look
	_check("паника: обзор шире с разгоном", max_fov > 95.0, "до %.0f°" % max_fov)
	_check("паника: голова поворачивается плавно, без рывков", max_speed < 6.0,
		"наибольшая скорость %.0f°/с; подвисших кадров: %d" % [rad_to_deg(max_speed), hitches])
	await process_frame
	_check("пробил крышу летающей машины — вид из салона", intro.state == intro.State.CAR and intro.car.cam.current)
	await _wait(1.0)
	_check("в салоне воет сигнализация, мигает лампа", intro.car.alarm.playing)
	var landed := await _until(func() -> bool: return intro.state != intro.State.CAR, 15.0)
	_check("машина по спирали падает и разбивается — тьма", landed and intro.fade.color.a > 0.99)
	await _wait(5.0)
	_check("во тьме текст ждёт пробел", intro.state == intro.State.STORY and intro.story.modulate.a > 0.99,
		"\"%s…\"" % intro.story.text.substr(0, 30))
	_check("текст во тьме — от первого лица", intro.story.text.begins_with("Я лежал"))
	_tap(KEY_SPACE)
	await _until(func() -> bool: return intro.state == intro.State.LYING, 5.0)
	await _wait(1.0)
	var to_peak := Mountain.CENTER + Vector3.UP * Mountain.PEAK
	_check("тьма спала — взгляд на гору", _yaw_error_to(to_peak) < 3.0, "ошибка %.1f°" % _yaw_error_to(to_peak))
	var wreck: Node3D = intro.car
	_check("рядом горит разбитая машина", wreck.phase == wreck.Phase.WRECK and wreck.flames.emitting
		and wreck.global_position.distance_to(player.global_position) < 12.0, "%.0f м" % wreck.global_position.distance_to(player.global_position))
	await _wait(1.5)
	_check("лежит и сам не встаёт", player.locked and intro.state <= intro.State.HINT)
	await _until(func() -> bool: return intro.state == intro.State.HINT and intro.hint.modulate.a > 0.9, 8.0)
	_check("подсказка «W — подняться»", intro.hint.modulate.a > 0.9, intro.hint.text)
	_key(KEY_W, true)
	_key(KEY_W, false)
	var stood := await _until(func() -> bool: return not player.locked and player.lying < 0.01, 8.0)
	_check("по W встал, управление есть", stood)


func _first_minutes() -> void:
	_section("Первые минуты: задание, подсказки, курение, рассказ об ангеле")
	var stood_at := Time.get_ticks_msec()
	await _until(func() -> bool: return hud.task.modulate.a > 0.95, 4.0)
	_check("задание «Нужно идти»", hud.task.get_child(0).text == "Нужно идти" and hud.task.modulate.a > 0.95, hud.task.get_child(0).text)
	await _until(func() -> bool: return hud.smoke_hint.modulate.a > 0.95, 5.0)
	_check("подсказка «Закурить - T»", hud.smoke_hint.modulate.a > 0.95)
	# Курение — пока ждём рассказ.
	_tap(KEY_T)
	var took := await _until(func() -> bool: return smoke.state == smoke.State.WAIT_STRIKE, 8.0)
	_check("T — сигарета из пачки, осталось 9", took and smoke.left_in_pack == 9, "в пачке %d" % smoke.left_in_pack)
	var strikes := 0
	while smoke.state != smoke.State.SMOKING and strikes < 40:
		if smoke.state == smoke.State.WAIT_STRIKE:
			strikes += 1
			_tap(KEY_T)
		await _wait(0.45)
	await _until(func() -> bool: return smoke.state == smoke.State.SMOKING, 6.0)
	_check("Zippo загорается не с первого раза всегда (50%)", smoke.state == smoke.State.SMOKING, "чирков: %d" % strikes)
	var paper: float = smoke.paper_len
	_key(KEY_T, true)
	await _wait(2.0)
	_check("затяжка: сигарета у губ, кончик разгорелся, тлеет", smoke.puff_amount > 0.9 and smoke.glow > 0.9 and smoke.paper_len < paper)
	_key(KEY_T, false)
	await _wait(1.0)
	_check("выдох — дым", smoke.exhale.emitting and smoke.puff_amount < 0.5)
	# Рассказ об ангеле (через ~11,5 с после подъёма) и новое задание.
	var narrated := await _until(func() -> bool: return hud.narration.modulate.a > 0.99, 20.0)
	_check("рассказ об ангеле — от первого лица", narrated and hud.narration.text.begins_with("В отчаянии") and "мне умереть" in hud.narration.text,
		"через %.1f с после подъёма" % ((Time.get_ticks_msec() - stood_at) / 1000.0))
	var gone := await _until(func() -> bool: return hud.narration.modulate.a < 0.01, 30.0)
	await _wait(0.5)
	_check("после рассказа задание «Я должен найти его»", gone and hud.task.get_child(0).text == hud.TASK_FIND)
	await _wait(9.0)
	_key(KEY_TAB, true)
	await _wait(1.0)
	var shown: float = hud.task.modulate.a
	_key(KEY_TAB, false)
	await _wait(1.0)
	_check("Tab показывает задание и прячет", shown > 0.95 and hud.task.modulate.a < 0.05)


func _city() -> void:
	_section("Город")
	var crowd := _find("crowd.gd")
	var playing := 0
	for p in crowd.find_children("*", "AnimationPlayer", true, false):
		if p.is_playing():
			playing += 1
	_check("манекены застыли", crowd.get_child_count() > 100 and playing == 0, "%d фигур" % crowd.get_child_count())
	_place(Vector3(-24, 0.5, -60), Vector3(-24, 0, -300))
	_key(KEY_W, true)
	var steps := await _steps_heard(5.0)
	_key(KEY_W, false)
	_check("шаги в городе слышно", steps >= 6, "%d шагов за 5 с" % steps)
	_place(Vector3(0, 0.5, -60), Vector3(0, 0, -300))
	await _wait(0.5)
	presence.call_now()
	var appeared := await _until(func() -> bool: return presence.figure.visible, 8.0)
	var cam := root.get_viewport().get_camera_3d()
	var dist: float = presence.figure.global_position.distance_to(player.global_position)
	_check("ангел появляется впереди, в кадре", appeared and cam.is_position_in_frustum(presence.figure.global_position + Vector3.UP) and dist > 15.0 and dist < 50.0, "%.0f м" % dist)
	var noticed := await _until(func() -> bool: return presence.noticed, 6.0)
	await _wait(2.5)
	_check("заметил её — субтитр-просьба", noticed and hud.subtitle.text in LINES, "\"%s\"" % hud.subtitle.text)
	_tap(KEY_C)   # снимок — он будет на финальных слайдах
	await _wait(0.6)
	_check("C — снимок бодикамерой", Photos.taken.size() == 1)


func _bridge() -> void:
	_section("Мост: припадки и оглядывание")
	await _until(func() -> bool: return hud.subtitle.modulate.a < 0.01, 10.0)
	_place(Vector3(0, 0.5, -380), Vector3(0, 0, -3000))
	steer_to = Vector3(0, 0, -3000)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	var cigarette_was_lit: bool = smoke.state == smoke.State.SMOKING
	for i in 3:
		var stop: Dictionary = seizure.stops[i]
		var hit := await _until(func() -> bool: return seizure.active == i, 90.0)
		var at_z: float = player.global_position.z
		var started := Time.get_ticks_msec()
		await _until(func() -> bool: return seizure.active == -2, 5.0)
		var length := (Time.get_ticks_msec() - started) / 1000.0
		_check("припадок %d: на %.0f → перенос на %.0f" % [i + 1, stop.at, stop.to], hit and absf(at_z - stop.at) < 15.0 and absf(player.global_position.z - stop.to) < 5.0,
			"сработал на %.0f, теперь %.0f, %.2f с" % [at_z, player.global_position.z, length])
		if i == 0:
			var creature := _find("creature.gd")
			_check("у перил стоит существо, смотрит в бездну (Idle)", creature != null and creature.visible and not creature.gone
				and creature.body.find_child("AnimationPlayer", true, false).current_animation == "pack/Idle")
		if i == 1:
			var creature := _find("creature.gd")
			_check("подошёл к существу — исчезло", creature != null and creature.gone and not creature.visible)
		if i == 0:
			_check("припадок гасит сигарету, руки дрожат", (not cigarette_was_lit or smoke.state == smoke.State.UNLIT) and smoke.tremor > 0.9,
				"было: %s" % ("горела" if cigarette_was_lit else "не курил"))
		await _until(func() -> bool: return hud.subtitle.modulate.a > 0.9, 5.0)
		_check("после припадка %d — мысль" % (i + 1), hud.subtitle.text == SEIZURE_LINES[i], "\"%s\"" % hud.subtitle.text)
		if i == 1:
			var told := await _until(func() -> bool: return hud.narration.modulate.a > 0.5 and hud.narration.text.begins_with("Чем"), 30.0)
			await _wait(4.0)
			_check("рассказ о тепле: стоит, управления нет, смотрит на город", told and player.locked and Vector2(player.velocity.x, player.velocity.z).length() < 0.2 and _yaw_error_to(Vector3(0, 0, -150)) < 25.0)
			var back := await _until(func() -> bool: return not player.locked, 40.0)
			_check("текст растаял — снова к горе, управление есть", back and _yaw_error_to(Mountain.CENTER) < 25.0)
	_tap(KEY_C)
	var arrived := await _until(func() -> bool: return player.global_position.z < Structures_end() + 20.0, 40.0)
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	steer_to = null
	_check("дошёл до горы", arrived, "z=%.0f" % player.global_position.z)


func Structures_end() -> float:
	return preload("res://scripts/structures.gd").CAUSEWAY_END


func _mountain_base() -> void:
	_section("Подножие: глитч к пещере, костёр")
	var start := Mountain.path_point(0.0)
	_place(start.origin + Vector3.UP * 0.5, start.origin - start.basis.z * 10.0)
	steer_path = true
	_key(KEY_W, true)
	var hit := await _until(func() -> bool: return seizure.active == 3, 60.0)
	await _until(func() -> bool: return seizure.active == -2, 5.0)
	_key(KEY_W, false)
	steer_path = false
	var expected := Mountain.path_point(Mountain.CAVE_AT - 0.014).origin
	_check("глитч у подножия — перенос к пещере", hit and player.global_position.distance_to(expected) < 5.0, "до точки %.1f м" % player.global_position.distance_to(expected))
	var fire := get_first_node_in_group("campfire") as Node3D
	_place(fire.global_position + Vector3(1.6, 0.5, 0), fire.global_position)
	var hint := await _until(func() -> bool: return hud.action_label.modulate.a > 0.9, 3.0)
	_check("у костра — «Разжечь костёр - E»", hint and hud.action_label.text == fire.HINT)
	_tap(KEY_E)
	await _wait(3.0)
	_check("E — костёр горит", fire.lit and fire.light.light_energy > 1.0)


func _cave() -> void:
	_section("Пещера и вспышка-падение")
	var cave := Mountain.cave_frame()
	_place(cave * Vector3(0, 0.5, -12.0), cave * Vector3(0, 0, -30.0))   # между выходом и дверью квартиры
	await _wait(1.0)
	_check("в пещере — уличный звук глохнет", _find("soundscape.gd")._zone() == "cave")
	steer_to = cave * Vector3(0, 0, 6.0)
	_key(KEY_W, true)
	var fell := await _until(func() -> bool: return flashback.falling, 20.0)
	_key(KEY_W, false)
	steer_to = null
	_check("вышел из пещеры — снова падение с небоскрёба", fell and player.lying > 0.9 and player.global_position.y > 150.0, "y=%.0f" % player.global_position.y)
	var woke := await _until(func() -> bool: return flashback.done and not player.locked, 8.0)
	var near := Mountain.path_point(Mountain.fraction_at_height(MountainFeatures.FAREWELL_HEIGHT) - 0.014).origin
	_check("очнулся на тропе у места прощания", woke and player.global_position.distance_to(near) < 5.0)


func _farewell() -> void:
	_section("Прощание, глитч к вершине")
	steer_path = true
	_key(KEY_W, true)
	var sorry := await _until(func() -> bool: return hud.subtitle.text == "Прости меня..." and hud.subtitle.modulate.a > 0.9, 90.0)
	var crying := false
	for v in presence.get_children():
		if v is AudioStreamPlayer and v.stream == presence.cry and v.playing:
			crying = true
	_check("ангел оборачивается — «Прости меня...»", sorry)
	_check("герой тихо плачет", crying)
	var from_y: float = player.global_position.y
	var hit := await _until(func() -> bool: return seizure.active == 4, 120.0)
	await _until(func() -> bool: return seizure.active == -2, 5.0)
	_key(KEY_W, false)
	steer_path = false
	_check("через ~100 м — глитч к вершине", hit and absf(player.global_position.y - (Mountain.PEAK - 40.0)) < 3.0, "y=%.0f" % player.global_position.y)
	var sun := await _until(func() -> bool: return hud.narration.modulate.a > 0.5, 6.0)
	_check("рассказ о солнце — от первого лица", sun and hud.narration.text.begins_with("Поднявшись выше облаков, я"))
	_check("на подъёме падают бинты", bandages.dropped >= 1, "%d полосок" % bandages.dropped)
	_check("после прощания ангел больше не приходит", presence.farewell_done)
	_tap(KEY_C)
	await _wait(0.6)
	await _until(func() -> bool: return hud.narration.modulate.a < 0.01, 30.0)


func _finale() -> void:
	_section("Финал")
	var pack_before: int = smoke.left_in_pack
	var photos: int = Photos.taken.size()
	_place(Mountain.CENTER + Vector3(0, Mountain.PEAK + 0.5, 0))
	var started := await _until(func() -> bool: return finale.started, 3.0)
	_check("на вершине — финал", started)
	var seen := {}
	var flashes := 0
	var longest := 0.0
	var on_for := 0.0
	var was := false
	var veil_flash := 0.0
	var waited := 0.0
	while finale.slide < 0 and waited < 60.0:
		if hud.subtitle.modulate.a > 0.5:
			var shown_text: String = hud.subtitle.text if hud.subtitle.visible_characters < 0 else hud.subtitle.text.substr(0, hud.subtitle.visible_characters)
			seen[shown_text] = true
		var vis: bool = presence.figure.visible
		if vis and not was:
			flashes += 1
		on_for = on_for + root.get_process_delta_time() if vis else 0.0
		longest = maxf(longest, on_for)
		was = vis
		if seen.has("Это...Всё...Я") and player.lying < 0.1:   # вспышка в миг взрыва (до того как он лёг и всё светлеет)
			veil_flash = maxf(veil_flash, finale.veil.color.a)
		await process_frame
		waited += root.get_process_delta_time()
	_check("«Это...» → «Это...Всё...» → «Это...Всё...Я»", seen.has("Это...") and seen.has("Это...Всё...") and seen.has("Это...Всё...Я"))
	_check("ангел мелькает «25-м кадром», рваным ритмом", flashes >= 6 and longest < 0.15, "%d вспышек, дольше всего %.2f с" % [flashes, longest])
	_check("солнце взрывается — вспышка", veil_flash > 0.6, "%.2f" % veil_flash)
	for i in finale.EPILOGUE.size():
		var ready := await _until(func() -> bool: return finale.slide == i and finale.slide_ready, 20.0)
		await _wait(2.5)
		_check("слайд %d стоит до пробела" % (i + 1), ready and finale.slide == i and finale.slide_text.text == finale.EPILOGUE[i], "\"%s\"" % finale.EPILOGUE[i])
		if i == finale.EPILOGUE.size() - 1:
			_check("на слайдах — снимки игрока, вразброс", photos >= 3 and finale.board.get_child_count() == photos, "%d снимков" % finale.board.get_child_count())
			root.get_viewport().get_texture().get_image().save_png("res://screenshots/regression_epilogue_photos.png")
		_tap(KEY_SPACE)
	var roof := preload("res://scripts/structures.gd").ROOF_SPOT
	var back := await _until(func() -> bool: return not player.locked and finale.veil.color.a < 0.05, 15.0)
	_check("снова на крыше той башни, управление есть", back and player.global_position.distance_to(roof) < 2.0 and player.is_on_floor(),
		"%s" % player.global_position.snapped(Vector3.ONE * 0.1))
	_check("звук мира вернулся", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")) > -1.0)
	_check("новый круг: пачка не пополнилась, снимки — заново", smoke.left_in_pack == pack_before and Photos.taken.is_empty(),
		"в пачке %d" % smoke.left_in_pack)


func _admin() -> void:
	_section("Админ-панель")
	if admin == null:
		_check("админ-панель есть", false)
		return
	var mat: ShaderMaterial = admin.bodycam.get_child(0).material
	admin._on_bodycam_strength(0.0)
	var off: bool = is_zero_approx(mat.get_shader_parameter("distortion")) and is_zero_approx(mat.get_shader_parameter("grain"))
	admin._on_bodycam_strength(100.0)
	_check("регулятор бодикамеры: 0% — чисто, 100% — как было", off and is_equal_approx(mat.get_shader_parameter("distortion"), 0.14))
	_check("регуляторы покачивания и крена — по умолчанию 100%", is_equal_approx(player.bob_scale, 1.0) and is_equal_approx(player.turn_roll_scale, 1.0))


func _finish() -> void:
	var total := passed + failed
	var summary := "ИТОГ: прошло %d из %d%s" % [passed, total, "" if failed == 0 else " — НЕ ПРОШЛО: %d" % failed]
	report.append("\n" + summary)
	print("REG ", summary)
	var file := FileAccess.open("res://tests/regression_playthrough.txt", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(report) + "\n")
	quit(0 if failed == 0 else 1)
