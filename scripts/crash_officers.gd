extends Node3D

## Офицеры у разбитой машины (вступление): герой очнулся — из глубины площади к горящим обломкам приближаются
## семеро в красной форме. Они не бегут: каждую секунду каждый рывком переносится ближе, застывший посреди бега
## (новый застывший кадр на каждом шаге). Дойдя, замирает по-своему — присел, говорит, навытяжку, руки за
## спиной, с пистолетом. Всё неподвижно, как манекены; героя они не замечают.

const MODEL := preload("res://assets/characters/officer/officer.glb")
const CAR := Vector3(7.5, 0.0, 77.5)    # где лежит машина (crash_car.gd)
const HOP_EVERY := 1.0                  # раз в столько секунд — рывок ближе
const HOPS := Vector2i(5, 8)            # за столько рывков доходят (у каждого своё)
## откуда бежит (x, z), где встаёт у машины (смещение от неё), во что замирает, задержка старта
const SQUAD := [
	[Vector2(-3, 32), Vector2(-5.5, -3.0), "Crouch_Idle", 0.0],
	[Vector2(6, 22), Vector2(1.0, -6.5), "Idle_Talking", 0.6],
	[Vector2(-9, 40), Vector2(-6.5, 2.5), "Stand_HandsBehind", 1.1],
	[Vector2(14, 30), Vector2(6.0, -3.5), "Pistol_Idle", 0.3],
	[Vector2(1, 12), Vector2(-2.5, -6.5), "Fixing_Kneeling", 1.6],
	[Vector2(-14, 26), Vector2(-7.0, -1.0), "Idle_Torch", 2.0],
	[Vector2(10, 14), Vector2(4.0, -7.0), "Idle", 2.5],
]

var runners: Array[Dictionary] = []


func start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for entry in SQUAD:
		var body: Node3D = MODEL.instantiate()
		add_child(body)
		var from := Vector3(entry[0].x, 0.0, entry[0].y)
		var to := CAR + Vector3(entry[1].x, 0.0, entry[1].y)
		body.global_position = from
		_face(body, to)
		body.visible = false
		var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
		runners.append({"body": body, "anim": anim, "from": from, "to": to, "pose": entry[2], "wait": entry[3],
			"hops": rng.randi_range(HOPS.x, HOPS.y), "hop": 0, "run": "Sprint" if rng.randf() < 0.5 else "Jog_Fwd",
			"state": 0, "rng": rng.randi()})


func _face(body: Node3D, at: Vector3) -> void:
	var d := at - body.global_position
	body.rotation.y = atan2(d.x, d.z)   # модель смотрит в +Z


func _process(delta: float) -> void:
	for r in runners:
		if r.state == 2:
			continue
		r.wait -= delta
		if r.wait > 0.0:
			continue
		r.wait = HOP_EVERY
		var body: Node3D = r.body
		r.hop += 1
		var k: float = float(r.hop) / r.hops
		if r.state == 0:   # появился — сразу застывший посреди бега, у дальнего края площади
			r.state = 1
			body.visible = true
			k = 0.0
		body.global_position = (r.from as Vector3).lerp(r.to, k)
		if k >= 1.0:
			_face(body, CAR)   # дошёл — лицом к огню, замер в своей позе
			r.state = 2
			_freeze(r.anim, r.pose, 0.35)
		else:
			_face(body, r.to)
			_freeze(r.anim, r.run, randf())   # новый застывший кадр бега на каждом рывке


## Поза — один застывший кадр анимации (at — доля её длины).
func _freeze(anim: AnimationPlayer, name: String, at: float) -> void:
	if not anim.has_animation(name):
		name = "Idle"
	anim.play(name)
	anim.seek(anim.get_animation(name).length * at, true)
	anim.pause()
