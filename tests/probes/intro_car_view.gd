extends SceneTree

## Новое вступление глазами: падение → пробил крышу летающей машины → салон (сигнализация, спираль) →
## удар, тьма, текст → пробуждение рядом с горящей машиной → встал. Снимки — screenshots/intro_car_*.png.
## Запуск (с окном): godot --path . -s tests/probes/intro_car_view.gd

var world: Node
var intro: Node
var player: CharacterBody3D


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/intro_car_%s.png" % name)


func _space() -> void:
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = down
		Input.parse_input_event(key)


func _run() -> void:
	while intro == null:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				intro = c
		await process_frame
	player = get_first_node_in_group("player")
	var t0 := Time.get_ticks_msec()
	var shot_pre := false
	while intro.state == intro.State.FALLING:
		if not shot_pre and player.global_position.y < intro.car.IMPACT.y + 12.0:
			shot_pre = true
			_shot("prehit")   # за мгновение до удара: летит на крышу машины
		await process_frame
	print("ICV in car after %.1f s, car at %s" % [(Time.get_ticks_msec() - t0) / 1000.0, intro.car.global_position.snapped(Vector3.ONE)])
	var last := 0.0
	for k in [0.3, 1.5, 3.0, 4.2]:
		await create_timer(k - last).timeout
		last = k
		_shot("cabin_%.0f" % (k * 10))
		print("ICV cabin t=%.1f y=%.0f alarm=%s cam=%s" % [k, intro.car.global_position.y, intro.car.alarm.playing, intro.car.cam.current])
	while intro.state == intro.State.CAR:
		await process_frame
	print("ICV crashed: car at %s, %.1f m from hero" % [intro.car.global_position.snapped(Vector3.ONE), intro.car.global_position.distance_to(player.global_position)])
	while intro.state != intro.State.STORY:
		await process_frame
	await create_timer(2.5).timeout
	_space()
	while intro.state != intro.State.LYING:
		await process_frame
	await create_timer(4.5).timeout
	_shot("wake")
	while intro.state != intro.State.HINT:
		await process_frame
	await create_timer(1.0).timeout
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await create_timer(0.1).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = false
	Input.parse_input_event(key)
	while player.locked:
		await process_frame
	var to: Vector3 = intro.car.global_position - player.global_position
	player.target_yaw = atan2(-to.x, -to.z)
	player.target_pitch = -0.1
	await create_timer(1.5).timeout
	_shot("wreck")
	print("ICV done")
	quit()
