extends SceneTree

## Длинный прогон: герой бежит по мосту от города до горы (~2 км) и дальше на тропу.
## Каждые 100 м печатает средний FPS, самый долгий кадр и не сломались ли координаты (NaN).
## Запуск (с окном — нужны настоящие кадры): godot --path <проект> -s res://tests/causeway_run_test.gd

const START := Vector3(0, 0.5, -380)
const FINISH_Z := -2420.0   # чуть за концом моста — уже на тропе

var world: Node
var player: CharacterBody3D
var stage := 0
var t := 0.0
var next_mark := -400.0
var frames := 0
var frame_time := 0.0
var worst := 0.0
var worst_total := 0.0
var nan_seen := false
var started_ms := 0


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	t += delta
	match stage:
		0:
			if t < 0.5:
				return false
			player = get_first_node_in_group("player")
			for c in world.get_children():
				if c.get_script() and str(c.get_script().resource_path).ends_with("intro.gd"):
					c.skip()
			stage = 1
		1:
			if player.locked:
				return false
			player.global_position = START
			player.velocity = Vector3.ZERO
			player.target_yaw = 0.0   # лицом к горе (-Z)
			player.target_pitch = 0.0
			player.rotation.y = 0.0
			stage = 2
			t = 0.0
		2:
			if t < 1.0:
				return false
			_key(KEY_W, true)
			_key(KEY_SHIFT, true)
			started_ms = Time.get_ticks_msec()
			stage = 3
		3:
			player.target_yaw = 0.0
			frames += 1
			frame_time += delta
			worst = maxf(worst, delta)
			worst_total = maxf(worst_total, delta)
			if not player.global_transform.is_finite() and not nan_seen:
				nan_seen = true
				print("RUN NaN at frame, pos=", player.global_position)
			var z := player.global_position.z
			if z <= next_mark:
				print("RUN z=%6.0f  y=%5.1f  fps=%5.1f  worst_frame=%5.0f ms" % [z, player.global_position.y, frames / maxf(frame_time, 0.001), worst * 1000.0])
				next_mark -= 100.0
				frames = 0
				frame_time = 0.0
				worst = 0.0
			if z <= FINISH_Z or t > 600.0:
				print("RUN done z=", snappedf(z, 1), " time=", (Time.get_ticks_msec() - started_ms) / 1000.0, "s worst_frame_overall=", snappedf(worst_total * 1000.0, 1), "ms nan=", nan_seen)
				return true
	return false
