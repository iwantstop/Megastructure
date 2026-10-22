extends SceneTree

## Новые механики: ветер перекрывает город на мосту; звук припадка (сердце и звон, мир возвращается за 13 с);
## пачка не пополняется; окурок в бездну (Q); скамейка на мосту (сесть — время быстрее, туман гуще);
## снимки бодикамерой (C); голос рекламы. Снимки экрана — screenshots/feature_*.png.
## Запуск (с окном): godot --path . -s tests/features_test.gd

var world: Node
var player: CharacterBody3D
var smoke: Node
var seizure: Node
var soundscape: Node
var passed := 0
var failed := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("FEAT %s %s%s" % ["✔" if ok else "✘", name, (" — " + detail) if detail else ""])


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _tap(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout   # реальное время, даже если время в игре ускорено


func _place(pos: Vector3, look: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	var to := look - pos
	player.rotation.y = atan2(-to.x, -to.z)
	player.target_yaw = player.rotation.y
	player.target_pitch = 0.0


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/feature_%s.png" % name)


func _loop_db(name: String) -> float:
	return soundscape.loops[name].volume_db


func _run() -> void:
	while _find("intro.gd") == null:
		await process_frame
	await _wait(0.5)
	player = get_first_node_in_group("player")
	smoke = get_first_node_in_group("smoke")
	seizure = _find("seizure.gd")
	soundscape = _find("soundscape.gd")
	_find("intro.gd").skip()
	while player.locked:
		await process_frame
	_find("journey.gd").warm_told = true   # рассказ о тепле не нужен в этом тесте

	# 1. Пачка: взял сигарету — в пачке и в «прогрессе» на одну меньше.
	_tap(KEY_T)
	while smoke.state != smoke.State.WAIT_STRIKE:
		await process_frame
	_check("пачка: взял сигарету — осталось 9, запомнено", smoke.left_in_pack == 9 and Progress.cigarettes == 9)
	while smoke.state != smoke.State.SMOKING:
		if smoke.state == smoke.State.WAIT_STRIKE:
			_tap(KEY_T)
		await _wait(0.45)

	# 4. Мост: у города — слышен город, к середине моста — только ветер.
	_place(Vector3(0, 0.5, -400), Vector3(0, 0, -3000))
	await _wait(6.0)
	var near_city := [_loop_db("traffic"), _loop_db("wind")]
	_place(Vector3(0, 0.5, -1700), Vector3(0, 0, -3000))
	await _wait(9.0)
	var mid := [_loop_db("traffic"), _loop_db("wind")]
	_check("мост: ветер перекрывает город", near_city[0] > mid[0] + 10.0 and mid[1] > near_city[1] + 3.0,
		"у города: машины %.0f дБ, ветер %.0f; середина: машины %.0f, ветер %.0f" % [near_city[0], near_city[1], mid[0], mid[1]])

	# 2. Припадок: звук мира пропадает, сердце и звон; за 13 с — обратно.
	seizure.trigger_now()
	await _wait(0.3)
	_check("припадок: мир без звука, сердце и звон", Settings.duck_db < -70.0 and seizure.heart.playing and seizure.ring.playing,
		"мир %.0f дБ" % Settings.duck_db)
	await _wait(6.5)
	_check("через 6–7 с мир возвращается", Settings.duck_db > -70.0 and Settings.duck_db < -3.0 and seizure.heart.volume_db < -3.0,
		"мир %.0f дБ, сердце %.0f дБ" % [Settings.duck_db, seizure.heart.volume_db])
	await _wait(7.0)
	_check("через 13 с — тишина в ушах, мир как был", Settings.duck_db > -0.5 and not seizure.heart.playing, "мир %.1f дБ" % Settings.duck_db)

	# 6. Окурок в бездну: у перил, лицом наружу, Q.
	_place(Vector3(12.6, 0.5, -1680), Vector3(100, 0, -1680))
	player.target_pitch = -0.35
	await _wait(1.0)
	var can_throw: bool = smoke.state == smoke.State.SMOKING or smoke.state == smoke.State.UNLIT
	_tap(KEY_Q)
	await _wait(0.4)
	var butt: RigidBody3D = smoke.butt
	await _shot("butt")
	await _wait(5.0)
	_check("Q — окурок летит в бездну", can_throw and is_instance_valid(butt) and butt.global_position.y < -30.0 and not smoke.cig.visible,
		"через 5 с: y=%.0f" % (butt.global_position.y if is_instance_valid(butt) else 0.0))

	# 5. Скамейка: подошёл — «Сесть - E», сел — время быстрее, туман гуще; E — встал.
	var bench := _find("bench_spot.gd")
	_place(bench.SPOT + Vector3(1.6, 0.5, 0), bench.SPOT)
	await _wait(1.0)
	var hint: Label = Game.hud.action_label
	_check("у скамейки — «Сесть - E»", hint.text == bench.HINT_SIT and hint.modulate.a > 0.8)
	await _shot("bench")
	_tap(KEY_E)
	await _wait(6.0)
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var to_abyss := rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(-1, 0)))
	_check("сел: время быстрее, туман гуще, смотрит в бездну", bench.sitting and player.locked and Engine.time_scale > 3.5 and Game.journey.fog_boost > 0.3 and absf(to_abyss) < 10.0,
		"время ×%.1f, туман %.2f, взгляд от бездны %.0f°" % [Engine.time_scale, Game.journey.fog_boost, to_abyss])
	await _shot("bench_sitting")
	_tap(KEY_E)
	await _wait(2.5)
	_check("E — встал, всё как было", not bench.sitting and not player.locked and is_equal_approx(Engine.time_scale, 1.0))

	# 7. Снимки: три кадра в разных местах.
	var before := DirAccess.get_files_at("user://photos").size() if DirAccess.dir_exists_absolute("user://photos") else 0
	var taken_before := Photos.taken.size()   # считаем только свои снимки (если в окно теста кто-то нажимал C)
	for spot in [[Vector3(0, 0.5, -1500), Vector3(0, 0, -3000)], [Vector3(-24, 0.5, -60), Vector3(-24, 0, -300)], [Vector3(0, 0.5, -170), Vector3(0, 0, -400)]]:
		_place(spot[0], spot[1])
		await _wait(1.0)
		_tap(KEY_C)
		await _wait(0.6)
	var after := DirAccess.get_files_at("user://photos").size()
	var mine := Photos.taken.size() - taken_before
	_check("C — снимки бодикамерой", mine == 3 and after == before + 3, "%d снимка, в папке +%d" % [mine, after - before])

	# 3. Голос рекламы: у билбордов в городе.
	var ads := _find("ad_voices.gd")
	_place(Vector3(-24, 0.5, -60), Vector3(-24, 0, -300))
	await _wait(0.5)
	var spoke: bool = ads.speak_nearest()
	await _wait(0.5)
	_check("реклама говорит фразой из пролога", spoke and DisplayServer.tts_is_speaking(), "голос: %s" % ("есть" if ads.voice != "" else "нет"))
	await _wait(3.0)
	DisplayServer.tts_stop()

	print("FEAT ИТОГ: прошло %d из %d" % [passed, passed + failed])
	quit()
