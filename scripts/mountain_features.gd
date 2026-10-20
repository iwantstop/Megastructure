extends Node3D

## То, что стоит на горе поверх ландшафта:
## - смотровые уступы — каменные плиты, нависающие над обрывом с внешнего края тропы (по ним можно выйти);
## - уступ прощания — сразу над облаками: там ангел оборачивается и исчезает навсегда (presence.gd);
## - пещера в стене над тропой (выемку в ландшафте делает mountain.gd): своды из глыб, у входа — костёр,
##   в глубине — «неправильная» квартира: обои текут, стены дышат, пол ползёт к телевизору,
##   в помехах экрана проступает силуэт, стул висит на потолке, на диване застыла фигура.

const Builder = preload("res://scripts/builder.gd")
const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")
const LEDGES := [0.06, 0.16, 0.42, 0.66, 0.8, 0.92]   # доли подъёма со смотровыми уступами
const FAREWELL_HEIGHT := 428.0                         # уступ прощания — чуть выше облаков (420 м)

var player: CharacterBody3D
var b := Builder.new()
var rng := RandomNumberGenerator.new()
var rock: StandardMaterial3D
var farewell_spot: Transform3D       # где стоит ангел: на краю уступа, -Z — к облакам
var cave: Transform3D
var lamp_light: OmniLight3D
var tv_light: OmniLight3D
var t := 0.0
var cave_inverse: Transform3D
var last_depth := 0.0
var rift: AudioStreamPlayer3D


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	rng.seed = 7070
	add_to_group("mountain_features")
	rock = _rock_material()
	var farewell_f := Mountain.fraction_at_height(FAREWELL_HEIGHT)
	for f in LEDGES:
		if absf(f - farewell_f) > 0.04:
			_ledge(f, 10.0)
	farewell_spot = _ledge(farewell_f, 13.0)
	cave = Mountain.cave_frame()
	cave_inverse = cave.affine_inverse()
	_cave_shell()
	_apartment()
	b.finish(self)
	var fire = preload("res://scripts/campfire.gd").new()
	fire.setup(player)
	add_child(fire)
	fire.transform = cave * Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.0, -8.0))


func _process(delta: float) -> void:
	t += delta
	# Шагнул в дверной проём квартиры — глухой «разрыв» реальности.
	if player:
		var local := cave_inverse * player.global_position
		var depth := -local.z
		if absf(local.x) < 3.0 and last_depth < 14.0 and depth >= 14.0 and rift:
			rift.play()
		last_depth = depth
	# Лампа в квартире то гаснет, то вспыхивает; экран дрожит светом помех.
	if lamp_light:
		var dip := 1.0 if fmod(t, 7.3) > 0.25 else 0.15
		lamp_light.light_energy = (2.2 + 0.2 * sin(t * 23.0)) * dip
	if tv_light:
		tv_light.light_energy = 0.9 + 0.4 * sin(t * 37.0) * sin(t * 11.0)


## Шершавый камень: шумовая текстура по мировым координатам (у склеенной геометрии нет UV).
func _rock_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.36, 0.34, 0.32)
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.18
	return m


func _mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


## Глыба: повёрнутая как попало коробка.
func _boulder(center: Vector3, size: Vector3, collide := true) -> void:
	var basis := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
	b.box(center, size, rock, basis, collide)


# --- Уступы -------------------------------------------------------------------

## Каменная плита с внешнего края тропы, нависает над обрывом; под ней — глыбы-опоры.
## Возвращает точку на самом краю плиты (-Z — наружу, к пустоте).
func _ledge(fraction: float, reach: float) -> Transform3D:
	var p := Mountain.path_point(fraction).origin
	var outward := Vector3(p.x - Mountain.CENTER.x, 0, p.z - Mountain.CENTER.z).normalized()
	var basis := Basis.looking_at(outward, Vector3.UP)
	var edge := p + outward * (Mountain.PATH_W / 2.0 - 1.0)
	var slab_center := edge + outward * (reach / 2.0) + Vector3.DOWN * 0.45
	b.box(slab_center, Vector3(8.0, 0.9, reach + 1.0), rock, basis)
	b.occluder(slab_center, Vector3(8.0, 0.9, reach + 1.0), basis)
	for i in 4:
		var depth := 2.0 + i * 2.2
		var under := edge + outward * (reach * (0.25 + 0.18 * i)) + Vector3.DOWN * depth
		_boulder(under, Vector3(rng.randf_range(4, 7), rng.randf_range(3, 5), rng.randf_range(4, 6)), false)
	# Пара камней на краях плиты — чтобы не было ровной «полки».
	for side in [-1.0, 1.0]:
		var stone: Vector3 = edge + outward * rng.randf_range(2.0, reach - 2.0) + basis.x * side * 3.6
		_boulder(stone + Vector3.UP * 0.3, Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.6, 1.2), rng.randf_range(0.8, 1.6)))
	var tip := edge + outward * (reach - 1.2)
	return Transform3D(basis, Vector3(tip.x, p.y, tip.z))


# --- Пещера ---------------------------------------------------------------------

func _cave_point(x: float, y: float, depth: float) -> Vector3:
	return cave * Vector3(x, y, -depth)


## Своды: стены и потолок из глыб над выемкой; вход — со стороны тропы, с нависающим козырьком.
func _cave_shell() -> void:
	var half := Mountain.CAVE_HALF_W
	var deep := Mountain.CAVE_DEPTH
	var basis := cave.basis
	for side in [-1.0, 1.0]:
		var wall := _cave_point(side * (half + 0.6), 4.5, deep / 2.0 + 1.5)
		b.box(wall, Vector3(2.4, 11.0, deep + 1.0), rock, basis)
		b.occluder(wall, Vector3(2.4, 11.0, deep + 1.0), basis)
	var back := _cave_point(0, 4.5, deep + 0.8)
	b.box(back, Vector3(half * 2.0 + 4.0, 11.0, 2.4), rock, basis)
	var roof := _cave_point(0, 8.2, deep / 2.0 + 2.5)
	b.box(roof, Vector3(half * 2.0 + 5.0, 2.6, deep - 1.0), rock, basis)
	b.occluder(roof, Vector3(half * 2.0 + 5.0, 2.6, deep - 1.0), basis)
	# Неровный свод изнутри и курган глыб снаружи — чтобы это читалось как скала, а не коробка.
	for i in 22:
		_boulder(_cave_point(rng.randf_range(-half, half), rng.randf_range(6.4, 7.2), rng.randf_range(4.0, deep - 1.0)),
			Vector3(rng.randf_range(1.5, 3.5), rng.randf_range(0.8, 1.6), rng.randf_range(1.5, 3.5)), false)
	for i in 26:
		_boulder(_cave_point(rng.randf_range(-half - 4, half + 4), rng.randf_range(8.5, 14.0), rng.randf_range(2.0, deep + 4.0)),
			Vector3(rng.randf_range(4, 9), rng.randf_range(3, 6), rng.randf_range(4, 9)), false)
	# Козырёк над входом и камни по бокам входа.
	for i in 5:
		_boulder(_cave_point(rng.randf_range(-half, half), rng.randf_range(6.8, 8.2), rng.randf_range(2.0, 4.5)),
			Vector3(rng.randf_range(3, 5), rng.randf_range(1.5, 2.5), rng.randf_range(2, 4)), false)
	for side in [-1.0, 1.0]:
		for i in 3:
			_boulder(_cave_point(side * rng.randf_range(half - 1.5, half + 1.0), rng.randf_range(0.6, 2.5), rng.randf_range(0.5, 4.0)),
				Vector3(rng.randf_range(1.5, 3.0), rng.randf_range(1.5, 3.5), rng.randf_range(1.5, 3.0)))


# --- Квартира -------------------------------------------------------------------

## Обрывок чужой квартиры посреди пещеры. Комната — между глубинами 14 и 31 м, телевизор у входа в неё,
## диван у дальней стены лицом к экрану.
func _apartment() -> void:
	var basis := cave.basis
	var wallpaper := _shader("res://shaders/wallpaper.gdshader")
	var parquet := _shader("res://shaders/parquet.gdshader")
	var dark := _mat(Color(0.05, 0.05, 0.05), 0.5)
	var fabric := _mat(Color(0.28, 0.06, 0.07), 0.95)
	var wood := _mat(Color(0.2, 0.12, 0.07), 0.6)
	var white := _mat(Color(0.85, 0.83, 0.8), 0.4)
	var frame_mat := _mat(Color(0.12, 0.09, 0.06), 0.7)

	b.box(_cave_point(0, 0.05, 22.5), Vector3(11.0, 0.1, 17.0), parquet, basis)
	# Стены: дальняя целиком, левая — половина, правой нет (там голая скала).
	b.box(_cave_point(0, 1.55, 31.0), Vector3(11.0, 3.1, 0.2), wallpaper, basis)
	b.box(_cave_point(-5.5, 1.55, 25.5), Vector3(0.2, 3.1, 11.0), wallpaper, basis)
	# Потолок — кусок, чуть перекошенный: смотреть на него неуютно.
	var ceiling := Basis(basis.x, 0.07) * basis
	b.box(_cave_point(-0.8, 3.15, 26.0), Vector3(9.0, 0.15, 10.0), wallpaper, ceiling, false)
	# Дверной проём без стены — вход в квартиру из пещеры, слегка завален набок.
	var door := Basis(basis.z, 0.05) * basis
	for side in [-1.0, 1.0]:
		b.box(_cave_point(side * 0.55, 1.05, 14.0), Vector3(0.1, 2.1, 0.12), frame_mat, door)
	b.box(_cave_point(0, 2.12, 14.0), Vector3(1.2, 0.1, 0.12), frame_mat, door)

	# Диван у дальней стены, лицом к телевизору (к выходу).
	var sofa_d := 28.6
	b.box(_cave_point(0, 0.2, sofa_d), Vector3(2.3, 0.4, 0.95), fabric, basis)
	b.box(_cave_point(0, 0.65, sofa_d + 0.42), Vector3(2.3, 0.9, 0.22), fabric, basis)
	for side in [-1.0, 1.0]:
		b.box(_cave_point(side * 1.2, 0.35, sofa_d), Vector3(0.2, 0.7, 0.95), fabric, basis)
	# Ковёр, столик, две кружки — «на двоих».
	b.box(_cave_point(0, 0.11, 24.0), Vector3(3.2, 0.02, 2.4), _mat(Color(0.18, 0.05, 0.05), 1.0), basis, false)
	b.box(_cave_point(0, 0.22, 25.6), Vector3(1.2, 0.44, 0.6), wood, basis)
	for side in [-1.0, 1.0]:
		b.cylinder(_cave_point(side * 0.22, 0.5, 25.6), 0.045, 0.1, white, basis, false)
	# Тумба и телевизор у входа в комнату, экраном к дивану.
	b.box(_cave_point(0, 0.25, 18.5), Vector3(1.6, 0.5, 0.45), wood, basis)
	b.box(_cave_point(0, 0.86, 18.5), Vector3(1.15, 0.72, 0.14), dark, basis, false)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.02, 0.6)
	screen.mesh = quad
	screen.material_override = _shader("res://shaders/tv_static.gdshader")
	screen.transform = Transform3D(basis.rotated(Vector3.UP, PI), _cave_point(0, 0.86, 18.58))  # смотрит вглубь, на диван
	add_child(screen)
	tv_light = OmniLight3D.new()
	tv_light.light_color = Color(0.7, 0.8, 1.0)
	tv_light.omni_range = 5.0
	tv_light.position = _cave_point(0, 0.9, 19.2)
	add_child(tv_light)
	# Торшер у дивана: тёплый мигающий свет.
	var lamp_pos := _cave_point(1.9, 0.0, 28.8)
	b.cylinder(lamp_pos + Vector3.UP * 0.8, 0.02, 1.6, dark, basis, false)
	var shade := _mat(Color(0.9, 0.7, 0.45), 0.8)
	shade.emission_enabled = true
	shade.emission = Color(1.0, 0.7, 0.4)
	shade.emission_energy_multiplier = 1.5
	b.cylinder(lamp_pos + Vector3.UP * 1.65, 0.22, 0.3, shade, basis, false)
	lamp_light = OmniLight3D.new()
	lamp_light.light_color = Color(1.0, 0.7, 0.42)
	lamp_light.omni_range = 9.0
	lamp_light.position = lamp_pos + Vector3.UP * 1.6
	add_child(lamp_light)
	# Часы и фотографии на дальней стене.
	b.cylinder(_cave_point(-2.2, 2.2, 30.86), 0.25, 0.05, white, basis * Basis(Vector3.RIGHT, PI / 2.0), false)
	for i in 3:
		b.box(_cave_point(1.0 + i * 0.75, 1.75 + (i % 2) * 0.25, 30.86), Vector3(0.45, 0.6, 0.03), frame_mat, basis, false)
	# Стул на потолке — ножками вверх.
	var chair := Transform3D(basis * Basis(Vector3.FORWARD, PI), _cave_point(-2.6, 2.85, 24.0))
	b.box_local(chair, Vector3(0, 0.45, 0), Vector3(0.45, 0.05, 0.45), wood, false)
	b.box_local(chair, Vector3(0, 0.75, -0.2), Vector3(0.45, 0.6, 0.05), wood, false)
	for leg in [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
		b.box_local(chair, Vector3(leg.x, 0.22, leg.y), Vector3(0.04, 0.45, 0.04), wood, false)
	_figure_on_sofa(sofa_d)
	_room_sounds()


## Застывшая фигура на диване смотрит в экран. Сиденье дивана — на 0.40 м, как у замеренной позы.
func _figure_on_sofa(sofa_d: float) -> void:
	var body: Node3D = MODEL.instantiate()
	var holder := Node3D.new()
	# Фигура смотрит к телевизору — к выходу из пещеры (+Z в координатах пещеры).
	holder.transform = Transform3D(cave.basis.rotated(Vector3.UP, PI), _cave_point(-0.45, 0.0, sofa_d - 0.3))
	body.rotation.y = PI
	holder.add_child(body)
	add_child(holder)
	var plastic := _mat(Color(0.78, 0.74, 0.7), 0.5)
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = plastic
	var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	anim.play("Sitting_Idle")
	anim.seek(0.4, true)
	anim.pause()


func _room_sounds() -> void:
	for spec in [
		["res://assets/sounds/tv.ogg", _cave_point(0, 0.9, 18.7), -10.0],
		["res://assets/sounds/clock.ogg", _cave_point(-2.2, 2.2, 30.7), -14.0],
		["res://assets/sounds/dissonance.ogg", _cave_point(0, 1.5, 26.0), -20.0],
	]:
		var stream: AudioStreamOggVorbis = load(spec[0])
		stream.loop = true
		var p := AudioStreamPlayer3D.new()
		p.stream = stream
		p.position = spec[1]
		p.volume_db = spec[2]
		p.unit_size = 3.0
		p.max_distance = 30.0
		p.bus = "Interior"
		p.autoplay = true
		add_child(p)
	rift = AudioStreamPlayer3D.new()
	rift.stream = load("res://assets/sounds/rift.ogg")
	rift.position = _cave_point(0, 1.2, 14.0)
	rift.volume_db = -4.0
	rift.bus = "Interior"
	add_child(rift)
