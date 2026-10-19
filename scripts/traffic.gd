extends Node3D

## Летающие машины: потоки огней на разных высотах над улицами-каньонами.
## Все машины — одна MultiMesh, их положения обновляются каждый кадр.

const HEIGHTS := [24.0, 55.0, 95.0, 130.0, 180.0, 260.0, 340.0]  # между пешеходными уровнями 14, 40 и 75 м и выше, среди гигантов
const LANES := 30
const PER_LANE := 14
const LANE_LENGTH := 3000.0

var lanes: Array[Dictionary] = []  # {from, dir, speed}
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
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-2000, 0, -2000), Vector3(4000, 400, 4000))
	add_child(instance)


func _process(delta: float) -> void:
	t += delta
	for i in offsets.size():
		var lane: Dictionary = lanes[i / PER_LANE]
		var dir: Vector3 = lane.dir
		var d := fmod(offsets[i] + t * float(lane.speed), LANE_LENGTH)
		var pos: Vector3 = lane.from + dir * d
		pos.y += sin(t * 0.7 + i) * 0.4
		multimesh.set_instance_transform(i, Transform3D(Basis.looking_at(dir, Vector3.UP), pos))


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
