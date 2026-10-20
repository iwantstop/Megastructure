extends CharacterBody3D

## Игрок от первого лица с камерой «на груди», как у бодикамеры.
## Мышь управляет «целевым» поворотом, а камера плавно догоняет его с небольшой задержкой.
## Умеет сам шагать на бордюры и ступеньки.
## Режим полёта включается из админ-панели (F1) или клавишей F.

const WALK_SPEED := 4.0
const RUN_SPEED := 8.0
const JUMP_VELOCITY := 3.3
const MOUSE_SENSITIVITY := 0.0025
const LOOK_SMOOTHING := 14.0  # чем меньше, тем сильнее задержка поворота
const EYE_HEIGHT := 1.5       # камера на груди, чуть ниже глаз
const STEP_HEIGHT := 0.35     # на сколько можно шагнуть вверх без прыжка
const BREATH_PERIOD := 5.0    # секунд на один вдох-выдох
const ROLL_STRENGTH := 1.08   # сила крена камеры при поворотах и шагах вбок
const MAX_FALL_SPEED := 55.0  # предельная скорость падения, м/с

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var head: Node3D
var camera: Camera3D
var collision: CollisionShape3D

var flying := false
var fly_speed := 20.0
var locked := false   # во вступлении: осматриваться можно, ходить — нет
var lying := 0.0      # 1 — лежит на спине и смотрит в небо, 0 — стоит
var kneeling := 0.0   # 1 — стоит на коленях (финал на вершине)
var fall_shake := 0.0  # тряска от встречного ветра при падении (вступление)
var turn_roll_scale := 1.0  # крен при повороте камеры (админ-панель): 1 — как задумано, 0 — без крена
var bob_scale := 1.0   # покачивание при ходьбе (админ-панель): 1 — как задумано, 0 — нет
var panic := 0.0       # паника в падении: крупная дрожь, кувырок по крену, шире обзор (вступление)
var panic_look := Vector2.ZERO  # резкие рывки головы в панике: x — вбок, y — вверх-вниз, рад

# Куда смотрим по мыши; тело и голова плавно догоняют.
var target_yaw := 0.0
var target_pitch := 0.0

# Состояние камеры.
var noise := FastNoiseLite.new()
var shake_time := 0.0
var step_phase := 0.0
var breath_phase := 0.0
var walk_amount := 0.0    # сглаженная «сила» ходьбы: 0 стоим, 1 идём, 2 бежим
var tilt := 0.0
var strafe_tilt := 0.0
var land_dip := 0.0
var move_input := Vector2.ZERO
var was_on_floor := true
var fall_speed := 0.0
var last_safe := Vector3.ZERO
var safe_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	target_yaw = rotation.y
	last_safe = position

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision = CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)

	camera = Camera3D.new()
	camera.fov = 85
	camera.far = 8000
	head.add_child(camera)
	camera.make_current()

	noise.frequency = 0.05
	noise.seed = randi()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_flying(on: bool) -> void:
	flying = on
	velocity = Vector3.ZERO


func set_noclip(on: bool) -> void:
	collision.disabled = on


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		target_yaw -= event.relative.x * MOUSE_SENSITIVITY
		target_pitch = clampf(target_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-89), deg_to_rad(89))
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1
	move_input = Vector2.ZERO if locked else input.normalized()

	if flying:
		_fly(move_input, delta)
		return

	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -MAX_FALL_SPEED)
		fall_speed = -velocity.y
	elif Input.is_physical_key_pressed(KEY_SPACE) and not locked:
		velocity.y = JUMP_VELOCITY

	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	var dir := transform.basis * Vector3(move_input.x, 0, move_input.y)
	var accel := 10.0 if is_on_floor() else 2.0
	velocity.x = lerpf(velocity.x, dir.x * speed, accel * delta)
	velocity.z = lerpf(velocity.z, dir.z * speed, accel * delta)
	_step_up(delta)
	move_and_slide()

	# Приземление — камера проседает.
	if is_on_floor() and not was_on_floor and fall_speed > 2.0:
		land_dip = clampf(fall_speed * 0.015, 0.0, 0.1)
	was_on_floor = is_on_floor()

	# Сорвался в бездну — возвращаемся туда, где твёрдо стоял полсекунды назад.
	if is_on_floor():
		safe_timer -= delta
		if safe_timer <= 0.0:
			last_safe = global_position
			safe_timer = 0.5
	if global_position.y < -150.0:
		global_position = last_safe + Vector3.UP * 0.5
		velocity = Vector3.ZERO


## Если впереди невысокое препятствие (бордюр, ступенька) — шагаем на него.
func _step_up(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if horizontal.length() < 0.3 or not is_on_floor():
		return
	var motion := horizontal.normalized() * maxf(horizontal.length() * delta, 0.08)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit):
		return
	if hit.get_normal().y > 0.7:
		return  # это пологий пандус — по нему и так можно идти
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return  # над головой потолок
	var raised := global_transform.translated(up)
	if test_move(raised, motion):
		return  # впереди стена, а не ступенька
	var ahead := raised.translated(motion)
	var landing := KinematicCollision3D.new()
	if test_move(ahead, -up, landing) and landing.get_normal().y > 0.7:
		global_position = ahead.origin + landing.get_travel()


## Полёт туда, куда смотришь. Space — вверх, Ctrl — вниз, Shift — быстрее.
func _fly(input: Vector2, delta: float) -> void:
	var dir := camera.global_transform.basis * Vector3(input.x, 0, input.y)
	if Input.is_physical_key_pressed(KEY_SPACE):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_CTRL):
		dir.y -= 1
	var speed := fly_speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var target := dir.normalized() * speed if dir.length() > 0.01 else Vector3.ZERO
	velocity = velocity.lerp(target, 8.0 * delta)
	move_and_slide()


# --- Камера ------------------------------------------------------------------

func _process(delta: float) -> void:
	# Плавно догоняем поворот мыши.
	var follow := 1.0 - exp(-LOOK_SMOOTHING * delta)
	var yaw_gap := angle_difference(rotation.y, target_yaw)
	rotation.y += yaw_gap * follow
	head.rotation.x = lerpf(head.rotation.x, target_pitch, follow)

	shake_time += delta
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor() and not flying
	var moving := clampf(flat_speed / WALK_SPEED, 0.0, 2.0) if grounded else 0.0
	walk_amount = lerpf(walk_amount, moving, 5.0 * delta)
	# На бегу шаг длиннее, а раскачка почти не растёт — иначе укачивает.
	var run := clampf((flat_speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var stride := lerpf(3.4, 5.2, run)
	if grounded:
		step_phase += flat_speed * delta * TAU / stride
	var amp := (minf(walk_amount, 1.0) + maxf(walk_amount - 1.0, 0.0) * 0.2) * bob_scale

	# Лёгкий наклон в сторону поворота: чем быстрее поворачиваешь, тем сильнее, но не больше 2°.
	var roll := ROLL_STRENGTH * turn_roll_scale
	var tilt_target := clampf(-yaw_gap * 0.25 * roll, -0.035 * roll, 0.035 * roll)
	tilt = lerpf(tilt, tilt_target, 4.0 * delta)
	strafe_tilt = lerpf(strafe_tilt, -move_input.x * 0.015 * ROLL_STRENGTH, 4.0 * delta)
	land_dip = lerpf(land_dip, 0.0, 7.0 * delta)

	var sway := sin(step_phase)          # влево-вправо, один цикл на два шага
	var bounce := sin(step_phase) ** 2   # плавный подскок на каждом шаге
	var shake := amp * 0.3 + fall_shake  # лёгкая тряска на ходу; сильная — в свободном падении

	# В покое — только медленное дыхание.
	breath_phase += delta * TAU / BREATH_PERIOD
	var breath := sin(breath_phase) * (1.0 - clampf(walk_amount, 0.0, 1.0))

	# Лёжа: камера у самой земли, взгляд в небо, голова чуть завалена набок.
	var lie := lying * lying * (3.0 - 2.0 * lying)
	var kneel := kneeling * kneeling * (3.0 - 2.0 * kneeling)
	camera.position = Vector3(
		sway * 0.014 * amp,
		-bounce * 0.022 * amp + breath * 0.008 - land_dip - 1.25 * lie - 0.75 * kneel,
		0.3 * lie)
	camera.rotation = Vector3(
		-bounce * 0.004 * amp + breath * 0.003 + _shake(0.0) * 0.01 * shake + 1.05 * lie,
		_shake(100.0) * 0.01 * shake,
		tilt + strafe_tilt + sway * 0.006 * amp + _shake(200.0) * 0.008 * shake + 0.25 * lie)
	if panic > 0.0:
		camera.rotation += Vector3(
			panic_look.y + _shake(300.0) * 0.07 * panic,
			panic_look.x + _shake(400.0) * 0.09 * panic,
			_shake(500.0) * 0.22 * panic)
	camera.fov = 85.0 + 18.0 * panic


## Плавный шум для тряски: медленная «качка» плюс мелкая дрожь.
func _shake(offset: float) -> float:
	return noise.get_noise_2d(shake_time * 16.0, offset) + 0.2 * noise.get_noise_2d(shake_time * 50.0, offset + 50.0)
