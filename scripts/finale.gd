extends CanvasLayer

## Финал на вершине. Герой падает на колени, лицом к солнцу. Ангела нет — его не было никогда.
## Он долго смотрит на солнце — внизу на миг проступает «Это... Всё я», — ложится, закрывает глаза;
## мир медленно растворяется в тёплом свете, потом в темноте. Конец.

const SILENCE := 10.0  # сколько он смотрит на солнце, стоя на коленях
const REALIZATION := "Это... Всё я"
const REALIZATION_HOLD := 4.0  # столько субтитр полностью на экране

var player: CharacterBody3D
var ambient: AudioStreamPlayer
var started := false
var veil: ColorRect


func setup(p_player: CharacterBody3D, p_ambient: AudioStreamPlayer) -> void:
	player = p_player
	ambient = p_ambient


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
	var smoke := get_tree().get_first_node_in_group("smoke")
	if smoke:
		smoke.put_away()  # в финале руки пусты
	player.velocity = Vector3.ZERO
	# Лицом к солнцу: оно низко над облаками, по ту сторону горы от города.
	player.target_yaw = 0.0
	player.target_pitch = 0.08

	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(player, "kneeling", 1.0, 3.0).set_trans(Tween.TRANS_SINE)  # падает на колени
	tween.tween_interval(1.5)
	tween.tween_callback(_realize)
	tween.tween_interval(SILENCE - 1.5)
	# Ложится на спину, смотрит в небо и закрывает глаза.
	tween.tween_property(player, "kneeling", 0.0, 3.0)
	tween.parallel().tween_property(player, "lying", 1.0, 4.0).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(3.0)
	tween.tween_property(veil, "color:a", 1.0, 8.0)
	tween.parallel().tween_property(ambient, "volume_db", -60.0, 10.0)
	tween.tween_property(veil, "color", Color(0, 0, 0, 1), 4.0)


## На коленях, лицом к солнцу, — он понимает: ангела не было. Субтитр держится 4 секунды.
func _realize() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.say(REALIZATION, REALIZATION_HOLD, 1.0, 1.5)
