extends AnimatableBody3D

## Открытая платформа-лифт в шахте башни доступа. Ездит вверх-вниз по всем уровням,
## на каждом стоит несколько секунд. Встань на неё — и она увезёт.

const SPEED := 5.0
const WAIT := 4.0

var stops: Array[float] = []
var index := 0
var step := 1
var gates: Array[Dictionary] = []  # по остановкам: {shape, light} или пусто
var closed_mat: Material
var open_mat: Material


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


## Створки шахты на уровнях (см. world._make_elevators).
func set_gates(p_gates: Array[Dictionary], closed: Material, open: Material) -> void:
	gates = p_gates
	closed_mat = closed
	open_mat = open


func _ready() -> void:
	sync_to_physics = true
	position.y = stops[index] - 0.15
	_wait_then_move()


## Стоим на остановке: створка этого уровня открыта, остальные закрыты.
func _wait_then_move() -> void:
	_set_gates(index)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_interval(WAIT)
	tween.tween_callback(_move_next)


func _set_gates(open_index: int) -> void:
	for i in gates.size():
		if gates[i].is_empty():
			continue
		var open := i == open_index
		gates[i].shape.set_deferred("disabled", open)
		gates[i].light.material_override = open_mat if open else closed_mat


## Едет к следующей остановке; на верхней и нижней разворачивается.
func _move_next() -> void:
	_set_gates(-1)
	if index + step < 0 or index + step >= stops.size():
		step = -step
	index += step
	var target := stops[index] - 0.15
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "position:y", target, absf(position.y - target) / SPEED) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_wait_then_move)
