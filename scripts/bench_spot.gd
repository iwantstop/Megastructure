extends Node3D

## Скамейка у самого левого края моста, лицом к бездне (перил напротив нет — открытый обрыв), рядом — горящий
## торшер (непонятно чей и для кого).
## Подойти — «Сесть - E». Сел: герой опускается на скамейку, время вокруг ускоряется (дождь, машины, туман
## бегут быстрее), туман медленно сгущается. «Встать - E» (или W) — всё возвращается.

const SPOT := preload("res://scripts/structures.gd").BENCH_SPOT   # второй кусок моста, в 1,5 м от края, перил напротив нет
const REACH := 2.4                           # с какого расстояния можно сесть, м
const SIT_LOWER := 0.55                      # насколько ниже камера сидя (player.kneeling)
const TIME_FAST := 4.0                       # во сколько раз быстрее идёт время, пока сидишь
const SIT_TIME := 1.2
const SIT_PITCH := 0.1                       # сидя взгляд чуть вверх — поверх перил, в бездну и на башни
const HINT_SIT := "Сесть - E"
const HINT_STAND := "Встать - E"

var sitting := false
var near := false
var busy := false
var fog_tween: Tween
var sit_tween: Tween     # сесть и разогнать время — обрывается, если встал раньше


func _ready() -> void:
	position = SPOT
	rotation.y = PI / 2.0   # «вперёд» (-Z) скамейки смотрит в бездну (-X)
	var wood := Shapes.mat(Color(0.2, 0.13, 0.08), 0.75)
	var iron := Shapes.mat(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	# Скамейка: сиденье из досок, спинка, чугунные ножки.
	for k in 3:
		Shapes.box(self, Vector3(1.7, 0.035, 0.12), Vector3(0, 0.45, -0.14 + k * 0.14), wood)
	for k in 2:
		Shapes.box(self, Vector3(1.7, 0.1, 0.03), Vector3(0, 0.65 + k * 0.17, 0.24), wood)
	for side in [-0.75, 0.75]:
		Shapes.box(self, Vector3(0.05, 0.45, 0.5), Vector3(side, 0.225, 0.02), iron)
		Shapes.box(self, Vector3(0.05, 0.45, 0.05), Vector3(side, 0.7, 0.25), iron)
	# Торшер сбоку: тонкая стойка, тёплый абажур, свет.
	var lamp := Vector3(-1.25, 0, 0.1)
	Shapes.cylinder(self, 0.16, 0.16, 0.03, lamp + Vector3(0, 0.015, 0), iron)
	Shapes.cylinder(self, 0.015, 0.015, 1.55, lamp + Vector3(0, 0.79, 0), iron)
	var shade := Shapes.glow(Color(0.9, 0.75, 0.5), Color(1.0, 0.72, 0.42), 3.0)
	Shapes.cylinder(self, 0.14, 0.24, 0.28, lamp + Vector3(0, 1.62, 0), shade)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 1.8
	light.omni_range = 9.0
	light.shadow_enabled = true
	light.position = lamp + Vector3(0, 1.5, 0)
	add_child(light)


func _process(_delta: float) -> void:
	var player := Game.player
	if player == null or busy:
		return
	var p := player.global_position
	var close: bool = not sitting and Vector2(p.x - SPOT.x, p.z - SPOT.z).length() < REACH and absf(p.y - SPOT.y) < 1.5 and not player.locked
	if close != near:
		near = close
		if Game.hud:
			Game.hud.action_hint(HINT_SIT, near)


func _unhandled_input(event: InputEvent) -> void:
	if busy or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_E and near:
		get_viewport().set_input_as_handled()
		sit()
	elif sitting and (event.physical_keycode == KEY_E or event.physical_keycode == KEY_W):
		get_viewport().set_input_as_handled()
		stand()


## Сесть: на середину скамейки, лицом к бездне; время ускоряется, туман сгущается.
func sit() -> void:
	var player := Game.player
	busy = true
	near = false
	player.locked = true
	player.velocity = Vector3.ZERO
	var seat := global_transform * Vector3(0, 0, -0.05)
	seat.y = SPOT.y + 0.05
	var face := global_transform.basis * Vector3.FORWARD
	var yaw := atan2(-face.x, -face.z)
	var from_yaw: float = player.target_yaw
	var tween := create_tween().set_parallel().set_ignore_time_scale(true).set_trans(Tween.TRANS_SINE)
	sit_tween = tween
	tween.tween_property(player, "global_position", seat, SIT_TIME)
	tween.tween_property(player, "target_yaw", from_yaw + angle_difference(from_yaw, yaw), SIT_TIME)
	tween.tween_property(player, "target_pitch", SIT_PITCH, SIT_TIME)   # поверх поручня — вдаль
	tween.tween_property(player, "kneeling", SIT_LOWER, SIT_TIME)
	tween.chain().tween_callback(func() -> void:
		sitting = true
		player.seated = true   # сидя курить можно
		busy = false
		if Game.hud:
			Game.hud.action_hint(HINT_STAND, true))
	tween.chain().tween_method(_set_time, 1.0, TIME_FAST, 3.0)
	_fog_to(1.0, 12.0)


## Встать: время снова обычное, туман редеет, управление возвращается.
func stand() -> void:
	var player := Game.player
	busy = true
	sitting = false
	player.seated = false
	if Game.hud:
		Game.hud.action_hint(HINT_STAND, false)
	if sit_tween:
		sit_tween.kill()   # встал раньше, чем время разогналось, — разгон не должен продолжиться после
	var tween := create_tween().set_parallel().set_ignore_time_scale(true).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_set_time, Engine.time_scale, 1.0, 1.0)
	tween.tween_property(player, "kneeling", 0.0, SIT_TIME)
	tween.chain().tween_callback(func() -> void:
		Engine.time_scale = 1.0
		player.locked = false
		busy = false)
	_fog_to(0.0, 5.0)


func _set_time(scale: float) -> void:
	Engine.time_scale = scale


func _fog_to(value: float, seconds: float) -> void:
	if Game.journey == null:
		return
	if fog_tween:
		fog_tween.kill()
	fog_tween = create_tween().set_ignore_time_scale(true)
	fog_tween.tween_property(Game.journey, "fog_boost", value, seconds).set_trans(Tween.TRANS_SINE)


func _exit_tree() -> void:
	Engine.time_scale = 1.0   # уходя (перезапуск, выход) — время снова обычное
