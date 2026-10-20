extends SceneTree

## Сюжетные моменты горы: глитч у подножия → у пещеры; выход из пещеры → падение с небоскрёба 2 с →
## тропа у места прощания; финал: ангел перед героем + взрыв солнца (кадры в screenshots/).
## Запуск с окном: godot --path <проект> -s res://tests/story_test.gd

var world: Node
var player: CharacterBody3D
var seizure: Node
var flashback: Node
var finale: Node
var stage := 0
var t := 0.0
var frame := 0
var fall_seen := false


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _put(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.last_safe = pos


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/story_%s.png" % name)
	print("STORY shot ", name)


func _process(delta: float) -> bool:
	frame += 1
	t += delta
	match stage:
		0:
			if frame < 5:
				return false
			player = get_first_node_in_group("player")
			seizure = _find("seizure.gd")
			flashback = _find("flashback.gd")
			finale = _find("finale.gd")
			_find("intro.gd").skip()
			stage = 1
		1:
			if player.locked:
				return false
			seizure.next_stop = 3   # мостовые уже позади
			var start := Mountain.path_point(0.0).origin
			_put(start + Vector3.UP * 0.3)
			stage = 2
			t = 0.0
		2:
			# Идём вверх по тропе к точке глитча.
			var target := Mountain.path_point(0.012).origin
			var d := target - player.global_position
			player.global_position += Vector3(d.x, 0, d.z).normalized() * 6.0 * delta
			player.global_position.y = target.y + 0.3
			if seizure.active != -2:
				print("STORY foot glitch started at fraction 0.012")
				stage = 3
				t = 0.0
			elif t > 20.0:
				print("STORY FAIL foot glitch")
				return true
		3:
			if seizure.active == -2:
				var cave_d := player.global_position.distance_to(Mountain.cave_frame().origin)
				print("STORY after glitch: %.0f m from cave mouth, y=%.0f" % [cave_d, player.global_position.y])
				# В пещеру поглубже, потом наружу.
				var cave := Mountain.cave_frame()
				_put(cave * Vector3(0, 0.3, -12.0))
				stage = 4
				t = 0.0
		4:
			if t > 0.5:
				var cave := Mountain.cave_frame()
				_put(cave * Vector3(0, 0.3, 4.0))
				stage = 5
				t = 0.0
		5:
			if flashback.falling and not fall_seen:
				fall_seen = true
				print("STORY flashback: falling at y=%.0f near tower" % player.global_position.y)
			if fall_seen and t > 1.0 and t < 1.1:
				_shot("fall")
			if flashback.done:
				var fw: Transform3D = get_first_node_in_group("mountain_features").farewell_spot
				print("STORY after flashback: %.0f m from farewell ledge, y=%.0f, locked=%s" % [player.global_position.distance_to(fw.origin), player.global_position.y, player.locked])
				_put(Mountain.CENTER + Vector3(0, Mountain.PEAK + 0.5, 0))
				player.rotation.y = 0.0
				player.target_yaw = 0.0
				stage = 6
				t = 0.0
			elif t > 12.0:
				print("STORY FAIL flashback (falling=%s)" % flashback.falling)
				return true
		6:
			if t > 1.0:
				finale.start()
				stage = 7
				t = 0.0
		7:
			# realize — через 1+3+1.5 = 5.5 с; «Я» — ещё через 3.2 с.
			if t > 7.0 and t - delta <= 7.0:
				_shot("angel")
			if t > 8.95 and t - delta <= 8.95:
				_shot("explosion")
			if t > 10.2 and t - delta <= 10.2:
				_shot("after")
			if t > 11.7 and t - delta <= 11.7:
				_shot("after2")
				return true
	return false
