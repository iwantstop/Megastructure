extends SceneTree

## Видео падения во вступлении (Movie Maker): 10 с от начала игры, без пролога.
## Запуск: godot --path . --write-movie <файл.avi> --fixed-fps 30 -s tests/fall_clip.gd

var world: Node
var frames := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(_delta: float) -> bool:
	frames += 1
	return frames > 30 * 11
