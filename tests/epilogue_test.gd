extends SceneTree

## Финал до конца: колени, «Это...Всё...Я», вспышки ангела, затемнение, заключительные слайды по пробелу.
## На каждом слайде ждём 4 с (сам не листается), потом пробел. Снимки — screenshots/epilogue_*.png.
## Запуск (с окном): godot --path . -s tests/epilogue_test.gd

var world: Node
var finale: Node
var player: CharacterBody3D
var t := 0.0
var stage := 0
var shown_at := -1.0
var last_slide := -1
var end_printed := false


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _space() -> void:
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = down
		Input.parse_input_event(key)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
				return false
			for c in world.get_children():
				if c.get_script() and str(c.get_script().resource_path).ends_with("finale.gd"):
					finale = c
				if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
					c.skip()
			player = get_first_node_in_group("player")
			stage = 1
		1:
			if player.locked:
				return false
			for c in world.get_children():   # рассказ о тепле герой уже слышал на мосту
				if c.get_script() and str(c.get_script().resource_path).ends_with("journey.gd"):
					c.warm_told = true
			# Шесть снимков для слайдов: последние настоящие снимки из user://photos (если есть), иначе кадр игры.
			var files := DirAccess.get_files_at("user://photos") if DirAccess.dir_exists_absolute("user://photos") else PackedStringArray()
			for k in range(files.size() - 1, maxi(files.size() - 7, -1), -1):
				Photos.taken.append(Image.load_from_file("user://photos/" + files[k]))
			while Photos.taken.size() < 6:
				var frame := root.get_viewport().get_texture().get_image()
				frame.resize(960, 540)
				Photos.taken.append(frame)
			player.global_position = Mountain.CENTER + Vector3(0, Mountain.PEAK + 0.5, 0)
			player.velocity = Vector3.ZERO
			finale.start()
			stage = 2
			t = 0.0
		2:
			if finale.slide != last_slide and finale.slide_ready:
				last_slide = finale.slide
				shown_at = t
				print("EPILOGUE slide %d at t=%.1f: \"%s\"" % [finale.slide + 1, t, finale.slide_text.text])
				root.get_viewport().get_texture().get_image().save_png("res://screenshots/epilogue_%d.png" % (finale.slide + 1))
			if shown_at > 0.0 and t - shown_at > 3.8 and not has_meta("shot%d" % finale.slide):
				set_meta("shot%d" % finale.slide, true)   # снимки уже всплыли
				root.get_viewport().get_texture().get_image().save_png("res://screenshots/epilogue_%d.png" % (finale.slide + 1))
			if shown_at > 0.0 and t - shown_at > 4.0:
				print("EPILOGUE slide %d after 4 s without space: still=%s" % [finale.slide + 1, finale.slide == last_slide])
				shown_at = -1.0
				_space()
			if finale.slide >= finale.EPILOGUE.size():
				stage = 3
				t = 0.0
		3:
			if t > 1.0 and not end_printed:
				end_printed = true
				print("EPILOGUE end: text alpha=%.2f, screen black=%s" % [finale.slide_text.modulate.a, finale.veil.color.a > 0.99])
			if t > 9.0:
				root.get_viewport().get_texture().get_image().save_png("res://screenshots/epilogue_roof.png")
				print("EPILOGUE roof: pos=%s on_floor=%s locked=%s veil=%.2f" % [player.global_position.snapped(Vector3.ONE * 0.1), player.is_on_floor(), player.locked, finale.veil.color.a])
				return true
	return t > 120.0
