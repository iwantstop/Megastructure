class_name Photos
extends CanvasLayer

## Снимки с бодикамеры. C — кадр без надписей (как видит камера), короткая белая вспышка и щелчок затвора.
## Снимки этого круга хранятся в taken: в финале они лежат на заключительных слайдах вперемешку с текстом
## (finale.gd), и финал у каждого свой. Каждый снимок ещё и сохраняется — user://photos/ (папка игрока).
## После финала список очищается: новый круг — новые снимки.

const MAX := 24
const SIZE := Vector2i(960, 540)
const HINT := "Снимок - C"

static var taken: Array[Image] = []

var flash: ColorRect
var shutter: AudioStreamWAV
var busy := false


func _ready() -> void:
	layer = 60
	taken.clear()
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	shutter = Synth.wav(0.16, func(t: float) -> float:
		var click := (randf() * 2.0 - 1.0) * exp(-t * 160.0) * 0.8
		var spring := sin(TAU * 1900.0 * t) * exp(-t * 60.0) * 0.25 if t > 0.05 else 0.0
		return click + spring)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		if Game.player and not get_tree().paused:
			get_viewport().set_input_as_handled()
			take()


## Снимок: прячем надписи на один кадр, берём картинку, возвращаем надписи, вспышка и щелчок.
func take() -> void:
	if busy:
		return
	busy = true
	var hidden: Array[CanvasLayer] = []
	for layer_node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if layer_node.visible and layer_node.layer >= 2 and layer_node != self:   # всё, кроме бодикамеры (слой 1)
			layer_node.visible = false
			hidden.append(layer_node)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	for layer_node in hidden:
		layer_node.visible = true
	image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_BILINEAR)
	taken.append(image)
	if taken.size() > MAX:
		taken.pop_front()
	_save(image)
	Synth.play_once(self, shutter, -6.0)
	flash.color.a = 0.55
	create_tween().tween_property(flash, "color:a", 0.0, 0.25)
	busy = false


func _save(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute("user://photos")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	image.save_png("user://photos/megastructure_%s_%d.png" % [stamp, taken.size()])
