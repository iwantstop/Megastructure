extends SceneTree

## Регулятор бодикамеры в админ-панели: снимки при 0%, 100% и 200%, значения параметров шейдера,
## и покачивание при ходьбе 0% — камера не качается.
## Запуск (с окном): godot --path . -s tests/bodycam_slider_test.gd

var world: Node
var admin: Node
var player: CharacterBody3D
var t := 0.0
var found := false
var max_roll := 0.0
var step := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(delta: float) -> bool:
	t += delta
	if t < 1.0:
		return false
	if not found:
		found = true
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("admin.gd"):
				admin = c
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				c.skip()
		player = get_first_node_in_group("player")
		return false
	var levels := [0.0, 100.0, 200.0]
	if step < levels.size() and t > 7.0 + step * 1.5:
		admin._on_bodycam_strength(levels[step])
		var mat: ShaderMaterial = admin.bodycam.get_child(0).material
		RenderingServer.force_draw()
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/bodycam_%d.png" % int(levels[step]))
		print("BODYCAM %d%%: distortion=%.3f aberration=%.4f vignette=%.2f grain=%.3f" % [levels[step],
			mat.get_shader_parameter("distortion"), mat.get_shader_parameter("aberration"),
			mat.get_shader_parameter("vignette"), mat.get_shader_parameter("grain")])
		step += 1
	if step == 3 and t > 12.0:
		player.bob_scale = 0.0
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		step = 4
	if step == 4 and t > 14.0:
		print("BODYCAM bob 0%%: walking speed=%.1f, camera offset=%.4f" % [player.velocity.length(), player.camera.position.length()])
		step = 5
	# Крен при повороте: быстрый поворот мышью, наибольший крен при 0%, 100% и 300%.
	if step >= 5 and step <= 7:
		var scales := [0.0, 1.0, 3.0]
		var phase := t - 14.0 - (step - 5) * 1.5
		player.turn_roll_scale = scales[step - 5]
		if phase < 0.6:
			player.target_yaw += 3.0 * delta
			max_roll = maxf(max_roll, absf(player.tilt))
		elif phase > 1.5:
			print("BODYCAM turn roll %d%%: max roll=%.2f deg" % [int(scales[step - 5] * 100), rad_to_deg(max_roll)])
			max_roll = 0.0
			step += 1
	if step == 8:
		return true
	return false
