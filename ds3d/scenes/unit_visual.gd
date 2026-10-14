extends Node3D

## Purely cosmetic: a composed low-poly rig for one simulated unit, driven
## entirely by state snapshots from MatchClient.get_state(). Holds no
## gameplay truth — march/attack/hit are animated locally from what the
## sim already reports (pos, state, cooldown, hp), never invents outcomes.

var team_color: Color
var phase: float = 0.0
var local_time: float = 0.0
var prev_hp: float = -1.0
var prev_cooldown: int = -1
var hit_flash_t: float = 0.0
var attack_lunge_t: float = 0.0
var facing: float = 1.0

var torso: MeshInstance3D
var head: MeshInstance3D
var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var weapon: MeshInstance3D
var core: MeshInstance3D
var torso_mat: StandardMaterial3D
var core_mat: StandardMaterial3D

func build(color: Color, id_phase: float) -> void:
	team_color = color
	phase = id_phase

	leg_l = _box(Vector3(0.14, 0.5, 0.14), Vector3(-0.14, 0.25, 0.0), color.darkened(0.35))
	leg_r = _box(Vector3(0.14, 0.5, 0.14), Vector3(0.14, 0.25, 0.0), color.darkened(0.35))
	torso = _box(Vector3(0.5, 0.56, 0.34), Vector3(0.0, 0.78, 0.0), color)
	torso_mat = torso.material_override as StandardMaterial3D
	head = _box(Vector3(0.26, 0.24, 0.26), Vector3(0.0, 1.18, 0.0), color.darkened(0.15))
	weapon = _box(Vector3(0.1, 0.1, 0.62), Vector3(0.32, 0.82, 0.14), Color(0.12, 0.12, 0.14))
	core = _box(Vector3(0.13, 0.13, 0.08), Vector3(0.0, 0.8, 0.175), color)
	core_mat = core.material_override as StandardMaterial3D
	core_mat.emission_enabled = true
	core_mat.emission = color
	core_mat.emission_energy_multiplier = 2.2

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

func update(u: Dictionary, delta: float, z_offset: float) -> void:
	local_time += delta
	facing = 1.0 if u["side"] == "A" else -1.0
	rotation.y = 0.0 if facing > 0.0 else PI

	var base_pos := Vector3(u["pos"], 0.0, z_offset)
	var marching: bool = u["state"] == "marching"

	if marching:
		var bob := sin(local_time * 9.0 + phase) * 0.05
		position = base_pos + Vector3(0.0, 0.08 + bob, 0.0)
		leg_l.rotation.x = sin(local_time * 9.0 + phase) * 0.6
		leg_r.rotation.x = -sin(local_time * 9.0 + phase) * 0.6
		torso.rotation.x = 0.0
	else:
		position = base_pos + Vector3(0.0, 0.08, 0.0)
		leg_l.rotation.x = lerp(leg_l.rotation.x, 0.0, clamp(delta * 8.0, 0.0, 1.0))
		leg_r.rotation.x = lerp(leg_r.rotation.x, 0.0, clamp(delta * 8.0, 0.0, 1.0))

	# Attack lunge: fires when cooldown jumps up (an attack just landed and reset it).
	var cooldown: int = u["cooldown"]
	if prev_cooldown != -1 and cooldown > prev_cooldown + 1:
		attack_lunge_t = 0.18
	prev_cooldown = cooldown
	if attack_lunge_t > 0.0:
		attack_lunge_t -= delta
		var k: float = clamp(attack_lunge_t / 0.18, 0.0, 1.0)
		position += Vector3(facing * 0.22 * sin(k * PI), 0.0, 0.0)
		core_mat.emission_energy_multiplier = 2.2 + 3.0 * sin(k * PI)
	else:
		core_mat.emission_energy_multiplier = 2.2

	# Hit feedback: a hp drop since last check flashes the torso white/red.
	var hp: float = u["hp"]
	if prev_hp >= 0.0 and hp < prev_hp:
		hit_flash_t = 0.22
	prev_hp = hp
	if hit_flash_t > 0.0:
		hit_flash_t -= delta
		var k2: float = clamp(hit_flash_t / 0.22, 0.0, 1.0)
		torso_mat.albedo_color = team_color.lerp(Color(1.0, 0.25, 0.2), k2 * 0.85)
	else:
		torso_mat.albedo_color = team_color
