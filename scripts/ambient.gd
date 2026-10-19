extends AudioStreamPlayer

## Временный эмбиент, синтезируется прямо в коде, пока нет своей музыки.
## Мягкий светлый пэд (каждая нота медленно «дышит») и редкие тихие ноты, как капли.

const MIX_RATE := 22050.0
const CHORD_TIME := 18.0
const CHORDS := [
	[130.81, 196.0, 246.94, 329.63, 392.0],   # Cmaj7
	[220.0, 261.63, 329.63, 392.0, 493.88],   # Am7
	[174.61, 220.0, 261.63, 329.63, 440.0],   # Fmaj7
	[196.0, 246.94, 293.66, 329.63, 493.88],  # G6
]
const DROPS := [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]  # пентатоника

var playback: AudioStreamGeneratorPlayback
var freqs := PackedFloat32Array()
var phases := PackedFloat32Array()
var lfo_speeds := PackedFloat32Array()
var lfo_offsets := PackedFloat32Array()
var chord_index := 0
var chord_timer := 0.0
var t := 0.0

var drop_freq := 0.0
var drop_phase := 0.0
var drop_age := 10.0
var next_drop := 4.0


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.5
	stream = generator
	volume_db = -12.0

	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.85
	reverb.damping = 0.5
	reverb.wet = 0.4
	AudioServer.add_bus_effect(0, reverb)

	var voices: int = CHORDS[0].size()
	freqs.resize(voices)
	phases.resize(voices)
	lfo_speeds.resize(voices)
	lfo_offsets.resize(voices)
	for i in voices:
		freqs[i] = CHORDS[0][i]
		lfo_speeds[i] = TAU / randf_range(10.0, 18.0)
		lfo_offsets[i] = randf() * TAU

	play()
	playback = get_stream_playback()


func _process(delta: float) -> void:
	chord_timer += delta
	if chord_timer > CHORD_TIME:
		chord_timer = 0.0
		chord_index = (chord_index + 1) % CHORDS.size()
	var chord: Array = CHORDS[chord_index]

	next_drop -= delta
	if next_drop <= 0.0:
		next_drop = randf_range(2.5, 7.0)
		drop_freq = DROPS.pick_random()
		drop_phase = 0.0
		drop_age = 0.0

	var dt := 1.0 / MIX_RATE
	for frame in playback.get_frames_available():
		t += dt
		var left := 0.0
		var right := 0.0
		for i in freqs.size():
			var envelope := sin(t * lfo_speeds[i] + lfo_offsets[i])
			var amp := envelope * envelope
			if amp < 0.0005:
				freqs[i] = chord[i]
			phases[i] = fmod(phases[i] + freqs[i] * dt, 1.0)
			var p := phases[i] * TAU
			var v := (sin(p) + 0.1 * sin(p * 2.0)) * amp
			# Голоса чуть разнесены по каналам — звук шире.
			if i % 2 == 0:
				left += v
				right += v * 0.6
			else:
				left += v * 0.6
				right += v

		if drop_age < 5.0:
			drop_age += dt
			drop_phase = fmod(drop_phase + drop_freq * dt, 1.0)
			var env := minf(drop_age * 100.0, 1.0) * exp(-drop_age * 1.8)
			var dp := drop_phase * TAU
			var dv := (sin(dp) + 0.3 * sin(dp * 2.0) + 0.1 * sin(dp * 3.0)) * env * 0.5
			left += dv
			right += dv

		playback.push_frame(Vector2(left, right) * 0.1)
