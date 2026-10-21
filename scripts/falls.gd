extends Node3D

## Время от времени кто-то срывается с крыши — вдалеке, впереди по взгляду. Без звука.

var roofs: Array[Dictionary] = []
var player: Node3D
var figure: MeshInstance3D
var timer := 40.0
var falling := false
var velocity := Vector3.ZERO
var spin := Vector3.ZERO


func setup(p_roofs: Array[Dictionary]) -> void:
	roofs = p_roofs


func _ready() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.25
	mesh.height = 1.75
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	mat.roughness = 1.0
	figure = MeshInstance3D.new()
	figure.mesh = mesh
	figure.material_override = mat
	figure.visible = false
	add_child(figure)


func _process(delta: float) -> void:
	if player == null:
		player = Game.player
		return
	if falling:
		velocity.y -= 9.8 * delta
		figure.position += velocity * delta
		figure.rotation += spin * delta
		if figure.position.y < 0.6:
			falling = false
			figure.visible = false
			timer = randf_range(35, 80)
		return
	timer -= delta
	if timer <= 0.0:
		_try_start()


func _try_start() -> void:
	timer = 3.0
	if roofs.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var forward := -cam.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	for attempt in 20:
		var roof: Dictionary = roofs.pick_random()
		var pos: Vector3 = roof.pos
		if pos.y < 12.0:
			continue
		var to := pos - player.global_position
		to.y = 0
		var dist := to.length()
		if dist < 40.0 or dist > 220.0 or forward.dot(to / dist) < 0.5:
			continue
		var extent: float = roof.extent
		# Край крыши, обращённый к игроку, — чтобы падение было видно.
		figure.position = pos - to / dist * (extent / 2.0 - 0.3) + Vector3.UP * 0.9
		figure.rotation = Vector3.ZERO
		velocity = -to / dist * 1.5 + Vector3.UP * 0.5
		spin = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		figure.visible = true
		falling = true
		return
