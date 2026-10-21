extends SceneTree

## Проба модели Mixamo в игре: ставит её перед героем (у башни и в квартире в пещере), печатает скелет,
## снимает кадры. Запуск (с окном): godot --path . -s tests/probes/mixamo_view.gd -- res://assets/mixamo/ch30.glb

var world: Node
var model: Node3D
var frames := 0
var stage := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 30:
		return false
	var player: CharacterBody3D = get_first_node_in_group("player")
	if stage == 0:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
				c.skip()
		var path: String = OS.get_cmdline_user_args()[0]
		model = (load(path) as PackedScene).instantiate()
		world.add_child(model)
		var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
		var fingers := 0
		for i in skeleton.get_bone_count():
			if "Hand" in skeleton.get_bone_name(i) and skeleton.get_bone_name(i).right(1).is_valid_int():
				fingers += 1
		var aabb := AABB()
		for m in model.find_children("*", "MeshInstance3D", true, false):
			aabb = aabb.merge(m.get_aabb())
		print("MIXAMO bones=%d finger_bones=%d height=%.2f m anims=%s" % [skeleton.get_bone_count(), fingers, aabb.size.y,
			model.find_child("AnimationPlayer", true, false).get_animation_list() if model.find_child("AnimationPlayer", true, false) else []])
		stage = 1
		frames = 0
		return false
	if stage == 1 and frames > 200 and not player.locked:
		# У башни, на улице: в 3,5 м перед героем, лицом к нему.
		var ahead := player.global_position - player.global_transform.basis.z * 3.5
		ahead.y = player.global_position.y
		model.global_position = ahead
		model.look_at(player.global_position, Vector3.UP, true)
		player.target_pitch = -0.05
		stage = 2
		frames = 0
	if stage == 2 and frames > 20:
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/mixamo_street.png")
		# В квартире в пещере: у стены, в свете торшера.
		var cave := Mountain.cave_frame()
		player.global_position = cave * Vector3(0, 0.3, -20.0)
		player.velocity = Vector3.ZERO
		var look := cave * Vector3(1.5, 0, -27.0)
		var to := look - player.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		player.target_yaw = player.rotation.y
		model.global_position = cave * Vector3(1.5, 0.0, -27.0)
		model.look_at(player.global_position, Vector3.UP, true)
		model.global_rotation.x = 0
		model.global_rotation.z = 0
		stage = 3
		frames = 0
	if stage == 3 and frames > 40:
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/mixamo_cave.png")
		return true
	return false
