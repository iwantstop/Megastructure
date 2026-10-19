extends Node

## Вступление: герой лежит на спине у подножия самой высокой башни, с которой прыгнул,
## и смотрит в тучи. Мимо пробегают крысы. Осмотреться можно мышью; по W он медленно поднимается.

const GET_UP_TIME := 3.5

var player: CharacterBody3D
var layer: CanvasLayer
var fade: ColorRect
var hint: Label
var state := 0  # 0 — лежит, 1 — показана подсказка, 2 — поднимается, 3 — готово
var t := 0.0
var rat_mat := StandardMaterial3D.new()


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	player.locked = true
	player.lying = 1.0
	player.rotation.y = PI  # лицом к башне
	player.target_yaw = PI

	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	create_tween().tween_property(fade, "color:a", 0.0, 6.0).set_trans(Tween.TRANS_SINE)

	hint = Label.new()
	hint.text = "W — подняться"
	hint.modulate.a = 0.0
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y -= 80
	layer.add_child(hint)

	rat_mat.albedo_color = Color(0.08, 0.07, 0.07)
	rat_mat.roughness = 0.6
	for i in 4:
		_rat(i)


func _process(delta: float) -> void:
	t += delta
	if state == 0 and t > 8.0:
		state = 1
		create_tween().tween_property(hint, "modulate:a", 0.6, 2.0)
	elif state == 1 and Input.is_physical_key_pressed(KEY_W):
		_get_up()


func _get_up() -> void:
	state = 2
	create_tween().tween_property(hint, "modulate:a", 0.0, 0.8)
	var tween := create_tween()
	tween.tween_property(player, "lying", 0.0, GET_UP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish)


func _finish() -> void:
	state = 3
	player.locked = false
	layer.queue_free()


## Из админ-панели.
func skip() -> void:
	if state < 2:
		fade.color.a = 0.0
		_get_up()


## Крыса пробегает мимо лежащего героя.
func _rat(i: int) -> void:
	var rat := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.05
	capsule.height = 0.24
	body.mesh = capsule
	body.material_override = rat_mat
	body.rotation.x = PI / 2.0
	body.position.y = 0.05
	rat.add_child(body)
	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.004
	tail_mesh.bottom_radius = 0.01
	tail_mesh.height = 0.2
	tail.mesh = tail_mesh
	tail.material_override = rat_mat
	tail.rotation.x = PI / 2.0 - 0.15
	tail.position = Vector3(0, 0.03, 0.2)
	rat.add_child(tail)
	player.get_parent().add_child(rat)

	# Путь: из темноты сбоку, мимо героя, и дальше.
	var origin := player.global_position
	var side := -1.0 if i % 2 == 0 else 1.0
	var from := origin + Vector3(side * 6.0, 0, randf_range(-3, 3))
	var past := origin + Vector3(side * -0.2, 0, randf_range(-1.2, 1.2))
	var to := origin + Vector3(side * -7.0, 0, randf_range(-4, 4))
	rat.position = from
	rat.look_at(past, Vector3.UP)
	rat.visible = false
	var tween := create_tween()
	tween.tween_interval(2.0 + i * randf_range(1.5, 3.0))
	tween.tween_callback(func() -> void: rat.visible = true)
	tween.tween_property(rat, "position", past, randf_range(1.2, 2.0))
	tween.tween_callback(func() -> void: rat.look_at(to, Vector3.UP))
	tween.tween_property(rat, "position", to, randf_range(1.5, 2.5))
	tween.tween_callback(rat.queue_free)
