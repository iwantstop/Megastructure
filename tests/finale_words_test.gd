extends SceneTree

## Финал: «Это...» → «Это...Всё...» → «Это...Всё...Я» в одном субтитре.
## Запуск: godot --headless --path <проект> -s res://tests/finale_words_test.gd

var world: Node
var hud: Node
var started := false
var t := 0.0
var last := ""


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(delta: float) -> bool:
	t += delta
	if not started:
		if t < 0.5:
			return false
		hud = get_first_node_in_group("hud")
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("finale.gd"):
				c.start()
		started = true
		t = 0.0
		return false
	var label: Label = hud.subtitle
	var shown := label.text if label.visible_characters < 0 else label.text.substr(0, label.visible_characters)
	if label.modulate.a > 0.01 and shown != last:
		last = shown
		print("WORDS t=%.1f \"%s\"" % [t, shown])
	return t > 16.0
