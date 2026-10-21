class_name Synth
extends RefCounted

## Звук из кода — общие кирпичики для всех, кто синтезирует звуки (курение, вступление, финал, костёр, шаги…):
## - wav(): короткий звук по формуле от времени t (для звуков без «памяти» между отсчётами);
## - wav_from(): звук из готовых отсчётов (когда отсчёты зависят от предыдущих: фильтры, щелчки);
## - play_once(): проиграть и сразу убрать проигрыватель — ничего не копится в памяти;
## - WindRoar: рёв встречного ветра при падении, громче и «ярче» с ростом скорости.

const MIX_RATE := 22050.0


## Звук длиной seconds: sample(t) возвращает отсчёт -1..1 в момент t (с).
static func wav(seconds: float, sample: Callable, loop := false) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(MIX_RATE * seconds))
	for i in samples.size():
		samples[i] = sample.call(i / MIX_RATE)
	return wav_from(samples, loop)


## Звук из готовых отсчётов (-1..1, лишнее срезается).
static func wav_from(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(MIX_RATE)
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream


## Проиграть один раз; проигрыватель удаляется, как только звук закончился.
static func play_once(parent: Node, stream: AudioStream, volume_db := 0.0, bus := &"Master", pitch := 1.0) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus
	player.pitch_scale = pitch
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player


## Рёв ветра в падении: шум через два фильтра — чем выше level (0..1), тем громче и «ярче», с порывами.
## Каждый кадр — fill(level), пока звучит.
class WindRoar extends AudioStreamPlayer:
	var playback: AudioStreamGeneratorPlayback
	var lp := 0.0
	var lp2 := 0.0
	var time := 0.0

	func _init() -> void:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = MIX_RATE
		generator.buffer_length = 0.25
		stream = generator

	func start() -> void:
		play()
		playback = get_stream_playback()

	func fill(level: float) -> void:
		if playback == null:
			return
		var bright := lerpf(0.05, 0.35, level)
		for frame in playback.get_frames_available():
			time += 1.0 / MIX_RATE
			lp += (randf() * 2.0 - 1.0 - lp) * bright
			lp2 += (lp - lp2) * bright
			var gust := 0.75 + 0.25 * sin(time * 1.7) * sin(time * 0.6)
			var s := lp2 * level * gust * 2.2
			playback.push_frame(Vector2(s, s * 0.92))
