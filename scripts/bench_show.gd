extends Node3D

## Со скамейки на мосту видна мегабашня (левее взгляда, ~140 м). Она обрезана: сразу над огромным табло —
## крыша, а на крыше шпиль в виде меча, остриём в небо. Табло тёмное; сел на скамейку — оно загорается
## фиолетовым и по нему бежит строка новостей, а через несколько секунд на верхнем краю табло появляется
## человек: стоит, шагает — и падает мимо строки в бездну.
## Строка и падение идут в обычном времени, хотя вокруг скамейки время ускорено.

const Structures = preload("res://scripts/structures.gd")
const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")
const TEXT := "На протяжении последнего месяца оперативники следят за Натальей. Наталья торговала продукцией с целью наживы, она обменивала продукты на деньги. Деньги шли напрямую ей. Можно сказать Наталья наживалась на собственном труде. По итогам расследования у Натальи были найдены денежные средства."
const BOARD := Vector2(88.0, 26.0)      # табло во всю грань, м
const BOARD_Y := Structures.BENCH_TOWER_ROOF - 7.0 - 13.0   # центр табло: верх — в 7 м под крышей
const PIXELS := Vector2i(2048, 605)     # разрешение табло
const SPEED := 1300.0                   # бег строки, пикселей в секунду
const GAP := 1200.0                     # пустое место между повторами строки, пикселей
const GLOW := 16.0                      # очень ярко: сквозь туман бездны пробивается мягким ореолом (блюм)
const SCREEN := Color(0.3, 0.06, 0.6)            # фиолетовый экран
const HALO := Color(0.45, 0.2, 0.85)             # ореол в тумане вокруг экрана
const HALO_ALPHA := 0.5
const LETTERS := Color(0.85, 0.75, 0.9)          # и светлые буквы (не белые — иначе выжигают ореол)
const BLADE := 150.0                    # длина клинка шпиля-меча, м
const SWORD := 1.5                      # во сколько раз меч крупнее «обычных» размеров ниже
const FALL_AFTER := 9.0                 # через столько секунд после того, как сел, — человек на краю табло
const STAND := 2.5                      # столько он стоит, прежде чем шагнуть
const FALL_SPEED := 4.0                 # падение быстрее обычного во столько раз (вокруг скамейки время ускорено)
const FIGURE_X := 0.0                   # где на верхнем краю табло он встаёт (от середины), м

var viewport: SubViewport
var label: Label
var screen_mat: StandardMaterial3D
var halo_mat: StandardMaterial3D        # ореол вокруг экрана: свет в тумане (блюм)
var edge_mat: StandardMaterial3D        # светящиеся кромки табло: в тумане видно, на чём он стоит
var running := false
var figure: Node3D
var fall_state := 0                     # 0 — ждёт, 1 — стоит на краю, 2 — падает, 3 — всё
var timer := 0.0
var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var outward := Vector3.ZERO
var spire := Node3D.new()              # шпиль-меч на крыше (в мировых координатах)


## Башня — та, что structures обрезал по крыше напротив скамейки (structures.bench_tower).
func setup(best: Dictionary) -> void:
	var bench := Vector2(Structures.BENCH_SPOT.x, Structures.BENCH_SPOT.z)
	if best.is_empty():
		return
	# Грань башни, обращённая к скамейке.
	var t: Transform3D = best.xform
	var to_bench := Vector3(bench.x - best.pos.x, 0, bench.y - best.pos.y).normalized()
	var face := Vector3.ZERO
	var half := 0.0
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var n: Vector3 = t.basis * axis
		if face == Vector3.ZERO or n.dot(to_bench) > face.dot(to_bench):
			face = n
			half = (best.size.x if absf(axis.x) > 0.5 else best.size.y) / 2.0
	outward = face
	var origin: Vector3 = t.origin + face * (half + 3.5)   # перед рёбрами грани
	origin.y = BOARD_Y
	transform = Transform3D(Basis.looking_at(-face, Vector3.UP), origin)   # лицом (+Z) наружу
	# Крыша и шпиль — посередине крыши (оси — как у башни), клинок плоской стороной к скамейке.
	spire.top_level = true
	spire.transform = Transform3D(t.basis, t.origin + Vector3.UP * best.roof)
	spire.set_meta("roof", Vector2(best.size.x, best.size.y))
	spire.set_meta("facing", t.basis.inverse() * Basis.looking_at(to_bench, Vector3.UP))
	spire.set_meta("sword_at", t.basis.inverse() * (face * (half - 14.0)))   # у переднего края крыши — снизу не заслонён


func _ready() -> void:
	add_to_group("bench_show")   # скамейка спрашивает, прыгнул ли уже человек
	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var back := ColorRect.new()
	back.color = SCREEN
	back.size = PIXELS
	viewport.add_child(back)
	label = Label.new()
	label.text = TEXT
	label.add_theme_font_size_override("font_size", 340)
	label.add_theme_color_override("font_color", LETTERS)
	label.position = Vector2(PIXELS.x, (PIXELS.y - 470) / 2.0)
	viewport.add_child(label)

	var frame := Shapes.mat(Color(0.06, 0.06, 0.07), 0.5, 0.6)
	Shapes.box(self, Vector3(BOARD.x + 1.6, BOARD.y + 1.6, 1.0), Vector3(0, 0, -0.55), frame, false)
	screen_mat = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.02, 0.02, 0.025)
	screen_mat.roughness = 0.25
	screen_mat.emission_enabled = true
	screen_mat.emission_texture = viewport.get_texture()
	screen_mat.emission_energy_multiplier = 0.0   # пока не сел — табло тёмное
	# Ореол: мягкое фиолетовое пятно больше табло — экран подсвечивает туман вокруг себя. Сам ореол — это свет
	# в тумане, поэтому туман на него не ложится (иначе сложением выйдет серый прямоугольник).
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var spot := GradientTexture2D.new()
	spot.gradient = fade
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5, 0.5)
	spot.fill_to = Vector2(0.5, 0.0)
	halo_mat = StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.disable_fog = true
	halo_mat.albedo_texture = spot
	halo_mat.albedo_color = Color(HALO.r, HALO.g, HALO.b, 0.0)   # пока табло тёмное — ореола нет
	var halo := QuadMesh.new()
	halo.size = BOARD * Vector2(1.5, 2.6)
	Shapes.node(self, halo, Vector3(0, 0, 0.6), halo_mat, false)
	edge_mat = Shapes.glow(Color(0.08, 0.04, 0.1), Color(0.75, 0.4, 1.0), 0.0)
	for side in [-1.0, 1.0]:
		Shapes.box(self, Vector3(BOARD.x + 1.6, 0.5, 0.4), Vector3(0, side * (BOARD.y / 2.0 + 0.6), 0.05), edge_mat, false)
	var quad := QuadMesh.new()
	quad.size = BOARD
	Shapes.node(self, quad, Vector3(0, 0, 0.0), screen_mat, false)

	# Человек на краю табло — тёмный силуэт в тумане, как всё вокруг; пролетая мимо строки, виден на её фоне.
	var silhouette := StandardMaterial3D.new()
	silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette.albedo_color = Color(0.04, 0.04, 0.05)
	figure = Node3D.new()
	figure.scale = Vector3.ONE * 2.2   # до него ~100 м: в натуральную величину он — точка; так — заметный силуэт
	var body: Node3D = MODEL.instantiate()
	figure.add_child(body)   # модель смотрит в +Z — к скамейке
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = silhouette
	(body.find_child("AnimationPlayer", true, false) as AnimationPlayer).play("Idle")
	figure.visible = false
	add_child(figure)
	_build_spire()


## Крыша с карнизом и шпиль-меч остриём вверх: навершие, рукоять, гарда, длинный ромбовидный клинок,
## на острие — красный огонь, как у всех высоток.
func _build_spire() -> void:
	add_child(spire)
	var roof: Vector2 = spire.get_meta("roof", Vector2(90, 90))
	var dark := Shapes.mat(Color(0.12, 0.12, 0.13), 0.6)
	var steel := Shapes.mat(Color(0.2, 0.21, 0.24), 0.3, 0.9)
	Shapes.box(spire, Vector3(roof.x + 4.0, 1.6, roof.y + 4.0), Vector3(0, 0.8, 0), dark, false)   # карниз крыши
	var sword := Node3D.new()
	sword.basis = spire.get_meta("facing", Basis.IDENTITY).scaled(Vector3.ONE * SWORD)
	sword.position = spire.get_meta("sword_at", Vector3.ZERO) + Vector3.UP * 1.6
	spire.add_child(sword)
	var pommel := SphereMesh.new()
	pommel.radius = 2.6
	pommel.height = 5.2
	Shapes.node(sword, pommel, Vector3(0, 4.2, 0), steel, false)
	Shapes.cylinder(sword, 1.1, 1.3, 13.0, Vector3(0, 13.0, 0), steel, 8, 1, false)   # рукоять
	Shapes.box(sword, Vector3(34.0, 2.6, 3.4), Vector3(0, 20.8, 0), steel, false)    # гарда
	for side in [-1.0, 1.0]:   # концы гарды чуть загнуты к клинку
		var tip := Shapes.box(sword, Vector3(6.0, 2.2, 3.0), Vector3(side * 18.5, 22.2, 0), steel, false)
		tip.rotation.z = side * 0.45
	var blade := CylinderMesh.new()   # четыре грани, сужается в острие; сплющен — ромб с ребром посередине
	blade.radial_segments = 4
	blade.rings = 1
	blade.bottom_radius = 4.2
	blade.top_radius = 0.05
	blade.height = BLADE / SWORD
	var b := Shapes.node(sword, blade, Vector3(0, 22.0 + BLADE / SWORD / 2.0, 0), steel, false)
	b.basis = Basis.from_scale(Vector3(1.0, 1.0, 0.28)) * Basis(Vector3.UP, PI / 4.0)   # квадрат на 45° → ромб: широкий к скамейке, ребро посередине
	var beacon := Shapes.glow(Color(0.3, 0.02, 0.02), Color(1.0, 0.05, 0.03), 4.0)
	var light := SphereMesh.new()
	light.radius = 0.6
	light.height = 1.2
	Shapes.node(sword, light, Vector3(0, 22.0 + BLADE / SWORD + 0.4, 0), beacon, false)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)   # строка и падение — в обычном времени
	var player := Game.player
	if not running:
		if player and player.seated:
			_switch_on()
		return
	label.position.x -= SPEED * real
	if label.position.x < -label.size.x - GAP:
		label.position.x = PIXELS.x
	match fall_state:
		0:
			timer -= real
			if timer <= 0.0 and player.seated:
				figure.position = Vector3(FIGURE_X, BOARD.y / 2.0 + 0.6, -0.4)
				figure.rotation = Vector3.ZERO
				figure.visible = true
				fall_state = 1
				timer = STAND
		1:
			timer -= real
			if timer <= 0.0:
				fall_state = 2
				velocity = Vector3(0, 0.6, 1.4)   # шаг вперёд, с края табло
				spin = Vector3(1.4, 0.3, -0.9)
		2:
			var fall := real * FALL_SPEED
			velocity.y -= 9.8 * fall
			figure.position += velocity * fall
			figure.rotation += spin * fall
			if figure.position.y < -BOARD_Y - 250.0:   # скрылся в тумане бездны
				figure.visible = false
				fall_state = 3


## Табло мигает и загорается, строка начинает бежать; человек — через FALL_AFTER секунд.
func _switch_on() -> void:
	running = true
	timer = FALL_AFTER
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var tween := create_tween().set_ignore_time_scale(true)
	for k in 3:
		tween.tween_property(screen_mat, "emission_energy_multiplier", GLOW, 0.05)
		tween.tween_property(screen_mat, "emission_energy_multiplier", 0.2, 0.08)
	tween.tween_property(screen_mat, "emission_energy_multiplier", GLOW, 0.3)
	tween.parallel().tween_property(edge_mat, "emission_energy_multiplier", GLOW * 0.6, 0.3)
	tween.parallel().tween_property(halo_mat, "albedo_color:a", HALO_ALPHA, 0.6)
