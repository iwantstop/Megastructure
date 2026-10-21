class_name Shapes
extends RefCounted

## Мелкие заготовки для вещей, собранных из кода: материалы, коробки, цилиндры, шары
## и мягкая круглая «точка» для частиц (дым, огонь, искры).

## Матовый (или металлический) материал одного цвета.
static func mat(color: Color, roughness := 0.7, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## Светящийся материал: тёмная подложка color и свечение emission силой energy.
static func glow(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := mat(color, 0.3)
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


## Меш на месте pos внутри parent; shadows = false — не отбрасывает тени (вещи «в руках»).
static func node(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, shadows := true, size_scale := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.scale = size_scale
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, shadows := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return node(parent, mesh, pos, material, shadows)


static func cylinder(parent: Node3D, r_top: float, r_bottom: float, height: float, pos: Vector3, material: Material,
		segments := 16, rings := 4, shadows := true) -> MeshInstance3D:
	return node(parent, cone_mesh(r_top, r_bottom, height, segments, rings), pos, material, shadows)


static func cone_mesh(r_top: float, r_bottom: float, height: float, segments := 64, rings := 4) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


static func sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


## Мягкая круглая точка: белая в центре, прозрачная к краю.
static func soft_dot() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex
