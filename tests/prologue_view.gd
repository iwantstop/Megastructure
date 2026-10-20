extends SceneTree

## Пролог как в настоящей игре (`-- --prologue`): на каждом абзаце ждём 6 с — текст не должен
## листаться сам, герой должен висеть на месте (падение не началось). Потом пробел. После пробела
## на последнем абзаце — герой падает. Снимки: название, первый абзац, последний.
## Запуск: godot --path . -s tests/prologue_view.gd -- --prologue

const WAIT := 6.0

var world: Node
var player: Node3D
var t := 0.0
var shots := {}
var step_since := 0.0
var last_index := -2
var start_y := 0.0
var ok := true
var finished_at := -1.0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _shot(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/prologue_%s.png" % name)


func _space() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	Input.parse_input_event(up)


func _process(delta: float) -> bool:
	t += delta
	if t > 0.8:
		_shot("title")
	if player == null:
		var found := world.find_children("*", "CharacterBody3D", true, false)
		if not found.is_empty():
			player = found[0]
			start_y = player.global_position.y
	var prologue := world.get_node_or_null("Prologue")
	if prologue == null:
		for child in world.get_children():
			if child.get_script() == preload("res://scripts/prologue.gd"):
				prologue = child
	if finished_at < 0.0 and (prologue == null or not prologue.playing) and last_index >= 0:
		finished_at = t
		print("PROLOGUE finished at t=%.1f, hero y=%.1f (start %.1f)" % [t, player.global_position.y, start_y])
	if finished_at >= 0.0:
		if t - finished_at > 5.0:
			var fell := start_y - player.global_position.y
			print("PROLOGUE after start: fell %.0f m in 5 s -> %s" % [fell, "FALLING" if fell > 20.0 else "NOT FALLING"])
			print("PROLOGUE RESULT: ", "OK" if ok and fell > 20.0 else "FAIL")
			return true
		return false
	if prologue == null or prologue.index < 0:
		return t > 120.0
	if prologue.index != last_index:
		last_index = prologue.index
		step_since = t
		print("PROLOGUE paragraph %d shown at t=%.1f" % [last_index + 1, t])
	if last_index == 0:
		_shot("p1")
	if last_index == prologue.PARAGRAPHS.size() - 1 and t - step_since > 3.0:
		_shot("last")
	if t - step_since > WAIT:
		var drift := absf(player.global_position.y - start_y)
		var still: bool = prologue.index == last_index and drift < 0.01
		print("PROLOGUE paragraph %d: %.0f s without space -> same paragraph=%s, hero moved %.2f m" % [last_index + 1, WAIT, prologue.index == last_index, drift])
		ok = ok and still
		step_since = t + 100.0  # нажать один раз
		_space()
	return t > 120.0
