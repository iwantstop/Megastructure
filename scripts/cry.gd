extends RefCounted

## Тихий плач из кода (ангел при прощании, presence.gd): всхлипы «ых-ых-ых», прерывистый вдох,
## тонкое «мм…» и ещё пара всхлипов затихая. Голос — дрожащий тон ~300 Гц с придыханием, пропущенный
## через «резонаторы рта» (форманты): так шум и тон звучат как голос, а не как писк.

const RATE := Synth.MIX_RATE

# Звуки по порядку: [начало, длина, вид, тон в начале, тон в конце, громкость].
# Виды: "sob" — всхлип «ых», "inhale" — прерывистый вдох, "hum" — тонкое «мм» с закрытым ртом.
const PHRASE := [
	[0.00, 0.22, "sob", 340.0, 300.0, 0.9],
	[0.34, 0.20, "sob", 330.0, 290.0, 0.8],
	[0.66, 0.26, "sob", 320.0, 280.0, 0.85],
	[1.05, 0.65, "inhale", 0.0, 0.0, 0.55],
	[1.85, 0.95, "hum", 310.0, 250.0, 0.7],
	[3.00, 0.20, "sob", 300.0, 270.0, 0.55],
	[3.32, 0.24, "sob", 290.0, 255.0, 0.45],
	[3.75, 0.80, "exhale", 0.0, 0.0, 0.35],
]
const LENGTH := 4.8


## Звук плача (около 5 с).
static func sound() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * LENGTH))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var phase := 0.0
	var soft := 0.0          # сглаженный голосовой тон — без «жужжания»
	var f1 := Resonator.new()
	var f2 := Resonator.new()
	var f3 := Resonator.new()
	for i in samples.size():
		var t := i / RATE
		var part = _part_at(t)
		if part == null:
			samples[i] = f1.step(0.0) + f2.step(0.0) + f3.step(0.0)  # хвост резонаторов затихает
			continue
		var k: float = (t - part[0]) / part[1]               # 0..1 внутри звука
		var kind: String = part[2]
		var gain: float = part[5]
		var noise := rng.randf() * 2.0 - 1.0
		var source := 0.0
		if kind == "sob" or kind == "hum":
			# Тон падает к концу звука и дрожит (голос срывается).
			var f0 := lerpf(part[3], part[4], k) * (1.0 + 0.035 * sin(TAU * 7.0 * t) + 0.02 * sin(TAU * 13.0 * t))
			phase = fmod(phase + f0 / RATE, 1.0)
			soft += ((1.0 - 2.0 * phase) - soft) * 0.25
			var breath := 0.55 if kind == "sob" else 0.25
			source = soft * (1.0 - breath) + noise * breath
			if kind == "sob":
				f1.tune(650.0 + 150.0 * (1.0 - k), 140.0)   # «ы-х»: рот приоткрыт
				f2.tune(1250.0, 160.0)
				f3.tune(2600.0, 250.0)
			else:
				f1.tune(320.0, 90.0)                       # «мм»: рот закрыт, звук в нос
				f2.tune(1000.0, 200.0)
				f3.tune(2300.0, 300.0)
		else:
			# Вдох — шипящий шум, прерывается тремя «рывками»; выдох — мягкий и ровный.
			source = noise
			if kind == "inhale":
				source *= 0.55 + 0.45 * absf(sin(PI * 3.0 * k))
				f1.tune(1500.0 + 900.0 * k, 600.0)
			else:
				f1.tune(900.0, 700.0)
			f2.tune(2400.0, 800.0)
			f3.tune(3800.0, 900.0)
		# Огибающая: мягкий вход и выход, у всхлипа — резкий толчок в начале.
		var env := sin(PI * k)
		if kind == "sob":
			env = minf(k * 12.0, 1.0) * pow(1.0 - k, 1.6)
		var x := source * env * gain
		samples[i] = (f1.step(x) * 1.0 + f2.step(x) * 0.6 + f3.step(x) * 0.25) * 0.5
	return Synth.wav_from(samples)


static func _part_at(t: float) -> Variant:
	for part in PHRASE:
		if t >= part[0] and t < part[0] + part[1]:
			return part
	return null


## Резонатор (двухполюсный фильтр): пропускает полосу вокруг частоты — одна «форманта» голоса.
class Resonator:
	var a1 := 0.0
	var a2 := 0.0
	var b0 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func tune(freq: float, bandwidth: float) -> void:
		var r := exp(-PI * bandwidth / Synth.MIX_RATE)
		a1 = 2.0 * r * cos(TAU * freq / Synth.MIX_RATE)
		a2 = -r * r
		b0 = 1.0 - r

	func step(x: float) -> float:
		var y := b0 * x + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		return y
