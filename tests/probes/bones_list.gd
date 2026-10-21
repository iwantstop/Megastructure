extends SceneTree

## Печатает кости рук у моделей персонажей — есть ли пальцы.

func _initialize() -> void:
	for path in ["res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb", "res://assets/characters/rpg_unarmed/Unarmed.glb"]:
		var scene: Node = load(path).instantiate()
		var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
		var names := []
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if n.to_lower().contains("hand") or n.to_lower().contains("f_") or n.to_lower().contains("thumb") or n.to_lower().contains("index") or n.to_lower().contains("finger") or n.to_lower().contains("palm"):
				names.append(n)
		print("BONES ", path.get_file(), " total=", sk.get_bone_count(), " hand/finger: ", names)
		scene.free()
	quit()
