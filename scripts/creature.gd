extends Node3D

## Существо на мосту: стоит у перил в позе «Idle» и смотрит вдаль, в бездну. Подходишь — резко исчезает,
## навсегда. Модель — с Mixamo (ch30.glb), анимация — из пака Quaternius: скелеты сопоставлены со стандартным
## человеческим профилем при импорте (assets/characters/retarget), поэтому анимации пака ей подходят.

const MODEL := preload("res://assets/mixamo/ch30.glb")
const ANIMATIONS := preload("res://assets/characters/retarget/ual_humanoid.glb")
const SPOT := Vector3(12.8, 0.0, -1210.0)   # у правых перил, между фонарями (второй кусок моста, после 1-го припадка)
const VANISH_DISTANCE := 14.0              # ближе — исчезает (мимо по середине моста — тоже)

var body: Node3D
var gone := false


func _ready() -> void:
	body = MODEL.instantiate()
	add_child(body)
	position = SPOT
	rotation.y = PI / 2.0   # модель смотрит в +Z, повёрнута к бездне (+X)
	var player: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	var source: Node = ANIMATIONS.instantiate()
	var idle: Animation = (source.find_child("AnimationPlayer", true, false) as AnimationPlayer).get_animation("Idle").duplicate()
	source.free()
	idle.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation("Idle", idle)
	player.add_animation_library("pack", library)
	player.play("pack/Idle")
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 260.0   # дальше — туман всё равно скрывает


func _process(_delta: float) -> void:
	if gone or Game.player == null:
		return
	var p := Game.player.global_position
	if Vector2(p.x - SPOT.x, p.z - SPOT.z).length() < VANISH_DISTANCE:
		gone = true
		visible = false
		set_process(false)
		body.queue_free()
