extends SceneTree

## Печатает методы классов Terrain3D — справка по API аддона.

func _initialize() -> void:
	for cls in ["Terrain3DUtil"]:
		print("=== ", cls)
		for m in ClassDB.class_get_method_list(cls, true):
			var args := []
			for a in m.args:
				args.append("%s:%s" % [a.name, type_string(a.type)])
			print("  func ", m.name, "(", ", ".join(args), ")")
	quit()
