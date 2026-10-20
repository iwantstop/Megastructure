extends RefCounted

## Сборщик геометрии: складывает тысячи коробок и цилиндров в один меш
## (по поверхности на материал) и одно статическое тело с коллизиями.
## Так огромный мир рисуется быстро.

var body := StaticBody3D.new()
var _pieces := {}  # материал -> куски [вершины, нормали]
var _shapes := {}  # заготовка -> её треугольники из памяти
var _unit_box := BoxMesh.new()
var _unit_cylinder := CylinderMesh.new()
var _unit_rod := CylinderMesh.new()


func _init() -> void:
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0
	_unit_cylinder.radial_segments = 24
	_unit_cylinder.rings = 1
	_unit_rod.top_radius = 0.5
	_unit_rod.bottom_radius = 0.5
	_unit_rod.height = 1.0
	_unit_rod.radial_segments = 6
	_unit_rod.rings = 1


## Тонкий стержень (ветка, провод, столб) — мало полигонов, без коллизии.
func rod(center: Vector3, radius: float, height: float, mat: Material, basis := Basis.IDENTITY) -> void:
	var size := Vector3(radius * 2.0, height, radius * 2.0)
	_append(_unit_rod, Transform3D(basis * Basis.from_scale(size), center), mat)


## Стержень от точки до точки.
func rod_between(a: Vector3, c: Vector3, radius: float, mat: Material) -> void:
	var dir := c - a
	if dir.length() < 0.001:
		return
	rod((a + c) / 2.0, radius, dir.length(), mat, Basis(Quaternion(Vector3.UP, dir.normalized())))


func box(center: Vector3, size: Vector3, mat: Material, basis := Basis.IDENTITY, collide := true) -> void:
	_append(_unit_box, Transform3D(basis * Basis.from_scale(size), center), mat)
	if collide:
		collider_box(center, size, basis)


func cylinder(center: Vector3, radius: float, height: float, mat: Material, basis := Basis.IDENTITY, collide := true) -> void:
	var size := Vector3(radius * 2.0, height, radius * 2.0)
	_append(_unit_cylinder, Transform3D(basis * Basis.from_scale(size), center), mat)
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_add_collision(shape, Transform3D(basis, center))


## Коробка в локальных координатах постройки (t — её положение и поворот).
func box_local(t: Transform3D, local_center: Vector3, size: Vector3, mat: Material, collide := true) -> void:
	box(t * local_center, size, mat, t.basis, collide)


## Любой меш (капсула, сфера…) с произвольным положением, без коллизии.
func part(source: Mesh, xform: Transform3D, mat: Material) -> void:
	_append(source, xform, mat)


## Невидимая стенка/пандус — только коллизия.
func collider_box(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_add_collision(shape, Transform3D(basis, center))


## Склеивает накопленные куски в один меш: по поверхности на материал.
func finish(parent: Node) -> void:
	var mesh := ArrayMesh.new()
	for mat in _pieces:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		for piece in _pieces[mat]:
			verts.append_array(piece[0])
			norms.append_array(piece[1])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		# Склеиваем одинаковые вершины: так видеокарте втрое меньше работы.
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.index()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	parent.add_child(body)


## Деталь = форма-заготовка, сдвинутая и повёрнутая. Форму берём один раз из памяти
## (а не у видеокарты — такой запрос на каждую из десятков тысяч деталей занимал минуты),
## дальше только преобразуем её вершины. Куски копятся в обычном массиве и склеиваются в finish.
func _append(source: Mesh, xform: Transform3D, mat: Material) -> void:
	var shape := _shape(source)
	var normal_xform := Transform3D(xform.basis.inverse().transposed(), Vector3.ZERO)
	if not _pieces.has(mat):
		_pieces[mat] = []
	_pieces[mat].append([xform * shape[0], normal_xform * shape[1]])


## Вершины и нормали заготовки треугольниками подряд (без индексов), из памяти, один раз.
func _shape(source: Mesh) -> Array:
	if not _shapes.has(source):
		var arrays: Array = (source as PrimitiveMesh).get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		if index.is_empty():
			verts = v
			norms = n
		else:
			for i in index:
				verts.append(v[i])
				norms.append(n[i])
		_shapes[source] = [verts, norms]
	return _shapes[source]


func _add_collision(shape: Shape3D, xform: Transform3D) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)
