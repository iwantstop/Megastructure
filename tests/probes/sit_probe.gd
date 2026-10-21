extends SceneTree

## Замер позы «сидит»: где таз, бёдра, колени и стопы (в метрах, «вперёд» фигуры — -Z, как у манекенов).

const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")

var holder: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var frame := 0


func _initialize() -> void:
	holder = Node3D.new()
	var body: Node3D = MODEL.instantiate()
	body.rotation.y = PI
	holder.add_child(body)
	root.add_child(holder)
	anim = body.find_child("AnimationPlayer", true, false)
	skeleton = body.find_child("Skeleton3D", true, false)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	var at := (frame - 2) / 4.0
	anim.play("Sitting_Idle")
	anim.seek(anim.current_animation_length * at, true)
	anim.pause()
	if frame >= 2:
		var line := "SIT at=%.2f" % at
		for bone in ["DEF-hips", "DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-spine.003"]:
			var i := skeleton.find_bone(bone)
			if i < 0:
				line += " %s=?" % bone
				continue
			var p := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
			line += "  %s=(%.2f, %.2f, %.2f)" % [bone.replace("DEF-", ""), p.x, p.y, p.z]
		print(line)
	return frame >= 6
