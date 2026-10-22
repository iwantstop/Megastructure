extends RefCounted

## Генератор мира. Всё складывается в Builder.
## В центре — заброшенный город: дороги, тротуары, кварталы зданий, машины, столбы.
## Вокруг — мегаструктуры до горизонта.

const Builder = preload("res://scripts/builder.gd")

const BLOCK := 36.0    # размер квартала
const PITCH := 48.0    # квартал + улица
const PLATE := 40.0    # квартал с тротуаром вокруг
const CURB := 0.15     # высота тротуара
const FLOOR_H := 3.2   # высота этажа

var b: Builder
var rng: RandomNumberGenerator
var m: Dictionary
var towers: Array[Dictionary] = []
var roofs: Array[Dictionary] = []
var occupied: Array[Vector3] = []  # занятые места за городом: (x, z, радиус)
var district := Rect2(-270, -366, 540, 444)  # город; вне его — гиганты

# То, что пригодится другим: вещи в домах, свет в окнах, улицы для манекенов.
var interior_spots: Array[Transform3D] = []
var lights: Array[Vector3] = []
var streets: Array[Vector4] = []  # оси улиц: (x0, z0, x1, z1)
var plazas: Array[Vector2] = []
var ads: Array[Dictionary] = []   # места под горящие билборды: {xform, size}
var signs: Array[Dictionary] = [] # вертикальные неоновые вывески поперёк улицы: {xform, size}
var crossings: Array[Vector2] = []  # перекрёстки
var open_hubs: Array[Vector2] = []  # хабы L1 без шахты лифта — на них стоят проекторы голограмм
var city_towers: Array[Dictionary] = []  # небоскрёбы — между ними воздушные мосты

## Самая высокая башня — с неё прыгнул герой. Он лежит у её подножия, в HERO_SPOT.
const TALLEST_TOWER := Vector3(0, 0, 118)
const TALLEST_HEIGHT := 760.0
const HERO_SPOT := Vector3(4, 0.2, 86)
const ROOF_SPOT := Vector3(4, TALLEST_HEIGHT + 0.2, 100)  # на крыше, у того края, с которого он прыгнул

## Уровни города над землёй: галереи вдоль кварталов, мосты над улицами.
const L1 := 14.0
const L2 := 40.0
const L3 := 75.0

var plated: Array[Vector2] = []          # кварталы на плитах — вокруг них галереи
var decks: Array[Vector4] = []           # оси галерей уровня L1 (для манекенов)
var elevators: Array[Dictionary] = []    # {pos, stops} — лифты в башнях доступа
var access_points: Array[Vector3] = []   # куда можно поставить игрока на каждом уровне (для демо)


func _init(builder: Builder, random: RandomNumberGenerator, materials: Dictionary) -> void:
	b = builder
	rng = random
	m = materials


## Платформа города висит над бездной: края, мост к горе.
const PLATFORM := Rect2(-268, -368, 536, 518)  # x, z, ширина, глубина (включая подножие башни героя)
const CAUSEWAY_END := -2350.0                   # мост над бездной тянется до подножия горы
const BENCH_SPOT := Vector3(-12.4, 0, -1240)     # скамейка у левого края моста (bench_spot.gd)…
const BENCH_GAP := Vector2(-1242.0, -1237.5)     # …и напротив неё в перилах разрыв — открытый обрыв (z от и до)
const BENCH_TOWER_NEAR := 160.0                   # мегабашня ближе этого к скамейке — та, что видна с неё (bench_show.gd)…
const BENCH_TOWER_ROOF := 58.0                   # …обрезана: крыша сразу над табло, на ней шпиль-меч
const ABYSS := -900.0                            # докуда уходят основания построек (дальше — туман)

var walk_spots: Array[Vector3] = []   # где можно стоять: для вещей и прочего
var bench_tower: Dictionary = {}     # гигант напротив скамейки (обрезан по крыше BENCH_TOWER_ROOF)
var giants: Array[Dictionary] = []   # гиганты за городом: вид, место, размеры (для билборда у скамейки и проб)
var wells: Dictionary = {}            # Vector2i квартала -> true: провалы в бездну


func build() -> void:
	_colonnade()
	_city()
	_platform()
	_causeway()
	reserve(TALLEST_TOWER.x, TALLEST_TOWER.z, 60)
	_tallest_tower()
	_gate(Vector3(0, 0, -480), 0.0, 90.0, 260.0)
	_megaslab(Vector3(-650, 0, -350), 520.0, 280.0)
	_megaslab(Vector3(900, 0, 700), 700.0, 420.0)

	for i in 8:
		var p = spot(450, 900, 20)
		if p != null:
			_wall(p.x, p.y, rng.randf() * TAU, rng.randf_range(250, 800), rng.randf_range(50, 220))

	# Гиганты до горизонта: аркологии с тысячами окон и бетонные мегаструктуры.
	for i in 150:
		var p = spot(330, 2400, 60)
		if p == null:
			continue
		var roll := rng.randf()
		if roll < 0.55:
			var w := rng.randf_range(30, 110)
			var d := rng.randf_range(30, 110)
			var h := rng.randf_range(250, 1200)
			giants.append({"kind": "slab", "pos": Vector2(p.x, p.y), "size": Vector2(w, d), "h": h})
			# Башня напротив скамейки на мосту: крыша сразу над табло с бегущей строкой (шпиль-меч ставит bench_show).
			var cap := INF
			if not bench_tower and Vector2(p.x, p.y).distance_to(Vector2(BENCH_SPOT.x, BENCH_SPOT.z)) < BENCH_TOWER_NEAR:
				cap = BENCH_TOWER_ROOF
				bench_tower = giants.back()
			_slab_tower(p.x, p.y, w, d, h, cap)
		elif roll < 0.72:
			var r := rng.randf_range(15, 50)
			var h := rng.randf_range(250, 1000)
			giants.append({"kind": "round", "pos": Vector2(p.x, p.y), "r": r, "h": h})
			_round_tower(p.x, p.y, r, h)
		elif roll < 0.86:
			_lattice(p.x, p.y, rng.randf_range(50, 130), rng.randf_range(150, 600))
		else:
			_needles(p.x, p.y)

	_bridges_and_pipes()


# --- Размещение --------------------------------------------------------------

func reserve(x: float, z: float, r: float) -> void:
	occupied.append(Vector3(x, z, r))


func is_free(x: float, z: float, r: float) -> bool:
	if PLATFORM.grow(r + 20.0).has_point(Vector2(x, z)):
		return false
	if absf(x) < r + 30.0 and z < PLATFORM.position.y + r and z > CAUSEWAY_END - r:
		return false  # мост к горе
	for o in occupied:
		if Vector2(x, z).distance_to(Vector2(o.x, o.y)) < r + o.z:
			return false
	return true


## Случайное свободное место на кольце [min_d, max_d] вокруг старта (вне города). Сразу занимает его.
func spot(min_d: float, max_d: float, r: float) -> Variant:
	for attempt in 30:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(min_d, max_d)
		var x := cos(angle) * dist
		var z := sin(angle) * dist
		if is_free(x, z, r):
			reserve(x, z, r)
			return Vector2(x, z)
	return null


## Есть ли пол в этой точке на уровне улиц: не над колодцем, не за краем платформы (кроме моста).
func has_floor(p: Vector2) -> bool:
	var cell := Vector2i(roundi(p.x / PITCH), roundi(p.y / PITCH))
	if wells.has(cell) and absf(p.x - cell.x * PITCH) < PLATE / 2.0 + 0.5 and absf(p.y - cell.y * PITCH) < PLATE / 2.0 + 0.5:
		return false
	if PLATFORM.has_point(p):
		return true
	return absf(p.x) < 13.0 and p.y < PLATFORM.position.y and p.y > CAUSEWAY_END


func _yaw_at(x: float, z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, 0, z))


func _pick(list: Array) -> Variant:
	return list[rng.randi() % list.size()]


## Наклонная плита от точки до точки (локальные координаты t). Верх плиты лежит на линии.
## railings: 0 — без перил, 1 — справа, 2 — слева, 3 — с обеих сторон.
func _ramp(t: Transform3D, from_local: Vector3, to_local: Vector3, width: float, mat: Material, visible := true, railings := 0) -> void:
	var a := t * from_local
	var c := t * to_local
	var dir := c - a
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	var thick := 0.4
	var size := Vector3(width, thick, dir.length())
	var center := (a + c) / 2.0 - basis.y * (thick / 2.0)
	if visible:
		b.box(center, size, mat, basis)
	else:
		b.collider_box(center, size, basis)
	for side in [1, 2]:
		if railings & side:
			var off := basis.x * ((1.0 if side == 1 else -1.0) * (width / 2.0 - 0.06))
			_railing(a + off, c + off)


## Решётчатые перила от точки до точки (точки — на уровне пола): поручень, средняя планка, стойки.
## Невидимая стенка вдоль них не даёт упасть.
func _railing(a: Vector3, c: Vector3) -> void:
	var dir := c - a
	var length := dir.length()
	if length < 0.2:
		return
	var basis := Basis.looking_at(dir / length, Vector3.UP)
	var mid := (a + c) / 2.0
	b.box(mid + Vector3.UP * 1.05, Vector3(0.06, 0.06, length), m.metal, basis, false)
	b.box(mid + Vector3.UP * 0.55, Vector3(0.03, 0.03, length), m.metal, basis, false)
	var posts := maxi(int(length / 2.5), 1)
	for i in posts + 1:
		b.box(a.lerp(c, float(i) / posts) + Vector3.UP * 0.53, Vector3(0.05, 1.06, 0.05), m.metal, Basis.IDENTITY, false)
	b.collider_box(mid + Vector3.UP * 0.55, Vector3(0.1, 1.1, length), basis)


## Лестница из ступеней (поднимается в сторону -Z локально) + невидимый пандус под ней.
## Пандус начинается под полом внизу и заканчивается ровно на уровне верхнего пола.
func _stairs(t: Transform3D, bottom: Vector3, h: float, width: float, mat: Material) -> float:
	var st := t * Transform3D(Basis.IDENTITY, bottom)
	var tread := 0.3
	var steps := int(ceil(h / 0.2))
	var rise := h / steps
	for i in steps:
		var top := (i + 1) * rise
		b.box_local(st, Vector3(0, top / 2.0, -(i + 0.5) * tread), Vector3(width, top, tread), mat, false)
	var run := steps * tread
	_ramp(st, Vector3(0, -0.3 * h / run, 0.3), Vector3(0, h, -run), width, mat, false)
	return run


# --- Земля и колоннада -------------------------------------------------------

## Пол города — плиты кварталов и полосы улиц толщиной 30 м. Там, где квартал-колодец, плиты нет.
## По краю платформы — перила (кроме выхода на мост), под ней — опоры, уходящие в бездну.
func _platform() -> void:
	var thick := 30.0
	for i in range(-5, 6):
		for j in range(-7, 2):
			if wells.has(Vector2i(i, j)):
				_well(i * PITCH, j * PITCH)
			else:
				b.box(Vector3(i * PITCH, -thick / 2.0, j * PITCH), Vector3(PLATE, thick, PLATE), m.ground)
				b.occluder(Vector3(i * PITCH, -thick / 2.0, j * PITCH), Vector3(PLATE, thick, PLATE))
	var x0 := PLATFORM.position.x
	var x1 := PLATFORM.end.x
	var z0 := PLATFORM.position.y
	var z1 := PLATFORM.end.y
	for i in range(-6, 6):
		var x := (i + 0.5) * PITCH
		b.box(Vector3(x, -thick / 2.0, (z0 + 76.0) / 2.0), Vector3(8, thick, 76.0 - z0), m.ground)
		b.occluder(Vector3(x, -thick / 2.0, (z0 + 76.0) / 2.0), Vector3(8, thick, 76.0 - z0))
	for j in range(-8, 2):
		var z := (j + 0.5) * PITCH
		b.box(Vector3(0, -thick / 2.0, z), Vector3(x1 - x0, thick, 8), m.ground)
		b.occluder(Vector3(0, -thick / 2.0, z), Vector3(x1 - x0, thick, 8))
	b.box(Vector3(0, -thick / 2.0, z0 + 2.0), Vector3(x1 - x0, thick, 4), m.ground)
	b.box(Vector3(0, -thick / 2.0, (76.0 + z1) / 2.0), Vector3(x1 - x0, thick, z1 - 76.0), m.ground)

	# Перила по краю; на юге — проход на мост к горе.
	_railing(Vector3(x0, 0, z1), Vector3(x1, 0, z1))
	_railing(Vector3(x0, 0, z0), Vector3(x0, 0, z1))
	_railing(Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	_railing(Vector3(x0, 0, z0), Vector3(-16, 0, z0))
	_railing(Vector3(16, 0, z0), Vector3(x1, 0, z0))

	# Опоры под городом, на них — редкие огни, чтобы чувствовалась глубина.
	var px := x0 + 40.0
	while px < x1:
		var pz := z0 + 40.0
		while pz < z1:
			b.box(Vector3(px, (ABYSS - thick) / 2.0, pz), Vector3(18, -ABYSS - thick, 18), m.weathered, Basis.IDENTITY, false)
			for depth in [-80.0, -220.0, -420.0]:
				b.box(Vector3(px + 9.1, depth, pz), Vector3(0.2, 1.5, 0.6), m.beacon, Basis.IDENTITY, false)
			pz += 96.0
		px += 96.0


## Квартал-колодец: провал в бездну. Стены шахты в окнах уходят вниз, поперёк — узкий мостик.
func _well(cx: float, cz: float) -> void:
	var half := PLATE / 2.0
	var depth := 400.0
	var wall: Material = _pick(m.arcology)
	for s in [-1.0, 1.0]:
		b.box(Vector3(cx + s * (half - 1.0), -depth / 2.0, cz), Vector3(2, depth, PLATE), wall, Basis.IDENTITY, false)
		b.box(Vector3(cx, -depth / 2.0, cz + s * (half - 1.0)), Vector3(PLATE - 4.0, depth, 2), wall, Basis.IDENTITY, false)
	for s in [-1.0, 1.0]:
		_railing(Vector3(cx - half, 0, cz + s * half), Vector3(cx + half, 0, cz + s * half))
		_railing(Vector3(cx + s * half, 0, cz - half), Vector3(cx + s * half, 0, cz - 1.6))
		_railing(Vector3(cx + s * half, 0, cz + 1.6), Vector3(cx + s * half, 0, cz + half))
	# Мостик через провал, с перилами.
	_ramp(Transform3D.IDENTITY, Vector3(cx - half, 0.02, cz), Vector3(cx + half, 0.02, cz), 3.0, m.concrete_dark, true, 3)


## Мост над бездной от края города к подножию горы. Широкий, с перилами, фонарями и опорами.
func _causeway() -> void:
	var z0 := PLATFORM.position.y
	var length := z0 - CAUSEWAY_END
	var mid := (z0 + CAUSEWAY_END) / 2.0
	var width := 28.0
	b.box(Vector3(0, -4, mid), Vector3(width, 8, length), m.ground)
	b.occluder(Vector3(0, -4, mid), Vector3(width, 8, length))
	b.box(Vector3(0, 0, mid), Vector3(8, 0.1, length), m.stone, Basis.IDENTITY, false)
	var edge := width / 2.0 - 0.1
	_railing(Vector3(edge, 0, z0), Vector3(edge, 0, CAUSEWAY_END))
	_railing(Vector3(-edge, 0, z0), Vector3(-edge, 0, BENCH_GAP.y))          # слева — разрыв напротив скамейки
	_railing(Vector3(-edge, 0, BENCH_GAP.x), Vector3(-edge, 0, CAUSEWAY_END))
	var z := z0 - 30.0
	while z > CAUSEWAY_END:
		_lamp_post(Vector3(12.5, 0, z), PI / 2.0)
		_lamp_post(Vector3(-12.5, 0, z - 30.0), -PI / 2.0)
		walk_spots.append(Vector3(rng.randf_range(-8, 8), 0, z - 15.0))
		z -= 60.0
	z = z0 - 80.0
	while z > CAUSEWAY_END:
		b.box(Vector3(0, (ABYSS - 8.0) / 2.0, z), Vector3(14, -ABYSS - 8.0, 14), m.weathered, Basis.IDENTITY, false)
		z -= 160.0
	# Широкая площадка в конце — у подножия горы.
	# (на запад — до самой тропы: между площадкой и склоном была яма, из которой не выбраться)
	b.box(Vector3(-17.5, -4, CAUSEWAY_END - 30.0), Vector3(115, 8, 60), m.ground)


## Основание постройки, уходящее в бездну (без коллизии — туда не дойти).
func _foundation(center: Vector3, size: Vector2, basis: Basis, mat: Material) -> void:
	b.box(Vector3(center.x, ABYSS / 2.0, center.z), Vector3(size.x, -ABYSS, size.y), mat, basis, false)


func _colonnade() -> void:
	for i in 31:
		var z := 10.0 - i * 12.0
		for side in [-1.0, 1.0]:
			var x: float = side * 10.0
			b.box(Vector3(x, 22.5, z), Vector3(3, 45, 3), m.concrete)
			b.box(Vector3(x, 0.75, z), Vector3(4.5, 1.5, 4.5), m.concrete_dark)
			b.box(Vector3(x, 44, z), Vector3(4.2, 2, 4.2), m.concrete_dark, Basis.IDENTITY, false)
		b.box(Vector3(0, 46.5, z), Vector3(26, 3, 3), m.concrete, Basis.IDENTITY, false)
	for side in [-1.0, 1.0]:
		b.box(Vector3(side * 10.0, 46.5, -175), Vector3(3, 3, 372), m.concrete, Basis.IDENTITY, false)
	# Тёмная каменная дорожка посередине.
	b.box(Vector3(0, 0, -175), Vector3(14, 0.1, 372), m.stone, Basis.IDENTITY, false)


# --- Город -------------------------------------------------------------------

func _city() -> void:
	# Оси улиц между кварталами.
	for i in range(-6, 6):
		var x := (i + 0.5) * PITCH
		streets.append(Vector4(x, district.position.y, x, district.end.y))
	for j in range(-8, 2):
		var z := (j + 0.5) * PITCH
		streets.append(Vector4(district.position.x, z, district.end.x, z))

	for i in range(-5, 6):
		if i == 0:
			continue  # бульвар с колоннадой
		for j in range(-7, 2):
			var cx := i * PITCH
			var cz := j * PITCH
			var roll := rng.randf()
			if roll < 0.5:
				_sidewalk_plate(cx, cz)
				_perimeter_block(cx, cz)
			elif roll < 0.75:
				_sidewalk_plate(cx, cz)
				_megablock(cx, cz)
			elif roll < 0.82:
				_sidewalk_plate(cx, cz)
				_park(cx, cz)
			elif roll < 0.86:
				_parking_lot(cx, cz)
			elif roll < 0.9:
				_sidewalk_plate(cx, cz)
				_ramp_tower(cx, cz, rng.randf_range(12, 16), rng.randf_range(40, 110))
			elif roll < 0.93:
				_sidewalk_plate(cx, cz)
				_construction_site(cx, cz)
			else:
				wells[Vector2i(i, j)] = true  # провал в бездну; стены и мостик строит _platform

	_roads()
	_levels()
	_street_furniture()
	_roof_bridges()
	_skybridges()


## Квартал стоит на плите тротуара — край плиты и есть бордюр.
func _sidewalk_plate(cx: float, cz: float) -> void:
	b.box(Vector3(cx, CURB / 2.0, cz), Vector3(PLATE, CURB, PLATE), m.sidewalk)
	plated.append(Vector2(cx, cz))


# --- Уровни над землёй -------------------------------------------------------

## Многоуровневый город:
## L1 — галереи вокруг кварталов вдоль фасадов + площадки-хабы над перекрёстками;
## башни доступа с лифтами на части перекрёстков, с площадками на L2 и L3;
## L2 — мосты над улицами вдоль оси X между башнями, L3 — вдоль оси Z;
## длинные лестницы с улицы на хабы.
func _levels() -> void:
	var towers_at := {}  # Vector2i(ix, jz) -> Vector2 позиция перекрёстка
	var hubs := {}
	for c in crossings:
		var key := Vector2i(roundi(c.x / PITCH - 0.5), roundi(c.y / PITCH - 0.5))
		if posmod(key.x, 2) == 0 and posmod(key.y, 2) == 0 and absf(c.x) > 14.0:
			towers_at[key] = c
			hubs[key] = c
		elif rng.randf() < 0.3:
			hubs[key] = c

	for blk in plated:
		_deck_ring(blk, hubs)
	for key in hubs:
		_hub(hubs[key], towers_at.has(key))
		if not towers_at.has(key):
			open_hubs.append(hubs[key])
	for key in towers_at:
		_access_tower(towers_at[key])

	# Мосты L2 — вдоль X между соседними башнями в одном ряду; L3 — вдоль Z в одной колонке.
	for key in towers_at:
		var right := Vector2i(key.x + 2, key.y)
		if towers_at.has(right):
			_level_bridge(towers_at[key], towers_at[right], L2)
		var down := Vector2i(key.x, key.y + 2)
		if towers_at.has(down):
			_level_bridge(towers_at[key], towers_at[down], L3)


## Галерея L1 вокруг квартала: настил над тротуаром вдоль фасадов, перила со стороны улицы,
## опоры. У перекрёстков с хабом перила обрываются, чтобы можно было пройти на хаб.
func _deck_ring(c: Vector2, hubs: Dictionary) -> void:
	var inner := BLOCK / 2.0      # фасады
	var outer := PLATE / 2.0 + 1.5  # край настила над дорогой
	var width := outer - inner
	var mid := (inner + outer) / 2.0
	var length := outer * 2.0
	for side in 4:
		# Ось галереи: вдоль X (север/юг) или вдоль Z (восток/запад).
		var along_x := side < 2
		var sgn := 1.0 if side % 2 == 0 else -1.0
		var center := Vector3(c.x, L1 - 0.2, c.y + sgn * mid) if along_x else Vector3(c.x + sgn * mid, L1 - 0.2, c.y)
		var size := Vector3(length, 0.4, width) if along_x else Vector3(width, 0.4, length)
		b.box(center, size, m.concrete_dark)

		# Перила по внешнему краю; у хабов — короче.
		var rail_from := -outer
		var rail_to := outer
		var ends := [Vector2(c.x - outer - 2.5, c.y + sgn * (outer + 2.5)), Vector2(c.x + outer + 2.5, c.y + sgn * (outer + 2.5))] if along_x \
			else [Vector2(c.x + sgn * (outer + 2.5), c.y - outer - 2.5), Vector2(c.x + sgn * (outer + 2.5), c.y + outer + 2.5)]
		if hubs.has(_crossing_key(ends[0])):
			rail_from += 4.0
		if hubs.has(_crossing_key(ends[1])):
			rail_to -= 4.0
		var edge := sgn * (outer - 0.05)
		if along_x:
			_railing(Vector3(c.x + rail_from, L1, c.y + edge), Vector3(c.x + rail_to, L1, c.y + edge))
		else:
			_railing(Vector3(c.x + edge, L1, c.y + rail_from), Vector3(c.x + edge, L1, c.y + rail_to))

		# Тёплые светильники на стене вдоль галереи.
		var lamp := -inner + 4.0
		var wall := sgn * (inner + 0.08)
		while lamp < inner - 2.0:
			var at := Vector3(c.x + lamp, L1 + 2.6, c.y + wall) if along_x else Vector3(c.x + wall, L1 + 2.6, c.y + lamp)
			b.box(at, Vector3(0.6, 0.12, 0.16) if along_x else Vector3(0.16, 0.12, 0.6), m.lamp_warm, Basis.IDENTITY, false)
			lamp += 8.0
		walk_spots.append(Vector3(center.x, L1, center.z))

		# Опоры и иногда неоновая полоса снизу.
		var p := -outer + 4.0
		while p < outer - 2.0:
			var pillar := Vector3(c.x + p, L1 / 2.0, c.y + sgn * (outer - 0.3)) if along_x \
				else Vector3(c.x + sgn * (outer - 0.3), L1 / 2.0, c.y + p)
			b.box(pillar, Vector3(0.35, L1, 0.35), m.metal)
			p += 12.0
		if rng.randf() < 0.35:
			var strip := center + Vector3(0, -0.22, 0)
			b.box(strip, Vector3(length, 0.05, 0.12) if along_x else Vector3(0.12, 0.05, length), _pick(m.neon), Basis.IDENTITY, false)

		var a := Vector2(center.x - length / 2.0, center.z) if along_x else Vector2(center.x, center.z - length / 2.0)
		var e := Vector2(center.x + length / 2.0, center.z) if along_x else Vector2(center.x, center.z + length / 2.0)
		decks.append(Vector4(a.x, a.y, e.x, e.y))


func _crossing_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / PITCH - 0.5), roundi(p.y / PITCH - 0.5))


## Площадка над перекрёстком на уровне L1: соединяет углы четырёх кварталов.
## Если тут башня доступа — в центре проём под шахту лифта.
func _hub(c: Vector2, has_tower: bool) -> void:
	var half := 6.0
	if has_tower:
		_ring_platform(Vector3(c.x, L1, c.y), half * 2.0, 3.6, m.concrete_dark)
	else:
		b.box(Vector3(c.x, L1 - 0.2, c.y), Vector3(half * 2.0, 0.4, half * 2.0), m.concrete_dark)
	# Перила посередине каждой стороны — там под хабом пустая улица. С востока у башни — лестница.
	for s in [-1.0, 1.0]:
		var e := half - 0.05
		_railing(Vector3(c.x - 2.5, L1, c.y + s * e), Vector3(c.x + 2.5, L1, c.y + s * e))
		if not has_tower or s < 0.0:
			_railing(Vector3(c.x + s * e, L1, c.y - 2.5), Vector3(c.x + s * e, L1, c.y + 2.5))
	access_points.append(Vector3(c.x + 4.5, L1 + 0.3, c.y + 4.5))
	walk_spots.append(Vector3(c.x + 4.5, L1, c.y - 4.5))


## Квадратная площадка с квадратным проёмом в центре (под шахту лифта). y — уровень пола.
func _ring_platform(center: Vector3, outer: float, hole: float, mat: Material) -> void:
	var band := (outer - hole) / 2.0
	var y := center.y - 0.2
	for s in [-1.0, 1.0]:
		b.box(Vector3(center.x, y, center.z + s * (hole / 2.0 + band / 2.0)), Vector3(outer, 0.4, band), mat)
		b.box(Vector3(center.x + s * (hole / 2.0 + band / 2.0), y, center.z), Vector3(band, 0.4, hole), mat)


## Башня доступа на перекрёстке: шахта с лифтом от земли до L3, площадки на L2 и L3,
## длинная лестница с улицы на хаб L1.
func _access_tower(c: Vector2) -> void:
	var top := L3 + 4.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Vector3(c.x + sx * 1.9, top / 2.0, c.y + sz * 1.9), Vector3(0.3, top, 0.3), m.metal)
	b.box(Vector3(c.x, top + 0.2, c.y), Vector3(4.4, 0.4, 4.4), m.concrete_dark)
	b.box(Vector3(c.x - 1.9, top / 2.0, c.y - 2.06), Vector3(0.08, top, 0.02), _pick(m.neon), Basis.IDENTITY, false)
	b.box(Vector3(c.x, top + 0.6, c.y), Vector3(0.5, 0.5, 0.5), m.beacon, Basis.IDENTITY, false)

	for level in [L2, L3]:
		_ring_platform(Vector3(c.x, level, c.y), 10.0, 3.6, m.concrete_dark)
		# Перила площадки; проёмы там, куда подходят мосты (L2 — по X, L3 — по Z).
		var e := 4.95
		for s in [-1.0, 1.0]:
			if level == L3:
				_railing(Vector3(c.x + s * e, level, c.y - e), Vector3(c.x + s * e, level, c.y + e))
				_railing(Vector3(c.x - e, level, c.y + s * e), Vector3(c.x - 2.0, level, c.y + s * e))
				_railing(Vector3(c.x + 2.0, level, c.y + s * e), Vector3(c.x + e, level, c.y + s * e))
			else:
				_railing(Vector3(c.x - e, level, c.y + s * e), Vector3(c.x + e, level, c.y + s * e))
				_railing(Vector3(c.x + s * e, level, c.y - e), Vector3(c.x + s * e, level, c.y - 2.0))
				_railing(Vector3(c.x + s * e, level, c.y + 2.0), Vector3(c.x + s * e, level, c.y + e))
		access_points.append(Vector3(c.x + 3.5, level + 0.3, c.y + 3.5))

	# Ограждение шахты на каждом уровне; проход с юга (-Z) закрывает створка,
	# которая открывается, только когда платформа стоит на этом уровне.
	var gates: Array[Vector3] = []
	for level in [L1, L2, L3]:
		var f := 1.85
		_railing(Vector3(c.x - f, level, c.y + f), Vector3(c.x + f, level, c.y + f))
		_railing(Vector3(c.x - f, level, c.y - f), Vector3(c.x - f, level, c.y + f))
		_railing(Vector3(c.x + f, level, c.y - f), Vector3(c.x + f, level, c.y + f))
		_railing(Vector3(c.x - f, level, c.y - f), Vector3(c.x - 0.8, level, c.y - f))
		_railing(Vector3(c.x + 0.8, level, c.y - f), Vector3(c.x + f, level, c.y - f))
		gates.append(Vector3(c.x, level, c.y - f))

	var stops: Array[float] = [0.0, L1, L2, L3]
	elevators.append({"pos": Vector3(c.x, 0, c.y), "stops": stops, "gates": gates})

	# Лестница с дороги на хаб: подходит к перекрёстку с востока (+X), там у хаба нет перил.
	var t := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(c.x, 0, c.y))
	var steps := int(ceil(L1 / 0.2))
	_stairs(t, Vector3(0, 0, 6.0 + steps * 0.3), L1, 2.0, m.concrete_dark)


## Пешеходный мост над улицей между площадками двух башен, с перилами.
func _level_bridge(a: Vector2, c: Vector2, level: float) -> void:
	var dir := (c - a).normalized()
	var from := Vector3(a.x + dir.x * 4.8, level + 0.02, a.y + dir.y * 4.8)
	var to := Vector3(c.x - dir.x * 4.8, level + 0.02, c.y - dir.y * 4.8)
	_ramp(Transform3D.IDENTITY, from, to, 4.0, m.concrete_dark, true, 3)
	if rng.randf() < 0.5:
		var mid := (from + to) / 2.0 + Vector3.DOWN * 0.45
		var length := from.distance_to(to)
		b.box(mid, Vector3(0.12, 0.05, length) if absf(dir.y) > 0.5 else Vector3(length, 0.05, 0.12), _pick(m.neon), Basis.IDENTITY, false)


## Здания стоят плотным рядом по периметру квартала, фасадами на улицу; внутри — двор.
func _perimeter_block(cx: float, cz: float) -> void:
	var half := BLOCK / 2.0
	var depth := rng.randf_range(10, 13)
	# Северный и южный ряды — во всю ширину, восточный и западный — между ними.
	var rows := [
		{"from": Vector2(cx - half, cz + half - depth / 2.0), "dir": Vector2(1, 0), "length": BLOCK, "yaw": 0.0},
		{"from": Vector2(cx + half, cz - half + depth / 2.0), "dir": Vector2(-1, 0), "length": BLOCK, "yaw": PI},
		{"from": Vector2(cx + half - depth / 2.0, cz + half - depth), "dir": Vector2(0, -1), "length": BLOCK - 2 * depth, "yaw": PI / 2.0},
		{"from": Vector2(cx - half + depth / 2.0, cz - half + depth), "dir": Vector2(0, 1), "length": BLOCK - 2 * depth, "yaw": -PI / 2.0},
	]
	var base_floors := rng.randi_range(5, 12)
	var tall_corner := rng.randf() < 0.4  # иногда угол квартала занимает небоскрёб
	for r in rows.size():
		var row: Dictionary = rows[r]
		var pos := 0.0
		var length: float = row.length
		while pos < length - 6.0:
			var w := minf(rng.randf_range(9, 16), length - pos)
			if length - pos - w < 7.0:
				w = length - pos  # последний дом добирает до угла
			var first := pos == 0.0
			var center: Vector2 = row.from + row.dir * (pos + w / 2.0)
			pos += w
			if rng.randf() < 0.08:
				continue  # проулок
			var t := Transform3D(Basis(Vector3.UP, row.yaw), Vector3(center.x, CURB, center.y))
			if r == 0 and first and tall_corner:
				_skyscraper(t, w - 0.3, depth, rng.randf_range(80, 220))
				continue
			var floors := clampi(base_floors + rng.randi_range(-3, 4), 2, 18)
			if rng.randf() < 0.15 and w >= 8.0:
				_house(t, w - 0.3, depth, rng.randi_range(2, 5))  # старый дом, в который можно зайти
			else:
				_facade_building(t, w - 0.3, depth, floors, rng.randf() < 0.6)
	# Во дворе — мёртвое дерево или брошенная машина.
	if rng.randf() < 0.6:
		_dead_tree(Vector3(cx + rng.randf_range(-3, 3), CURB, cz + rng.randf_range(-3, 3)))
	if rng.randf() < 0.3:
		_car(Vector3(cx + rng.randf_range(-3, 3), CURB, cz + rng.randf_range(-3, 3)), rng.randf() * TAU)


func _facade_mat() -> Material:
	return _pick(m.facades)


## Здание, в которое нельзя зайти. Окна рисует шейдер фасада, внизу — магазин или вход.
## Фасад смотрит в сторону +Z локально.
func _facade_building(t: Transform3D, w: float, d: float, floors: int, shop: bool) -> void:
	var h := floors * FLOOR_H + 0.3
	b.box_local(t, Vector3(0, h / 2.0, 0), Vector3(w, h, d), _facade_mat())
	b.occluder_local(t, Vector3(0, h / 2.0, 0), Vector3(w, h, d))
	b.box_local(t, Vector3(0, h + 0.4, 0), Vector3(w + 0.3, 0.8, d + 0.3), m.concrete_dark, false)
	if shop:
		_storefront(t, w, d)
	else:
		b.box_local(t, Vector3(-w / 2.0 + 1.1, 1.1, d / 2.0 + 0.03), Vector3(1.1, 2.2, 0.06), m.door, false)
	if rng.randf() < 0.4:
		_vertical_sign(t, w, d, h)

	# Что-то на крыше.
	var roof := h + 0.8
	var roll := rng.randf()
	if roll < 0.2:
		b.box_local(t, Vector3(w * 0.2, roof + 1.2, -d * 0.2), Vector3(3, 2.4, 3), m.concrete_dark, false)
	elif roll < 0.4:
		_billboard(t, roof, w)
	elif roll < 0.55:
		b.rod(t * Vector3(w * 0.3, roof + 4, 0), 0.06, 8.0, m.metal)
		b.box_local(t, Vector3(w * 0.3, roof + 8.2, 0), Vector3(0.4, 0.4, 0.4), m.beacon, false)
	roofs.append({"pos": t * Vector3(0, roof, 0), "extent": minf(w, d)})


## Магазин: большая витрина, светящаяся вывеска и козырёк.
func _storefront(t: Transform3D, w: float, d: float) -> void:
	var front := d / 2.0
	b.box_local(t, Vector3(0.6, 1.45, front + 0.03), Vector3(w - 2.6, 2.3, 0.06), m.glass_lit if rng.randf() < 0.3 else m.glass, false)
	b.box_local(t, Vector3(-w / 2.0 + 0.9, 1.1, front + 0.03), Vector3(1.0, 2.2, 0.06), m.door, false)
	b.box_local(t, Vector3(0, 3.0, front + 0.1), Vector3(w * 0.7, 0.55, 0.15), _pick(m.neon), false)
	var awning_center := t * Vector3(0.6, 2.65, front + 0.7)
	b.box(awning_center, Vector3(w - 2.4, 0.05, 1.4), _pick(m.awnings), t.basis * Basis(Vector3.RIGHT, 0.28), false)


## Вертикальная неоновая вывеска, торчащая из стены поперёк улицы.
func _vertical_sign(t: Transform3D, w: float, d: float, h: float) -> void:
	var length := minf(rng.randf_range(6, 14), h - 6.0)
	if length < 4.0:
		return
	var x := (w / 2.0 - 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
	var center := Vector3(x, 5.0 + length / 2.0, d / 2.0 + 0.7)
	b.box_local(t, center, Vector3(0.18, length + 0.3, 1.2), m.metal, false)
	signs.append({"xform": t * Transform3D(Basis(Vector3.UP, PI / 2.0), center + Vector3(0.1, 0, 0)), "size": Vector2(1.0, length)})


## Небоскрёб со ступенчатыми уступами, неоновыми кантами, причалами для летающих машин,
## шпилем с красным огнём и рекламой. Стоит основанием в t.
func _skyscraper(t: Transform3D, w: float, d: float, h: float) -> void:
	var mat := _facade_mat()
	var tiers := rng.randi_range(2, 4)
	var y := 0.0
	var cw := w
	var cd := d
	for tier in tiers:
		var th := h * 0.5 if tier == 0 else h * 0.5 / (tiers - 1)
		var line: Material = _pick(m.neon)
		b.box_local(t, Vector3(0, y + th / 2.0, 0), Vector3(cw, th, cd), mat, y < 60.0)
		b.occluder_local(t, Vector3(0, y + th / 2.0, 0), Vector3(cw, th, cd))
		b.box_local(t, Vector3(0, y + th + 0.4, 0), Vector3(cw + 0.6, 0.8, cd + 0.6), m.concrete_dark, false)
		b.box_local(t, Vector3(0, y + th + 0.85, cd / 2.0 + 0.32), Vector3(cw + 0.6, 0.12, 0.05), line, false)
		# Причал для летающих машин.
		if rng.randf() < 0.35 and th > 20.0:
			var py := y + th * rng.randf_range(0.3, 0.8)
			b.box_local(t, Vector3(cw / 2.0 + 4.0, py, 0), Vector3(8, 0.6, cd * 0.5), m.concrete_dark, false)
			b.box_local(t, Vector3(cw / 2.0 + 8.0, py + 0.35, 0), Vector3(0.1, 0.1, cd * 0.5), line, false)
		y += th
		cw *= rng.randf_range(0.6, 0.85)
		cd *= rng.randf_range(0.6, 0.85)
	var spire := rng.randf_range(15, 60)
	b.box_local(t, Vector3(0, y + spire / 2.0, 0), Vector3(1, spire, 1), m.metal, false)
	b.box_local(t, Vector3(0, y + spire + 0.4, 0), Vector3(0.8, 0.8, 0.8), m.beacon, false)
	if rng.randf() < 0.5:
		_add_ad(t, Vector3(0, minf(h * 0.3, 80.0), d / 2.0 + 0.12), Vector2(w * 0.7, w * 0.9))
	if rng.randf() < 0.5:
		_vertical_sign(t, w, d, h)
	city_towers.append({"pos": t.origin, "height": h, "radius": maxf(w, d) / 2.0})
	towers.append({"pos": t.origin, "height": h, "radius": maxf(w, d) * 0.6})


## Мегаблок: квартал-подиум с магазинами, на нём один или два небоскрёба.
func _megablock(cx: float, cz: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, (rng.randi() % 4) * PI / 2.0), Vector3(cx, CURB, cz))
	var podium := rng.randf_range(10, 22)
	b.box_local(t, Vector3(0, podium / 2.0, 0), Vector3(34, podium, 34), _facade_mat())
	b.occluder_local(t, Vector3(0, podium / 2.0, 0), Vector3(34, podium, 34))
	_storefront(t, 34, 34)
	_add_ad(t, Vector3(0, podium * 0.6, 17.12), Vector2(20, podium * 0.55))
	var top := t.translated_local(Vector3(0, podium, 0))
	if rng.randf() < 0.3:
		for s in [-1.0, 1.0]:
			_skyscraper(top.translated_local(Vector3(s * 8.5, 0, -s * 8.5)), 13, 13, rng.randf_range(100, 260))
	else:
		_skyscraper(top, rng.randf_range(18, 26), rng.randf_range(18, 26), rng.randf_range(120, 380))


## Застеклённые воздушные мосты между соседними небоскрёбами — не больше двух на башню,
## иначе из первой же башни расходится веер ко всем соседям.
func _skybridges() -> void:
	var made := 0
	var per_tower := {}
	for a in city_towers.size():
		for c in range(a + 1, city_towers.size()):
			if made >= 25:
				return
			var pa: Vector3 = city_towers[a].pos
			var pb: Vector3 = city_towers[c].pos
			var dist := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
			if dist < 25.0 or dist > 110.0 or rng.randf() > 0.4:
				continue
			var ha: float = city_towers[a].height
			var hb: float = city_towers[c].height
			var y := maxf(pa.y, pb.y) + minf(ha, hb) * rng.randf_range(0.3, 0.45)
			if per_tower.get(a, 0) >= 2 or per_tower.get(c, 0) >= 2:
				continue
			per_tower[a] = per_tower.get(a, 0) + 1
			per_tower[c] = per_tower.get(c, 0) + 1
			var mid := Vector3((pa.x + pb.x) / 2.0, y, (pa.z + pb.z) / 2.0)
			var basis := Basis(Vector3.UP, atan2(pb.x - pa.x, pb.z - pa.z))
			b.box(mid, Vector3(5, 3.5, dist), _facade_mat(), basis)  # твёрдый: летающие машины его облетают
			b.box(mid + Vector3.DOWN * 1.8, Vector3(0.3, 0.1, dist), _pick(m.neon), basis, false)
			made += 1


func _billboard(t: Transform3D, roof: float, w: float) -> void:
	for s in [-1.0, 1.0]:
		b.rod(t * Vector3(s * w * 0.25, roof + 2.0, 0), 0.08, 4.0, m.metal)
	b.box_local(t, Vector3(0, roof + 5.0, 0), Vector3(w * 0.7, 3.0, 0.15), m.billboard, false)
	_add_ad(t, Vector3(0, roof + 5.0, 0.09), Vector2(w * 0.7, 3.0))


## Запоминает место под рекламу: панель смотрит в +Z локально.
func _add_ad(t: Transform3D, local_center: Vector3, size: Vector2) -> void:
	ads.append({"xform": t * Transform3D(Basis.IDENTITY, local_center), "size": size})


## Башня, с которой прыгнул герой: самая высокая в городе, тёмная, с огромной рекламой.
func _tallest_tower() -> void:
	var t := Transform3D(Basis(Vector3.UP, PI), TALLEST_TOWER)
	var w := 46.0
	var h := TALLEST_HEIGHT
	b.box_local(t, Vector3(0, h / 2.0, 0), Vector3(w, h, w), m.tower_panels)
	b.occluder_local(t, Vector3(0, h / 2.0, 0), Vector3(w, h, w))
	_slits(t, 0.0, h, w, w, 0.0)
	var ledge := 30.0
	while ledge < h:
		b.box_local(t, Vector3(0, ledge, 0), Vector3(w + 3, 1.5, w + 3), m.concrete_dark, false)
		ledge += 40.0
	b.box_local(t, Vector3(0, h + 40, 0), Vector3(2, 80, 2), m.metal, false)
	# Огромные горящие экраны на фасаде, обращённом к городу, — между карнизами (30, 70, 110… м),
	# чтобы карниз не перечёркивал надпись.
	_add_ad(t, Vector3(0, 90, w / 2.0 + 0.45), Vector2(30, 34))
	_add_ad(t, Vector3(0, 250, w / 2.0 + 0.45), Vector2(34, 30))
	towers.append({"pos": TALLEST_TOWER, "height": h, "radius": w * 0.7})


## Сквер: мёртвые деревья, скамейки, пустой фонтан.
func _park(cx: float, cz: float) -> void:
	b.box(Vector3(cx, CURB + 0.01, cz), Vector3(BLOCK, 0.02, BLOCK), m.soil, Basis.IDENTITY, false)
	for k in rng.randi_range(6, 10):
		_dead_tree(Vector3(cx + rng.randf_range(-15, 15), CURB, cz + rng.randf_range(-15, 15)))
	for k in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		_bench(Vector3(cx + cos(a) * 9.0, CURB, cz + sin(a) * 9.0), a + PI / 2.0)
	for s in [-1.0, 1.0]:
		b.box(Vector3(cx + s * 3.0, CURB + 0.3, cz), Vector3(0.4, 0.6, 6.4), m.concrete)
		b.box(Vector3(cx, CURB + 0.3, cz + s * 3.0), Vector3(6, 0.6, 0.4), m.concrete)
	plazas.append(Vector2(cx, cz))


## Парковка: разметка и ряды брошенных машин.
func _parking_lot(cx: float, cz: float) -> void:
	b.box(Vector3(cx, 0.02, cz), Vector3(PLATE, 0.04, PLATE), m.asphalt, Basis.IDENTITY, false)
	for row in [-9.0, 9.0]:
		for k in 12:
			var x := cx - 16.5 + k * 3.0
			b.box(Vector3(x, 0.045, cz + row), Vector3(0.1, 0.01, 5.0), m.paint, Basis.IDENTITY, false)
			if rng.randf() < 0.45 and k < 11:
				_car(Vector3(x + 1.5, 0, cz + row), (0.0 if row > 0 else PI) + rng.randf_range(-0.1, 0.1))


## Стройка: бетонный каркас за забором.
func _construction_site(cx: float, cz: float) -> void:
	_lattice(cx, cz, rng.randf_range(22, 28), rng.randf_range(20, 45))
	for s in [-1.0, 1.0]:
		b.box(Vector3(cx + s * 17.5, CURB + 1.0, cz), Vector3(0.08, 2.0, 35), m.fence)
		b.box(Vector3(cx, CURB + 1.0, cz + s * 17.5), Vector3(35, 2.0, 0.08), m.fence)


## Асфальт, разделительная разметка, зебры у перекрёстков.
func _roads() -> void:
	var cross_x: Array[float] = []
	var cross_z: Array[float] = []
	for s in streets:
		if s.x == s.z:
			cross_x.append(s.x)
		else:
			cross_z.append(s.y)

	for s in streets:
		var vertical := s.x == s.z
		var a := Vector2(s.x, s.y)
		var c := Vector2(s.z, s.w)
		var length := a.distance_to(c)
		var mid := (a + c) / 2.0
		var size := Vector3(8.4, 0.02, length) if vertical else Vector3(length, 0.02, 8.4)
		b.box(Vector3(mid.x, 0.01, mid.y), size, m.asphalt, Basis.IDENTITY, false)

		# Пунктир посередине, кроме перекрёстков.
		var crossings := cross_z if vertical else cross_x
		var pos := 0.0
		while pos < length:
			var p := a.lerp(c, pos / length)
			var along := p.y if vertical else p.x
			var near := false
			for q in crossings:
				if absf(along - q) < 8.0:
					near = true
			if not near:
				var dash := Vector3(0.12, 0.012, 2.5) if vertical else Vector3(2.5, 0.012, 0.12)
				b.box(Vector3(p.x, 0.025, p.y), dash, m.paint_yellow, Basis.IDENTITY, false)
			pos += 6.0

	# Зебры и светофоры.
	for x in cross_x:
		for z in cross_z:
			crossings.append(Vector2(x, z))
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.5:
					for k in 7:
						b.box(Vector3(x - 3.0 + k, 0.025, z + side * 9.0), Vector3(0.5, 0.012, 3.0), m.paint, Basis.IDENTITY, false)
			if rng.randf() < 0.6:
				_traffic_light(Vector3(x + 5.6, CURB, z + 5.6))


func _traffic_light(pos: Vector3) -> void:
	b.cylinder(pos + Vector3(0, 2.25, 0), 0.07, 4.5, m.metal)
	b.box(pos + Vector3(-2.0, 4.4, 0), Vector3(4.0, 0.08, 0.08), m.metal, Basis.IDENTITY, false)
	var head := pos + Vector3(-3.6, 3.9, 0)
	b.box(head, Vector3(0.35, 1.0, 0.3), m.metal, Basis.IDENTITY, false)
	b.box(head + Vector3(0, 0.3, 0.16), Vector3(0.22, 0.22, 0.04), m.signal_off, Basis.IDENTITY, false)
	b.box(head + Vector3(0, 0.0, 0.16), Vector3(0.22, 0.22, 0.04), m.signal_amber, Basis.IDENTITY, false)
	b.box(head + Vector3(0, -0.3, 0.16), Vector3(0.22, 0.22, 0.04), m.signal_off, Basis.IDENTITY, false)


## Фонари, столбы с проводами, деревья, скамейки, урны, гидранты, машины вдоль улиц.
func _street_furniture() -> void:
	for s in streets:
		var a := Vector2(s.x, s.y)
		var c := Vector2(s.z, s.w)
		var length := a.distance_to(c)
		var dir := (c - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var has_wires := rng.randf() < 0.5
		var last_pole := Vector3.INF
		var pos := 10.0
		while pos < length:
			var center := a + dir * pos
			if absf(center.x) > 14.0:
				var lamp := center + side * 5.5
				if has_floor(lamp):
					_lamp_post(Vector3(lamp.x, CURB, lamp.y), atan2(side.x, side.y))
				var pole := center - side * 5.5
				if not has_floor(pole):
					last_pole = Vector3.INF  # над колодцем столба нет — провода обрываются
				elif has_wires:
					var top := Vector3(pole.x, CURB + 8.5, pole.y)
					_utility_pole(Vector3(pole.x, CURB, pole.y), atan2(dir.x, dir.y))
					if last_pole != Vector3.INF:
						_wires(last_pole, top, Vector3(side.x, 0, side.y))
					last_pole = top
			pos += 30.0

		# Между фонарями — деревья, скамейки, урны, гидранты.
		pos = 22.0
		while pos < length:
			var center := a + dir * pos
			if absf(center.x) > 14.0:
				var sgn := 1.0 if rng.randf() < 0.5 else -1.0
				var p := center + side * (5.0 * sgn)
				var p3 := Vector3(p.x, CURB, p.y)
				var yaw := atan2(side.x * sgn, side.y * sgn)
				var kind := rng.randi() % 5 if has_floor(p) else -1
				match kind:
					0, 1: _dead_tree(p3)
					2: _bench(p3, yaw)
					3: b.cylinder(p3 + Vector3(0, 0.45, 0), 0.25, 0.9, m.metal)  # урна
					4: b.cylinder(p3 + Vector3(0, 0.35, 0), 0.12, 0.7, m.hydrant)
			pos += rng.randf_range(10, 20)

		# Брошенные машины у обочины и посреди дороги.
		pos = rng.randf_range(5, 30)
		while pos < length:
			var center := a + dir * pos
			if absf(center.x) > 14.0:
				var heading := atan2(-dir.x, -dir.y)
				if rng.randf() < 0.75:
					var curb_side := 1.0 if rng.randf() < 0.5 else -1.0
					var p := center + side * (2.9 * curb_side)
					_car(Vector3(p.x, 0, p.y), heading + (PI if curb_side < 0 else 0.0) + rng.randf_range(-0.05, 0.05))
				else:
					_car(Vector3(center.x, 0, center.y), heading + rng.randf_range(-0.8, 0.8))
			pos += rng.randf_range(25, 60)


func _lamp_post(pos: Vector3, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.cylinder(pos + Vector3(0, 3, 0), 0.08, 6.0, m.metal)
	b.box_local(t, Vector3(0, 5.95, -0.6), Vector3(0.08, 0.08, 1.2), m.metal, false)
	b.box_local(t, Vector3(0, 5.85, -1.15), Vector3(0.25, 0.15, 0.4), m.metal, false)


func _utility_pole(pos: Vector3, yaw: float) -> void:
	b.cylinder(pos + Vector3(0, 4.5, 0), 0.13, 9.0, m.wood_pole)
	b.box(pos + Vector3(0, 8.5, 0), Vector3(1.8, 0.12, 0.12), m.wood_pole, Basis(Vector3.UP, yaw + PI / 2.0), false)


## Провисающие провода между двумя столбами.
func _wires(a: Vector3, c: Vector3, across: Vector3) -> void:
	for k in [-0.8, 0.0, 0.8]:
		var off: Vector3 = across * k
		var p0 := a + off
		var p2 := c + off
		var sag := (p0 + p2) / 2.0 + Vector3.DOWN * 0.9
		var q1 := p0.lerp(sag, 0.5) + Vector3.DOWN * 0.25
		var q2 := sag.lerp(p2, 0.5) + Vector3.DOWN * 0.25
		b.rod_between(p0, q1, 0.015, m.wire)
		b.rod_between(q1, sag, 0.015, m.wire)
		b.rod_between(sag, q2, 0.015, m.wire)
		b.rod_between(q2, p2, 0.015, m.wire)


## Голое мёртвое дерево.
func _dead_tree(pos: Vector3) -> void:
	var h := rng.randf_range(4, 7)
	b.cylinder(pos + Vector3(0, h / 2.0, 0), 0.13, h, m.bark)
	b.box(pos + Vector3(0, 0.01, 0), Vector3(1.2, 0.02, 1.2), m.soil, Basis.IDENTITY, false)
	for k in rng.randi_range(4, 7):
		var start := pos + Vector3(0, rng.randf_range(h * 0.45, h * 0.95), 0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.5, 1.1))
		var length := rng.randf_range(1.0, 2.5)
		var end := start + basis * Vector3.UP * length
		b.rod_between(start, end, 0.045, m.bark)
		var twig := basis * Basis(Vector3.RIGHT, rng.randf_range(-0.7, 0.7))
		b.rod_between(end, end + twig * Vector3.UP * length * 0.6, 0.025, m.bark)


func _bench(pos: Vector3, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.box_local(t, Vector3(0, 0.45, 0), Vector3(1.6, 0.06, 0.4), m.wood_pole)
	b.box_local(t, Vector3(0, 0.75, 0.2), Vector3(1.6, 0.4, 0.05), m.wood_pole, false)
	for lx in [-0.7, 0.7]:
		b.box_local(t, Vector3(lx, 0.22, 0), Vector3(0.06, 0.44, 0.4), m.metal, false)


## Брошенная машина. Смотрит в сторону -Z локально.
func _car(pos: Vector3, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), pos)
	var paint: Material = _pick(m.car_paints)
	var long := rng.randf() < 0.3  # иногда фургон
	var length := 5.0 if long else 4.3
	b.box_local(t, Vector3(0, 0.6, 0), Vector3(1.8, 0.6, length), paint)
	if long:
		b.box_local(t, Vector3(0, 1.45, 0.4), Vector3(1.75, 1.1, length - 1.3), paint, false)
		b.box_local(t, Vector3(0, 1.2, -length / 2.0 + 0.85), Vector3(1.6, 0.55, 0.5), m.glass, false)
	else:
		b.box_local(t, Vector3(0, 1.12, 0.2), Vector3(1.6, 0.48, 2.2), m.glass, false)
		b.box_local(t, Vector3(0, 1.38, 0.25), Vector3(1.55, 0.05, 1.9), paint, false)
	for z in [-length / 2.0 + 0.04, length / 2.0 - 0.04]:
		b.box_local(t, Vector3(0, 0.42, z), Vector3(1.85, 0.2, 0.12), m.rubber, false)
	for wx in [-0.82, 0.82]:
		for wz in [-length / 2.0 + 0.85, length / 2.0 - 0.85]:
			b.cylinder(t * Vector3(wx, 0.33, wz), 0.33, 0.25, m.rubber, t.basis * Basis(Vector3.FORWARD, PI / 2.0), false)


## Мостики между соседними крышами.
func _roof_bridges() -> void:
	var made := 0
	for a in roofs.size():
		for c in range(a + 1, roofs.size()):
			if made >= 40:
				return
			var pa: Vector3 = roofs[a].pos
			var pb: Vector3 = roofs[c].pos
			var flat := Vector2(pb.x - pa.x, pb.z - pa.z)
			if flat.length() < 18 or flat.length() > 34 or absf(pa.y - pb.y) > 4.0 or rng.randf() > 0.35:
				continue
			var dir := Vector3(flat.x, 0, flat.y).normalized()
			var extent_a: float = roofs[a].extent
			var extent_b: float = roofs[c].extent
			var start := pa + dir * (extent_a / 2.0 - 0.6) + Vector3.UP * 0.02
			var end := pb - dir * (extent_b / 2.0 - 0.6) + Vector3.UP * 0.02
			_ramp(Transform3D.IDENTITY, start, end, 2.2, m.concrete_dark, true, 3)
			made += 1


# --- Дома, в которые можно зайти ----------------------------------------------

## Дом с дверью, окнами, лестницами на каждом этаже и выходом на крышу.
## Фасад смотрит в +Z локально. Лестницы чередуются: на чётных этажах у левой стены, на нечётных — у правой.
func _house(t: Transform3D, w: float, d: float, floors: int) -> void:
	var th := 0.3
	var stair_w := 1.4
	var mat: Material = _pick(m.house_facades)  # штукатурка/кирпич — у этих домов настоящие окна
	var z_bottom := d / 2.0 - th - 1.5  # перед лестницей полтора метра, чтобы удобно зайти
	for f in floors:
		var y0 := f * FLOOR_H
		var side := -1.0 if f % 2 == 0 else 1.0

		var front: Array[Vector4] = []
		var balcony := f > 0 and rng.randf() < 0.25
		if f == 0 or balcony:
			front.append(Vector4(0, 1.4 if f == 0 else 1.1, 0, 2.3))  # дверь (или выход на балкон)
		_add_windows(front, w - 2 * th, f == 0 or balcony)
		_holed_wall(t, Vector3(0, 0, d / 2.0 - th / 2.0), true, w, y0, th, front, mat)
		if balcony:
			_balcony(t, y0, d)
		var back: Array[Vector4] = []
		_add_windows(back, w - 2 * th, false)
		_holed_wall(t, Vector3(0, 0, -d / 2.0 + th / 2.0), true, w, y0, th, back, mat)
		for s in [-1.0, 1.0]:
			var holes: Array[Vector4] = []
			_add_windows(holes, d - 2 * th, false)
			_holed_wall(t, Vector3(s * (w / 2.0 - th / 2.0), 0, 0), false, d - 2 * th, y0, th, holes, mat)

		# Лестница наверх и перекрытие с проёмом над ней — на всю длину, чтобы не биться головой.
		# Край проёма наверху совпадает с концом пандуса — без щели и без ступеньки.
		var sx := side * (w / 2.0 - th - stair_w / 2.0)
		var run := _stairs(t, Vector3(sx, y0, z_bottom), FLOOR_H, stair_w, m.concrete_dark)
		var z_top := z_bottom - run
		var hole := Rect2(sx - stair_w / 2.0 - 0.3, z_top, stair_w + 0.6, run + 0.3)
		_slab(t, (f + 1) * FLOOR_H, w + 0.3, d + 0.3, hole, m.concrete_dark)

		if rng.randf() < 0.12:
			lights.append(t * Vector3(0, y0 + 2.6, 0))
		if rng.randf() < 0.15:
			interior_spots.append(t * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(-side * w * 0.15, y0, 0)))

	var roof_y := floors * FLOOR_H
	b.cylinder(t * Vector3(w / 2.0 + 0.08, roof_y / 2.0, d / 2.0 + 0.08), 0.06, roof_y, m.metal, t.basis, false)
	if rng.randf() < 0.3:  # бак на крыше
		var tank := t * Vector3(-w * 0.2, roof_y, -d * 0.25)
		b.cylinder(tank + Vector3(0, 1.4, 0), 0.9, 1.8, m.metal)
	roofs.append({"pos": t * Vector3(0, roof_y, 0), "extent": minf(w, d)})


func _add_windows(holes: Array[Vector4], length: float, has_door: bool) -> void:
	var count := maxi(int(length / 3.0), 1)
	for i in count:
		var c := -length / 2.0 + (i + 0.5) * length / count
		if has_door and absf(c) < 1.5:
			continue
		if rng.randf() < 0.15:
			continue  # глухой участок стены
		holes.append(Vector4(c, 1.1, 0.9, 2.3))
	holes.sort_custom(func(a: Vector4, c: Vector4) -> bool: return a.x < c.x)


## Стена этажа с проёмами. Проём: (центр вдоль стены, ширина, низ, верх).
## Под окнами — подоконники, иногда кондиционер.
func _holed_wall(t: Transform3D, origin: Vector3, along_x: bool, length: float, y0: float, thick: float, holes: Array[Vector4], mat: Material) -> void:
	var outward := Vector3(0, 0, signf(origin.z)) if along_x else Vector3(signf(origin.x), 0, 0)
	var cursor := -length / 2.0
	for hole in holes:
		var left := hole.x - hole.y / 2.0
		var right := hole.x + hole.y / 2.0
		_wall_piece(t, origin, along_x, cursor, left, y0, y0 + FLOOR_H, thick, mat)
		_wall_piece(t, origin, along_x, left, right, y0, y0 + hole.z, thick, mat)
		_wall_piece(t, origin, along_x, left, right, y0 + hole.w, y0 + FLOOR_H, thick, mat)
		cursor = right
		if hole.z > 0.1:
			var along := Vector3(hole.x, 0, 0) if along_x else Vector3(0, 0, hole.x)
			var sill := origin + along + outward * (thick / 2.0 + 0.08)
			sill.y = y0 + hole.z - 0.03
			var sill_size := Vector3(hole.y + 0.2, 0.06, 0.16) if along_x else Vector3(0.16, 0.06, hole.y + 0.2)
			b.box_local(t, sill, sill_size, m.concrete_dark, false)
			if y0 > 0.0 and rng.randf() < 0.12:
				var ac := origin + along + outward * (thick / 2.0 + 0.2)
				ac.y = y0 + 0.4
				var ac_size := Vector3(0.75, 0.5, 0.35) if along_x else Vector3(0.35, 0.5, 0.75)
				b.box_local(t, ac, ac_size, m.metal, false)
	_wall_piece(t, origin, along_x, cursor, length / 2.0, y0, y0 + FLOOR_H, thick, mat)


func _wall_piece(t: Transform3D, origin: Vector3, along_x: bool, from: float, to: float, y_low: float, y_high: float, thick: float, mat: Material) -> void:
	if to - from < 0.01 or y_high - y_low < 0.01:
		return
	var mid := (from + to) / 2.0
	var c := origin + (Vector3(mid, 0, 0) if along_x else Vector3(0, 0, mid))
	c.y = (y_low + y_high) / 2.0
	var size := Vector3(to - from, y_high - y_low, thick) if along_x else Vector3(thick, y_high - y_low, to - from)
	b.box_local(t, c, size, mat)


## Небольшой балкон с перилами перед выходом на фасаде.
func _balcony(t: Transform3D, y0: float, d: float) -> void:
	var z := d / 2.0 + 0.6
	b.box_local(t, Vector3(0, y0 - 0.075, z), Vector3(2.6, 0.15, 1.2), m.concrete_dark)
	b.box_local(t, Vector3(0, y0 + 0.5, z + 0.57), Vector3(2.6, 1.0, 0.06), m.metal)
	for s in [-1.0, 1.0]:
		b.box_local(t, Vector3(s * 1.27, y0 + 0.5, z), Vector3(0.06, 1.0, 1.2), m.metal)


## Плита перекрытия с прямоугольным проёмом (в локальных x, z).
func _slab(t: Transform3D, y_top: float, w: float, d: float, hole: Rect2, mat: Material) -> void:
	var cy := y_top - 0.1
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var z0 := -d / 2.0
	var z1 := d / 2.0
	_slab_piece(t, x0, hole.position.x, z0, z1, cy, mat)
	_slab_piece(t, hole.end.x, x1, z0, z1, cy, mat)
	_slab_piece(t, hole.position.x, hole.end.x, z0, hole.position.y, cy, mat)
	_slab_piece(t, hole.position.x, hole.end.x, hole.end.y, z1, cy, mat)


func _slab_piece(t: Transform3D, xa: float, xb: float, za: float, zb: float, cy: float, mat: Material) -> void:
	if xb - xa < 0.01 or zb - za < 0.01:
		return
	b.box_local(t, Vector3((xa + xb) / 2.0, cy, (za + zb) / 2.0), Vector3(xb - xa, 0.2, zb - za), mat)


## Башня, вокруг которой спиралью поднимается пандус. Наверху — смотровая площадка.
func _ramp_tower(x: float, z: float, core: float, h: float) -> void:
	var t := _yaw_at(x, z)
	b.box_local(t, Vector3(0, h / 2.0, 0), Vector3(core, h, core), m.panels)
	b.occluder_local(t, Vector3(0, h / 2.0, 0), Vector3(core, h, core))
	var rw := 4.0
	var half := core / 2.0 + rw / 2.0
	var corners := [Vector2(half, half), Vector2(half, -half), Vector2(-half, -half), Vector2(-half, half)]
	var slope := tan(deg_to_rad(16.0))
	var y := 0.0
	var k := 0
	while y < h - 0.01:
		var a: Vector2 = corners[k % 4]
		var c: Vector2 = corners[(k + 1) % 4]
		var y2 := minf(y + a.distance_to(c) * slope, h)
		# Перила — с внешней стороны.
		var forward := Vector3(c.x - a.x, 0, c.y - a.y)
		var outward := Vector3((a.x + c.x) / 2.0, 0, (a.y + c.y) / 2.0)
		var rail := 1 if forward.cross(Vector3.UP).dot(outward) > 0 else 2
		_ramp(t, Vector3(a.x, y, a.y), Vector3(c.x, y2, c.y), rw, m.concrete_dark, true, rail)
		b.box_local(t, Vector3(c.x, y2 - 0.2, c.y), Vector3(rw, 0.4, rw), m.concrete_dark)
		y = y2
		k += 1
	var deck := core + 2 * rw
	b.box_local(t, Vector3(0, h - 0.2, 0), Vector3(deck, 0.4, deck), m.concrete_dark)
	for s in [-1.0, 1.0]:
		b.box_local(t, Vector3(s * deck / 2.0, h + 0.5, 0), Vector3(0.2, 1.0, deck), m.metal)
		b.box_local(t, Vector3(0, h + 0.5, s * deck / 2.0), Vector3(deck, 1.0, 0.2), m.metal)
	towers.append({"pos": Vector3(x, 0, z), "height": h, "radius": deck * 0.7})


# --- Мегаструктуры -----------------------------------------------------------

func _gate(c: Vector3, yaw: float, gap: float, h: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), c)
	var pw := 35.0
	for side in [-1.0, 1.0]:
		var lx: float = side * (gap / 2.0 + pw / 2.0)
		b.box_local(t, Vector3(lx, (h + ABYSS) / 2.0, 0), Vector3(pw, h - ABYSS, 30), m.weathered)
		b.occluder_local(t, Vector3(lx, (h + ABYSS) / 2.0, 0), Vector3(pw, h - ABYSS, 30))
		_slits(t, 0.0, h, pw, 30, lx)
		var wp := t * Vector3(lx, 0, 0)
		reserve(wp.x, wp.z, 30)
	b.box_local(t, Vector3(0, h + 15, 0), Vector3(gap + pw * 2 + 10, 30, 34), m.concrete_dark, false)


## Гигантская плита-потолок на опорах: под ней можно гулять.
func _megaslab(c: Vector3, size: float, height: float) -> void:
	var thick := 30.0
	b.box(c + Vector3(0, height + thick / 2.0, 0), Vector3(size, thick, size), m.concrete_dark, Basis.IDENTITY, false)
	b.occluder(c + Vector3(0, height + thick / 2.0, 0), Vector3(size, thick, size))
	var ribs := 8
	for i in ribs + 1:
		var off := -size / 2.0 + i * size / ribs
		b.box(c + Vector3(off, height - 4, 0), Vector3(4, 8, size), m.concrete, Basis.IDENTITY, false)
		b.box(c + Vector3(0, height - 4, off), Vector3(size, 8, 4), m.concrete, Basis.IDENTITY, false)
	for i in 3:
		for j in 3:
			var px := c.x + (i - 1) * size * 0.35
			var pz := c.z + (j - 1) * size * 0.35
			b.box(Vector3(px, (height + ABYSS) / 2.0, pz), Vector3(28, height - ABYSS, 28), m.weathered, Basis.IDENTITY, false)
			b.occluder(Vector3(px, (height + ABYSS) / 2.0, pz), Vector3(28, height - ABYSS, 28))
			reserve(px, pz, 30)
	# Конструкции, свисающие с потолка.
	for k in 7:
		var hx := c.x + rng.randf_range(-size / 2.5, size / 2.5)
		var hz := c.z + rng.randf_range(-size / 2.5, size / 2.5)
		var hh := rng.randf_range(40, 140)
		var hs := Vector3(rng.randf_range(10, 30), hh, rng.randf_range(10, 30))
		b.box(Vector3(hx, height - hh / 2.0, hz), hs, m.concrete, Basis.IDENTITY, false)


## Длинная стена с контрфорсами и проходами.
func _wall(x: float, z: float, yaw: float, length: float, h: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))
	var thick := rng.randf_range(8, 16)
	# Сначала проверяем, что стена ничего не перерезает.
	var points: Array[Vector3] = []
	var lx := -length / 2.0
	while lx <= length / 2.0:
		points.append(t * Vector3(lx, 0, 0))
		lx += 25.0
	for p in points:
		if Vector2(p.x, p.z).distance_to(Vector2(x, z)) > 1.0 and not is_free(p.x, p.z, thick + 10):
			return
	for p in points:
		reserve(p.x, p.z, thick + 10)

	var pos := -length / 2.0
	while pos < length / 2.0:
		var end := minf(pos + rng.randf_range(60, 160), length / 2.0)
		var seg := end - pos
		var mid := pos + seg / 2.0
		b.box_local(t, Vector3(mid, (h + ABYSS) / 2.0, 0), Vector3(seg, h - ABYSS, thick), m.panels, false)
		b.occluder_local(t, Vector3(mid, (h + ABYSS) / 2.0, 0), Vector3(seg, h - ABYSS, thick))
		b.box_local(t, Vector3(mid, h + 1.5, 0), Vector3(seg, 3, thick + 4), m.concrete_dark, false)
		var bx := pos + 12.0
		while bx < end - 6.0:
			for side in [-1.0, 1.0]:
				b.box_local(t, Vector3(bx, h * 0.35, side * (thick / 2.0 + 4.0)), Vector3(6, h * 0.7, 8), m.concrete)
			bx += 30.0
		pos = end + rng.randf_range(14, 30)  # проход


## cap — обрезать башню на этой высоте (крыша), не меняя остального мира: случайные числа берутся те же.
func _slab_tower(x: float, z: float, w: float, d: float, h: float, cap := INF) -> void:
	var t := _yaw_at(x, z)
	giants.back().xform = t
	var roll := rng.randf()
	# Чаще всего — аркология с тысячами окон, иногда — глухой бетонный гигант.
	var mat: Material = _pick(m.arcology) if roll < 0.6 else (m.weathered if roll < 0.8 else m.tower_panels)
	_foundation(Vector3(x, 0, z), Vector2(w, d), t.basis, mat)
	var footprint := maxf(w, d)
	var d_base := d
	var near := Vector2(x, z).length() < 800.0  # мелкие детали — только у ближних
	var tiers := rng.randi_range(1, 4)
	var y := 0.0
	for tier in tiers:
		var th := h if tiers == 1 else (h * 0.6 if tier == 0 else h * 0.4 / (tiers - 1))
		var top := minf(y + th, cap)
		if top > y:
			b.box_local(t, Vector3(0, (y + top) / 2.0, 0), Vector3(w, top - y, d), mat, false)
			b.occluder_local(t, Vector3(0, (y + top) / 2.0, 0), Vector3(w, top - y, d))
		if tier == 0:
			giants.back().base_h = top - y   # нижний ярус — во всю ширину
		# Карнизы.
		var ledge_y := y + rng.randf_range(25, 45)
		while ledge_y < y + th - 5.0:
			if ledge_y < cap - 2.0:
				b.box_local(t, Vector3(0, ledge_y, 0), Vector3(w + 3, 1.5, d + 3), m.concrete_dark, false)
			ledge_y += rng.randf_range(30, 60)
		if near and roll >= 0.6 and rng.randf() < 0.6 and top > y:
			_slits(t, y, top - y, w, d, 0.0)  # у аркологий окна рисует шейдер, щели только у бетонных
		# Рёбра по бокам.
		if tier == 0 and rng.randf() < 0.5:
			var fins := maxi(int(d / 12.0), 2)
			for f in fins:
				var fz := -d / 2.0 + (f + 0.5) * d / fins
				for side in [-1.0, 1.0]:
					b.box_local(t, Vector3(side * (w / 2.0 + 1.0), (top - y) / 2.0, fz), Vector3(2, top - y, 2.5), mat, false)
		y += th
		w *= rng.randf_range(0.55, 0.85)
		d *= rng.randf_range(0.55, 0.85)
	if rng.randf() < 0.5:
		var ah := rng.randf_range(40, 150)
		if cap == INF:
			b.box_local(t, Vector3(0, y + ah / 2.0, 0), Vector3(1.5, ah, 1.5), m.metal, false)
	# Гигантская реклама на ближних мегабашнях — светится сквозь туман (на обрезанной — помельче, под крышей).
	if near and rng.randf() < 0.4:
		var aw := footprint * 0.6 if cap == INF else cap * 0.35
		_add_ad(t, Vector3(0, minf(minf(h * 0.3, 140.0), cap * 0.5), d_base / 2.0 + 0.5), Vector2(aw, aw * 1.5))
	y = minf(y, cap)
	giants.back().roof = y
	towers.append({"pos": Vector3(x, 0, z), "height": y, "radius": footprint * 0.6})


## Узкие тёмные окна-щели на четырёх гранях блока.
func _slits(t: Transform3D, y: float, th: float, w: float, d: float, offset_x: float) -> void:
	var sh := th * 0.85
	var cy := y + th / 2.0
	var across := maxi(int(w / 7.0), 1)
	for i in across:
		var sx := offset_x - w / 2.0 + (i + 0.5) * w / across
		for side in [-1.0, 1.0]:
			b.box_local(t, Vector3(sx, cy, side * (d / 2.0 + 0.2)), Vector3(1.4, sh, 0.4), m.slit, false)
	var along := maxi(int(d / 7.0), 1)
	for i in along:
		var sz := -d / 2.0 + (i + 0.5) * d / along
		for side in [-1.0, 1.0]:
			b.box_local(t, Vector3(offset_x + side * (w / 2.0 + 0.2), cy, sz), Vector3(0.4, sh, 1.4), m.slit, false)


func _round_tower(x: float, z: float, r: float, h: float) -> void:
	var c := Vector3(x, 0, z)
	var mat: Material = _pick(m.arcology) if rng.randf() < 0.5 else m.concrete
	b.cylinder(c + Vector3(0, (h + ABYSS) / 2.0, 0), r, h - ABYSS, mat, Basis.IDENTITY, false)
	var ry := rng.randf_range(20, 40)
	while ry < h:
		b.cylinder(c + Vector3(0, ry, 0), r + 1.5, 2.0, m.metal, Basis.IDENTITY, false)
		ry += rng.randf_range(25, 50)
	b.cylinder(c + Vector3(0, h + 8, 0), r * 0.6, 16, m.concrete_dark, Basis.IDENTITY, false)
	if rng.randf() < 0.5:
		var core := Vector3(r * 0.8, h * 0.9, r * 0.8)
		b.box(c + Vector3(r, (core.y + ABYSS) / 2.0, 0), Vector3(core.x, core.y - ABYSS, core.z), m.weathered, Basis.IDENTITY, false)
	towers.append({"pos": c, "height": h, "radius": r})


## Голый бетонный каркас: колонны и перекрытия, часть этажей обрушена.
func _lattice(x: float, z: float, size: float, h: float) -> void:
	var t := _yaw_at(x, z)
	if not PLATFORM.has_point(Vector2(x, z)):
		_foundation(Vector3(x, 0, z), Vector2(size * 0.9, size * 0.9), t.basis, m.concrete_dark)
	var n := rng.randi_range(2, 4)
	var step := size / (n - 1)
	var col := rng.randf_range(2, 9) if size > 40 else rng.randf_range(0.5, 0.8)
	for i in n:
		for j in n:
			b.box_local(t, Vector3(-size / 2.0 + i * step, h / 2.0, -size / 2.0 + j * step), Vector3(col, h, col), m.concrete_dark)
	var fy := rng.randf_range(18, 30) if size > 40 else FLOOR_H
	while fy < h:
		if rng.randf() < 0.7:
			b.box_local(t, Vector3(0, fy, 0), Vector3(size + col, 0.3 if size <= 40 else 2.5, size + col), m.concrete, false)
		else:
			b.box_local(t, Vector3(-size / 4.0, fy, 0), Vector3(size / 2.0, 0.3 if size <= 40 else 2.5, size + col), m.concrete, false)
		fy += rng.randf_range(16, 30) if size > 40 else FLOOR_H
	towers.append({"pos": Vector3(x, 0, z), "height": h, "radius": size * 0.7})


## Пучок тонких высоченных игл.
func _needles(x: float, z: float) -> void:
	var top := 0.0
	for i in rng.randi_range(3, 7):
		var nw := rng.randf_range(6, 16)
		var nh := rng.randf_range(200, 900)
		var pos := Vector3(x + rng.randf_range(-40, 40), (nh + ABYSS) / 2.0, z + rng.randf_range(-40, 40))
		b.box(pos, Vector3(nw, nh - ABYSS, nw), m.weathered, Basis(Vector3.UP, rng.randf() * TAU), false)
		top = maxf(top, nh)
	towers.append({"pos": Vector3(x, 0, z), "height": top, "radius": 30.0})


## Мосты и трубы между соседними башнями высоко над землёй — не больше трёх на башню.
func _bridges_and_pipes() -> void:
	var bridges := 0
	var pipes := 0
	var per_tower := {}
	for a in towers.size():
		for c in range(a + 1, towers.size()):
			var p1: Vector3 = towers[a].pos
			var p2: Vector3 = towers[c].pos
			var dist := p1.distance_to(p2)
			if dist < 120 or dist > 450:
				continue
			if per_tower.get(a, 0) >= 3 or per_tower.get(c, 0) >= 3:
				continue
			# Небоскрёбы города соединяет _skybridges — бетонные балки над улицами не нужны.
			if PLATFORM.has_point(Vector2(p1.x, p1.z)) or PLATFORM.has_point(Vector2(p2.x, p2.z)):
				continue
			var top := minf(towers[a].height, towers[c].height)
			if top < 60:
				continue
			var dir := p2 - p1
			var mid := (p1 + p2) / 2.0
			if bridges < 20 and rng.randf() < 0.25:
				var y := top * rng.randf_range(0.4, 0.8)
				b.box(mid + Vector3(0, y, 0), Vector3(12, 6, dist), m.concrete_dark, Basis(Vector3.UP, atan2(dir.x, dir.z)))  # твёрдые — машины облетают
				bridges += 1
			elif pipes < 25 and rng.randf() < 0.2:
				var y := rng.randf_range(30, maxf(top * 0.5, 40))
				var basis := Basis(Quaternion(Vector3.UP, dir.normalized()))
				b.cylinder(mid + Vector3(0, y, 0), rng.randf_range(2, 5), dist, m.metal, basis)
				pipes += 1
			else:
				continue
			per_tower[a] = per_tower.get(a, 0) + 1
			per_tower[c] = per_tower.get(c, 0) + 1
