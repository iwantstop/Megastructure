extends SceneTree

## Вид со скамейки: герой садится, снимок того, что напротив, и что там за дом (лучи вдаль).
## Запуск (с окном): godot --path . -s tests/probes/bench_view.gd

var world: Node


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _run() -> void:
	var intro: Node = null
	while intro == null:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				intro = c
		await process_frame
	intro.skip()
	var player: CharacterBody3D = get_first_node_in_group("player")
	while player.locked:
		await process_frame
	var bench: Node = null
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("bench_spot.gd"):
			bench = c
	player.global_position = bench.SPOT + Vector3(1.5, 0.5, 0)
	for k in 20:
		await process_frame
	var show: Node3D = null
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("bench_show.gd"):
			show = c
	print("BV board at %s, %.0f m from bench" % [show.global_position.snapped(Vector3.ONE), show.global_position.distance_to(bench.SPOT)])
	bench.sit()
	await create_timer(1.6, true, false, true).timeout
	var to: Vector3 = show.global_position - player.camera.global_position
	player.target_yaw = atan2(-to.x, -to.z)
	player.target_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	await create_timer(2.0, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/bench_board_1.png")
	await create_timer(5.0, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/bench_board_2.png")
	while show.fall_state < 1:
		await process_frame
	await create_timer(1.0, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/bench_board_stand.png")
	while show.fall_state < 2:
		await process_frame
	await create_timer(0.9, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/bench_board_fall.png")
	player.target_pitch = deg_to_rad(32.0)   # вся башня: табло, крыша, шпиль
	await create_timer(1.5, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/bench_tower.png")
	print("BV fall: figure y=%.1f state=%d time_scale=%.1f" % [show.figure.global_position.y, show.fall_state, Engine.time_scale])
	quit()
