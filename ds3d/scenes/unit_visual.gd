extends Node3D

## Purely cosmetic: wraps a RosterUnitVisual rig (ds3d/units/roster_visuals.gd,
## one of Slice 2's six role rigs) and animates it from state snapshots from
## MatchClient.get_state(). Holds no gameplay truth — march/attack/hit are
## animated locally from what the sim already reports (pos, state, cooldown,
## hp), never invents outcomes.

const RosterUnitVisualScript = preload("res://units/roster_visuals.gd")

var team_color: Color
var phase: float = 0.0
var local_time: float = 0.0
var prev_hp: float = -1.0
var prev_cooldown: int = -1
var hit_flash_t: float = 0.0
var attack_lunge_t: float = 0.0
var facing: float = 1.0

var rig # RosterUnitVisualScript instance; untyped (custom script, see main.gd's note on this pattern)
var mesh_parts: Array = [] # MeshInstance3D
var mesh_base_colors: Array = [] # Color, parallel to mesh_parts
var core_glow: MeshInstance3D

func build(role: String, color: Color, id_phase: float) -> void:
	team_color = color
	phase = id_phase
	rig = RosterUnitVisualScript.new()
	add_child(rig)
	rig.build(role, color)
	for child in rig.get_children():
		if child is MeshInstance3D:
			mesh_parts.append(child)
			var mat := child.material_override as StandardMaterial3D
			mesh_base_colors.append(mat.albedo_color)
			if mat.emission_enabled and core_glow == null:
				core_glow = child

func update(u: Dictionary, delta: float, z_offset: float) -> void:
	local_time += delta
	facing = 1.0 if u["side"] == "A" else -1.0
	rig.rotation.y = 0.0 if facing > 0.0 else PI

	var base_pos := Vector3(u["pos"], 0.0, z_offset + u.get("lane_offset", 0.0))
	var marching: bool = u["state"] == "marching"

	if marching:
		var bob := sin(local_time * 9.0 + phase) * 0.05
		position = base_pos + Vector3(0.0, bob, 0.0)
		rig.rotation.x = sin(local_time * 9.0 + phase) * 0.08
	else:
		position = base_pos
		rig.rotation.x = lerp(rig.rotation.x, 0.0, clamp(delta * 8.0, 0.0, 1.0))

	# Attack lunge: fires when cooldown jumps up (an attack just landed and reset it).
	var cooldown: int = u["cooldown"]
	if prev_cooldown != -1 and cooldown > prev_cooldown + 1:
		attack_lunge_t = 0.18
	prev_cooldown = cooldown
	var core_mat: StandardMaterial3D = core_glow.material_override if core_glow else null
	if attack_lunge_t > 0.0:
		attack_lunge_t -= delta
		var k: float = clamp(attack_lunge_t / 0.18, 0.0, 1.0)
		position += Vector3(facing * 0.22 * sin(k * PI), 0.0, 0.0)
		if core_mat:
			core_mat.emission_energy_multiplier = 2.2 + 3.0 * sin(k * PI)
	elif core_mat:
		core_mat.emission_energy_multiplier = 2.2

	# Hit feedback: a hp drop since last check flashes every part white/red.
	var hp: float = u["hp"]
	if prev_hp >= 0.0 and hp < prev_hp:
		hit_flash_t = 0.22
	prev_hp = hp
	if hit_flash_t > 0.0:
		hit_flash_t -= delta
		var k2: float = clamp(hit_flash_t / 0.22, 0.0, 1.0)
		for i in range(mesh_parts.size()):
			var mat: StandardMaterial3D = mesh_parts[i].material_override
			mat.albedo_color = mesh_base_colors[i].lerp(Color(1.0, 0.25, 0.2), k2 * 0.85)
	else:
		for i in range(mesh_parts.size()):
			var mat: StandardMaterial3D = mesh_parts[i].material_override
			mat.albedo_color = mesh_base_colors[i]
