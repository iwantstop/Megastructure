extends SceneTree

## Конец моста и начало тропы: высоты пола сеткой (лучами сверху) и два кадра — сверху и с моста.
## Запуск (с окном): godot --path . -s tests/probes/bridge_end_view.gd

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
	player.flying = true
	player.global_position = Vector3(-20, 1, -2330)
	for k in 30:
		await process_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for z in range(-2335, -2415, -8):
		var row := "BE z=%d:" % z
		for x in range(-90, 50, 8):
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -200, z)))
			row += " %4d" % (int(round(hit.position.y)) if not hit.is_empty() else -999)
		print(row)
	for shot in [[Vector3(-20, 60, -2310), Vector3(-30, 0, -2370), "top"], [Vector3(0, 1.7, -2320), Vector3(-40, 3, -2370), "bridge"]]:
		player.global_position = shot[0] - Vector3.UP * 1.5
		var to: Vector3 = shot[1] - shot[0]
		player.rotation.y = atan2(-to.x, -to.z)
		player.target_yaw = player.rotation.y
		player.target_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		player.head.rotation.x = player.target_pitch
		for k in 40:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/bridge_end_%s.png" % shot[2])
	quit()
