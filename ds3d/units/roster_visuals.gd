class_name RosterUnitVisual
extends Node3D

## Static rig for one Slice 2 roster role, built from the box-primitive list in
## roster_models.json — the same data the contact-sheet render reads, so the
## two can't drift apart. Cosmetic only, same box/StandardMaterial3D pattern
## as scenes/unit_visual.gd and scenes/base_visual.gd; holds no gameplay state
## and is not wired into main.gd/host.gd this slice (prototype/models only —
## stats, counters, and live spawning are the real Slice 2 build's job).

static var _data: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open("res://units/roster_models.json", FileAccess.READ)
	if f == null:
		push_error("roster_models.json not found")
		return
	_data = JSON.parse_string(f.get_as_text())
	f.close()

static func role_order() -> Array:
	_ensure_loaded()
	return _data.get("role_order", [])

static func role_label(role: String) -> String:
	_ensure_loaded()
	return _data.get("roles", {}).get(role, {}).get("label", role)

## Builds one role's rig in the given team color. Returns a new Node3D
## (feet at local y=0, matching unit_visual.gd's convention) ready to add_child.
func build(role: String, team_color: Color) -> void:
	_ensure_loaded()
	var role_data: Dictionary = _data.get("roles", {}).get(role, {})
	var metal: Color = _color_from_array(_data["colors"]["metal"])
	for part in role_data.get("parts", []):
		var size: Vector3 = _vec3_from_array(part["size"])
		var pos: Vector3 = _vec3_from_array(part["pos"])
		var color: Color = _resolve_color(part["color"], team_color, metal)
		var mi := _box(size, pos, color)
		if part["color"] == "emissive":
			var mat := mi.material_override as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 2.2

func _resolve_color(key: String, team_color: Color, metal: Color) -> Color:
	match key:
		"team":
			return team_color
		"team_dark1":
			return team_color.darkened(0.15)
		"team_dark2":
			return team_color.darkened(0.35)
		"emissive":
			return team_color
		"metal":
			return metal
		_:
			return team_color

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = 0.25
	mi.material_override = mat
	add_child(mi)
	return mi

static func _vec3_from_array(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

static func _color_from_array(a: Array) -> Color:
	return Color(a[0], a[1], a[2])
