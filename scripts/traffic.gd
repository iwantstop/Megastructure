extends Node3D

## Летающие машины: потоки огней на разных высотах над улицами-каньонами.
## Все машины — одна MultiMesh, их положения обновляются каждый кадр.
## Трасса — прямая вдоль улицы, но перед зданием (шахта лифта, мост, мегаструктура) машины
## заранее и плавно набирают высоту или уходят в сторону и облетают его: при запуске трасса
## «прощупывается» каждые SAMPLE метров, и для каждой точки ищется ближайший свободный сдвиг.

const HEIGHTS := [24.0, 55.0, 95.0, 130.0, 180.0, 260.0, 340.0]  # между пешеходными уровнями 14, 40 и 75 м и выше, среди гигантов
const LANES := 30
const PER_LANE := 14
const LANE_LENGTH := 3000.0
const SAMPLE := 8.0           # шаг прощупывания трассы, м
const AHEAD := 7              # за сколько точек (×SAMPLE) до препятствия начинать манёвр
const CLIMB_MAX := 160.0      # выше этого не набираем — тогда облёт сбоку
const SIDE_MAX := 96.0        # дальше этого в сторону не уходим

var lanes: Array[Dictionary] = []  # {from, dir, speed, path: PackedVector3Array — сдвиги (вбок, вверх, 0) по точкам}
var ready_paths := false
var offsets := PackedFloat32Array()
var multimesh: MultiMesh
var t := 0.0


func setup(streets: Array[Vector4], rng: RandomNumberGenerator) -> void:
	for k in LANES:
		var s: Vector4 = streets[rng.randi() % streets.size()]
		var y: float = HEIGHTS[rng.randi() % HEIGHTS.size()]
		var lateral := rng.randf_range(-3, 3)
		var from: Vector3
		var dir: Vector3
		if s.x == s.z:
			from = Vector3(s.x + lateral, y, -LANE_LENGTH / 2.0)
			dir = Vector3(0, 0, 1)
		else:
			from = Vector3(-LANE_LENGTH / 2.0, y, s.y + lateral)
			dir = Vector3(1, 0, 0)
		if rng.randf() < 0.5:
			from += dir * LANE_LENGTH
			dir = -dir
		lanes.append({"from": from, "dir": dir, "speed": rng.randf_range(25, 45)})
	offsets.resize(LANES * PER_LANE)
	for i in offsets.size():
		offsets[i] = rng.randf() * LANE_LENGTH


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _vehicle_mesh()
	multimesh.instance_count = offsets.size()
	multimesh.visible_instance_count = 0  # пока трассы не проложены — машин нет
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-2000, 0, -2000), Vector3(4000, 400, 4000))
	add_child(instance)


var physics_frames := 0


## Трассы прощупываются, когда коллизии мира уже в физике (на втором кадре физики).
func _physics_process(_delta: float) -> void:
	if ready_paths:
		return
	physics_frames += 1
	if physics_frames < 2:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 7)  # машина с запасом
	query.shape = box
	for lane in lanes:
		lane.path = _plan(space, query, lane)
	ready_paths = true
	multimesh.visible_instance_count = -1


## Для каждой точки трассы — ближайший свободный сдвиг (вбок, вверх), потом сглаживание:
## манёвр начинается за AHEAD точек до препятствия и плавно сходит на нет после него.
func _plan(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, lane: Dictionary) -> PackedVector3Array:
	var dir: Vector3 = lane.dir
	var right := dir.cross(Vector3.UP)
	var count := int(LANE_LENGTH / SAMPLE) + 1
	var raw := PackedVector3Array()
	raw.resize(count)
	for k in count:
		var base: Vector3 = lane.from + dir * (k * SAMPLE)
		raw[k] = _free_offset(space, query, base, right, dir)
	# Проверка готовой трассы с шагом в полточки: где машина всё ещё задевает здание
	# (тонкий мост между точками, стык двух манёвров) — поднимаем трассу там и пересчитываем.
	var path := _smooth(raw)
	for attempt in 8:
		lane.path = path
		var bumped := false
		var d := 0.0
		while d < LANE_LENGTH:
			var pos := _point(lane, d)
			if not _clear(space, query, pos, Basis.looking_at(dir, Vector3.UP)):
				# Ищем свободное место от того, где машина оказалась, а не от прямой трассы.
				var k := clampi(roundi(d / SAMPLE), 0, count - 1)
				var start: Vector3 = lane.from
				var current := pos - (start + dir * d)
				var offset := Vector3(current.dot(right), current.y, 0)
				raw[k] = offset + _free_offset(space, query, pos, right, dir)
				bumped = true
			d += SAMPLE / 2.0
		if not bumped:
			break
		path = _smooth(raw)
	# Где облететь так и не вышло (тесная группа гигантов далеко в тумане) — там машину не рисуем,
	# будто она скрылась в тумане.
	lane.path = path
	var hidden := PackedByteArray()
	hidden.resize(count)
	for k in count:
		var pos := _point(lane, k * SAMPLE)
		hidden[k] = 0 if _clear(space, query, pos, Basis.looking_at(dir, Vector3.UP)) else 1
	for k in count:  # с запасом в точку с каждой стороны — машина не торчит из стены наполовину
		if hidden[k] == 1:
			if k > 0 and hidden[k - 1] == 0:
				hidden[k - 1] = 2
			if k + 1 < count and hidden[k + 1] == 0:
				hidden[k + 1] = 2
	lane.hidden = hidden
	return path


## Сглаживание: берём самый большой сдвиг в окне ±AHEAD (заранее), потом усредняем (плавно).
func _smooth(raw: PackedVector3Array) -> PackedVector3Array:
	var count := raw.size()
	var wide := PackedVector3Array()
	wide.resize(count)
	for k in count:
		var up := 0.0
		var side := 0.0
		for j in range(maxi(k - AHEAD, 0), mini(k + AHEAD + 1, count)):
			up = maxf(up, raw[j].y)
			if absf(raw[j].x) > absf(side):
				side = raw[j].x
		wide[k] = Vector3(side, up, 0)
	var smooth := PackedVector3Array()
	smooth.resize(count)
	for k in count:
		var sum := Vector3.ZERO
		var n := 0
		for j in range(maxi(k - 3, 0), mini(k + 4, count)):
			sum += wide[j]
			n += 1
		smooth[k] = sum / n
	return smooth


func _free_offset(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, base: Vector3, right: Vector3, dir: Vector3) -> Vector3:
	var basis := Basis.looking_at(dir, Vector3.UP)
	if _clear(space, query, base, basis):
		return Vector3.ZERO
	# Сначала вверх (так естественнее для летающей машины), потом вбок — что ближе.
	var up := 8.0
	while up <= CLIMB_MAX:
		if _clear(space, query, base + Vector3.UP * up, basis):
			return Vector3(0, up, 0)
		up += 8.0
	var side := 8.0
	while side <= SIDE_MAX:
		for sign in [1.0, -1.0]:
			if _clear(space, query, base + right * side * sign, basis):
				return Vector3(side * sign, 0, 0)
		side += 8.0
	return Vector3(0, CLIMB_MAX, 0)  # не нашли — хотя бы повыше


func _clear(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, pos: Vector3, basis: Basis) -> bool:
	query.transform = Transform3D(basis, pos)
	return space.intersect_shape(query, 1).is_empty()


func _process(delta: float) -> void:
	t += delta
	if not ready_paths:
		return
	for i in offsets.size():
		var lane: Dictionary = lanes[i / PER_LANE]
		var dir: Vector3 = lane.dir
		var d := fmod(offsets[i] + t * float(lane.speed), LANE_LENGTH)
		var pos := _point(lane, d)
		var ahead := _point(lane, minf(d + 6.0, LANE_LENGTH))
		pos.y += sin(t * 0.7 + i) * 0.4
		var heading := ahead - pos if (ahead - pos).length() > 0.5 else dir
		var basis := Basis.looking_at(heading, Vector3.UP)
		var hidden: PackedByteArray = lane.hidden
		if hidden[mini(roundi(d / SAMPLE), hidden.size() - 1)] != 0:
			basis = basis.scaled(Vector3.ZERO)  # здесь облететь нельзя — машина скрыта
		multimesh.set_instance_transform(i, Transform3D(basis, pos))


## Точка трассы на расстоянии d от начала, с плавным сдвигом объезда.
func _point(lane: Dictionary, d: float) -> Vector3:
	var dir: Vector3 = lane.dir
	var right := dir.cross(Vector3.UP)
	var path: PackedVector3Array = lane.path
	var f := d / SAMPLE
	var k := mini(int(f), path.size() - 2)
	var o := path[k].lerp(path[k + 1], f - k)
	return lane.from + dir * d + right * o.x + Vector3.UP * o.y


## Машина смотрит в -Z: белые фары спереди, красные огни сзади, голубая подсветка днища.
func _vehicle_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.1, 0.1, 0.12)
	body.metallic = 0.7
	body.roughness = 0.3
	_add_surface(mesh, body, [
		[Vector3(0, 0, 0), Vector3(1.9, 0.7, 4.6)],
		[Vector3(0, 0.55, 0.3), Vector3(1.6, 0.5, 2.0)],
	])
	_add_surface(mesh, _light(Color(1.0, 0.95, 0.85), 5.0), [
		[Vector3(-0.6, 0, -2.31), Vector3(0.4, 0.12, 0.05)],
		[Vector3(0.6, 0, -2.31), Vector3(0.4, 0.12, 0.05)],
	])
	_add_surface(mesh, _light(Color(1.0, 0.1, 0.08), 4.0), [
		[Vector3(0, 0.05, 2.31), Vector3(1.7, 0.1, 0.05)],
	])
	_add_surface(mesh, _light(Color(0.2, 0.8, 1.0), 2.5), [
		[Vector3(0, -0.37, 0), Vector3(1.5, 0.04, 3.8)],
	])
	return mesh


func _add_surface(mesh: ArrayMesh, mat: Material, boxes: Array) -> void:
	var unit := BoxMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in boxes:
		st.append_from(unit, 0, Transform3D(Basis.from_scale(box[1]), box[0]))
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _light(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
