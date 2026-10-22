class_name Progress
extends RefCounted

## Что остаётся у героя между кругами и между запусками игры (user://progress.cfg):
## сколько сигарет в пачке — пачка не пополняется никогда.
## В тестах (запуск с -s) ничего не читается и не пишется: пачка полная, сохранение игрока не портится.

const FILE := "user://progress.cfg"
const FULL_PACK := 10

static var cigarettes := FULL_PACK
static var persist := true


static func load_saved(enabled: bool) -> void:
	persist = enabled
	cigarettes = FULL_PACK
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		cigarettes = cfg.get_value("hero", "cigarettes", FULL_PACK)


static func set_cigarettes(count: int) -> void:
	cigarettes = count
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("hero", "cigarettes", count)
	cfg.save(FILE)
