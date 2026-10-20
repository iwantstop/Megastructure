extends SceneTree

## Пролог глазами: запускает игру как обычно (без -s нельзя — поэтому сцена мира создаётся вручную
## с флагом), снимает экран на названии, на первом абзаце, на последнем и сразу после пролога.

var world: Node
var prologue: Node
var t := 0.0
var shots := {}


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	world.set_script(world.get_script())
	root.add_child(world)
	prologue = preload("res://scripts/prologue.gd").new()
	root.add_child(prologue)
	prologue.title_shown.connect(func() -> void: prologue.play_text())


func _process(delta: float) -> bool:
	t += delta
	for moment in [0.8, 4.0, 12.0]:
		if t > moment and not shots.has(moment):
			shots[moment] = true
			root.get_viewport().get_texture().get_image().save_png("res://screenshots/prologue_%d.png" % int(moment * 10))
			print("PROLOGUE shot at ", moment, " index=", prologue.index)
	if int(t * 2) != int((t - delta) * 2):
		print("PROLOGUE t=%.1f index=%d shown=%.1f hold=%.1f" % [t, prologue.index, prologue.shown_for, prologue.hold])
	if t > 13.0:
		return true
	return false
