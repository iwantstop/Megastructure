extends SceneTree

## Все припадки подряд, как в настоящей игре: без телепортов теста — герой идёт пешком от начала моста
## до вершины (мост → подножие → пещера → вспышка → прощание → вершина). Печатает каждый припадок:
## где сработал, куда перенёс; и где герой застрял, если застрял.
## Запуск (с окном): godot --path . -s tests/mountain_walk_test.gd [-- mountain]   (mountain — сразу с конца моста;
## pit — проверка: застрял на склоне под краем площадки — через 2 с возвращает наверх)

const START := Vector3(0, 0.5, -380)
const LIMIT := 600.0

var world: Node
var player: CharacterBody3D
var seizure: Node
var flashback: Node
var hud: Node
var t := 0.0
var last_log := 0.0
var fits := 0
var was_active := -2
var fit_from := Vector3.ZERO
var stuck_at := Vector3.ZERO
var stuck_time := 0.0
var was_falling := false
var in_cave := false


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _find(script_name: String) -> Node:
	for c in world.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _run() -> void:
	var intro: Node = null
	while intro == null:
		intro = _find("intro.gd")
		await process_frame
	intro.skip()
	player = get_first_node_in_group("player")
	hud = get_first_node_in_group("hud")
	seizure = _find("seizure.gd")
	flashback = _find("flashback.gd")
	while player.locked:
		await process_frame
	if "mountain" in OS.get_cmdline_user_args():   # сразу с конца моста (мостовые припадки уже позади)
		seizure.next_stop = 3
		player.global_position = Vector3(0, 0.5, -2340)
	else:
		player.global_position = START
	player.velocity = Vector3.ZERO
	player.target_yaw = 0.0
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	set_meta("running", true)


func _aim() -> Vector3:
	var p := player.global_position
	if p.z > -2366.0 and absf(p.x) < 20.0 and p.y < 5.0:
		return Vector3(0, 0, -2372.0)   # по мосту — к началу тропы
	# После глитча к пещере — внутрь, в глубину (как игрок, который её исследует), и обратно на тропу.
	if fits >= 4 and not flashback.done and not flashback.falling:
		if -Mountain.cave_local(p).z > flashback.DEEP_INSIDE + 2.0:
			in_cave = true
		return Mountain.cave_frame() * Vector3(0, 0, 6.0 if in_cave else -40.0)
	var f := Mountain.fraction_at_height(p.y)
	return Mountain.path_point(minf(f + 0.006, 1.0)).origin


func _process(delta: float) -> bool:
	if not has_meta("running"):
		return false
	t += delta
	var p := player.global_position
	if not player.locked:
		var to := _aim() - p
		player.target_yaw = atan2(-to.x, -to.z)
	# Припадки.
	if seizure.active != was_active:
		if seizure.active != -2:
			fit_from = p
		else:
			fits += 1
			print("WALK fit #%d (stop %d) at t=%.0f: %s -> %s  y=%.0f" % [fits, was_active, t, fit_from.snapped(Vector3.ONE), p.snapped(Vector3.ONE), p.y])
		was_active = seizure.active
	# Вспышка-падение после пещеры.
	if flashback and flashback.falling != was_falling:
		was_falling = flashback.falling
		print("WALK flashback falling=%s at t=%.0f pos=%s" % [was_falling, t, p.snapped(Vector3.ONE)])
	# Застрял?
	if p.distance_to(stuck_at) > 1.5:
		stuck_at = p
		stuck_time = 0.0
	elif not player.locked:
		stuck_time += delta
		if stuck_time > 6.0:
			stuck_time = -30.0
			print("WALK stuck at t=%.0f pos=%s y=%.0f next_stop=%d held=%s narr=%.2f" % [t, p.snapped(Vector3.ONE), p.y, seizure.next_stop, seizure.held, hud.narration.modulate.a])
	if t - last_log > 10.0:
		last_log = t
		print("WALK t=%.0f pos=%s y=%.0f next_stop=%d held=%s locked=%s narr=%.2f" % [t, p.snapped(Vector3.ONE), p.y, seizure.next_stop, seizure.held, player.locked, hud.narration.modulate.a])
	if "pit" in OS.get_cmdline_user_args() and t > 0.5:   # стоит на склоне под краем площадки — должен вернуться
		if not has_meta("pit"):
			set_meta("pit", true)
			_key(KEY_W, false)
			_key(KEY_SHIFT, false)
			player.global_position = Vector3(-60, -38, -2343)
			player.velocity = Vector3.ZERO
			t = 0.5
		elif t > 5.0:
			print("WALK pit: pos=%s back on top=%s" % [p.snapped(Vector3.ONE), p.y > -1.0])
			return true
		return false
	if p.y > Mountain.PEAK - 15.0 or t > LIMIT:
		print("WALK end at t=%.0f y=%.0f fits=%d next_stop=%d" % [t, p.y, fits, seizure.next_stop])
		return true
	return false
