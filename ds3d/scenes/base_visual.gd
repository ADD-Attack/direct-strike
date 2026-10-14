extends Node3D

## A composed command-structure rig for one base: foundation, tapered core
## tower, two side pods, a beacon spire, and emissive team-color trim.
## Cosmetic only — reads hp fraction from the state the caller passes it,
## never touches the sim.

var trim_mats: Array = []
var beacon_mat: StandardMaterial3D
var flash_t: float = 0.0
var team_color: Color

func build(color: Color, facing: float) -> void:
	team_color = color
	var structure_color := color.darkened(0.45).lerp(Color(0.25, 0.26, 0.3), 0.35)

	_box(Vector3(3.6, 0.4, 3.0), Vector3(0, 0.2, 0), Color(0.16, 0.17, 0.2), 0.75, 0.1)

	_box(Vector3(1.6, 1.4, 1.6), Vector3(0, 1.1, 0), structure_color, 0.5, 0.35)
	_box(Vector3(1.05, 1.3, 1.05), Vector3(0, 2.45, 0), structure_color, 0.5, 0.35)
	_box(Vector3(0.7, 1.0, 0.7), Vector3(0, 3.55, 0), structure_color, 0.5, 0.35)

	_box(Vector3(0.95, 1.0, 1.1), Vector3(-1.35 * facing, 0.7, 1.1), structure_color, 0.5, 0.35)
	_box(Vector3(0.95, 1.0, 1.1), Vector3(-1.35 * facing, 0.7, -1.1), structure_color, 0.5, 0.35)

	var spire := _cylinder(0.07, 1.3, Vector3(0, 4.65, 0), Color(0.3, 0.3, 0.33))
	var beacon := _sphere(0.14, Vector3(0, 5.35, 0), color)
	beacon_mat = beacon.material_override as StandardMaterial3D
	beacon_mat.emission_enabled = true
	beacon_mat.emission = color
	beacon_mat.emission_energy_multiplier = 3.0

	_trim(Vector3(3.5, 0.12, 0.12), Vector3(0, 0.46, 1.5), color)
	_trim(Vector3(3.5, 0.12, 0.12), Vector3(0, 0.46, -1.5), color)
	_trim(Vector3(0.12, 0.12, 3.0), Vector3(1.78, 0.46, 0), color)
	_trim(Vector3(0.12, 0.12, 3.0), Vector3(-1.78, 0.46, 0), color)
	_trim(Vector3(1.2, 0.08, 0.08), Vector3(1.35 * facing, 1.55, 1.1), color)
	_trim(Vector3(1.2, 0.08, 0.08), Vector3(1.35 * facing, 1.55, -1.1), color)

func _box(size: Vector3, pos: Vector3, color: Color, roughness: float, metallic: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	mi.material_override = mat
	add_child(mi)
	return mi

func _cylinder(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mi.mesh = cyl
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	mat.metallic = 0.6
	mi.material_override = mat
	add_child(mi)
	return mi

func _sphere(radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	mi.mesh = sph
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi

func _trim(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := _box(size, pos, color, 0.3, 0.0)
	var mat := mi.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	trim_mats.append(mat)

func flash_damage() -> void:
	flash_t = 0.35

func process_flash(delta: float) -> void:
	if flash_t > 0.0:
		flash_t -= delta
		var k: float = clamp(flash_t / 0.35, 0.0, 1.0)
		beacon_mat.emission_energy_multiplier = 3.0 + 5.0 * sin(k * PI)
		for m in trim_mats:
			m.emission = Color(1.0, 0.25, 0.15).lerp(team_color, 1.0 - k)
			m.emission_energy_multiplier = 1.6 + 3.0 * k
	else:
		beacon_mat.emission_energy_multiplier = 3.0
		for m in trim_mats:
			m.emission = team_color
			m.emission_energy_multiplier = 1.6
