extends SceneTree

## Пролог: абзацы проматываются ускоренно, на последнем ждём 10 с — игра не должна начаться сама;
## потом пробел — пролог заканчивается. Снимки: название, первый абзац, последний с подсказкой.

var world: Node
var prologue: Node
var t := 0.0
var shots := {}
var done := false
var last_since := -1.0
var space_at := -1.0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	prologue = preload("res://scripts/prologue.gd").new()
	root.add_child(prologue)
	prologue.title_shown.connect(func() -> void: prologue.play_text())
	prologue.finished.connect(func() -> void:
		done = true
		print("PROLOGUE finished at t=%.1f (space at %.1f)" % [t, space_at]))


func _shot(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/prologue_%s.png" % name)


func _process(delta: float) -> bool:
	t += delta
	if not is_instance_valid(prologue):
		print("PROLOGUE result: waited without space, finished after space=", done)
		return true
	if t > 0.8:
		_shot("title")
	var last: int = prologue.PARAGRAPHS.size() - 1
	if prologue.index == 0 and prologue.shown_for > 1.0:
		_shot("p1")
	# Промотка: абзацы до последнего — сразу дальше.
	if prologue.index >= 0 and prologue.index < last and prologue.shown_for > 1.2:
		prologue.shown_for = prologue.hold
	if prologue.index == last:
		if last_since < 0.0:
			last_since = t
		if t - last_since > 4.0:
			_shot("last")
		if t - last_since > 10.0 and space_at < 0.0:
			print("PROLOGUE on last paragraph 10 s, finished=", done)
			space_at = t
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.pressed = true
			Input.parse_input_event(key)
	return t > 60.0
