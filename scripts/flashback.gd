extends Node

## Вспышка-воспоминание на выходе из пещеры. Герой вышел из «квартиры» наружу — и его снова
## швыряет в падение с небоскрёба: на спине, взгляд на удаляющуюся крышу, ревёт ветер — 2 секунды,
## чтобы напрячь. Потом чернота, ветер обрывается — и он приходит в себя на тропе над облаками,
## недалеко от уступа, где его ждёт ангел (прощание — presence.gd).

const TOWER := Vector3(4, 0, 86)          # подножие башни героя — как во вступлении
const FALL_FROM := 300.0
const FALL_TIME := 2.0
const BLACK_TIME := 0.6
const DEEP_INSIDE := 10.0                 # зашёл в пещеру глубже этого — «был внутри», м
const MIX_RATE := 22050.0

var player: CharacterBody3D
var screen: ShaderMaterial
var cave_inverse: Transform3D
var was_inside := false
var done := false
var falling := false
var waking := false
var t := 0.0
var wind: AudioStreamPlayer
var wind_playback: AudioStreamGeneratorPlayback
var lp := 0.0
var lp2 := 0.0
var wind_t := 0.0


func setup(p_player: CharacterBody3D, p_screen: ShaderMaterial) -> void:
	player = p_player
	screen = p_screen


func _ready() -> void:
	cave_inverse = Mountain.cave_frame().affine_inverse()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.25
	wind = AudioStreamPlayer.new()
	wind.stream = generator
	wind.volume_db = 2.0
	add_child(wind)


func _process(delta: float) -> void:
	if done or player == null:
		return
	if not falling:
		var local := cave_inverse * player.global_position
		var depth := -local.z
		if depth > DEEP_INSIDE and absf(local.x) < Mountain.CAVE_HALF_W:
			was_inside = true
		elif was_inside and depth < -2.0 and not player.locked and not player.flying:
			_start()
		return
	t += delta
	var speed := -player.velocity.y
	player.fall_shake = clampf(speed / 50.0, 0.0, 1.0) * 2.5
	_fill_wind(clampf(speed / 55.0, 0.5, 1.0))
	if t >= FALL_TIME and not waking:
		waking = true
		_wake_above_clouds()


## Вышел из пещеры — срыв кадра, и он уже падает с крыши.
func _start() -> void:
	falling = true
	t = 0.0
	player.locked = true
	screen.set_shader_parameter("glitch", 1.0)
	screen.set_shader_parameter("glitch_seed", randf() * 100.0)
	get_tree().create_timer(0.15).timeout.connect(func() -> void: screen.set_shader_parameter("glitch", 0.0))
	var smoke := get_tree().get_first_node_in_group("smoke")
	if smoke:
		smoke.put_away()
	player.global_position = TOWER + Vector3.UP * FALL_FROM
	player.velocity = Vector3(0, -32, 0)
	player.lying = 1.0          # на спине, лицом вверх — к крыше
	player.rotation.y = PI
	player.target_yaw = PI
	player.target_pitch = 0.0
	wind.play()
	wind_playback = wind.get_stream_playback()


## Чернота, ветер обрывается — и он на тропе над облаками, лицом вверх по тропе.
func _wake_above_clouds() -> void:
	screen.set_shader_parameter("blackout", 1.0)
	wind.stop()
	player.fall_shake = 0.0
	var features := get_tree().get_first_node_in_group("mountain_features")
	var height: float = features.FAREWELL_HEIGHT if features else 428.0
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


## Рёв ветра: шум, громче и «ярче» с ростом скорости, с порывами (как во вступлении).
func _fill_wind(level: float) -> void:
	if wind_playback == null:
		return
	var bright := lerpf(0.05, 0.35, level)
	for frame in wind_playback.get_frames_available():
		wind_t += 1.0 / MIX_RATE
		lp += (randf() * 2.0 - 1.0 - lp) * bright
		lp2 += (lp - lp2) * bright
		var gust := 0.75 + 0.25 * sin(wind_t * 1.7) * sin(wind_t * 0.6)
		var s := lp2 * level * gust * 2.2
		wind_playback.push_frame(Vector2(s, s * 0.92))
