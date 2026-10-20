extends SceneTree

## Отладка Terrain3D: принята ли текстура камня и включена ли шахматка.

var step := 0
var mountain: Node3D


func _process(_delta: float) -> bool:
	step += 1
	if step == 1:
		mountain = load("res://scripts/mountain.gd").new()
		root.add_child(mountain)
		return false
	if step < 4:
		return false
	var terrain: Terrain3D = mountain.terrain
	print("PROBE textures=", terrain.assets.get_texture_count(), " albedo_rid=", terrain.assets.get_albedo_array_rid(),
		" terrain.checkered=", terrain.show_checkered, " material.checkered=", terrain.material.show_checkered,
		" asset.albedo=", terrain.assets.get_texture(0).albedo_texture if terrain.assets.get_texture(0) else null)
	return true
