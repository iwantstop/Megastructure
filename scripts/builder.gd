extends RefCounted

## Сборщик геометрии: складывает тысячи коробок и цилиндров в один меш
## (по поверхности на материал) и одно статическое тело с коллизиями.
## Так огромный мир рисуется быстро.

var body := StaticBody3D.new()
var _tools := {}
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


func finish(parent: Node) -> void:
	var mesh := ArrayMesh.new()
	for mat in _tools:
		var st: SurfaceTool = _tools[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	parent.add_child(body)


func _append(source: Mesh, xform: Transform3D, mat: Material) -> void:
	if not _tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[mat] = st
	_tools[mat].append_from(source, 0, xform)


func _add_collision(shape: Shape3D, xform: Transform3D) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)
