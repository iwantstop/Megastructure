extends Node3D

## Бинты: чем выше герой поднимается по горе, тем больше старых грязных бинтов
## разматывается и падает. Каждые ~70 м подъёма перед камерой срывается полоска бинта
## и, кружась, улетает вниз по ветру.

const STEP := 70.0       # метров подъёма на одну полоску
const MAX_STRIPS := 8

var player: CharacterBody3D
var best_height := 20.0
var dropped := 0
var cloth: StandardMaterial3D


func _ready() -> void:
	cloth = StandardMaterial3D.new()
	cloth.albedo_color = Color(0.82, 0.78, 0.7)
	cloth.albedo_texture = _stain_texture()
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 1.0


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return
	if dropped >= MAX_STRIPS or player.flying:
		return
	var on_mountain := Vector2(player.global_position.x - Mountain.CENTER.x, player.global_position.z - Mountain.CENTER.z).length() < Mountain.R_BASE + 20.0
	if on_mountain and player.is_on_floor() and player.global_position.y > best_height + STEP:
		best_height = player.global_position.y
		_drop()


## Полоска бинта появляется внизу кадра и улетает, кружась, по ветру и вниз.
func _drop() -> void:
	dropped += 1
	var cam := get_viewport().get_camera_3d()
	var basis := cam.global_transform.basis
	var strip := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, randf_range(0.6, 1.1))
	strip.mesh = quad
	strip.material_override = cloth
	add_child(strip)
	strip.global_position = cam.global_position - basis.z * 0.7 - basis.y * 0.45 + basis.x * randf_range(-0.25, 0.25)
	strip.global_rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	var wind := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var tween := create_tween().set_parallel()
	tween.tween_property(strip, "global_position", strip.global_position + wind * 6.0 + Vector3.DOWN * 9.0, 5.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(strip, "rotation", strip.rotation + Vector3(6.0, 9.0, 4.0), 5.0)
	tween.chain().tween_callback(strip.queue_free)


## Грязная ткань с бурыми пятнами засохшей крови.
func _stain_texture() -> ImageTexture:
	var stains := FastNoiseLite.new()
	stains.frequency = 0.08
	var img := Image.create(32, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 32:
			var n := stains.get_noise_2d(x, y)
			var c := Color(0.95, 0.93, 0.88).lerp(Color(0.6, 0.55, 0.48), randf() * 0.2)
			if n > 0.25:
				c = c.lerp(Color(0.38, 0.12, 0.08), smoothstep(0.25, 0.5, n))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
