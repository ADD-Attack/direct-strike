extends Node3D

## Render/UI layer. Talks ONLY to MatchClient (never to Host directly).
## Holds no gameplay state of its own beyond visual node bookkeeping.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")

const TICK_DT := 1.0 / 30.0

var client: MatchClient
var tick_accum: float = 0.0
var unit_nodes: Dictionary = {}
var base_a_mesh: MeshInstance3D
var base_b_mesh: MeshInstance3D

@onready var units_container: Node3D = $UnitsContainer
@onready var cam: Camera3D = $Cam
@onready var base_a_label: Label = $HUDLayer/HUD/BaseALabel
@onready var base_b_label: Label = $HUDLayer/HUD/BaseBLabel
@onready var wave_label: Label = $HUDLayer/HUD/WaveLabel
@onready var status_label: Label = $HUDLayer/HUD/StatusLabel

func _ready() -> void:
	client = MatchClient.new(true)
	_build_static_scene()
	cam.look_at(Vector3(Host.LANE_LENGTH * 0.5, 0.0, 0.0), Vector3.UP)
	_update_hud()

func _build_static_scene() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Host.LANE_LENGTH + 8.0, 6.0)
	ground.mesh = plane
	ground.position = Vector3(Host.LANE_LENGTH * 0.5, 0.0, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.18, 0.2, 0.16)
	ground.material_override = ground_mat
	add_child(ground)

	base_a_mesh = _make_base_mesh(Color(0.3, 0.5, 0.9))
	base_a_mesh.position = Vector3(-1.5, 1.0, 0.0)
	add_child(base_a_mesh)

	base_b_mesh = _make_base_mesh(Color(0.9, 0.35, 0.3))
	base_b_mesh.position = Vector3(Host.LANE_LENGTH + 1.5, 1.0, 0.0)
	add_child(base_b_mesh)

func _make_base_mesh(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 3.0)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	return mi

func _physics_process(delta: float) -> void:
	tick_accum += delta
	while tick_accum >= TICK_DT:
		tick_accum -= TICK_DT
		client.step()
		_apply_events(client.drain_new_events())
	_sync_visuals()
	_update_hud()

func _apply_events(events: Array) -> void:
	for ev in events:
		if ev["type"] == "match_restarted":
			_clear_all_unit_visuals()

func _sync_visuals() -> void:
	var state := client.get_state()
	var units: Dictionary = state["units"]
	for id in units.keys():
		if not unit_nodes.has(id):
			_spawn_unit_visual(id, units[id])
		var node: MeshInstance3D = unit_nodes[id]
		var u: Dictionary = units[id]
		var z: float = -0.6 if u["side"] == "A" else 0.6
		node.position = Vector3(u["pos"], 0.5, z)
	for id in unit_nodes.keys():
		if not units.has(id):
			_remove_unit_visual(id)

func _spawn_unit_visual(id: int, u: Dictionary) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.5, 0.9) if u["side"] == "A" else Color(0.9, 0.35, 0.3)
	mi.material_override = mat
	units_container.add_child(mi)
	unit_nodes[id] = mi

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
