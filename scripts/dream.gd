extends Node

## «Сон»: мир меняется почти незаметно, чем дольше гуляешь.
## - солнце медленно опускается, небо и туман теплеют;
## - иногда вещь, оставшаяся далеко позади, снова оказывается где-то рядом.

const DUSK_TIME := 1500.0   # за сколько секунд «день» доходит до заката

var time_scale := 1.0       # меняется из админ-панели
var sun: DirectionalLight3D
var sky: ProceduralSkyMaterial
var vignettes: Array[Node3D] = []
var player: CharacterBody3D
var elapsed := 0.0
var next_shift := 180.0
var rng := RandomNumberGenerator.new()
var sun_color_start: Color
var sun_pitch_start: float
var sky_top_start: Color
var horizon_start: Color


func setup(p_sun: DirectionalLight3D, p_sky: ProceduralSkyMaterial, p_vignettes: Array[Node3D]) -> void:
	sun = p_sun
	sky = p_sky
	vignettes = p_vignettes
	sun_color_start = sun.light_color
	sun_pitch_start = sun.rotation_degrees.x
	sky_top_start = sky.sky_top_color
	horizon_start = sky.sky_horizon_color


func _ready() -> void:
	rng.randomize()


func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return
	var step := delta * time_scale
	elapsed += step

	# Небом и светом теперь управляет путь героя (journey.gd), здесь только «сон».
	next_shift -= step
	if next_shift <= 0.0:
		next_shift = rng.randf_range(150, 240)
		shift_vignette()


## Берёт вещь, которую игрок сейчас не видит и оставил далеко, и тихо ставит её
## сбоку от него — он заметит, когда обернётся.
func shift_vignette() -> void:
	var cam := get_viewport().get_camera_3d()
	var candidates: Array[Node3D] = []
	for v in vignettes:
		if not cam.is_position_in_frustum(v.global_position) and v.global_position.distance_to(player.global_position) > 120:
			candidates.append(v)
	if candidates.is_empty():
		return
	var vignette := candidates[rng.randi() % candidates.size()]

	var forward := -player.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	for attempt in 20:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var dir := forward.rotated(Vector3.UP, rng.randf_range(1.0, 1.6) * side)
		var spot := player.global_position + dir * rng.randf_range(15, 80)
		var floor_y = _open_floor(spot)
		if floor_y == null:
			continue
		spot.y = floor_y
		if cam.is_position_in_frustum(spot + Vector3.UP):
			continue
		vignette.global_position = spot
		vignette.rotation.y = rng.randf() * TAU
		return


## Есть ли под точкой пол (земля, крыша) и свободное место вокруг. Возвращает высоту пола.
func _open_floor(spot: Vector3) -> Variant:
	var space := player.get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3, spot + Vector3.DOWN * 30)
	down.exclude = [player.get_rid()]
	var hit := space.intersect_ray(down)
	if hit.is_empty() or hit.normal.y < 0.9:
		return null
	var floor_y: float = hit.position.y
	var probe := PhysicsPointQueryParameters3D.new()
	for offset in [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
		probe.position = Vector3(spot.x, floor_y + 1.0, spot.z) + offset
		if not space.intersect_point(probe, 1).is_empty():
			return null
	return floor_y
