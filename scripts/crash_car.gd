extends Node3D

## Летающая машина из вступления. Герой падает с самой высокой башни и пробивает ей крышу — дальше он
## в салоне: над головой рваная дыра, мигает красная лампа, ревёт сигнализация, на приборной панели
## «ВНИМАНИЕ» и тающая высота. Машина падает как подбитый вертолёт: бешено вращается вокруг себя,
## болтается, всё трясётся, за несколько секунд — к подножию башни (CRASH), удар — дальше тьма (intro.gd).
## После удара она лежит рядом с героем и горит.
## Сама машина — без коллизии, только вид; вид из салона — своя камера (мышью можно чуть оглядеться).

signal crashed

const Structures = preload("res://scripts/structures.gd")
const IMPACT := Vector3(4.0, 300.0, 86.0)     # где герой пробивает крышу (он падает отвесно над HERO_SPOT)
const CRASH := Vector3(7.5, 0.0, 77.5)        # где машина бьётся о землю — в 9 м от героя, в сторону горы
const ROOF := 1.25                            # крыша над полом салона, м
const APPROACH_SPEED := 32.0                  # с такой скоростью машина подлетает под падающего героя, м/с
const APPROACH_FROM := Vector3(-1.0, 0.0, 0.0)  # подлетает вдоль фасада башни
const DESCENT := 5.5                          # сколько длится падение машины, с
const SPIRAL_R := 4.0                         # её мотает по небольшому кругу (у фасада башни места ~9 м)…
const SPIRAL_TURNS := 1.0
const SPIN_TURNS := 4.5                       # …а сама она крутится вокруг себя, как вертолёт без хвоста
const EYE := Vector3(0.05, 0.92, 1.2)         # глаза героя: полулёжа на заднем сиденье, под дырой в крыше
const LOOK_LIMIT := Vector2(1.2, 0.7)         # насколько можно оглядеться мышью (рад)
const ALARM_HZ := 2.4                         # мигание тревожной лампы

enum Phase { WAITING, APPROACH, FALLING, WRECK }

var phase := Phase.WAITING
var s := 0.0                                   # 0..1 — доля падения
var cam: Camera3D
var look := Vector2.ZERO
var alarm_light: OmniLight3D
var alarm_mat: StandardMaterial3D
var warn: Label3D
var altitude: Label3D
var alarm: AudioStreamPlayer
var fire_light: OmniLight3D
var flames: GPUParticles3D
var smoke: GPUParticles3D
var crackle: AudioStreamPlayer3D
var clock := 0.0
var cabin_fx: Array = []                      # дым и искры в салоне — пока машина падает
var lights: Array[StandardMaterial3D] = []    # фары, огни, подсветка — после удара гаснут
var flame_pm: ParticleProcessMaterial         # пламя: общее для остова и горящих обломков
var flame_quad: QuadMesh
var kick := 1.0                                # удар при падении на крышу: тряска сильнее и спадает


func _ready() -> void:
	visible = false
	_build_body()
	_build_cabin()
	cam = Camera3D.new()
	cam.fov = 85.0
	cam.near = 0.03
	cam.position = EYE
	add_child(cam)
	alarm = AudioStreamPlayer.new()
	alarm.stream = _siren()
	alarm.volume_db = 0.0   # ревёт
	alarm.bus = &"Interior"
	add_child(alarm)


# --- Падение -------------------------------------------------------------------

## Пока герой летит: машина подлетает так, чтобы оказаться под ним ровно к удару.
## seconds — через сколько он долетит до крыши машины.
func approach(seconds: float) -> void:
	if phase == Phase.WRECK or phase == Phase.FALLING:
		return
	phase = Phase.APPROACH
	visible = seconds < 5.0   # издалека её всё равно не видно
	var dir := APPROACH_FROM.normalized()
	position = IMPACT - dir * APPROACH_SPEED * maxf(seconds, 0.0)
	basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z))


## Удар: герой в салоне. Камера — его глаза, сигнализация, машина падает по спирали.
func begin() -> void:
	phase = Phase.FALLING
	visible = true
	s = 0.0
	kick = 1.0
	cam.make_current()
	alarm.play()
	_cabin_smoke_and_sparks()
	Synth.play_once(self, _crunch_sound(), 6.0)
	_place(0.0)


func _process(delta: float) -> void:
	clock += delta
	match phase:
		Phase.FALLING:
			s = minf(s + delta / DESCENT, 1.0)
			_place(s)
			_cabin_fx(delta)
			if s >= 1.0:
				_crash()
		Phase.WRECK:
			# Огонь дышит: свет мерцает рывками.
			fire_light.light_energy = 2.2 + sin(clock * 13.0) * 0.45 + sin(clock * 31.0) * 0.3 + randf() * 0.4


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.FALLING and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look -= event.relative * 0.0025
		look = look.clamp(-LOOK_LIMIT, LOOK_LIMIT)


## Точка спирали: от места удара к месту крушения, кругами; высота сначала тает медленно (ещё планирует),
## потом всё быстрее.
func _path(at: float) -> Vector3:
	var base := Vector2(IMPACT.x, IMPACT.z).lerp(Vector2(CRASH.x, CRASH.z), at)
	var angle := SPIRAL_TURNS * TAU * at
	var off := Vector2(cos(angle), sin(angle)) * SPIRAL_R * sin(PI * at)
	var y := lerpf(IMPACT.y, CRASH.y + 0.45, pow(at, 1.35))
	return Vector3(base.x + off.x, y, base.y + off.y)


func _place(at: float) -> void:
	var here := _path(at)
	var yaw := SPIN_TURNS * TAU * at * at * 0.8 + SPIN_TURNS * TAU * at * 0.2   # вращение разгоняется
	var dive := -0.25 - 0.2 * at + sin(clock * 9.0) * 0.12             # нос вниз, клюёт
	var bank := sin(clock * 6.5) * 0.3 + sin(clock * 17.0) * 0.06      # болтается с боку на бок
	transform = Transform3D(Basis.from_euler(Vector3(dive, yaw, bank)), here)


## В салоне: тревожная лампа, «ВНИМАНИЕ», высота, тряска камеры (это падение — трясти можно).
func _cabin_fx(delta: float) -> void:
	var on := fmod(clock * ALARM_HZ, 1.0) < 0.5
	alarm_light.light_energy = 3.0 if on else 0.15
	alarm_mat.emission_energy_multiplier = 4.0 if on else 0.3
	warn.modulate.a = 1.0 if on else 0.25
	altitude.text = "ВЫС %d м" % maxi(int(position.y), 0)
	kick = move_toward(kick, 0.0, delta * 2.5)
	var shake := 0.045 + 0.06 * s + kick * 0.25
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)) * shake * 0.5
	cam.position = EYE + jitter
	cam.rotation = Vector3(0.12 + look.y + randf_range(-1, 1) * shake, look.x + randf_range(-1, 1) * shake * 0.8,
		randf_range(-1, 1) * shake * 1.5)


## В салоне: дым валит из-под приборной панели и тянется к дыре в крыше; из панели и проводки сыплются искры.
func _cabin_smoke_and_sparks() -> void:
	var soot := StandardMaterial3D.new()
	soot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	soot.vertex_color_use_as_albedo = true
	soot.albedo_texture = Shapes.soft_dot()
	var grey := Gradient.new()
	grey.set_color(0, Color(0.25, 0.24, 0.24, 0.0))
	grey.add_point(0.15, Color(0.22, 0.21, 0.21, 0.45))
	grey.set_color(grey.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	var grey_tex := GradientTexture1D.new()
	grey_tex.gradient = grey
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(0.7, 0.1, 0.2)
	sm.direction = Vector3(0, 1, 0.8)          # вверх и назад — к дыре над задним сиденьем
	sm.spread = 25.0
	sm.initial_velocity_min = 0.4
	sm.initial_velocity_max = 0.9
	sm.gravity = Vector3(0, 0.6, 0.4)
	sm.turbulence_enabled = true
	sm.turbulence_noise_strength = 1.5
	sm.scale_min = 0.6
	sm.scale_max = 1.2
	sm.color_ramp = grey_tex
	var puff := QuadMesh.new()
	puff.size = Vector2(0.9, 0.9)
	puff.material = soot
	var smoke_in := GPUParticles3D.new()
	smoke_in.local_coords = true    # дым крутится вместе с машиной
	smoke_in.process_material = sm
	smoke_in.draw_pass_1 = puff
	smoke_in.amount = 60
	smoke_in.lifetime = 2.5
	smoke_in.preprocess = 1.0
	smoke_in.position = Vector3(0, 0.55, -1.05)
	smoke_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke_in)

	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	hot.vertex_color_use_as_albedo = true
	var spark_ramp := Gradient.new()
	spark_ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	spark_ramp.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	var spark_tex := GradientTexture1D.new()
	spark_tex.gradient = spark_ramp
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(0.6, 0.05, 0.05)
	sp.direction = Vector3(0, 0.6, 1)          # из панели — в салон
	sp.spread = 50.0
	sp.initial_velocity_min = 1.5
	sp.initial_velocity_max = 3.5
	sp.gravity = Vector3(0, -6.0, 0)
	sp.color_ramp = spark_tex
	var dot := QuadMesh.new()
	dot.size = Vector2(0.025, 0.025)
	dot.material = hot
	var sparks := GPUParticles3D.new()
	sparks.local_coords = true
	sparks.process_material = sp
	sparks.draw_pass_1 = dot
	sparks.amount = 40
	sparks.lifetime = 0.7
	sparks.explosiveness = 0.85               # пачками — коротит
	sparks.position = Vector3(0, 0.76, -1.08)
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	cabin_fx = [smoke_in, sparks]


## Удар о землю: камера — снова героя (intro дальше показывает тьму), машина ложится набок и горит.
func _crash() -> void:
	alarm.stop()
	var player := Game.player
	if player:
		player.camera.make_current()
	Synth.play_once(self, _crunch_sound(), 6.0, &"Master", 0.6)
	wreck_now()
	crashed.emit()


## Сразу разбитая и горящая (после удара или когда вступление пропущено).
func wreck_now() -> void:
	if not is_node_ready():
		wreck_now.call_deferred()   # вступление пропустили раньше, чем машина появилась в мире
		return
	if phase == Phase.WRECK:
		return
	phase = Phase.WRECK
	visible = true
	alarm.stop()
	var player := Game.player
	if player and cam.current:
		player.camera.make_current()
	# Остов: сплющен и перекошен, лежит днищем на асфальте (высота — лучом вниз), один бок задран.
	var ground := _ground_at(CRASH)
	var yaw := rotation.y if s > 0.0 else 2.3
	var crushed := Basis.from_euler(Vector3(-0.08, yaw, 0.16)) * Basis.from_scale(Vector3(1.06, 0.62, 0.9))
	transform = Transform3D(crushed, Vector3(CRASH.x, ground + 0.22, CRASH.z))
	alarm_light.light_energy = 0.0
	alarm_mat.emission_energy_multiplier = 0.0
	for m in lights:
		m.emission_energy_multiplier = 0.0
	warn.visible = false
	altitude.visible = false
	for fx in cabin_fx:
		fx.queue_free()
	cabin_fx.clear()
	_build_fire()
	_build_debris(ground)


# --- Модель --------------------------------------------------------------------

func _build_body() -> void:
	var shell := Shapes.mat(Color(0.09, 0.09, 0.11), 0.35, 0.7)
	Shapes.box(self, Vector3(2.0, 0.45, 4.7), Vector3(0, -0.24, 0), shell, false)          # днище и бока снизу
	Shapes.box(self, Vector3(1.95, 0.14, 0.95), Vector3(0, 0.52, -2.15), shell, false)       # капот
	Shapes.box(self, Vector3(1.95, 0.22, 0.45), Vector3(0, 0.5, 2.2), shell, false)          # багажник
	var head := Shapes.glow(Color(0.9, 0.9, 0.85), Color(1.0, 0.95, 0.85), 5.0)
	var tail := Shapes.glow(Color(0.5, 0.05, 0.04), Color(1.0, 0.1, 0.08), 4.0)
	var under := Shapes.glow(Color(0.1, 0.4, 0.5), Color(0.2, 0.8, 1.0), 2.5)
	lights.append_array([head, tail, under])
	for x in [-0.6, 0.6]:
		Shapes.box(self, Vector3(0.4, 0.12, 0.05), Vector3(x, 0.4, -2.37), head, false)
	Shapes.box(self, Vector3(1.7, 0.1, 0.05), Vector3(0, 0.45, 2.44), tail, false)
	Shapes.box(self, Vector3(1.5, 0.04, 3.8), Vector3(0, -0.48, 0), under, false)
	var roof_strip := Shapes.glow(Color(0.1, 0.4, 0.5), Color(0.3, 0.85, 1.0), 4.0)
	lights.append(roof_strip)
	for x in [-0.9, 0.9]:   # огни по краям крыши — сверху, из падения, её видно на тёмном городе
		Shapes.box(self, Vector3(0.06, 0.05, 3.6), Vector3(x, ROOF + 0.05, 0.3), roof_strip, false)


func _build_cabin() -> void:
	var shell := Shapes.mat(Color(0.09, 0.09, 0.11), 0.35, 0.7)
	var trim := Shapes.mat(Color(0.12, 0.12, 0.13), 0.8)
	var seat := Shapes.mat(Color(0.16, 0.13, 0.12), 0.9)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.6, 0.7, 0.18)
	glass.roughness = 0.05
	glass.metallic = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	Shapes.box(self, Vector3(1.85, 0.05, 4.3), Vector3(0, 0.0, 0), trim, false)              # пол
	for side in [-1.0, 1.0]:
		Shapes.box(self, Vector3(0.07, 0.62, 4.3), Vector3(side * 0.95, 0.31, 0), shell, false)   # двери
		Shapes.box(self, Vector3(0.02, 0.52, 3.2), Vector3(side * 0.93, 0.9, 0.25), glass, false) # боковые стёкла
		for z in [-1.3, 0.15, 1.85]:
			Shapes.box(self, Vector3(0.07, 0.6, 0.12), Vector3(side * 0.93, 0.93, z), shell, false)  # стойки
	# Крыша с рваной дырой над задним сиденьем — сюда он и влетел.
	Shapes.box(self, Vector3(1.9, 0.06, 1.55), Vector3(0, ROOF, -0.58), shell, false)
	Shapes.box(self, Vector3(1.9, 0.06, 0.45), Vector3(0, ROOF, 1.85), shell, false)
	for side in [-1.0, 1.0]:
		Shapes.box(self, Vector3(0.32, 0.06, 1.4), Vector3(side * 0.79, ROOF, 0.9), shell, false)
	var flap := Shapes.box(self, Vector3(1.2, 0.04, 0.45), Vector3(0, ROOF - 0.12, 0.38), shell, false)
	flap.rotation.x = 0.7      # края дыры загнуты внутрь
	var flap2 := Shapes.box(self, Vector3(1.0, 0.04, 0.35), Vector3(0, ROOF - 0.1, 1.48), shell, false)
	flap2.rotation.x = -0.6
	var shred := Shapes.box(self, Vector3(0.05, 0.03, 0.5), Vector3(0.55, ROOF - 0.15, 0.95), shell, false)
	shred.rotation = Vector3(0.4, 0.3, 0.9)
	# Лобовое и заднее стекло.
	var wind := Shapes.box(self, Vector3(1.8, 0.02, 1.05), Vector3(0, 0.92, -1.72), glass, false)
	wind.rotation.x = -0.95
	var rear := Shapes.box(self, Vector3(1.75, 0.5, 0.02), Vector3(0, 0.95, 2.05), glass, false)
	rear.rotation.x = 0.35
	# Приборная панель, руль, кресла.
	Shapes.box(self, Vector3(1.8, 0.34, 0.5), Vector3(0, 0.58, -1.32), trim, false)
	alarm_mat = Shapes.glow(Color(0.3, 0.02, 0.02), Color(1.0, 0.05, 0.03), 4.0)
	Shapes.box(self, Vector3(1.5, 0.03, 0.05), Vector3(0, 0.76, -1.08), alarm_mat, false)
	var screen := Shapes.glow(Color(0.02, 0.05, 0.06), Color(0.1, 0.5, 0.6), 1.2)
	Shapes.box(self, Vector3(0.5, 0.2, 0.02), Vector3(0.38, 0.72, -1.07), screen, false)
	warn = _label("ВНИМАНИЕ\nПОТЕРЯ ВЫСОТЫ", Vector3(-0.32, 0.86, -1.06), Color(1.0, 0.15, 0.1))
	altitude = _label("ВЫС 300 м", Vector3(0.38, 0.73, -1.05), Color(0.5, 0.9, 1.0))
	Shapes.box(self, Vector3(0.05, 0.05, 0.35), Vector3(-0.45, 0.75, -0.95), trim, false)    # колонка руля
	Shapes.box(self, Vector3(0.36, 0.05, 0.05), Vector3(-0.45, 0.8, -0.78), trim, false)     # штурвал
	for x in [-0.45, 0.45]:
		Shapes.box(self, Vector3(0.55, 0.12, 0.55), Vector3(x, 0.32, -0.45), seat, false)
		var back := Shapes.box(self, Vector3(0.52, 0.42, 0.12), Vector3(x, 0.58, -0.12), seat, false)   # невысокие — видно панель
		back.rotation.x = -0.15
	Shapes.box(self, Vector3(1.65, 0.14, 0.6), Vector3(0, 0.3, 1.1), seat, false)            # заднее сиденье
	Shapes.box(self, Vector3(1.65, 0.62, 0.14), Vector3(0, 0.66, 1.62), seat, false)
	alarm_light = OmniLight3D.new()
	alarm_light.light_color = Color(1.0, 0.08, 0.05)
	alarm_light.omni_range = 4.5
	alarm_light.light_energy = 0.0
	alarm_light.position = Vector3(0, 1.0, -0.4)
	add_child(alarm_light)
	var fill := OmniLight3D.new()   # тусклый свет приборов — салон не проваливается в черноту между вспышками
	fill.light_color = Color(0.5, 0.75, 0.85)
	fill.omni_range = 3.0
	fill.light_energy = 0.5
	fill.position = Vector3(0, 0.9, -0.9)
	add_child(fill)


func _label(text: String, pos: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 32
	label.pixel_size = 0.0018
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.position = pos
	label.rotation.x = -0.45   # к лежащему сзади герою
	add_child(label)
	return label


## Огонь, дым и рыжий свет над обломками; треск пламени.
func _build_fire() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.albedo_texture = Shapes.soft_dot()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.5, 0.15, 0.2))     # тускло: языков много, под блюмом они складываются
	ramp.add_point(0.4, Color(0.85, 0.25, 0.05, 0.13))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.4, 0.05, 0.02, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.15, 1.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.25))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	pm.scale_curve = shrink_tex
	pm.color_ramp = ramp_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.55)   # отдельные языки, а не одно слепящее пятно
	quad.material = glow
	flame_pm = pm
	flame_quad = quad
	flames = GPUParticles3D.new()
	flames.process_material = pm
	flames.draw_pass_1 = quad
	flames.amount = 90
	flames.lifetime = 1.0
	flames.position = Vector3(0, 0.7, 0)
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	add_child(flames)

	var soot := StandardMaterial3D.new()
	soot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	soot.vertex_color_use_as_albedo = true
	soot.albedo_texture = Shapes.soft_dot()
	var grey := Gradient.new()
	grey.set_color(0, Color(0.12, 0.11, 0.1, 0.0))
	grey.add_point(0.12, Color(0.12, 0.11, 0.1, 0.55))
	grey.set_color(grey.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	var grey_tex := GradientTexture1D.new()
	grey_tex.gradient = grey
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(0.6, 0.2, 1.2)
	sm.direction = Vector3(0.15, 1, 0)
	sm.spread = 10.0
	sm.initial_velocity_min = 2.0
	sm.initial_velocity_max = 3.2
	sm.gravity = Vector3(0.3, 0.4, 0)
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	sm.scale_curve = grow_tex
	sm.scale_min = 1.0
	sm.scale_max = 1.6
	sm.color_ramp = grey_tex
	var puff := QuadMesh.new()
	puff.size = Vector2(3.0, 3.0)
	puff.material = soot
	smoke = GPUParticles3D.new()
	smoke.process_material = sm
	smoke.draw_pass_1 = puff
	smoke.amount = 70
	smoke.lifetime = 9.0
	smoke.preprocess = 6.0
	smoke.position = Vector3(0, 1.4, 0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 40, 16))
	add_child(smoke)

	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.22)
	fire_light.omni_range = 14.0
	fire_light.light_energy = 2.5
	fire_light.shadow_enabled = true
	fire_light.position = Vector3(0, 2.0, 0)
	add_child(fire_light)

	crackle = AudioStreamPlayer3D.new()
	crackle.stream = _crackle_sound()
	crackle.unit_size = 5.0
	crackle.max_distance = 45.0
	crackle.volume_db = -2.0
	crackle.bus = &"Interior"
	crackle.position = Vector3(0, 0.8, 0)
	add_child(crackle)
	crackle.play()


## Высота асфальта под точкой (машина без коллизии — луч её не видит).
func _ground_at(at: Vector3) -> float:
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(at + Vector3.UP * 4.0, at + Vector3.DOWN * 6.0))
	return hit.position.y if not hit.is_empty() else at.y


## Обломки вокруг остова: куски обшивки и крыши, колёса, стекло — часть горит. Пятно гари под машиной.
func _build_debris(ground: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var scatter := Node3D.new()
	get_parent().add_child(scatter)
	scatter.global_position = Vector3(CRASH.x, 0, CRASH.z)
	var scorch := Decal.new()
	scorch.texture_albedo = Shapes.soft_dot()
	scorch.modulate = Color(0.02, 0.02, 0.02)
	scorch.size = Vector3(9.0, 2.0, 9.0)
	scorch.position.y = ground
	scatter.add_child(scorch)
	var metal := Shapes.mat(Color(0.09, 0.09, 0.11), 0.4, 0.7)
	var charred := Shapes.mat(Color(0.03, 0.03, 0.03), 0.9)
	var hot := Shapes.glow(Color(0.2, 0.05, 0.02), Color(1.0, 0.35, 0.08), 2.5)   # раскалённый край
	var glass := Shapes.mat(Color(0.5, 0.6, 0.65), 0.05, 0.3)
	var rubber := Shapes.mat(Color(0.03, 0.03, 0.03), 0.95)
	for i in 18:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(2.0, 9.5)
		var spot := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		spot.y = _ground_at(scatter.global_position + spot) - scatter.global_position.y
		var kind := i % 6
		var piece: MeshInstance3D
		if kind == 0:   # колесо
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.34
			wheel.bottom_radius = 0.34
			wheel.height = 0.24
			piece = Shapes.node(scatter, wheel, spot + Vector3.UP * 0.12, rubber, false)
		elif kind == 1:   # осколки стекла
			piece = Shapes.box(scatter, Vector3(rng.randf_range(0.2, 0.5), 0.02, rng.randf_range(0.15, 0.4)), spot + Vector3.UP * 0.02, glass, false)
		else:   # куски обшивки, крыши, дверей
			var size := Vector3(rng.randf_range(0.4, 1.6), rng.randf_range(0.04, 0.12), rng.randf_range(0.3, 1.1))
			piece = Shapes.box(scatter, size, spot + Vector3.UP * size.y * 0.5, charred if rng.randf() < 0.5 else metal, false)
			if rng.randf() < 0.4:
				Shapes.box(piece, Vector3(size.x, 0.02, 0.05), Vector3(0, size.y * 0.5, size.z * 0.5), hot, false)
		piece.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		if kind == 0:
			piece.rotation.x = PI / 2.0 + rng.randf_range(-0.2, 0.2)   # колесо лежит на боку… или катится
		if kind >= 2 and i % 3 != 0:   # горит
			var fire := GPUParticles3D.new()
			var pm: ParticleProcessMaterial = flame_pm.duplicate()
			pm.emission_box_extents = Vector3(0.25, 0.05, 0.25)
			pm.initial_velocity_max = 1.6
			fire.process_material = pm
			fire.draw_pass_1 = flame_quad
			fire.amount = 12
			fire.lifetime = 0.7
			fire.position = spot + Vector3.UP * 0.15
			fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			scatter.add_child(fire)
	for k in 2:   # пара небольших огней от горящих обломков
		var glow_light := OmniLight3D.new()
		glow_light.light_color = Color(1.0, 0.5, 0.2)
		glow_light.omni_range = 5.0
		glow_light.light_energy = 1.2
		glow_light.position = Vector3(cos(k * 2.6) * 5.0, ground + 0.6, sin(k * 2.6) * 5.0)
		scatter.add_child(glow_light)


# --- Звуки ---------------------------------------------------------------------

## Сигнализация: два тона попеременно, с хрипотцой динамика; петля 1 с.
func _siren() -> AudioStreamWAV:
	var tone := func(time: float) -> float:
		var f := 920.0 if fmod(time, 0.5) < 0.25 else 640.0   # быстрее и злее
		return clampf(sin(TAU * f * time) * 4.0, -1.0, 1.0) * 0.6
	return Synth.wav(1.0, tone, true)


## Удар о металл и стекло: глухой удар, скрежет и звон осколков.
func _crunch_sound() -> AudioStreamWAV:
	return Synth.wav(1.6, func(time: float) -> float:
		var body := sin(TAU * 55.0 * time) * exp(-time * 5.0)
		var metal := (randf() * 2.0 - 1.0) * exp(-time * 9.0) * 0.6
		var screech := sin(TAU * (900.0 + 300.0 * sin(time * 40.0)) * time) * exp(-time * 6.0) * 0.15
		var glass := sin(TAU * 3200.0 * time + randf() * 0.4) * exp(-time * 4.0) * 0.12 * float(randf() < 0.3)
		return (body + metal + screech + glass) * 0.9)


## Треск горящей машины: гул пламени и сухие щелчки, петля 3 с (как у костра, гуще).
func _crackle_sound() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(Synth.MIX_RATE * 3.0))
	var lp := 0.0
	var pop := 0.0
	for i in samples.size():
		lp += (randf() * 2.0 - 1.0 - lp) * 0.04
		if randf() < 0.002:
			pop = randf_range(0.4, 0.9)
		pop *= 0.985
		samples[i] = lp * 1.6 + (randf() * 2.0 - 1.0) * pop
	return Synth.wav_from(samples, true)
