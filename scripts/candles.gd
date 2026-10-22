extends Node3D

## Свечи по пути из города к мосту: по краям тёмной каменной дорожки посреди колоннады, раз в 50 м, от подножия
## башни героя до выхода на мост. Горят и дрожат тёплым светом — без слов показывают, куда идти.

const PATH_X := 6.6                 # край дорожки колоннады (её ширина — 14 м)
const FROM_Z := 70.0                # от подножия башни героя…
const TO_Z := -360.0                # …до выхода на мост
const STEP := 50.0
const GROUND := 0.05                # дорожка — на 0,05 м над улицей

var flames: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
var phases: Array[float] = []
var clock := 0.0


func _ready() -> void:
	var wax := Shapes.mat(Color(0.82, 0.78, 0.68), 0.6)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_texture = Shapes.soft_dot()
	flame_mat.albedo_color = Color(1.0, 0.72, 0.35) * 3.0   # ярче единицы — мягкое свечение
	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.07, 0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var z := FROM_Z
	while z >= TO_Z:
		for side in [-1.0, 1.0]:
			# Пара свечей разной высоты, чуть вразнобой.
			for k in 2:
				var at := Vector3(side * (PATH_X + k * 0.22) + rng.randf_range(-0.05, 0.05), GROUND, z + rng.randf_range(-0.3, 0.3) + k * 0.18)
				var height := rng.randf_range(0.14, 0.3) * (1.0 if k == 0 else 0.7)
				Shapes.cylinder(self, 0.035, 0.035, height, at + Vector3.UP * height / 2.0, wax, 10, 1, false)
				var flame := Shapes.node(self, flame_mesh, at + Vector3.UP * (height + 0.07), flame_mat, false)
				flames.append(flame)
				phases.append(rng.randf() * TAU)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.68, 0.35)
			light.light_energy = 1.4
			light.omni_range = 4.5
			light.position = Vector3(side * PATH_X, GROUND + 0.45, z)
			add_child(light)
			lights.append(light)
		z -= STEP


func _process(delta: float) -> void:
	clock += delta
	for i in flames.size():   # язычки дрожат
		var ph := phases[i]
		flames[i].scale = Vector3(1.0, 0.85 + 0.2 * sin(clock * 11.0 + ph) * sin(clock * 3.7 + ph), 1.0)
	for i in lights.size():   # свет дрожит вместе с ними
		lights[i].light_energy = 1.25 + 0.2 * sin(clock * 9.0 + i) * sin(clock * 2.3 + i * 1.7)
