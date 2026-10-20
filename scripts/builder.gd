extends RefCounted

## Сборщик геометрии: складывает десятки тысяч коробок и цилиндров в немногие меши
## и одно статическое тело с коллизиями.
##
## Оптимизация (по руководству Godot «Optimizing 3D performance»):
## - мир разбит на куски по сетке, чтобы движок отсекал всё вне поля зрения и за стенами
##   (в одном гигантском меше отсечь нечего — он рисовался бы целиком);
## - мелочи (перила, провода, столбы, мусор) — отдельными кусками, которые не рисуются
##   дальше DETAIL_RANGE и не отбрасывают теней;
## - крупные глухие объёмы регистрируются как окклюдеры: то, что за ними, не рисуется.

const NEAR := Rect2(-300, -400, 600, 580)  # город с запасом: здесь сетка мельче
const CELL_NEAR := 192.0
const CELL_FAR := 640.0
const DETAIL_RANGE := 200.0               # дальше этого мелочи не рисуются
const CELL_DETAIL := 96.0                 # мелочи режем мелко везде: движок меряет дальность до ЦЕНТРА куска,
                                          # и в 640-метровом куске перила пропадали прямо под ногами
const DETAIL_THIN := 0.6                  # деталь «мелкая», если её средний размер меньше
const DETAIL_PIECE := 48.0                # длинные мелочи режутся на отрезки не длиннее этого, м
const OCCLUDER_MIN := 8.0                 # окклюдерами становятся объёмы крупнее этого

var body := StaticBody3D.new()
var _pieces := {}     # Vector3i(ячейка x, ячейка z, мелочь?) -> {материал -> куски [вершины, нормали]}
var _shapes := {}     # заготовка -> её треугольники из памяти
var _plain := {}      # глянцевый? -> общий одноцветный материал с цветом из вершин
var _occluders: Array[Transform3D] = []  # глухие объёмы: базис уже включает размер
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
	_append_box(center, size, mat, basis)
	if collide:
		collider_box(center, size, basis)


## Длинная тонкая деталь (поручень, провод) режется на отрезки не длиннее DETAIL_PIECE:
## мелочи прячутся по расстоянию до центра куска, и поручень на весь двухкилометровый мост
## исчезал целиком, стоило отойти от его середины.
func _append_box(center: Vector3, size: Vector3, mat: Material, basis: Basis) -> void:
	var dims := [size.x, size.y, size.z]
	var longest := 0
	for i in 3:
		if dims[i] > dims[longest]:
			longest = i
	var sorted := dims.duplicate()
	sorted.sort()
	var thin: bool = sorted[1] < DETAIL_THIN
	var pieces := ceili(dims[longest] / DETAIL_PIECE) if thin else 1
	if pieces <= 1:
		_append(_unit_box, Transform3D(basis * Basis.from_scale(size), center), mat)
		return
	var axis := basis.orthonormalized()[longest]
	var piece_size := size
	piece_size[longest] = dims[longest] / pieces
	for k in pieces:
		var offset := (k + 0.5 - pieces / 2.0) * piece_size[longest]
		_append(_unit_box, Transform3D(basis * Basis.from_scale(piece_size), center + axis * offset), mat)


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


## Глухой объём, за которым ничего не видно (здание, башня, плита): станет окклюдером.
func occluder(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	if minf(size.x, minf(size.y, size.z)) >= 1.0 and maxf(size.x, maxf(size.y, size.z)) >= OCCLUDER_MIN:
		_occluders.append(Transform3D(basis * Basis.from_scale(size), center))


func occluder_local(t: Transform3D, local_center: Vector3, size: Vector3) -> void:
	occluder(t * local_center, size, t.basis)


## Склеивает накопленные куски: по мешу на ячейку, по поверхности на материал.
func finish(parent: Node) -> void:
	for key in _pieces:
		var mesh := ArrayMesh.new()
		for mat in _pieces[key]:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var colors := PackedColorArray()
			for piece in _pieces[key][mat]:
				verts.append_array(piece[0])
				norms.append_array(piece[1])
				if piece.size() > 2:
					var tint := PackedColorArray()
					tint.resize(piece[0].size())
					tint.fill(piece[2])
					colors.append_array(tint)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			if not colors.is_empty():
				arrays[Mesh.ARRAY_COLOR] = colors
			# Склеиваем одинаковые вершины: так видеокарте втрое меньше работы.
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			st.index()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		if key.z & 1:  # мелочи
			instance.visibility_range_end = DETAIL_RANGE + CELL_DETAIL * 0.7  # до центра куска — плюс полдиагонали
			instance.visibility_range_end_margin = 20.0
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # плавное проявление делает объект прозрачным — дорого; границу прячет туман
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
	parent.add_child(body)

	var box_shape := BoxOccluder3D.new()
	box_shape.size = Vector3.ONE
	for xform in _occluders:
		var occ := OccluderInstance3D.new()
		occ.occluder = box_shape
		occ.transform = xform
		parent.add_child(occ)


## Деталь = форма-заготовка, сдвинутая и повёрнутая. Форму берём один раз из памяти
## (а не у видеокарты — такой запрос на каждую из десятков тысяч деталей занимал минуты),
## дальше только преобразуем её вершины. Куски копятся по ячейкам и склеиваются в finish.
func _append(source: Mesh, xform: Transform3D, mat: Material) -> void:
	var shape := _shape(source)
	var normal_xform := Transform3D(xform.basis.inverse().transposed(), Vector3.ZERO)
	var key := _chunk_key(xform)
	if not _pieces.has(key):
		_pieces[key] = {}
	var piece := [xform * shape[0], normal_xform * shape[1]]
	# Простой одноцветный материал заменяем общим: цвет детали едет в её вершинах.
	# Так два десятка материалов рисуются двумя вызовами отрисовки вместо двадцати.
	var shared := _plain_bucket(mat)
	if shared:
		piece.append((mat as StandardMaterial3D).albedo_color)
		mat = shared
	if not _pieces[key].has(mat):
		_pieces[key][mat] = []
	_pieces[key][mat].append(piece)


## Для простого непрозрачного материала без текстур и свечения — общий материал
## с цветом из вершин: матовый или глянцевый. Для остальных — null.
func _plain_bucket(mat: Material) -> Material:
	var plain := mat as StandardMaterial3D
	if plain == null or plain.emission_enabled or plain.albedo_texture or plain.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var glossy := plain.roughness < 0.5
	if not _plain.has(glossy):
		var shared := StandardMaterial3D.new()
		shared.vertex_color_use_as_albedo = true
		shared.vertex_color_is_srgb = true
		shared.roughness = 0.25 if glossy else 0.85
		shared.metallic = 0.35 if glossy else 0.0
		_plain[glossy] = shared
	return _plain[glossy]


## Ячейка сетки по центру детали и признак «мелочь» (тонкая или маленькая деталь).
func _chunk_key(xform: Transform3D) -> Vector3i:
	var p := xform.origin
	var s := xform.basis.get_scale()
	var dims := [s.x, s.y, s.z]
	dims.sort()
	var detail := 1 if dims[1] < DETAIL_THIN or dims[2] < 2.5 else 0
	var cell := CELL_NEAR if NEAR.has_point(Vector2(p.x, p.z)) else CELL_FAR
	if detail:
		cell = CELL_DETAIL
	# Ближние и дальние ячейки разной величины: разводим их по разным ключам.
	var far := 0 if cell == CELL_NEAR else 2
	return Vector3i(floori(p.x / cell), floori(p.z / cell), detail + far)


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
