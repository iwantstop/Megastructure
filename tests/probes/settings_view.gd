extends SceneTree

## Экран настроек: снимок с раскрытыми «Расширенными настройками графики» и проверка, что значения дошли до движка
## и что пресет качества переставляет расширенные. Настройки игрока в конце возвращаются как были.
## Запуск (с окном): godot --path . -s tests/probes/settings_view.gd -- --prologue

var world: Node


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	_run()


func _run() -> void:
	var saved := Settings.values.duplicate()
	var prologue: Node = null
	while prologue == null or prologue.menu == null:
		for c in world.get_children():
			if c.get_script() and str(c.get_script().resource_path).ends_with("prologue.gd"):
				prologue = c
		await process_frame
	await create_timer(1.0, true, false, true).timeout
	prologue.menu.get_child(1).emit_signal("pressed")
	await create_timer(0.5, true, false, true).timeout
	var panel: Control = prologue.settings
	for b in panel.rows.get_children():
		if b is Button and b.text.begins_with("Расширенные"):
			b.emit_signal("pressed")
	await create_timer(0.3, true, false, true).timeout
	var scroll: ScrollContainer = panel.rows.get_parent().get_parent()
	scroll.scroll_vertical = 10000
	await create_timer(0.3, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/settings_advanced.png")
	var vp := root.get_viewport()
	print("SV defaults: roll=%s bodycam=%s vsync=%s | msaa=%d taa=%s aniso=%d fxaa=%d" % [Settings.get_value("roll"), Settings.get_value("bodycam"),
		Settings.get_value("vsync"), vp.msaa_3d, vp.use_taa, vp.anisotropic_filtering_level, vp.screen_space_aa])
	Settings.set_value("quality", 0)
	print("SV quality low: gi=%s ssr=%s shadows=%s env.sdfgi=%s env.ssao=%s atlas=%d" % [Settings.get_value("gi"), Settings.get_value("ssr"),
		Settings.get_value("shadows"), Game.env.sdfgi_enabled, Game.env.ssao_enabled, vp.positional_shadow_atlas_size])
	Settings.set_value("msaa", Viewport.MSAA_DISABLED)
	Settings.set_value("aniso", Viewport.ANISOTROPY_DISABLED)
	print("SV msaa off: %d aniso off: %d" % [vp.msaa_3d, vp.anisotropic_filtering_level])
	Settings.values = saved
	Settings.apply()
	Settings.save()
	quit()
