extends SceneTree

## Билборды глазами: герой встаёт перед рекламными экранами (с лицевой стороны, в 18–30 м) и снимает кадр.
## Снимки — screenshots/ads_N.png. Запуск (с окном): godot --path . -s tests/probes/ads_view.gd [-- after]

var world: Node
var player: CharacterBody3D
var targets: Array = []


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
	player = get_first_node_in_group("player")
	while player.locked:
		await process_frame
	var structures_ads: Array = []
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("ad_voices.gd"):
			structures_ads = c.get_meta("ads", [])
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for ad in structures_ads:
		var xform: Transform3D = ad.xform
		var size: Vector2 = ad.size
		if xform.origin.y > 70.0 or targets.size() >= 4:
			continue
		var out: Vector3 = xform.basis.z.normalized()      # лицевая сторона экрана
		var dist := clampf(size.x * 1.6, 14.0, 30.0)
		var eye := xform.origin + out * dist
		eye.y = maxf(xform.origin.y - 6.0, 1.5)
		var free: bool = space.intersect_ray(PhysicsRayQueryParameters3D.create(xform.origin + out * 0.5, eye)).is_empty()
		if free:
			targets.append([xform.origin, eye])
	if "tower" in OS.get_cmdline_user_args():   # экраны самой высокой башни — с улицы перед ней
		targets.clear()
		for ad in structures_ads:
			var o: Vector3 = (ad.xform as Transform3D).origin
			if Vector2(o.x, o.z - 118.0).length() < 40.0:
				targets.append([o, Vector3(4, 20, 30) if o.y < 150.0 else Vector3(4, 120, -20)])
	var shot := 0
	var suffix := ("_tower" if "tower" in OS.get_cmdline_user_args() else "") + ("_after" if "after" in OS.get_cmdline_user_args() else "")
	for target in targets:
		player.flying = true
		player.global_position = target[1] - Vector3.UP * 1.5
		player.velocity = Vector3.ZERO
		var to: Vector3 = target[0] - target[1]
		player.rotation.y = atan2(-to.x, -to.z)
		player.target_yaw = player.rotation.y
		player.target_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		player.head.rotation.x = player.target_pitch
		for k in 40:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/ads_%d%s.png" % [shot, suffix])
		shot += 1
	print("ADS shots: ", shot)
	quit()
