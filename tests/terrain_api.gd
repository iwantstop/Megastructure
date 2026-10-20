extends SceneTree

## Печатает методы и свойства классов Terrain3D — справка по API аддона.

func _initialize() -> void:
	for cls in ["Terrain3D", "Terrain3DData", "Terrain3DMaterial", "Terrain3DAssets", "Terrain3DTextureAsset"]:
		print("=== ", cls)
		for p in ClassDB.class_get_property_list(cls, true):
			print("  prop ", p.name, " : ", type_string(p.type))
		for m in ClassDB.class_get_method_list(cls, true):
			var args := []
			for a in m.args:
				args.append("%s:%s" % [a.name, type_string(a.type)])
			print("  func ", m.name, "(", ", ".join(args), ")")
	quit()
