extends SceneTree

## Снимки новой горы: вход в пещеру, костёр (до и после E), квартира, смотровой уступ, прощание ангела.
## Запуск с окном: godot --path <проект> -s res://tests/mountain_view.gd

var world: Node
var player: CharacterBody3D
var features: Node
var presence: Node
var hud: Node
var fire: Node
var shots: Array = []
var index := -1
var frame := 0
var wait := 0
var said := ""


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _place(pos: Vector3, look_at: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.last_safe = pos
	var d := look_at - (pos + Vector3.UP * 1.5)
	var yaw := atan2(-d.x, -d.z)
	player.rotation.y = yaw
	player.target_yaw = yaw
	player.target_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	player.head.rotation.x = player.target_pitch


func _process(_d: float) -> bool:
	frame += 1
	if frame < 5:
		return false
	if player == null:
		player = get_first_node_in_group("player")
		features = get_first_node_in_group("mountain_features")
		presence = _find("presence.gd")
		hud = get_first_node_in_group("hud")
		fire = get_first_node_in_group("campfire")
		_find("intro.gd").skip()
		var cave: Transform3D = features.cave
		var p := func(x: float, y: float, depth: float) -> Vector3: return cave * Vector3(x, y, -depth)
		var ledge := Mountain.path_point(0.42).origin
		var fw: Transform3D = features.farewell_spot
		var fw_path := Mountain.path_point(Mountain.fraction_at_height(features.FAREWELL_HEIGHT) - 0.012).origin
		shots = [
			["cave_mouth", p.call(0.0, 0.3, -6.0), p.call(0.0, 3.0, 8.0), ""],
			["campfire_dark", p.call(1.5, 0.3, 4.5), fire.global_position, ""],
			["campfire_lit", p.call(1.5, 0.3, 4.5), fire.global_position, "light"],
			["apartment", p.call(1.5, 0.3, 15.5), p.call(-0.4, 0.8, 28.5), ""],
			["apartment_tv", p.call(-0.4, 0.3, 27.4), p.call(0.0, 0.9, 18.5), ""],
			["ledge", ledge + Vector3.UP * 0.3, ledge + (ledge - Mountain.CENTER) * Vector3(1, 0, 1) * 0.05 + Vector3.DOWN * 4.0, ""],
			["farewell", fw_path + Vector3.UP * 0.3, fw.origin + Vector3.UP * 1.3, "farewell"],
		]
		return false
	if player.locked and index < 0:
		return false
	if wait > 0:
		wait -= 1
		if hud.subtitle.modulate.a > 0.5 and hud.subtitle.text != said:
			said = hud.subtitle.text
			print("VIEW subtitle: \"", said, "\"")
		if wait == 0:
			var shot: Array = shots[index]
			root.get_viewport().get_texture().get_image().save_png("res://screenshots/mtn_%s.png" % shot[0])
			print("VIEW saved ", shot[0])
		return false
	index += 1
	if index >= shots.size():
		print("VIEW farewell_done=", presence.farewell_done, " fire_lit=", fire.lit)
		return true
	var shot: Array = shots[index]
	_place(shot[1], shot[2])
	wait = 60
	if shot[3] == "light":
		fire.light_up()
		wait = 200
	elif shot[3] == "farewell":
		wait = 900   # дождаться: заметил → обернулась → растворилась
	return false
