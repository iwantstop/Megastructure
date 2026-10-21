extends SceneTree

## «Отпечаток» мира: сколько мешей, вершин, коллизий, окклюдеров, узлов и контрольная сумма положений.
## Переделки кода не должны менять мир — отпечаток до и после должен совпасть.
## Запуск: godot --path . -s tests/world_fingerprint.gd

var world: Node
var frames := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	var meshes := 0
	var verts := 0
	var shapes := 0
	var occluders := 0
	var nodes := 0
	var sum := 0.0
	var player := get_first_node_in_group("player")
	for node in world.find_children("*", "", true, false):
		nodes += 1
		if player and (node == player or player.is_ancestor_of(node)):
			continue  # герой падает — его положение каждый запуск своё
		if node is Node3D and not node is GPUParticles3D:
			var p: Vector3 = node.global_position
			sum += absf(p.x) * 0.001 + absf(p.y) * 0.002 + absf(p.z) * 0.003
		if node is MeshInstance3D and node.mesh:
			meshes += 1
			if node.mesh is ArrayMesh:
				for s in node.mesh.get_surface_count():
					verts += node.mesh.surface_get_array_len(s)
		elif node is CollisionShape3D:
			shapes += 1
		elif node is OccluderInstance3D:
			occluders += 1
	var mountain := world.find_children("*", "Terrain3D", true, false)
	print("FINGERPRINT meshes=%d verts=%d shapes=%d occluders=%d nodes=%d sum=%.0f terrain=%d" % [
		meshes, verts, shapes, occluders, nodes, sum, mountain.size()])
	# Гора: высоты, цвета и дыры ландшафта в сетке точек и контрольная сумма коллизии.
	var terrain = mountain[0]
	var h_sum := 0.0
	var c_sum := 0.0
	var holes := 0
	for i in 60:
		for j in 60:
			var q := Mountain.CENTER + Vector3(-700 + i * 23.7, 0, -700 + j * 23.7)
			var h: float = terrain.data.get_height(q)
			if is_nan(h):
				holes += 1
			else:
				h_sum += h
			var c: Color = terrain.data.get_pixel(Terrain3DRegion.TYPE_COLOR, q)
			c_sum += c.r + c.g * 2.0 + c.b * 3.0 + c.a * 4.0
	var col_sum := 0.0
	for shape in world.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is HeightMapShape3D:
			var data: PackedFloat32Array = shape.shape.map_data
			for k in range(0, data.size(), 97):
				col_sum += data[k]
			col_sum += data.size()
	print("FINGERPRINT mountain heights=%.2f colors=%.3f holes=%d collision=%.2f" % [h_sum, c_sum, holes, col_sum])
	return true
