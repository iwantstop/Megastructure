extends Node

## Звук мира по зонам, шаги и музыка.
## - Петли: дождь на улицах, дождь в переулках (капли по металлу), далёкие машины, ветер. На мосту ветер
##   постепенно перекрывает шум города — к середине моста город затихает совсем. Громкость каждой
##   плавно подстраивается под зону (город / высота / мост / гора / над облаками / пещера) и под погоду пути.
## - В пещере уличные звуки глохнут (фильтр на шине Ambience), внутри слышны телевизор, часы, гул (Interior).
## - Шаги — тихие, синтезированные: асфальт, камень, гравий, паркет; эхо сильнее на мосту и в пещере (шина Steps).
## - Музыка — генеративное пианино: редкие фразы из нескольких нот в миноре, над облаками светлее (шина Music
##   с большим залом-эхом; эхо — только у музыки, а не у всего звука игры).

const Structures = preload("res://scripts/structures.gd")
const MIX_RATE := Synth.MIX_RATE
const STEP_DB := -21.0          # шаги тихие
const CITY_STEP_BOOST := 3.0    # под дождём в городе — чуть громче, иначе их не слышно
const MUSIC_DB := -15.0
const LOOPS := {
	"rain": "res://assets/sounds/rain_city.ogg",
	"alley": "res://assets/sounds/rain_alley.ogg",
	"traffic": "res://assets/sounds/traffic_far.ogg",
	"wind": "res://assets/sounds/wind.ogg",
}
const SCALE_LOW := [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 659.25]   # ля минор
const SCALE_HIGH := [261.63, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25, 783.99]  # над облаками — светлее

var player: CharacterBody3D
var journey: Node
var loops := {}                  # имя -> AudioStreamPlayer
var steps := {}                  # поверхность -> [AudioStreamWAV]
var last_step := 0
var notes := {}                  # частота -> AudioStreamWAV (готовятся по одной за кадр)
var pending: Array = []
var next_phrase := 12.0
var phrase: Array = []
var phrase_timer := 0.0
var music_level := 1.0
var lowpass: AudioEffectLowPassFilter
var step_reverb: AudioEffectReverb
var rng := RandomNumberGenerator.new()


## Шины звука — до того, как кто-то начнёт в них играть.
static func make_buses() -> void:
	if AudioServer.get_bus_index("Ambience") >= 0:
		return
	for bus_name in ["Ambience", "Interior", "Steps", "Music", "Ads"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambience"), lp)
	var room := AudioEffectReverb.new()
	room.room_size = 0.45
	room.wet = 0.25
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Interior"), room)
	var echo := AudioEffectReverb.new()
	echo.predelay_msec = 90.0
	echo.room_size = 0.8
	echo.damping = 0.4
	echo.wet = 0.2
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Steps"), echo)
	var hall := AudioEffectReverb.new()
	hall.room_size = 0.85
	hall.damping = 0.5
	hall.wet = 0.4
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), hall)
	# Реклама: громкоговоритель (только середина частот, чуть хрипит) и эхо улиц между башнями.
	var ads := AudioServer.get_bus_index("Ads")
	var low_cut := AudioEffectHighPassFilter.new()
	low_cut.cutoff_hz = 380.0
	AudioServer.add_bus_effect(ads, low_cut)
	var high_cut := AudioEffectLowPassFilter.new()
	high_cut.cutoff_hz = 3200.0
	AudioServer.add_bus_effect(ads, high_cut)
	var horn := AudioEffectDistortion.new()
	horn.mode = AudioEffectDistortion.MODE_OVERDRIVE
	horn.drive = 0.35
	horn.post_gain = -1.0
	AudioServer.add_bus_effect(ads, horn)
	var street := AudioEffectReverb.new()
	street.predelay_msec = 140.0
	street.predelay_feedback = 0.45
	street.room_size = 0.95
	street.damping = 0.35
	street.spread = 1.0
	street.dry = 0.8
	street.wet = 0.55
	AudioServer.add_bus_effect(ads, street)


func setup(p_player: CharacterBody3D, p_journey: Node) -> void:
	player = p_player
	journey = p_journey


func _ready() -> void:
	rng.randomize()
	make_buses()
	lowpass = AudioServer.get_bus_effect(AudioServer.get_bus_index("Ambience"), 0) as AudioEffectLowPassFilter
	step_reverb = AudioServer.get_bus_effect(AudioServer.get_bus_index("Steps"), 0) as AudioEffectReverb
	for loop_name in LOOPS:
		var stream: AudioStreamOggVorbis = load(LOOPS[loop_name])
		stream.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Ambience"
		p.volume_db = -60.0
		add_child(p)
		p.play(rng.randf() * 50.0)  # петли с разных мест — не звучат одинаково
		loops[loop_name] = p
	for surface in ["concrete", "gravel", "stone", "wood"]:
		var variants: Array = []
		for i in 4:
			variants.append(_step_sound(surface))
		steps[surface] = variants
	for f in SCALE_LOW + SCALE_HIGH:
		if not pending.has(f):
			pending.append(f)


func _process(delta: float) -> void:
	if not pending.is_empty():
		var f: float = pending.pop_back()
		notes[f] = _piano_note(f)
	if player == null:
		return
	var zone := _zone()
	var dry: float = clampf(journey.progress / 0.45, 0.0, 1.0) if journey else 0.0
	var rain := 1.0 - dry
	var y := player.global_position.y
	# Мост: чем дальше от города, тем глуше его шум (дождь по улицам, машины) и тем сильнее ветер —
	# к середине моста ветер перекрывает город целиком: город «отпускает» героя.
	var away := _bridge_away()
	var target := {
		"rain": {"city": 0.9, "bridge": lerpf(0.6, 0.15, away), "cave": 0.0}.get(zone, 0.0) * rain,
		"alley": (0.7 * (1.0 - smoothstep(10.0, 45.0, y)) if zone == "city" else 0.0) * rain,
		"traffic": {"city": 0.55 + 0.3 * smoothstep(20.0, 120.0, y), "bridge": 0.55 * (1.0 - away)}.get(zone, 0.0),
		"wind": {"city": 0.15 + 0.5 * smoothstep(30.0, 150.0, y), "bridge": lerpf(0.3, 1.0, away), "mountain": 0.8, "high": 0.45, "cave": 0.12}.get(zone, 0.5),
	}
	for loop_name in loops:
		var p: AudioStreamPlayer = loops[loop_name]
		var current := db_to_linear(p.volume_db)
		var want: float = target[loop_name] * 0.8
		p.volume_db = linear_to_db(maxf(move_toward(current, want, delta * 0.4), 0.0005))
	# В пещере улица слышна глухо; эхо шагов — по зоне.
	lowpass.cutoff_hz = lerpf(lowpass.cutoff_hz, 700.0 if zone == "cave" else 20000.0, delta * 2.0)
	step_reverb.wet = lerpf(step_reverb.wet, {"bridge": 0.45, "cave": 0.5, "city": 0.15}.get(zone, 0.2), delta)
	music_level = move_toward(music_level, 0.0 if zone == "cave" else 1.0, delta * 0.3)
	_footsteps(zone)
	_music(delta, zone)


## Насколько герой ушёл по мосту от города: 0 — у края города, 1 — середина моста и дальше.
func _bridge_away() -> float:
	var from := Structures.PLATFORM.position.y
	return clampf((from - player.global_position.z) / ((from - Structures.CAUSEWAY_END) * 0.55), 0.0, 1.0)


func _zone() -> String:
	var p := player.global_position
	var local := Mountain.cave_local(p)
	if -local.z > 0.0 and -local.z < Mountain.CAVE_DEPTH and absf(local.x) < Mountain.CAVE_HALF_W and absf(local.y) < 8.0:
		return "cave"
	if Structures.PLATFORM.has_point(Vector2(p.x, p.z)) and p.y < 400.0:
		return "city"
	if absf(p.x) < 15.0 and p.z < Structures.PLATFORM.position.y and p.z > Structures.CAUSEWAY_END - 20.0:
		return "bridge"
	return "high" if p.y > 420.0 else "mountain"


## Шаг — на каждом полушаге камеры (там, где «подскок» доходит до низа), только когда идёт по земле.
func _footsteps(zone: String) -> void:
	var count := int(floor(player.step_phase / PI))
	if count == last_step:
		return
	last_step = count
	if not player.is_on_floor() or player.walk_amount < 0.3 or player.flying:
		return
	var surface := "concrete"
	if zone == "mountain" or zone == "high":
		surface = "gravel"
	elif zone == "cave":
		var depth := -Mountain.cave_local(player.global_position).z
		surface = "wood" if depth > 14.0 and depth < 31.0 else "stone"
	var variants: Array = steps[surface]
	var volume := STEP_DB + (2.0 if player.walk_amount > 1.3 else 0.0) + rng.randf_range(-1.5, 1.5)
	if zone == "city":
		volume += CITY_STEP_BOOST  # в городе шаги перекрывает дождь
	Synth.play_once(self, variants[rng.randi() % variants.size()], volume, &"Steps", rng.randf_range(0.92, 1.08))


## Редкие фразы пианино: 2–5 нот случайным шагом по ладу, с паузами; над облаками — светлый лад.
func _music(delta: float, zone: String) -> void:
	if not phrase.is_empty():
		phrase_timer -= delta
		if phrase_timer <= 0.0:
			var f: float = phrase.pop_front()
			if notes.has(f) and music_level > 0.05:
				Synth.play_once(self, notes[f], MUSIC_DB + linear_to_db(music_level) + rng.randf_range(-3.0, 0.0), &"Music")
			phrase_timer = rng.randf_range(0.7, 1.5)
		return
	next_phrase -= delta
	if next_phrase > 0.0:
		return
	next_phrase = rng.randf_range(10.0, 22.0)
	var scale: Array = SCALE_HIGH if zone == "high" else SCALE_LOW
	var i := rng.randi_range(2, 5)
	for k in rng.randi_range(2, 5):
		phrase.append(scale[i])
		i = clampi(i + [-2, -1, -1, 1, 1, 2].pick_random(), 0, scale.size() - 1)
	phrase_timer = 0.0


# --- Синтез -------------------------------------------------------------------------

## Шаг: глухой удар каблука + шорох; у гравия — хруст, у паркета — пустой стук и скрип.
func _step_sound(surface: String) -> AudioStreamWAV:
	var length := int(MIX_RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(length)
	var lp := 0.0
	var thump_f := rng.randf_range(70.0, 95.0)
	for i in length:
		var t := i / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		var v := 0.0
		match surface:
			"concrete":
				# Мокрый асфальт: щелчок каблука, шлепок по воде и немного глухого удара — слышно сквозь дождь.
				lp += (noise - lp) * 0.55
				var click := noise * exp(-t * 90.0) * 0.45
				var splash := lp * exp(-t * 22.0) * (0.75 if t > 0.012 else 0.35)
				v = sin(TAU * thump_f * t) * exp(-t * 45.0) * 0.45 + click + splash
			"stone":
				lp += (noise - lp) * 0.5
				v = sin(TAU * thump_f * 1.3 * t) * exp(-t * 50.0) * 0.5 + lp * exp(-t * 35.0) * 0.6
			"gravel":
				lp += (noise - lp) * 0.6
				var grains := 1.0 if rng.randf() < 0.25 else 0.3
				v = lp * grains * exp(-t * 14.0) * 0.7 + sin(TAU * thump_f * t) * exp(-t * 40.0) * 0.3
			"wood":
				lp += (noise - lp) * 0.2
				v = sin(TAU * 180.0 * t) * exp(-t * 30.0) * 0.5 + lp * exp(-t * 25.0) * 0.3 \
					+ sin(TAU * (600.0 + 200.0 * t) * t) * exp(-t * 12.0) * 0.06
		s[i] = v
	return Synth.wav_from(s)


## Нота пианино: несколько гармоник, верхние гаснут быстрее; мягкий удар молоточка.
func _piano_note(freq: float) -> AudioStreamWAV:
	var length := int(MIX_RATE * 3.5)
	var s := PackedFloat32Array()
	s.resize(length)
	for i in length:
		var t := i / MIX_RATE
		var v := sin(TAU * freq * t) * exp(-t * 0.9) \
			+ 0.45 * sin(TAU * freq * 2.001 * t) * exp(-t * 1.6) \
			+ 0.18 * sin(TAU * freq * 3.004 * t) * exp(-t * 2.6)
		v *= minf(t * 200.0, 1.0)
		s[i] = v * 0.35
	return Synth.wav_from(s)
