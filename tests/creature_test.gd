extends SceneTree

## Существо на мосту: стоит у перил в «Idle» (анимация идёт), смотрит в бездну; герой идёт по мосту —
## подходит ближе 14 м, и оно исчезает. Снимки — screenshots/creature_*.png.
## Запуск (с окном): godot --path . -s tests/creature_test.gd

var world: Node
var creature: Node3D
var player: CharacterBody3D
var t := 0.0
var stage := 0
var shot_far := false
var bone_moved := 0.0
var first_pose := Transform3D()


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
				return false
			for c in world.get_children():
				if c.get_script() and str(c.get_script().resource_path).ends_with("creature.gd"):
					creature = c
				if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
					c.skip()
			player = get_first_node_in_group("player")
			stage = 1
		1:
			if player.locked:
				return false
			player.global_position = Vector3(0, 0.5, -1150)   # сразу после 1-го припадка
			player.rotation.y = 0.0
			player.target_yaw = 0.0
			var sk: Skeleton3D = creature.body.find_child("GeneralSkeleton", true, false)
			first_pose = sk.get_bone_global_pose(sk.find_bone("Head"))
			stage = 2
			t = 0.0
		2:
			var sk: Skeleton3D = creature.body.find_child("GeneralSkeleton", true, false) if not creature.gone else null
			if sk:
				bone_moved = maxf(bone_moved, sk.get_bone_global_pose(sk.find_bone("Head")).origin.distance_to(first_pose.origin))
			if t > 1.5 and not shot_far:
				shot_far = true
				player.target_pitch = -0.02
				root.get_viewport().get_texture().get_image().save_png("res://screenshots/creature_far.png")
				print("CREATURE seen at %.0f m, visible=%s, idle playing=%s, head moves %.3f m" % [
					player.global_position.distance_to(creature.global_position), creature.visible,
					creature.body.find_child("AnimationPlayer", true, false).current_animation, bone_moved])
				_key(KEY_W, true)
			if shot_far and not creature.gone and Vector2(player.global_position.x - creature.SPOT.x, player.global_position.z - creature.SPOT.z).length() < 25.0 and t > 3.0 and not has_meta("near_shot"):
				set_meta("near_shot", true)
				root.get_viewport().get_texture().get_image().save_png("res://screenshots/creature_near.png")
			if creature.gone:
				_key(KEY_W, false)
				print("CREATURE vanished when hero was %.1f m away (z=%.0f)" % [
					Vector2(player.global_position.x - creature.SPOT.x, player.global_position.z - creature.SPOT.z).length(), player.global_position.z])
				stage = 3
				t = 0.0
			if t > 30.0:
				print("CREATURE FAIL: never vanished")
				return true
		3:
			if t > 0.5:
				root.get_viewport().get_texture().get_image().save_png("res://screenshots/creature_gone.png")
				print("CREATURE after: visible=%s" % creature.visible)
				return true
	return false
