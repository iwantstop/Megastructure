extends Node

## Голоса рекламы: в городе горящие билборды иногда «говорят» — обрывки из пролога. Звук идёт от самого экрана,
## через громкоговоритель (узкая полоса частот, лёгкий хрип) и с эхом улицы — где-то на фоне, над городом.
## Фразы записаны заранее голосом Windows (assets/sounds/ads), поэтому работают на любом компьютере.

const VOICES := [
	preload("res://assets/sounds/ads/ad_1.wav"), preload("res://assets/sounds/ads/ad_2.wav"),
	preload("res://assets/sounds/ads/ad_3.wav"), preload("res://assets/sounds/ads/ad_4.wav"),
	preload("res://assets/sounds/ads/ad_5.wav"), preload("res://assets/sounds/ads/ad_6.wav"),
	preload("res://assets/sounds/ads/ad_7.wav"), preload("res://assets/sounds/ads/ad_8.wav"),
]
const PAUSE := Vector2(25.0, 55.0)   # между фразами, с
const HEAR := 90.0                   # дальше этого экран не слышно, м
const PITCH := 0.84                  # ниже и медленнее записи — обезличенно
const Structures = preload("res://scripts/structures.gd")

var screens: Array[Vector3] = []
var timer := 12.0
var rng := RandomNumberGenerator.new()
var last_phrase := -1
var speaker: AudioStreamPlayer3D


func setup(ads: Array[Dictionary]) -> void:
	for ad in ads:
		screens.append((ad.xform as Transform3D).origin)
	set_meta("ads", ads)   # для проб и тестов: где какие экраны


func _ready() -> void:
	rng.randomize()
	speaker = AudioStreamPlayer3D.new()
	speaker.bus = &"Ads"
	speaker.pitch_scale = PITCH
	speaker.unit_size = 14.0
	speaker.max_distance = HEAR
	speaker.volume_db = 2.0
	add_child(speaker)


func _process(delta: float) -> void:
	if Game.player == null:
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = rng.randf_range(PAUSE.x, PAUSE.y)
	speak_nearest()


## Ближайший экран в пределах слышимости говорит фразу. Возвращает, заговорил ли.
func speak_nearest() -> bool:
	var p := Game.player.global_position
	if not Structures.PLATFORM.has_point(Vector2(p.x, p.z)) or p.y > 300.0 or Game.player.locked or speaker.playing:
		return false
	var nearest := Vector3.INF
	for screen in screens:
		if screen.distance_to(p) < nearest.distance_to(p):
			nearest = screen
	if nearest.distance_to(p) > HEAR:
		return false
	var pick := rng.randi() % VOICES.size()
	if pick == last_phrase:
		pick = (pick + 1) % VOICES.size()
	last_phrase = pick
	speaker.global_position = nearest
	speaker.stream = VOICES[pick]
	speaker.play()
	return true
