extends AnimatableBody3D

## Открытая платформа-лифт в шахте башни доступа. Ездит вверх-вниз по всем уровням,
## на каждом стоит несколько секунд. Встань на неё — и она увезёт.

const SPEED := 5.0
const WAIT := 4.0

var stops: Array[float] = []
var index := 0
var step := 1


func setup(p_stops: Array[float], start_index: int, mat: Material, light: Material) -> void:
	stops = p_stops
	index = start_index
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.2, 0.3, 3.2)
	var deck := MeshInstance3D.new()
	deck.mesh = mesh
	deck.material_override = mat
	add_child(deck)
	var strip := BoxMesh.new()
	strip.size = Vector3(3.22, 0.06, 3.22)
	var edge := MeshInstance3D.new()
	edge.mesh = strip
	edge.material_override = light
	edge.position.y = -0.17
	add_child(edge)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


func _ready() -> void:
	sync_to_physics = true
	position.y = stops[index] - 0.15
	_wait_then_move()


func _wait_then_move() -> void:
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_interval(WAIT)
	tween.tween_callback(_move_next)


## Едет к следующей остановке; на верхней и нижней разворачивается.
func _move_next() -> void:
	if index + step < 0 or index + step >= stops.size():
		step = -step
	index += step
	var target := stops[index] - 0.15
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "position:y", target, absf(position.y - target) / SPEED) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_wait_then_move)
