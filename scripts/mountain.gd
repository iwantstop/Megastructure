class_name Mountain
extends Node3D

## Гора за мостом — цель пути. Ландшафт Terrain3D, сгенерированный из кода.
## Тропа — спираль: начинается у конца моста над бездной (высота 0) и, обойдя гору
## два с половиной раза, выводит на вершину над облаками. Между витками тропы — скальные
## стены, снаружи — обрыв в бездну. Длина подъёма ~4 км, уклон тропы постоянный (~15%).

const CENTER := Vector3(0, 0, -2870)
const R_BASE := 500.0        # радиус первого витка тропы
const R_TOP := 40.0          # радиус вершинной площадки
const LAPS := 2.5
const PEAK := 650.0          # облака — на 420 м
const PATH_W := 12.0
const START_ANGLE := PI / 2.0  # тропа начинается со стороны моста (+Z)
const SPACING := 2.0         # метров между точками карты высот
const MARGIN := 220.0        # поле вокруг горы, где склон уходит в бездну
const REGION := 1024         # точек карты высот в регионе Terrain3D
const ABYSS_CUT := -480.0    # ниже этой высоты склон обрывается дырой — дна у бездны нет
const COLLISION_FLOOR := -900.0  # в коллизии на месте дыр — просто глубоко (игрок вернётся на тропу раньше)

const TERRACE_STEP := 9.0    # высота одного уступа на склонах, м
const CAVE_AT := 0.3          # пещера — на этой доле подъёма (под облаками, ~310 м)
const CAVE_DEPTH := 36.0      # глубина выемки в стене, м
const CAVE_HALF_W := 9.0      # половина ширины выемки, м

const THETA := LAPS * TAU
const C := (R_BASE - R_TOP) / THETA  # насколько тропа приближается к центру на радиан

static var _cave_inverse: Transform3D  # пещера — посчитана один раз (см. cave_local)
static var _cave_known := false

var terrain: Terrain3D
var cave_inverse: Transform3D  # пещера — посчитана один раз, а не на каждый пиксель карты
var cave_floor := 0.0
var noise := FastNoiseLite.new()


func _ready() -> void:
	noise.seed = 4242
	var cave := cave_frame()
	cave_inverse = cave.affine_inverse()
	cave_floor = cave.origin.y
	noise.frequency = 0.012
	noise.fractal_octaves = 4

	# Terrain3D при добавлении в сцену ставит свои материал и набор текстур по умолчанию,
	# поэтому всё настраиваем уже после add_child.
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.material.world_background = 0  # вне горы — ничего: никакого бесконечного пола
	terrain.assets.set_texture(0, _rock_texture())
	terrain.show_checkered = false
	terrain.vertex_spacing = SPACING
	terrain.change_region_size(REGION)
	# Своя коллизия (см. _build_collision): у Terrain3D дыры в коллизии — это NaN, и физика игрока
	# над ними тысячи раз в секунду пишет предупреждения — игра у горы зависала.
	terrain.collision_mode = 0

	# Terrain3D пишет карту высот с угла региона, поэтому карта покрывает регионы целиком:
	# от угла до угла. Всё, что не гора (поле вокруг и низ обрыва), — «дыры» ландшафта,
	# сквозь них видна бездна.
	var region_m := REGION * SPACING
	var half := R_BASE + MARGIN
	var origin := Vector3(floorf((CENTER.x - half) / region_m) * region_m, 0, floorf((CENTER.z - half) / region_m) * region_m)
	var width := int(ceilf((CENTER.x + half - origin.x) / region_m)) * REGION
	var depth := int(ceilf((CENTER.z + half - origin.z) / region_m)) * REGION
	var heights := Image.create(width, depth, false, Image.FORMAT_RF)
	var control := Image.create(width, depth, false, Image.FORMAT_RF)
	var colors := Image.create(width, depth, false, Image.FORMAT_RGBA8)
	var hole := Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_hole(true)), 0, 0)
	heights.fill(Color(-800.0, 0, 0))
	control.fill(hole)
	colors.fill(Color(0.3, 0.29, 0.28, 0.5))
	var px0 := maxi(int((CENTER.x - half - origin.x) / SPACING), 0)
	var pz0 := maxi(int((CENTER.z - half - origin.z) / SPACING), 0)
	var px1 := mini(int(ceilf((CENTER.x + half - origin.x) / SPACING)), width)
	var pz1 := mini(int(ceilf((CENTER.z + half - origin.z) / SPACING)), depth)
	var cols := px1 - px0
	var rows := pz1 - pz0
	# Рельеф считается построчно на всех ядрах (это самая долгая часть загрузки), в картинки — потом здесь.
	var lines := []
	lines.resize(rows)
	var compute_row := func(row: int) -> void:
		var z := origin.z + (pz0 + row) * SPACING
		var line := PackedVector3Array()   # (высота, «тропа», —) и цвет — двумя массивами
		var tint := PackedColorArray()
		line.resize(cols)
		tint.resize(cols)
		for i in cols:
			var x := origin.x + (px0 + i) * SPACING
			var sample := _sample(x, z)
			line[i] = Vector3(sample.x, sample.y, 0.0)
			tint[i] = _color(sample.x, sample.y, x, z)
		lines[row] = [line, tint]          # у каждой строки своя ячейка — потоки не мешают друг другу
	var task := WorkerThreadPool.add_group_task(compute_row, rows)
	WorkerThreadPool.wait_for_group_task_completion(task)
	var collision_heights := PackedFloat32Array()
	collision_heights.resize(cols * rows)
	for row in rows:
		var line: PackedVector3Array = lines[row][0]
		var tint: PackedColorArray = lines[row][1]
		var py := pz0 + row
		for i in cols:
			var h := line[i].x
			heights.set_pixel(px0 + i, py, Color(h, 0, 0))
			# Коллизия: там, где видна дыра, — просто очень глубоко, без NaN. Масштаб узла — SPACING.
			collision_heights[row * cols + i] = (h if h > ABYSS_CUT else COLLISION_FLOOR) / SPACING
			colors.set_pixel(px0 + i, py, tint[i])
			if h > ABYSS_CUT:
				control.set_pixel(px0 + i, py, Color(0, 0, 0))
	terrain.data.import_images([heights, control, colors], origin, 0.0, 1.0)
	_build_collision(collision_heights, cols, rows, origin + Vector3(px0 * SPACING, 0, pz0 * SPACING))


## Твёрдая гора: карта высот как HeightMapShape3D. Форма центрирована и с шагом 1, поэтому
## узел масштабирован в SPACING раз (равномерно — неравномерный масштаб физика не любит),
## а высоты заранее поделены на SPACING.
func _build_collision(data: PackedFloat32Array, cols: int, rows: int, corner: Vector3) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = cols
	shape.map_depth = rows
	shape.map_data = data
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.scale = Vector3.ONE * SPACING
	var body := StaticBody3D.new()
	body.position = corner + Vector3((cols - 1) * SPACING / 2.0, 0, (rows - 1) * SPACING / 2.0)
	body.add_child(holder)
	add_child(body)


## Высота тропы на угле спирали theta: пропорциональна пройденному пути, поэтому уклон везде одинаковый.
static func path_height(theta: float) -> float:
	return PEAK * _arc(theta) / _arc(THETA)


static func _arc(theta: float) -> float:
	return R_BASE * theta - C * theta * theta / 2.0


## Точка на тропе: fraction 0 — начало у моста, 1 — вершина. Возвращает положение и направление вперёд.
static func path_point(fraction: float) -> Transform3D:
	var theta := clampf(fraction, 0.0, 1.0) * THETA
	var r := R_BASE - C * theta
	var phi := START_ANGLE + theta
	var pos := CENTER + Vector3(cos(phi) * r, path_height(theta), sin(phi) * r)
	var ahead := CENTER + Vector3(cos(phi + 0.05) * (r - C * 0.05), 0, sin(phi + 0.05) * (r - C * 0.05))
	ahead.y = pos.y
	return Transform3D(Basis.looking_at(ahead - pos, Vector3.UP), pos)


## Высота земли в точке и признак «это тропа» (x — высота, y — 1 на тропе, 0 — скала).
func _sample(x: float, z: float) -> Vector2:
	var dx := x - CENTER.x
	var dz := z - CENTER.z
	var r := sqrt(dx * dx + dz * dz)
	var theta0 := fposmod(atan2(dz, dx) - START_ANGLE, TAU)
	var rock := noise.get_noise_2d(x, z)

	# Ближайший виток снаружи (k_out) и внутри (k_out + 1) от этой точки.
	var k_out := floori((R_BASE - r - C * theta0) / (C * TAU))
	var theta_out := theta0 + k_out * TAU
	var r_out := R_BASE - C * theta_out
	var theta_in := theta_out + TAU
	var r_in := R_BASE - C * theta_in

	if k_out < 0:
		# Снаружи первого витка: край тропы и обрыв в бездну.
		var h0 := path_height(theta_in)
		if r - r_in <= PATH_W / 2.0:
			return Vector2(h0, 1.0)
		var drop := r - r_in - PATH_W / 2.0
		var cliff := maxf(h0 - drop * 1.8 + rock * 12.0, -500.0)
		var outer := lerpf(cliff, _terrace(cliff, rock), smoothstep(3.0, 15.0, drop))
		# Перед самым началом тропы (если смотреть с моста — справа) снаружи первого витка был отвесный срез
		# до самого низа и шов с землёй у начала тропы. Здесь склон — как стена между витками: от тропы
		# первого витка вниз к земле у начала тропы, с выступами и террасами.
		var seam := smoothstep(TAU - 1.7, TAU - 0.02, theta0)
		if seam > 0.0:
			var r_start := R_BASE + C * (TAU - theta0)   # где шла бы тропа у земли, продолжись она назад
			var tt := clampf((r - r_in - PATH_W / 2.0) / maxf(r_start - r_in - PATH_W / 2.0, 1.0), 0.0, 1.0)
			var slope := lerpf(h0, 0.0, smoothstep(0.0, 1.0, tt)) + rock * 25.0 * sin(tt * PI)
			var ramp := lerpf(slope, _terrace(slope, rock), smoothstep(0.05, 0.25, tt) * (1.0 - smoothstep(0.85, 0.97, tt)))
			if r > r_start:
				ramp = maxf(-(r - r_start) * 1.8 + rock * 12.0, -500.0)   # за ним — обрыв в бездну, как у начала тропы
			outer = lerpf(outer, ramp, seam)
		return Vector2(outer, 0.0)

	var h_out := path_height(theta_out)
	# Пещера: выемка в стене над тропой с ровным полом — свод и стены построит mountain_features.gd.
	var local := cave_inverse * Vector3(x, cave_floor, z)
	var depth := -local.z
	if depth > -1.0 and depth < CAVE_DEPTH and absf(local.x) < CAVE_HALF_W:
		return Vector2(lerpf(h_out, cave_floor, smoothstep(0.0, 4.0, depth)), 1.0)
	if theta_in >= THETA:
		# Внутри последнего витка — вершинная площадка.
		r_in = maxf(r_in, R_TOP)
		if r - r_in <= PATH_W / 2.0 or r < R_TOP:
			return Vector2(PEAK, 1.0)
	var h_in := PEAK if theta_in >= THETA else path_height(theta_in)

	if r_out - r <= PATH_W / 2.0:
		return Vector2(h_out, 1.0)
	if r - r_in <= PATH_W / 2.0:
		return Vector2(h_in, 1.0)
	# Скальная стена между витками: от нижней тропы к верхней, с выступами и уступами-террасами.
	var t := clampf((r_out - PATH_W / 2.0 - r) / maxf(r_out - r_in - PATH_W, 1.0), 0.0, 1.0)
	var wall := lerpf(h_out, h_in, smoothstep(0.0, 1.0, t)) + rock * 25.0 * sin(t * PI)
	# У самих троп уступов нет — иначе у подножия стены получится канава или ступенька.
	var away_from_paths := smoothstep(0.05, 0.25, t) * (1.0 - smoothstep(0.85, 0.97, t))
	return Vector2(lerpf(wall, _terrace(wall, rock), away_from_paths), 0.0)


## Уступы: склон превращается в ступени — широкие почти ровные полки и крутые сбросы между ними.
## Шум сдвигает уровни, чтобы уступы не шли идеально ровными кольцами.
func _terrace(h: float, rock: float) -> float:
	var s := (h + rock * 4.0) / TERRACE_STEP
	var stepped := (floorf(s) + smoothstep(0.55, 1.0, fposmod(s, 1.0))) * TERRACE_STEP - rock * 4.0
	return lerpf(h, stepped, 0.85)


## Пещера: начало — у внутреннего края тропы на доле подъёма CAVE_AT, -Z — вглубь горы, Y — уровень пола.
static func cave_frame() -> Transform3D:
	var p := path_point(CAVE_AT).origin
	var inward := Vector3(CENTER.x - p.x, 0, CENTER.z - p.z).normalized()
	var origin := p + inward * (PATH_W / 2.0)
	return Transform3D(Basis.looking_at(inward, Vector3.UP), origin)


## Точка в координатах пещеры: -Z — вглубь горы (глубина = -z), X — поперёк, Y — над полом у входа.
static func cave_local(p: Vector3) -> Vector3:
	if not _cave_known:
		_cave_inverse = cave_frame().affine_inverse()
		_cave_known = true
	return _cave_inverse * p


## Доля подъёма, на которой тропа выходит на заданную высоту.
static func fraction_at_height(h: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 30:
		var mid := (lo + hi) / 2.0
		if path_point(mid).origin.y < h:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


## Доля подъёма на meters метров дальше по тропе от доли fraction. Длина пути пропорциональна _arc
## (и по горизонтали, и по высоте — уклон везде одинаковый).
static func fraction_after(fraction: float, meters: float) -> float:
	var full := _arc(THETA)
	var length := sqrt(full * full + PEAK * PEAK)
	var target := _arc(fraction * THETA) / full + meters / length
	var lo := fraction
	var hi := 1.0
	for i in 30:
		var mid := (lo + hi) / 2.0
		if _arc(mid * THETA) / full < target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


## Каменная текстура (без неё Terrain3D рисует отладочную шахматную клетку):
## светлый зернистый камень — цвет даёт карта цветов горы. Альфа альбедо — высота рельефа,
## альфа нормалей — шероховатость (так Terrain3D хранит эти каналы).
func _rock_texture() -> Terrain3DTextureAsset:
	var grain := FastNoiseLite.new()
	grain.frequency = 0.05
	grain.fractal_octaves = 5
	var size := 512
	var albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var normal := Image.create(size, size, false, Image.FORMAT_RGBA8)
	# Строки — параллельно на всех ядрах, как и рельеф.
	var lines := []
	lines.resize(size)
	var compute_row := func(y: int) -> void:
		var a_row := PackedColorArray()
		var n_row := PackedColorArray()
		a_row.resize(size)
		n_row.resize(size)
		for x in size:
			var n := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var v := lerpf(0.75, 1.0, n)
			a_row[x] = Color(v, v, v, n)
			var dx := grain.get_noise_2d(x + 1, y) - grain.get_noise_2d(x - 1, y)
			var dy := grain.get_noise_2d(x, y + 1) - grain.get_noise_2d(x, y - 1)
			var nrm := Vector3(-dx * 2.0, -dy * 2.0, 1.0).normalized() * 0.5 + Vector3.ONE * 0.5
			n_row[x] = Color(nrm.x, nrm.y, nrm.z, 0.85)
		lines[y] = [a_row, n_row]
	var task := WorkerThreadPool.add_group_task(compute_row, size)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for y in size:
		for x in size:
			albedo.set_pixel(x, y, lines[y][0][x])
			normal.set_pixel(x, y, lines[y][1][x])
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var asset := Terrain3DTextureAsset.new()
	asset.name = "Камень"
	asset.albedo_texture = ImageTexture.create_from_image(albedo)
	asset.normal_texture = ImageTexture.create_from_image(normal)
	asset.uv_scale = 0.15
	return asset


## Цвет: тропа — светлая утоптанная, скалы — тёмные; выше облаков всё теплее и светлее.
func _color(h: float, on_path: float, x: float, z: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
	var rock := Color(0.3, 0.29, 0.28).lerp(Color(0.42, 0.4, 0.37), n)
	var trail := Color(0.55, 0.5, 0.43).lerp(Color(0.62, 0.57, 0.5), n)
	var c := trail if on_path > 0.5 else rock
	var high := smoothstep(380.0, PEAK, h)
	c = c.lerp(Color(0.78, 0.72, 0.62), high * 0.5)
	c.a = 0.5  # шероховатость — нейтральная
	return c
