extends RefCounted

## Чужие вещи: маленькие домашние предметы посреди бесконечного бетона.
## Многое здесь — на двоих.

var rng: RandomNumberGenerator
var wood: StandardMaterial3D
var fabric: StandardMaterial3D
var linen: StandardMaterial3D
var ceramic: StandardMaterial3D
var metal: StandardMaterial3D
var clay: StandardMaterial3D
var leaf: StandardMaterial3D
var glow: StandardMaterial3D


func _init(random: RandomNumberGenerator) -> void:
	rng = random
	wood = Shapes.mat(Color(0.36, 0.25, 0.17), 0.7)
	fabric = Shapes.mat(Color(0.42, 0.38, 0.36), 1.0)
	linen = Shapes.mat(Color(0.82, 0.8, 0.76), 0.9)
	ceramic = Shapes.mat(Color(0.9, 0.9, 0.88), 0.3)
	metal = Shapes.mat(Color(0.2, 0.2, 0.22), 0.5)
	metal.metallic = 0.7
	clay = Shapes.mat(Color(0.55, 0.32, 0.22), 0.9)
	leaf = Shapes.mat(Color(0.22, 0.34, 0.2), 0.8)
	glow = Shapes.mat(Color(1.0, 0.9, 0.75), 1.0)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.78, 0.5)
	glow.emission_energy_multiplier = 3.0


## Расставляет все вещи по миру. Возвращает их — «сон» иногда их переставляет.
func place_all(parent: Node3D, structures: RefCounted) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	# Первая встреча — прямо посреди колоннады.
	placed.append(_put(parent, _table_for_two(), Vector3(0, 0.05, -170), 0.3))
	var makers := [_floor_lamp, _chair_alone, _bed, _bench_for_two, _door, _plant, _table_for_two, _floor_lamp, _bed]
	# Остальное — на галереях, хабах и на мосту к горе: мир висит над бездной, ставить можно только туда.
	var spots: Array[Vector3] = structures.walk_spots.duplicate()
	for maker in makers:
		if spots.is_empty():
			break
		var p: Vector3 = spots.pop_at(rng.randi() % spots.size())
		placed.append(_put(parent, maker.call(), p, rng.randf() * TAU))

	# Вещи внутри домов — будто хозяева только что вышли.
	var indoor := [_table_for_two, _bed, _chair_alone, _floor_lamp, _plant, _bed, _table_for_two, _chair_alone]
	var rooms: Array[Transform3D] = structures.interior_spots
	for i in mini(indoor.size(), rooms.size()):
		var node: Node3D = indoor[i].call()
		node.transform = rooms[i]
		parent.add_child(node)
		placed.append(node)
	return placed


func _put(parent: Node3D, node: Node3D, pos: Vector3, yaw: float) -> Node3D:
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)
	return node


# --- Наборы вещей ------------------------------------------------------------

func _table_for_two() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(1.0, 0.04, 0.7), Vector3(0, 0.74, 0), wood)
	for lx in [-0.45, 0.45]:
		for lz in [-0.3, 0.3]:
			_cyl(root, 0.02, 0.02, 0.72, Vector3(lx, 0.36, lz), wood)
	_chair(root, Vector3(0, 0, 0.65), 0.0)
	_chair(root, Vector3(0, 0, -0.65), PI)
	_cyl(root, 0.04, 0.035, 0.09, Vector3(0.1, 0.805, 0.18), ceramic)
	_cyl(root, 0.04, 0.035, 0.09, Vector3(-0.12, 0.805, -0.2), ceramic)
	return root


## Торшер, который горит неизвестно для кого.
func _floor_lamp() -> Node3D:
	var root := Node3D.new()
	_cyl(root, 0.15, 0.15, 0.03, Vector3(0, 0.015, 0), metal)
	_cyl(root, 0.015, 0.015, 1.5, Vector3(0, 0.78, 0), metal)
	_cyl(root, 0.12, 0.22, 0.25, Vector3(0, 1.6, 0), glow)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.5, 0)
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = 1.5
	light.omni_range = 9.0
	root.add_child(light)
	_chair(root, Vector3(0.6, 0, 0.1), rng.randf_range(-0.5, 0.5))
	return root


## Один стул, повёрнутый к горизонту.
func _chair_alone() -> Node3D:
	var root := Node3D.new()
	_chair(root, Vector3.ZERO, 0.0)
	return root


func _bed() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(1.6, 0.3, 2.1), Vector3(0, 0.15, 0), wood)
	_box(root, Vector3(1.5, 0.2, 2.0), Vector3(0, 0.4, 0), linen)
	_box(root, Vector3(1.6, 0.6, 0.06), Vector3(0, 0.6, -1.05), wood)
	for px in [-0.38, 0.38]:
		_box(root, Vector3(0.6, 0.12, 0.35), Vector3(px, 0.56, -0.75), linen)
	_box(root, Vector3(1.5, 0.08, 0.5), Vector3(0, 0.54, 0.65), fabric)
	return root


## Скамейка и две чашки на ней.
func _bench_for_two() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(1.6, 0.06, 0.4), Vector3(0, 0.45, 0), wood)
	_box(root, Vector3(1.6, 0.4, 0.05), Vector3(0, 0.75, 0.2), wood)
	for lx in [-0.7, 0.7]:
		_box(root, Vector3(0.06, 0.45, 0.4), Vector3(lx, 0.225, 0), metal)
	_cyl(root, 0.04, 0.035, 0.09, Vector3(-0.55, 0.525, -0.05), ceramic)
	_cyl(root, 0.04, 0.035, 0.09, Vector3(0.55, 0.525, -0.05), ceramic)
	return root


## Дверь без стен, приоткрытая.
func _door() -> Node3D:
	var root := Node3D.new()
	for px in [-0.5, 0.5]:
		_box(root, Vector3(0.1, 2.1, 0.12), Vector3(px, 1.05, 0), wood)
	_box(root, Vector3(1.1, 0.1, 0.12), Vector3(0, 2.15, 0), wood)
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.45, 0, 0)
	hinge.rotation.y = deg_to_rad(-55)
	root.add_child(hinge)
	_box(hinge, Vector3(0.9, 2.0, 0.05), Vector3(0.45, 1.0, 0), wood)
	_ball(hinge, 0.03, Vector3(0.8, 1.0, 0.05), metal)
	return root


## Цветок в горшке. Единственное живое здесь.
func _plant() -> Node3D:
	var root := Node3D.new()
	_cyl(root, 0.15, 0.11, 0.28, Vector3(0, 0.14, 0), clay)
	_ball(root, 0.18, Vector3(0, 0.45, 0), leaf, Vector3(1, 1.3, 1))
	_ball(root, 0.12, Vector3(0.1, 0.62, 0.05), leaf)
	_ball(root, 0.1, Vector3(-0.09, 0.58, -0.06), leaf)
	return root


func _chair(root: Node3D, pos: Vector3, yaw: float) -> void:
	var chair := Node3D.new()
	chair.position = pos
	chair.rotation.y = yaw
	root.add_child(chair)
	_box(chair, Vector3(0.45, 0.05, 0.45), Vector3(0, 0.45, 0), wood)
	for lx in [-0.2, 0.2]:
		for lz in [-0.2, 0.2]:
			_cyl(chair, 0.018, 0.018, 0.45, Vector3(lx, 0.225, lz), wood)
	_box(chair, Vector3(0.45, 0.5, 0.04), Vector3(0, 0.72, 0.21), wood)


# --- Примитивы ---------------------------------------------------------------

func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	Shapes.box(root, size, pos, mat)


func _cyl(root: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, mat: Material) -> void:
	Shapes.cylinder(root, r_top, r_bottom, h, pos, mat)


func _ball(root: Node3D, r: float, pos: Vector3, mat: Material, squash := Vector3.ONE) -> void:
	Shapes.node(root, Shapes.sphere_mesh(r), pos, mat, true, squash)
