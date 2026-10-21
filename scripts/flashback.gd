extends Node

## Вспышка-воспоминание на выходе из пещеры. Герой вышел из «квартиры» наружу — и его снова
## швыряет в падение с небоскрёба: на спине, взгляд на удаляющуюся крышу, ревёт ветер — 2 секунды,
## чтобы напрячь. Потом чернота, ветер обрывается — и он приходит в себя на тропе над облаками,
## недалеко от уступа, где его ждёт ангел (прощание — presence.gd).

const Structures = preload("res://scripts/structures.gd")
const TOWER := Structures.HERO_SPOT       # подножие башни героя — как во вступлении
const FALL_FROM := 300.0
const FALL_TIME := 2.0
const BLACK_TIME := 0.6
const DEEP_INSIDE := 10.0                 # зашёл в пещеру глубже этого — «был внутри», м

var player: CharacterBody3D
var screen: ShaderMaterial
var was_inside := false
var done := false
var falling := false
var waking := false
var t := 0.0
var wind := Synth.WindRoar.new()


func setup(p_player: CharacterBody3D, p_screen: ShaderMaterial) -> void:
	player = p_player
	screen = p_screen


func _ready() -> void:
	wind.volume_db = 2.0
	add_child(wind)


func _process(delta: float) -> void:
	if done or player == null:
		return
	if not falling:
		var local := Mountain.cave_local(player.global_position)
		var depth := -local.z
		if depth > DEEP_INSIDE and absf(local.x) < Mountain.CAVE_HALF_W:
			was_inside = true
		elif was_inside and depth < -2.0 and not player.locked and not player.flying:
			_start()
		return
	t += delta
	var speed := -player.velocity.y
	player.fall_shake = clampf(speed / 50.0, 0.0, 1.0) * 0.5
	player.panic = clampf(0.35 + speed / 55.0, 0.0, 1.0)   # тело заваливается, как во вступлении
	wind.fill(clampf(speed / 55.0, 0.5, 1.0))
	if t >= FALL_TIME and not waking:
		waking = true
		_wake_above_clouds()


## Вышел из пещеры — срыв кадра, и он уже падает с крыши.
func _start() -> void:
	falling = true
	t = 0.0
	screen.set_shader_parameter("glitch", 1.0)
	screen.set_shader_parameter("glitch_seed", randf() * 100.0)
	get_tree().create_timer(0.15).timeout.connect(func() -> void: screen.set_shader_parameter("glitch", 0.0))
	if Game.smoke:
		Game.smoke.put_away()
	player.fall_on_back(TOWER + Vector3.UP * FALL_FROM, 32.0)
	wind.start()


## Чернота, ветер обрывается — и он на тропе над облаками, лицом вверх по тропе.
func _wake_above_clouds() -> void:
	screen.set_shader_parameter("blackout", 1.0)
	wind.stop()
	player.end_fall()
	var height := MountainFeatures.FAREWELL_HEIGHT
	var at := Mountain.path_point(Mountain.fraction_at_height(height) - 0.014)
	var forward := -at.basis.z
	var spot := at.origin + Vector3.UP * 0.3
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.last_safe = spot
	player.lying = 0.0
	var yaw := atan2(-forward.x, -forward.z)
	player.rotation.y = yaw
	player.target_yaw = yaw
	var tween := create_tween()
	tween.tween_interval(BLACK_TIME)
	tween.tween_method(func(v: float) -> void: screen.set_shader_parameter("blackout", v), 1.0, 0.0, 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		player.locked = false
		falling = false
		done = true)

