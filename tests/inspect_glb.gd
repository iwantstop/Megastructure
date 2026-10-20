extends SceneTree

## Печатает содержимое GLB: узлы, меши, скелет, анимации — справка по ассетам персонажа.

const FILES := [
	"res://assets/characters/rpg_unarmed/Unarmed.glb",
	"res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb",
]


func _initialize() -> void:
	for path in FILES:
		print("=== ", path)
		var scene: Node = load(path).instantiate()
		_walk(scene, 0)
		for player in scene.find_children("*", "AnimationPlayer", true, false):
			var names: PackedStringArray = player.get_animation_list()
			print("  animations (", names.size(), "): ", ", ".join(names))
		for skel in scene.find_children("*", "Skeleton3D", true, false):
			var bones := []
			for i in mini(skel.get_bone_count(), 70):
				bones.append(skel.get_bone_name(i))
			print("  skeleton ", skel.name, " bones=", skel.get_bone_count(), ": ", ", ".join(bones))
		for mesh in scene.find_children("*", "MeshInstance3D", true, false):
			print("  mesh ", mesh.name, " aabb=", mesh.get_aabb(), " surfaces=", mesh.mesh.get_surface_count() if mesh.mesh else 0)
		scene.free()
	quit()


func _walk(node: Node, depth: int) -> void:
	if depth < 4:
		print("  ".repeat(depth + 1), node.name, " (", node.get_class(), ")")
		for c in node.get_children():
			_walk(c, depth + 1)
