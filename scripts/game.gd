class_name Game
extends RefCounted

## Справочник частей игры. world.gd записывает их сюда, пока строит мир, — остальные берут отсюда
## (Game.hud.say(...)), а не ищут по всему дереву. Чего в этом режиме нет (например, HUD в бенчмарке) — null.

static var player: CharacterBody3D
static var hud: Hud
static var smoke: Smoke
static var presence: Presence
static var mountain_features: MountainFeatures
static var sun: DirectionalLight3D
static var world: Node3D
static var env: Environment
static var bodycam_mat: ShaderMaterial


## Новый мир — справочник заново (прежние части, если были, уже удалены вместе со старым миром).
static func clear() -> void:
	player = null
	hud = null
	smoke = null
	presence = null
	mountain_features = null
	sun = null
	world = null
	env = null
	bodycam_mat = null
