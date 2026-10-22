extends CanvasLayer

## Финал на вершине. Герой падает на колени, лицом к солнцу. Пока внизу по слову проступает
## «Это...Всё...Я», перед ним, со стороны солнца, в последний раз появляется ангел — а на слове «Я»
## за её спиной взрывается солнце: ослепительное ядро, ударная волна по небу, вспышка, гул.
## Через секунду после взрыва экран заливает светом, свет плавно уходит в черноту, звук мира стихает.
## В темноте — заключительные слайды (EPILOGUE), как пролог: по центру, каждый ждёт пробела. Под текстом —
## снимки, которые игрок сделал за этот круг (photos.gd): плавно всплывают из темноты вокруг текста, без рамок,
## на каждом слайде — ещё несколько.
## Последний растаял — и он снова стоит на крыше той самой башни, с которой прыгнул. Круг замкнулся.

const LIGHT_AFTER := 1.0       # через столько секунд после взрыва экран заливает светом…
const LIGHT_IN := 1.5          # …за столько секунд…
const LIGHT_HOLD := 1.0        # …свет держится…
const TO_BLACK := 3.5          # …и плавно уходит в черноту, после — слайды
const WHITE := Color(1.0, 0.93, 0.82, 1.0)
## Фраза проступает по частям в одном субтитре: «Это...» → «Это...Всё...» → «Это...Всё...Я».
const REALIZATION := ["Это...", "Всё...", "Я"]
const WORD_PAUSE := 1.6        # пауза перед следующей частью, с
const REALIZATION_HOLD := 2.5  # столько вся фраза держится после последнего слова
const ANGEL_AHEAD := 7.0       # на каком расстоянии перед героем появляется ангел, м
const SUN_DISTANCE := 1800.0   # где взрывается солнце (в его стороне), м
const EPILOGUE := [
	"Вырванным из тьмы - всё стало на свои места. Боль ушла, оставив после себя умиротворение",
	"Ангела нет",
	"Теперь это обречено на покой",
]
const SLIDE_FADE := 1.6
const PHOTO_ALPHA := 0.75       # снимки полупрозрачные (на 15% прозрачнее, чем были)
const PHOTO_FADE := 2.2        # снимок проявляется из темноты, с
const PHOTO_RISE := 26.0       # …и всплывает на столько пикселей
const Structures = preload("res://scripts/structures.gd")
const ROOF_WAKE := 4.0          # за столько секунд на крыше спадает темнота

var player: CharacterBody3D
var started := false
var veil: ColorRect
var slide_text: Label
var slide_hint: Label
var board: Control             # снимки игрока на заключительных слайдах
var photo_spots: Array[Vector2] = []
var _edge_material: ShaderMaterial
var rng := RandomNumberGenerator.new()
var slide := -1
var slide_ready := false       # слайд проявился — пробел листает дальше


func setup(p_player: CharacterBody3D) -> void:
	player = p_player


func _ready() -> void:
	layer = 4
	veil = ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.color = Color(1.0, 0.93, 0.82, 0.0)
	add_child(veil)


func _process(_delta: float) -> void:
	if started or player == null:
		return
	var p := player.global_position
	var flat := Vector2(p.x - Mountain.CENTER.x, p.z - Mountain.CENTER.z).length()
	if flat < Mountain.R_TOP - 5.0 and p.y > Mountain.PEAK - 5.0 and not player.flying:
		start()


## Запускает финал (вызывается и из админ-панели).
func start() -> void:
	if started:
		return
	started = true
	player.locked = true
	if Game.smoke:
		Game.smoke.put_away()  # в финале руки пусты
	player.velocity = Vector3.ZERO
	# Лицом к солнцу: оно низко над облаками, по ту сторону горы от города.
	player.target_yaw = 0.0
	player.target_pitch = 0.08

	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(player, "kneeling", 1.0, 3.0).set_trans(Tween.TRANS_SINE)  # падает на колени
	tween.tween_interval(1.5)
	tween.tween_callback(_realize)   # дальше: взрыв солнца → свет → чернота → слайды (_sun_explodes)


## Заключительные слайды на чёрном: проявляются по одному, пробел — следующий; после последнего текст тает.
func _epilogue() -> void:
	rng.randomize()
	board = Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)   # под текстом
	slide_text = ScreenText.center(self, "", 24, Color(0.88, 0.87, 0.85, 0.82))
	slide_text.modulate.a = 0.0
	slide_hint = ScreenText.corner_hint(self, "пробел — дальше")
	slide_hint.modulate.a = 0.0
	_next_slide()


func _next_slide() -> void:
	slide_ready = false
	slide += 1
	var tween := create_tween()
	if slide > 0:
		tween.tween_property(slide_text, "modulate:a", 0.0, SLIDE_FADE * 0.6).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(slide_hint, "modulate:a", 0.0, 0.4)
	if slide >= EPILOGUE.size():
		tween.parallel().tween_property(board, "modulate:a", 0.0, SLIDE_FADE).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func() -> void:
			board.queue_free()
			Photos.taken.clear())   # новый круг — новые снимки
		tween.tween_interval(1.5)
		tween.tween_callback(_back_on_roof)   # последний слайд растаял — снова на крыше
		return
	var text: String = EPILOGUE[slide]
	tween.tween_callback(func() -> void: slide_text.text = text)
	tween.tween_callback(_scatter_photos.bind(slide))
	tween.tween_property(slide_text, "modulate:a", 1.0, SLIDE_FADE).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: slide_ready = true)
	tween.tween_property(slide_hint, "modulate:a", 1.0, 0.8)


## Снимки этого слайда (свою долю от всех снимков круга) — плавно всплывают из темноты вокруг текста, как попало.
func _scatter_photos(index: int) -> void:
	var all := Photos.taken
	if all.is_empty():
		return
	var per_slide := ceili(all.size() / float(EPILOGUE.size()))
	var screen := get_viewport().get_visible_rect().size
	var delay := 0.3
	for k in range(index * per_slide, mini((index + 1) * per_slide, all.size())):
		var card := _photo_card(all[k], screen)
		var spot := _free_spot(screen, card.size) - card.size / 2.0
		card.position = spot + Vector2(0, PHOTO_RISE)
		card.modulate.a = 0.0
		board.add_child(card)
		var rise := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		rise.tween_property(card, "modulate:a", PHOTO_ALPHA, PHOTO_FADE).set_delay(delay)
		rise.tween_property(card, "position:y", spot.y, PHOTO_FADE * 1.3).set_delay(delay)
		delay += 0.7


## Снимок без рамки: края растворяются в темноте (не «наклеен» поверх), чуть повёрнут.
func _photo_card(image: Image, screen: Vector2) -> Control:
	var width := screen.x * rng.randf_range(0.17, 0.24)
	var photo := TextureRect.new()
	photo.texture = ImageTexture.create_from_image(image)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_SCALE
	photo.size = Vector2(width, width * image.get_height() / image.get_width())
	photo.pivot_offset = photo.size / 2.0
	photo.rotation = rng.randf_range(-0.22, 0.22)
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.material = _soft_edges()
	return photo


func _soft_edges() -> ShaderMaterial:
	if _edge_material == null:
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
// Края снимка плавно уходят в прозрачность.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x)
		* smoothstep(0.0, 0.16, UV.y) * smoothstep(1.0, 0.84, UV.y);
	COLOR = vec4(c.rgb, c.a * edge) * COLOR;
}"""
		_edge_material = ShaderMaterial.new()
		_edge_material.shader = shader
	return _edge_material


## Случайное место на экране — карточка целиком (с запасом на поворот) не заходит на полосу текста
## посередине и не ложится прямо поверх прежних снимков.
func _free_spot(screen: Vector2, card: Vector2) -> Vector2:
	var half := Vector2.ONE * card.length() / 2.0          # повёрнутая карточка помещается в этот квадрат
	var text_half := Vector2(screen.x * 0.33, screen.y * 0.07)   # полоса текста (до двух строк)
	var best := screen / 2.0 + Vector2(0, screen.y * 0.3)
	for attempt in 60:
		var p := Vector2(rng.randf_range(half.x * 0.6, screen.x - half.x * 0.6), rng.randf_range(half.y * 0.6, screen.y - half.y * 0.6))
		if absf(p.x - screen.x / 2.0) < text_half.x + half.x and absf(p.y - screen.y / 2.0) < text_half.y + half.y:
			continue   # заходит на текст
		best = p
		var crowded := false
		for q in photo_spots:
			crowded = crowded or p.distance_to(q) < screen.x * 0.16
		if not crowded:
			break
	photo_spots.append(best)
	return best


## Снова на крыше самой высокой башни, у того края, с которого он прыгнул, лицом к горе.
## Звук мира возвращается, темнота плавно спадает — и можно идти.
func _back_on_roof() -> void:
	player.global_position = Structures.ROOF_SPOT
	player.velocity = Vector3.ZERO
	player.last_safe = Structures.ROOF_SPOT
	player.lying = 0.0
	player.kneeling = 0.0
	player.end_fall()
	var to := Mountain.CENTER - Structures.ROOF_SPOT
	var yaw := atan2(-to.x, -to.z)
	player.rotation.y = yaw
	player.target_yaw = yaw
	player.target_pitch = 0.0
	player.head.rotation.x = 0.0
	var tween := create_tween()
	tween.tween_method(_fade_world_sound, -60.0, 0.0, ROOF_WAKE)
	tween.parallel().tween_property(veil, "color:a", 0.0, ROOF_WAKE).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: player.locked = false)


func _unhandled_input(event: InputEvent) -> void:
	if slide_ready and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_next_slide()


## На коленях, лицом к солнцу, — он понимает: ангела не было. Фраза дополняется по слову;
## строка с самого начала разложена целиком, поэтому, дополняясь, не сдвигается по центру.
func _realize() -> void:
	var hud := Game.hud
	if hud == null:
		return
	_angel_appears()
	get_tree().create_timer(WORD_PAUSE * (REALIZATION.size() - 1)).timeout.connect(_sun_explodes)  # на слове «Я»
	var full := "".join(REALIZATION)
	hud.say(full, WORD_PAUSE * (REALIZATION.size() - 1) + REALIZATION_HOLD, 1.0, 1.5)
	var subtitle: Label = hud.subtitle
	var shown := 0
	var tween := create_tween()
	for i in REALIZATION.size():
		shown += (REALIZATION[i] as String).length()
		var count := shown if i < REALIZATION.size() - 1 else -1
		if i > 0:
			tween.tween_interval(WORD_PAUSE)
		tween.tween_callback(func() -> void: subtitle.visible_characters = count)


## Куда смотреть на солнце: по направлению солнечного света (свет идёт вдоль -Z лампы — солнце в стороне +Z).
func _sun_dir() -> Vector3:
	return Game.sun.global_transform.basis.z.normalized() if Game.sun else Vector3(0, 0.15, -1).normalized()


## Ангел — перед героем, со стороны солнца, лицом к нему.
func _angel_appears() -> void:
	var presence := Game.presence
	if presence == null:
		return
	var flat := _sun_dir()
	flat.y = 0
	var feet := player.global_position + flat.normalized() * ANGEL_AHEAD
	feet.y = Mountain.PEAK
	presence.finale_appear(feet, player.global_position, WORD_PAUSE * (REALIZATION.size() - 1))  # одна вспышка — на взрыв


## Солнце взрывается: ядро раздувается и гаснет, кольцо ударной волны расходится по небу,
## экран вспыхивает тёплым светом, низкий раскатистый гул.
func _sun_explodes() -> void:
	var cam := get_viewport().get_camera_3d()
	var center := cam.global_position + _sun_dir() * SUN_DISTANCE
	var world := player.get_parent()

	# Ядро сияет: свечение (emission) сильнее порога glow — вокруг диска ореол, как у настоящего солнца.
	var core_mat := StandardMaterial3D.new()
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.disable_fog = true
	core_mat.albedo_color = Color(0, 0, 0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.88, 0.62)
	core_mat.emission_energy_multiplier = 4.5   # диск сияет ореолом, но не выжигает весь кадр
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 1.0
	core_mesh.height = 2.0
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = center
	core.scale = Vector3.ONE * 40.0
	world.add_child(core)

	var ring_mat := core_mat.duplicate()
	ring_mat.emission = Color(1.0, 0.55, 0.25)
	ring_mat.emission_energy_multiplier = 2.0
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 64
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ring)
	ring.global_position = center
	ring.look_at(cam.global_position, Vector3.UP)
	ring.rotate_object_local(Vector3.RIGHT, PI / 2.0)   # кольцо — плашмя к герою
	ring.scale = Vector3.ONE * 60.0

	var tween := create_tween().set_parallel()
	tween.tween_property(core, "scale", Vector3.ONE * 650.0, 1.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(core_mat, "emission_energy_multiplier", 0.0, 3.5).set_delay(0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(ring, "scale", Vector3.ONE * 2600.0, 3.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_mat, "emission_energy_multiplier", 0.0, 3.0)
	# Вспышка: экран вспыхивает тёплым светом и чуть отпускает — виден диск и ангел; через секунду — свет заливает всё.
	tween.chain().tween_callback(func() -> void:
		core.queue_free()
		ring.queue_free())
	var flash := create_tween()   # отдельно: не ждёт, пока догорят ядро и кольцо
	flash.tween_property(veil, "color:a", 0.85, 0.12)          # яркая вспышка…
	flash.tween_property(veil, "color:a", 0.3, LIGHT_AFTER - 0.12).set_trans(Tween.TRANS_SINE)
	flash.tween_callback(_flood_with_light)

	Synth.play_once(self, _boom_sound(), 2.0, &"Music")


## Экран заливает светом, свет держится и плавно уходит в черноту; звук мира стихает. Потом — слайды.
func _flood_with_light() -> void:
	var tween := create_tween()
	tween.tween_property(veil, "color", WHITE, LIGHT_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(LIGHT_HOLD)
	tween.tween_property(veil, "color", Color(0, 0, 0, 1), TO_BLACK).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(1.5)
	tween.tween_callback(_epilogue)
	create_tween().tween_method(_fade_world_sound, 0.0, -60.0, LIGHT_IN + LIGHT_HOLD + TO_BLACK)   # мир стихает


## Гул взрыва: низкий удар и долгий раскатистый шум.
func _boom_sound() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(Synth.MIX_RATE * 5.0))
	var lp := 0.0
	for i in samples.size():
		var t := i / Synth.MIX_RATE
		lp += (randf() * 2.0 - 1.0 - lp) * 0.02
		var body := sin(TAU * 38.0 * t) * exp(-t * 1.6) * 0.7
		var rumble := lp * 6.0 * exp(-t * 0.7) * minf(t * 8.0, 1.0)
		samples[i] = body + rumble
	return Synth.wav_from(samples)


## Звук мира (дождь, ветер — шина Ambience; пианино — Music) уходит в тишину.
func _fade_world_sound(db: float) -> void:
	Settings.world_fade_db = db      # поверх громкости, выбранной в настройках
	Settings.apply_audio()
