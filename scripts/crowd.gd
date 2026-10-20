extends Node3D

## Застывшая толпа: модель манекена из библиотеки анимаций, остановленная в кадре
## живой анимации. Некоторые фигуры не совсем застыли — они продолжают движение
## в десятки раз медленнее, и это замечаешь, только если долго смотреть.

const MODEL := preload("res://assets/characters/animation_library/AnimationLibrary_Godot_Standard.glb")

var alive: Array[AnimationPlayer] = []


func setup(figures: Array[Dictionary], plastic: Material) -> void:
	for f in figures:
		var body := MODEL.instantiate()
		# Модель смотрит в +Z, а у нас «вперёд» — это -Z.
		body.rotation.y = PI
		var holder := Node3D.new()
		holder.position = f.pos
		holder.rotation.y = f.yaw
		holder.add_child(body)
		add_child(holder)

		for mesh in body.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = plastic
			# Дальше 130 м фигура не рисуется — в тумане её всё равно не разглядеть.
			mesh.visibility_range_end = 130.0
			mesh.visibility_range_end_margin = 15.0
			mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # плавное проявление делает объект прозрачным — дорого; границу прячет туман
		var player: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
		var anim: String = f.anim
		if not player.has_animation(anim):
			anim = "Idle"
		player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR  # «оживающие» идут по кругу
		player.play(anim)
		player.seek(player.current_animation_length * float(f.at), true)
		if f.alive:
			player.speed_scale = randf_range(0.03, 0.07)
			alive.append(player)
		else:
			player.pause()
