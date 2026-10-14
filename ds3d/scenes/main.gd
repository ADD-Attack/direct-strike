extends Node3D

## Render/UI layer. Talks ONLY to MatchClient (never to Host directly).
## Holds no gameplay state of its own beyond visual node bookkeeping.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")
const UnitVisualScript = preload("res://scenes/unit_visual.gd")
const BaseVisualScript = preload("res://scenes/base_visual.gd")

const TICK_DT := 1.0 / 30.0
const COLOR_A := Color(0.25, 0.55, 0.95)
const COLOR_B := Color(0.92, 0.32, 0.26)

var client: MatchClient
var tick_accum: float = 0.0
var unit_nodes: Dictionary = {}
# Untyped (Variant) on purpose: these hold script-attached Node3D instances
# (BaseVisualScript / UnitVisualScript) whose custom methods (build(),
# process_flash(), update()) aren't visible to Node3D's static type.
var base_a
var base_b

@onready var units_container: Node3D = $UnitsContainer
@onready var cam: Camera3D = $Cam
@onready var sun: DirectionalLight3D = $Sun
@onready var base_a_label: Label = $HUDLayer/HUD/BaseALabel
@onready var base_b_label: Label = $HUDLayer/HUD/BaseBLabel
@onready var wave_label: Label = $HUDLayer/HUD/WaveLabel
@onready var status_label: Label = $HUDLayer/HUD/StatusLabel

func _ready() -> void:
	client = MatchClient.new(true)
	_build_environment()
	_build_terrain()
	_build_bases()
	_configure_camera()
	_configure_lighting()
	_update_hud()

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.08, 0.16)
	sky_mat.sky_horizon_color = Color(0.22, 0.24, 0.3)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.06)
	sky_mat.ground_horizon_color = Color(0.22, 0.24, 0.3)
	sky_mat.sun_angle_max = 10.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.26, 0.28, 0.34)
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_terrain() -> void:
	var lane_len: float = Host.LANE_LENGTH
	var center_x: float = lane_len * 0.5

	var plating := _box_node(Vector3(lane_len + 10.0, 0.3, 6.4))
	plating.position = Vector3(center_x, -0.15, 0.0)
	_apply_mat(plating, Color(0.16, 0.18, 0.22), 0.4, 0.6)

	for i in range(int((lane_len + 10.0) / 3.0)):
		var seam := _box_node(Vector3(0.06, 0.32, 6.4))
		seam.position = Vector3(-5.0 + i * 3.0, -0.14, 0.0)
		_apply_mat(seam, Color(0.3, 0.6, 0.85), 0.3, 0.1, true, 0.9)

	for side in [1.0, -1.0]:
		var embank := _box_node(Vector3(lane_len + 14.0, 1.8, 4.2))
		embank.position = Vector3(center_x, -0.9, side * 5.3)
		_apply_mat(embank, Color(0.28, 0.22, 0.14), 0.95, 0.0)
		var ridge := _box_node(Vector3(lane_len + 14.0, 0.5, 1.2))
		ridge.position = Vector3(center_x, 0.05, side * 3.6)
		_apply_mat(ridge, Color(0.34, 0.28, 0.17), 0.9, 0.0)

	var rock_offsets := [-4.0, 4.0, 11.0, 19.0, 27.0, 35.0, 42.0, 48.0]
	for i in range(rock_offsets.size()):
		var x: float = rock_offsets[i]
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var mi := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.6 + (i % 3) * 0.2, 0.9 + (i % 2) * 0.4, 0.6)
		mi.mesh = prism
		add_child(mi)
		mi.position = Vector3(x, 0.35, side * (4.6 + (i % 2) * 0.6))
		mi.rotation.y = float(i) * 0.9
		_apply_mat(mi, Color(0.3, 0.29, 0.27), 0.85, 0.05)

func _box_node(size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	add_child(mi)
	return mi

func _apply_mat(mi: MeshInstance3D, color: Color, roughness: float, metallic: float, emissive: bool = false, energy: float = 1.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	mi.material_override = mat

func _build_bases() -> void:
	base_a = BaseVisualScript.new()
	add_child(base_a)
	base_a.position = Vector3(-2.6, 0.0, 0.0)
	base_a.build(COLOR_A, 1.0)

	base_b = BaseVisualScript.new()
	add_child(base_b)
	base_b.position = Vector3(Host.LANE_LENGTH + 2.6, 0.0, 0.0)
	base_b.rotation.y = PI
	base_b.build(COLOR_B, -1.0)

func _configure_camera() -> void:
	cam.fov = 55.0
	cam.position = Vector3(-9.5, 10.0, 14.0)
	cam.look_at(Vector3(Host.LANE_LENGTH * 0.5, 0.5, 0.0), Vector3.UP)

func _configure_lighting() -> void:
	sun.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(-50.0), 0.0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(150.0), 0.0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.5, 0.62, 0.95)
	add_child(fill)

func _physics_process(delta: float) -> void:
	tick_accum += delta
	while tick_accum >= TICK_DT:
		tick_accum -= TICK_DT
		client.step()
		_apply_events(client.drain_new_events())
	_sync_visuals(delta)
	base_a.process_flash(delta)
	base_b.process_flash(delta)
	_update_hud()

func _apply_events(events: Array) -> void:
	for ev in events:
		if ev["type"] == "match_restarted":
			_clear_all_unit_visuals()
		elif ev["type"] == "base_damage":
			var side: String = ev["data"]["side"]
			if side == "A":
				base_a.flash_damage()
			else:
				base_b.flash_damage()

func _sync_visuals(delta: float) -> void:
	var state := client.get_state()
	var units: Dictionary = state["units"]
	for id in units.keys():
		if not unit_nodes.has(id):
			_spawn_unit_visual(id, units[id])
		var node = unit_nodes[id]
		var u: Dictionary = units[id]
		var z: float = -0.7 if u["side"] == "A" else 0.7
		node.update(u, delta, z)
	for id in unit_nodes.keys():
		if not units.has(id):
			_remove_unit_visual(id)

func _spawn_unit_visual(id: int, u: Dictionary) -> void:
	var rig = UnitVisualScript.new()
	units_container.add_child(rig)
	var color := COLOR_A if u["side"] == "A" else COLOR_B
	rig.build(color, float(id % 7))
	unit_nodes[id] = rig

func _remove_unit_visual(id: int) -> void:
	if unit_nodes.has(id):
		unit_nodes[id].queue_free()
		unit_nodes.erase(id)

func _clear_all_unit_visuals() -> void:
	for id in unit_nodes.keys():
		unit_nodes[id].queue_free()
	unit_nodes.clear()

func _update_hud() -> void:
	var state := client.get_state()
	base_a_label.text = "Base A HP: %d" % int(state["base_hp"]["A"])
	base_b_label.text = "Base B HP: %d" % int(state["base_hp"]["B"])
	wave_label.text = "Waves — A: %d   B: %d" % [state["wave_count"]["A"], state["wave_count"]["B"]]
	if state["match_over"]:
		status_label.text = "MATCH OVER — Winner: %s   (press R to restart)" % state["winner"]
	else:
		status_label.text = "Tick: %d   (press R to restart)" % state["tick"]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		client.submit_command("owner", "RESTART", {})
