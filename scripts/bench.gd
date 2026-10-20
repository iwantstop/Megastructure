extends Node

## Бенчмарк: запуск с `-- --bench`. Ставит камеру в несколько типичных точек, в каждой
## 4 секунды меряет FPS, вызовы отрисовки, треугольники и объекты, печатает в лог и выходит.

const SPOTS := [
	{"name": "старт у башни", "pos": Vector3(4, 0.3, 86), "yaw": 0.0, "pitch": 0.1},
	{"name": "улица в городе", "pos": Vector3(72, 0.3, -100), "yaw": 0.0, "pitch": 0.05},
	{"name": "площадка 75 м", "pos": Vector3(72, 75.5, -72), "yaw": 0.7, "pitch": -0.2},
	{"name": "мост к горе", "pos": Vector3(0, 0.3, -1300), "yaw": PI, "pitch": 0.1},
	{"name": "тропа над облаками", "pos": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "path": 0.85},
]
const SETTLE := 1.5
const MEASURE := 4.0

var player: CharacterBody3D
var intro: Node
var index := -1
var t := 0.0
var frames := 0
var draw_calls := 0.0
var primitives := 0.0
var objects := 0.0


func setup(p_player: CharacterBody3D, p_intro: Node) -> void:
	player = p_player
	intro = p_intro


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	intro.skip()
	_next()


func _process(delta: float) -> void:
	t += delta
	_hold()
	if t < SETTLE:
		return
	frames += 1
	draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if t >= SETTLE + MEASURE:
		print("[bench] %-20s fps=%5.1f  draw_calls=%6d  triangles=%8d  objects=%5d" % [
			SPOTS[index].name, frames / MEASURE, int(draw_calls / frames), int(primitives / frames), int(objects / frames)])
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://screenshots/bench_%d.png" % index))
		_next()


func _next() -> void:
	index += 1
	if index >= SPOTS.size():
		print("[bench] video memory: %d MB" % int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
		get_tree().quit()
		return
	t = 0.0
	frames = 0
	draw_calls = 0.0
	primitives = 0.0
	objects = 0.0


## Держит героя в точке замера, не давая ему упасть или уйти.
func _hold() -> void:
	var spot: Dictionary = SPOTS[index]
	var pos: Vector3 = spot.pos
	var yaw: float = spot.yaw
	if spot.has("path"):
		var xform: Transform3D = Mountain.path_point(spot.path)
		pos = xform.origin + Vector3.UP * 0.5
		var forward := -xform.basis.z
		yaw = atan2(-forward.x, -forward.z)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.locked = true
	player.target_yaw = yaw
	player.target_pitch = spot.pitch
