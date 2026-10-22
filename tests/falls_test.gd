extends SceneTree

## Люди с крыш: на улице, по взгляду — силуэт на краю крыши, стоит, шагает, падает. Снимки — screenshots/falls_*.png.
## Запуск (с окном): godot --path . -s tests/falls_test.gd

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


func _run() -> void:
	while _find("intro.gd") == null:
		await process_frame
	_find("intro.gd").skip()
	var player: CharacterBody3D = get_first_node_in_group("player")
	while player.locked:
		await process_frame
	var falls := _find("falls.gd")
	var stood := false
	var fell := false
	var views := []
	for spot in [Vector3(-24, 0.5, -60), Vector3(24, 0.5, -200), Vector3(0, 0.5, -100), Vector3(-72, 0.5, -150), Vector3(72, 0.5, -20)]:
		for yaw in [0.0, PI / 2.0, PI, -PI / 2.0]:
			views.append([spot, yaw])
	for view in views:
		player.global_position = view[0]
		player.rotation.y = view[1]
		player.target_yaw = view[1]
		player.target_pitch = 0.25
		await create_timer(0.5).timeout
		falls.timer = 0.0
		await create_timer(0.3).timeout
		if falls.state == falls.State.STANDING:
			stood = true
			var d: float = falls.figure.global_position.distance_to(player.global_position)
			await create_timer(0.4).timeout
			var cam := root.get_viewport().get_camera_3d()
			var head: Vector3 = falls.figure.global_position + Vector3.UP * 1.0
			var px := cam.unproject_position(head)
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("res://screenshots/falls_standing.png")
			var crop := img.get_region(Rect2i(clampi(int(px.x) - 200, 0, img.get_width() - 400), clampi(int(px.y) - 150, 0, img.get_height() - 300), 400, 300))
			crop.resize(800, 600, Image.INTERPOLATE_NEAREST)
			crop.save_png("res://screenshots/falls_standing_zoom.png")
			var ray := PhysicsRayQueryParameters3D.create(cam.global_position, head)
			ray.exclude = [player.get_rid()]
			var blocker := root.get_world_3d().direct_space_state.intersect_ray(ray)
			print("FALLS ray camera->head: %s; camera at %s" % [("hit %s at %s" % [blocker.collider, (blocker.position as Vector3).round()]) if not blocker.is_empty() else "clear", cam.global_position.round()])
			print("FALLS standing on roof edge: %.0f m away, %.0f m high, on screen at %s (in view: %s)" % [d, falls.figure.global_position.y, px.round(), cam.is_position_in_frustum(head)])
			# Нацелиться прямо на фигуру с того же места и снять.
			var aim: Vector3 = falls.figure.global_position + Vector3.UP * 1.0 - cam.global_position
			player.target_yaw = atan2(-aim.x, -aim.z)
			player.rotation.y = player.target_yaw
			player.target_pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
			player.head.rotation.x = player.target_pitch
			falls.timer = 100.0
			await create_timer(0.3).timeout
			var aimed := root.get_viewport().get_texture().get_image()
			var mid := aimed.get_region(Rect2i(600, 300, 400, 300))
			mid.resize(800, 600, Image.INTERPOLATE_NEAREST)
			mid.save_png("res://screenshots/falls_aimed_zoom.png")
			# Отладка: подлететь к фигуре и снять вблизи.
			var fig: Node3D = falls.figure
			var meshes: Array = fig.find_children("*", "MeshInstance3D", true, false)
			print("FALLS debug: visible=%s meshes=%d first_mesh_visible=%s pos=%s" % [fig.is_visible_in_tree(), meshes.size(), meshes[0].is_visible_in_tree() if meshes.size() > 0 else false, fig.global_position.round()])
			falls.timer = 100.0
			player.flying = true
			var back: Vector3 = (player.global_position - fig.global_position)
			back.y = 0
			player.global_position = fig.global_position + back.normalized() * 8.0 + Vector3.UP * 0.2
			var look := fig.global_position + Vector3.UP * 1.0 - (player.global_position + Vector3.UP * 1.5)
			player.rotation.y = atan2(-look.x, -look.z)
			player.target_yaw = player.rotation.y
			player.target_pitch = 0.0
			player.head.rotation.x = 0.0
			await create_timer(0.6).timeout
			root.get_viewport().get_texture().get_image().save_png("res://screenshots/falls_close.png")
			falls.timer = 0.0
			player.flying = false
			while falls.state != falls.State.FALLING:
				await process_frame
			await create_timer(0.9).timeout
			root.get_viewport().get_texture().get_image().save_png("res://screenshots/falls_falling.png")
			var top: float = falls.figure.global_position.y
			while falls.state == falls.State.FALLING:
				await process_frame
			fell = true
			print("FALLS fell and vanished at the ground, next in %.0f s (fell from ~%.0f m)" % [falls.timer, top])
			break
	print("FALLS RESULT: stood=%s fell=%s" % [stood, fell])
	quit()
