extends SceneTree

## Проверка анимаций модели: список анимаций и двигаются ли кости при проигрывании.

const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")

var body: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var frames := 0
var before: Transform3D


func _initialize() -> void:
	body = MODEL.instantiate()
	root.add_child(body)
	anim = body.find_child("AnimationPlayer", true, false)
	skeleton = body.find_child("Skeleton3D", true, false)
	print("ANIM list: ", anim.get_animation_list())
	print("ANIM callback_mode_process=", anim.callback_mode_process, " active=", anim.active, " root=", anim.root_node)
	anim.play("Walk")
	print("ANIM playing=", anim.is_playing(), " current=", anim.current_animation, " len=", anim.current_animation_length)


func _process(_delta: float) -> bool:
	frames += 1
	var bone := skeleton.find_bone("DEF-thigh.L")
	if bone < 0:
		bone = 1
	if frames == 2:
		before = skeleton.get_bone_global_pose(bone)
	if frames == 30:
		var after := skeleton.get_bone_global_pose(bone)
		print("ANIM pos=", anim.current_animation_position, " bone moved=", not before.is_equal_approx(after))
		var track := anim.get_animation("Walk").track_get_path(0)
		print("ANIM first track: ", track, " resolves=", body.get_node_or_null(NodePath(str(track).split(":")[0])) != null if false else anim.get_node(anim.root_node).get_node_or_null(NodePath(str(track).split(":")[0])) != null)
		return true
	return false
