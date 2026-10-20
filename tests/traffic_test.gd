extends SceneTree

## Летающие машины: сколько точек трасс проходит сквозь твёрдое — до и после объезда.
## Запуск: godot --headless --path <проект> -s res://tests/traffic_test.gd

var world: Node
var traffic: Node
var frames := 0
var started := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	started = Time.get_ticks_msec()


func _physics_process(_d: float) -> bool:
	frames += 1
	if traffic == null:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("traffic.gd"):
				traffic = c
		return false
	if not traffic.ready_paths:
		return false
	var space: PhysicsDirectSpaceState3D = traffic.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.2, 4.6)  # сама машина
	query.shape = box
	var straight := 0
	var planned := 0
	var total := 0
	for lane in traffic.lanes:
		var d := 0.0
		while d < traffic.LANE_LENGTH:
			var dir: Vector3 = lane.dir
			query.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), lane.from + dir * d)
			if not space.intersect_shape(query, 1).is_empty():
				straight += 1
			query.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), traffic._point(lane, d))
			var hits := space.intersect_shape(query, 1)
			var hidden: PackedByteArray = lane.hidden
			if hidden[mini(roundi(d / traffic.SAMPLE), hidden.size() - 1)] != 0:
				hits = []  # в этой точке машина скрыта — не считается
			if not hits.is_empty():
				planned += 1
				if planned <= 12:
					var col: Object = hits[0].collider
					print("TRAFFIC hit at ", traffic._point(lane, d).snapped(Vector3.ONE), " offset=", lane.path[int(d / traffic.SAMPLE)].snapped(Vector3.ONE * 0.1), " collider=", col.name if col else "?", " parent=", (col.get_parent().name if col and col.get_parent() else "?"))
			total += 1
			d += 4.0
	print("TRAFFIC points=", total, " inside_solid: straight=", straight, " with_detours=", planned)
	return true
