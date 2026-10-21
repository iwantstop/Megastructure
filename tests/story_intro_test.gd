extends SceneTree

## Вступление с рассказом: паника в падении (обзор, рывки), текст во тьме ждёт пробел,
## после пробела взгляд — на гору и чуть выше вершины, W — подняться, после подсказок — рассказ
## о вере в ангела и новое задание «Я должен найти его». Снимки — в screenshots/story_*.png.
## Запуск (с окном): godot --path . -s tests/story_intro_test.gd

var world: Node
var intro: Node
var hud: Node
var player: CharacterBody3D
var t := 0.0
var stage := 0
var stage_t := 0.0
var max_fov := 0.0
var max_look := 0.0
var shots := {}
var narr_seen := -1.0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _shot(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/story_%s.png" % name)


func _key(code: Key, physical: bool) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		if physical:
			ev.physical_keycode = code
		else:
			ev.keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	t += delta
	stage_t += delta
	if intro == null:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				intro = c
		player = get_first_node_in_group("player")
		hud = get_first_node_in_group("hud")
		return false
	var state: String = intro.State.keys()[intro.state]
	match stage:
		0:  # падение
			max_fov = maxf(max_fov, player.camera.fov)
			max_look = maxf(max_look, player.panic_look.length())
			if t > 3.0:
				_shot("fall")
			if state == "STORY" or state == "BLACKOUT":
				print("STORY fall: max fov=%.0f, max head jerk=%.0f deg" % [max_fov, rad_to_deg(max_look)])
				stage = 1
				stage_t = 0.0
		1:  # во тьме: 8 с без пробела — должен остаться текст
			if stage_t > 6.0:
				_shot("dark_text")
			if stage_t > 8.0:
				print("STORY dark: state after 8 s without space=%s, text alpha=%.2f, fade=%.2f" % [state, intro.story.modulate.a, intro.fade.color.a])
				_key(KEY_SPACE, false)
				stage = 2
				stage_t = 0.0
		2:  # тьма спала
			if state == "LYING" and stage_t > 5.0:
				_shot("wake")
				var forward: Vector3 = -player.camera.global_transform.basis.z
				var to_peak: Vector3 = Mountain.CENTER + Vector3.UP * Mountain.PEAK - player.camera.global_position
				var yaw_err := rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(to_peak.x, to_peak.z)))
				var elev := rad_to_deg(atan2(forward.y, Vector2(forward.x, forward.z).length()))
				var peak_elev := rad_to_deg(atan2(to_peak.y, Vector2(to_peak.x, to_peak.z).length()))
				print("STORY wake: fade=%.2f, look vs mountain yaw error=%.1f deg, look elevation=%.1f deg (peak at %.1f deg)" % [intro.fade.color.a, yaw_err, elev, peak_elev])
				stage = 3
		3:
			if state == "HINT":
				_key(KEY_W, true)
				stage = 4
				stage_t = 0.0
		4:  # встал — ждём рассказ
			if stage_t > 4.6 and stage_t - delta <= 4.6:
				var forward: Vector3 = -player.camera.global_transform.basis.z
				print("STORY stood: look elevation=%.1f deg" % rad_to_deg(atan2(forward.y, Vector2(forward.x, forward.z).length())))
			if hud.narration.modulate.a > 0.99 and narr_seen < 0.0:
				narr_seen = stage_t
				_shot("angel_story")
				print("STORY narration at %.1f s after W: \"%s...\"  task=\"%s\"" % [stage_t, hud.narration.text.substr(0, 40), hud.task.get_child(0).text])
			if narr_seen > 0.0 and hud.narration.modulate.a < 0.01 and hud.task.modulate.a > 0.99 and hud.task.get_child(0).text == hud.TASK_FIND:
				_shot("new_task")
				print("STORY after narration (%.1f s on screen): task=\"%s\" visible" % [stage_t - narr_seen, hud.task.get_child(0).text])
				return true
			if stage_t > 60.0:
				print("STORY FAIL: no narration/task, narration alpha=%.2f" % hud.narration.modulate.a)
				return true
	return t > 150.0
