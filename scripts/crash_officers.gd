extends Node3D

## Офицеры у разбитой машины (вступление): герой очнулся — из глубины площади к горящим обломкам бегут
## семеро в красной форме. Добежав, каждый замирает по-своему: кто-то присел у обломков, кто-то говорит,
## кто-то стоит навытяжку, руки за спиной, кто-то держит пистолет наготове. Героя они не замечают.

const MODEL := preload("res://assets/characters/officer/officer.glb")
const CAR := Vector3(7.5, 0.0, 77.5)    # где лежит машина (crash_car.gd)
const RUN_SPEED := Vector2(4.6, 6.4)    # бегут по-разному
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
		var fast := rng.randf() < 0.5
		runners.append({"body": body, "anim": anim, "to": to, "pose": entry[2], "wait": entry[3],
			"speed": rng.randf_range(RUN_SPEED.x, RUN_SPEED.y), "run": "Sprint" if fast else "Jog_Fwd", "state": 0})


func _face(body: Node3D, at: Vector3) -> void:
	var d := at - body.global_position
	body.rotation.y = atan2(d.x, d.z)   # модель смотрит в +Z


func _process(delta: float) -> void:
	for r in runners:
		match r.state:
			0:   # ждёт своей очереди
				r.wait -= delta
				if r.wait <= 0.0:
					r.state = 1
					r.body.visible = true
					_loop(r.anim, r.run)
			1:   # бежит
				var body: Node3D = r.body
				var to: Vector3 = r.to
				var d := to - body.global_position
				var step: float = r.speed * delta
				if d.length() <= step:
					body.global_position = to
					_face(body, CAR)   # встал — лицом к огню
					r.state = 2
					_loop(r.anim, r.pose)
				else:
					body.global_position += d.normalized() * step


func _loop(anim: AnimationPlayer, name: String) -> void:
	if not anim.has_animation(name):
		name = "Idle"
	anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	anim.play(name, 0.3)
