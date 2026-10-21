extends SceneTree

## Карты костей для переноса анимаций (ретаргетинга): скелет Mixamo и скелет пака анимаций (Quaternius)
## сопоставляются со стандартным человеческим профилем Godot. После этого любые анимации пака подходят
## к любой модели с Mixamo. Запуск: godot --headless --path . -s tools/make_bone_maps.gd

const SIDES := {"Left": ["Left", ".L"], "Right": ["Right", ".R"]}
const FINGERS := {"Thumb": ["Thumb", "thumb"], "Index": ["Index", "f_index"], "Middle": ["Middle", "f_middle"],
	"Ring": ["Ring", "f_ring"], "Little": ["Pinky", "f_pinky"]}


func _initialize() -> void:
	var mixamo := {"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head"}
	var ual := {"Root": "root", "Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002",
		"UpperChest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head"}
	for side in SIDES:
		var m: String = SIDES[side][0]
		var u: String = SIDES[side][1]
		for pair in [["Shoulder", "Shoulder", "DEF-shoulder"], ["UpperArm", "Arm", "DEF-upper_arm"], ["LowerArm", "ForeArm", "DEF-forearm"],
				["Hand", "Hand", "DEF-hand"], ["UpperLeg", "UpLeg", "DEF-thigh"], ["LowerLeg", "Leg", "DEF-shin"], ["Foot", "Foot", "DEF-foot"],
				["Toes", "ToeBase", "DEF-toe"]]:
			mixamo[side + pair[0]] = m + pair[1]
			ual[side + pair[0]] = pair[2] + u
		for finger in FINGERS:
			var parts := ["Metacarpal", "Proximal", "Distal"] if finger == "Thumb" else ["Proximal", "Intermediate", "Distal"]
			for k in 3:
				mixamo[side + finger + parts[k]] = "%sHand%s%d" % [m, FINGERS[finger][0], k + 1]
				ual[side + finger + parts[k]] = "DEF-%s.%02d%s" % [FINGERS[finger][1], k + 1, u]
	_save(mixamo, "mixamorig_", "res://assets/characters/retarget/mixamo_bone_map.tres")
	_save(ual, "", "res://assets/characters/retarget/ual_bone_map.tres")
	quit()


func _save(names: Dictionary, prefix: String, path: String) -> void:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	for profile_bone in names:
		map.set_skeleton_bone_name(profile_bone, prefix + names[profile_bone])
	ResourceSaver.save(map, path)
	print("BONEMAP %s: %d bones" % [path.get_file(), names.size()])
