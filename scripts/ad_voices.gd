extends Node

## Голоса рекламы: в городе горящие билборды иногда «говорят» — обрывки из пролога, низким медленным голосом,
## громче, если экран близко. Голос — встроенный в Windows синтез речи (русский «Павел» или «Ирина»);
## если русского голоса в системе нет — реклама просто молчит.

const PHRASES := [
	"Меркантильность здесь возведена в культ.",
	"Эгоизм стал нормой.",
	"Духовный упадок — обыденностью.",
	"В этом мире нет места искренности.",
	"Каждый стремится обмануть другого.",
	"Ради денег. Ради минутного удовольствия.",
	"Ради самого факта победы над ближним.",
	"Разврат — едва ли не единственная форма общения.",
]
const PAUSE := Vector2(25.0, 55.0)   # между фразами, с
const HEAR := 70.0                   # дальше этого экран не слышно, м
const Structures = preload("res://scripts/structures.gd")

var screens: Array[Vector3] = []
var voice := ""
var timer := 12.0
var rng := RandomNumberGenerator.new()
var last_phrase := -1


func setup(ads: Array[Dictionary]) -> void:
	for ad in ads:
		screens.append((ad.xform as Transform3D).origin)


func _ready() -> void:
	rng.randomize()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		for wanted in ["Pavel", "Irina"]:
			for v in DisplayServer.tts_get_voices():
				if v.get("language", "").begins_with("ru") and wanted in v.get("name", ""):
					voice = v.get("id")
					break
			if voice != "":
				break


func _process(delta: float) -> void:
	if voice == "" or Game.player == null:
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = rng.randf_range(PAUSE.x, PAUSE.y)
	speak_nearest()


## Ближайший экран в пределах слышимости говорит фразу. Возвращает, заговорил ли.
func speak_nearest() -> bool:
	var p := Game.player.global_position
	if voice == "" or not Structures.PLATFORM.has_point(Vector2(p.x, p.z)) or p.y > 300.0 or Game.player.locked:
		return false
	var nearest := INF
	for screen in screens:
		nearest = minf(nearest, screen.distance_to(p))
	if nearest > HEAR:
		return false
	var pick := rng.randi() % PHRASES.size()
	if pick == last_phrase:
		pick = (pick + 1) % PHRASES.size()
	last_phrase = pick
	var loud: float = clampf(1.0 - (nearest - 10.0) / (HEAR - 10.0), 0.15, 1.0)
	var volume: float = Settings.get_value("master") * Settings.get_value("world")
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(PHRASES[pick], voice, int(100.0 * loud * volume), 0.6, 0.8)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		DisplayServer.tts_stop()   # пауза или выход — голос замолкает
