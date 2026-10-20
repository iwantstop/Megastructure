extends SceneTree

## Ориентация костей руки манекена (для «рук в кадре»): позиции и оси в пространстве модели.

func _initialize() -> void:
	var scene: Node3D = load("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb").instantiate()
	root.add_child(scene)
	var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	print("ARM skeleton xform in scene: ", sk.global_transform)
	for n in ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R", "DEF-f_index.01.R", "DEF-f_index.03.R", "DEF-f_middle.01.R", "DEF-thumb.01.R", "DEF-f_pinky.01.R"]:
		var i := sk.find_bone(n)
		if i < 0:
			print("ARM missing ", n)
			continue
		var g := sk.get_bone_global_rest(i)
		print("ARM %s pos=%s X=%s Y=%s Z=%s parent=%s" % [n, g.origin.snapped(Vector3.ONE * 0.001), g.basis.x.snapped(Vector3.ONE * 0.01), g.basis.y.snapped(Vector3.ONE * 0.01), g.basis.z.snapped(Vector3.ONE * 0.01), sk.get_bone_name(sk.get_bone_parent(i))])
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		print("ARM mesh ", m.name, " surfaces=", m.mesh.get_surface_count())
	quit()
