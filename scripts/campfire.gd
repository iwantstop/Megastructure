extends Node3D

## Костёр у входа в пещеру. Подойти — внизу появится «Разжечь костёр - E»; нажать E — огонь
## разгорается за пару секунд: языки пламени, искры, тёплый мерцающий свет, треск. Горит дальше сам.

const REACH := 2.6             # с какого расстояния можно разжечь, м
const HINT := "Разжечь костёр - E"

var player: CharacterBody3D
var lit := false
var near := false
var flames: GPUParticles3D
var sparks: GPUParticles3D
var light: OmniLight3D
var crackle: AudioStreamPlayer3D
var heat := 0.0                # 0..1 — насколько разгорелся
var t := 0.0


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	add_to_group("campfire")
	var stone := Shapes.mat(Color(0.3, 0.29, 0.28), 1.0)
	var bark := Shapes.mat(Color(0.17, 0.1, 0.06), 1.0)
	for i in 10:
		var a := TAU * i / 10.0
		var s := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.2, 0.22) * randf_range(0.8, 1.2)
		s.mesh = box
		s.material_override = stone
		s.position = Vector3(cos(a) * 0.62, 0.1, sin(a) * 0.62)
		s.rotation = Vector3(randf_range(-0.3, 0.3), a + randf_range(-0.4, 0.4), randf_range(-0.2, 0.2))
		add_child(s)
	for i in 4:
		var wood_log := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.07
		cyl.height = 0.9
		wood_log.mesh = cyl
		wood_log.material_override = bark
		var a := TAU * i / 4.0 + 0.4
		wood_log.position = Vector3(cos(a) * 0.15, 0.18, sin(a) * 0.15)
		wood_log.rotation = Vector3(0, -a, 1.15)   # шалашиком к центру
		add_child(wood_log)
	_build_fire()
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.omni_range = 10.0
	light.light_energy = 0.0
	light.position = Vector3(0, 0.6, 0)
	light.shadow_enabled = true
	add_child(light)
	crackle = AudioStreamPlayer3D.new()
	crackle.stream = _crackle_sound()
	crackle.unit_size = 2.5
	crackle.max_distance = 25.0
	crackle.volume_db = -6.0
	crackle.bus = "Interior"
	crackle.position = Vector3(0, 0.3, 0)
	add_child(crackle)


func _process(delta: float) -> void:
	t += delta
	if player == null:
		return
	var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	var close := not lit and flat < REACH and absf(player.global_position.y - global_position.y) < 2.0
	if close != near:
		near = close
		if Game.hud:
			Game.hud.action_hint(HINT, near)
	if lit:
		heat = move_toward(heat, 1.0, delta / 2.5)
		var flicker := 0.85 + 0.1 * sin(t * 13.0) + 0.05 * sin(t * 31.0 + 1.3)
		light.light_energy = 2.2 * heat * flicker
		flames.amount_ratio = heat
		sparks.amount_ratio = heat


func _unhandled_input(event: InputEvent) -> void:
	if near and not lit and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		light_up()
		get_viewport().set_input_as_handled()


## Разжечь (и из тестов).
func light_up() -> void:
	if lit:
		return
	lit = true
	near = false
	if Game.hud:
		Game.hud.action_hint(HINT, false)
	flames.emitting = true
	sparks.emitting = true
	crackle.play()


func _build_fire() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.albedo_texture = Shapes.soft_dot()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.6))
	ramp.add_point(0.45, Color(1.0, 0.4, 0.1, 0.35))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.4, 0.05, 0.02, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.2))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	pm.scale_curve = shrink_tex
	pm.color_ramp = ramp_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.32)  # мелкие языки, а не одно светящееся пятно
	quad.material = glow
	flames = GPUParticles3D.new()
	flames.process_material = pm
	flames.draw_pass_1 = quad
	flames.amount = 90
	flames.lifetime = 0.9
	flames.emitting = false
	flames.amount_ratio = 0.0
	flames.position = Vector3(0, 0.2, 0)
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)

	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.2
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 25.0
	sp.initial_velocity_min = 1.0
	sp.initial_velocity_max = 2.6
	sp.gravity = Vector3(0, 0.3, 0)
	sp.turbulence_enabled = true
	sp.turbulence_noise_strength = 2.0
	sp.color_ramp = ramp_tex
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.03, 0.03)
	spark_quad.material = glow
	sparks = GPUParticles3D.new()
	sparks.process_material = sp
	sparks.draw_pass_1 = spark_quad
	sparks.amount = 30
	sparks.lifetime = 2.2
	sparks.emitting = false
	sparks.amount_ratio = 0.0
	sparks.position = Vector3(0, 0.4, 0)
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)


## Треск костра: низкий гул пламени и частые сухие щелчки, петля 3 с.
func _crackle_sound() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(Synth.MIX_RATE * 3.0))
	var lp := 0.0
	var pop := 0.0
	for i in samples.size():
		lp += (randf() * 2.0 - 1.0 - lp) * 0.03
		if randf() < 0.0012:
			pop = randf_range(0.4, 0.9)
		pop *= 0.985
		samples[i] = lp * 1.4 + (randf() * 2.0 - 1.0) * pop
	return Synth.wav_from(samples, true)
