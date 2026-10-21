extends Node3D

## Render/UI layer. Talks ONLY to MatchClient (never to Host directly).
## Holds no gameplay state of its own beyond visual node bookkeeping.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")
const NetSession = preload("res://net/net_session.gd")
const UnitVisualScript = preload("res://scenes/unit_visual.gd")
const BaseVisualScript = preload("res://scenes/base_visual.gd")

const TICK_DT := 1.0 / 30.0
const COLOR_A := Color(0.25, 0.55, 0.95)
const COLOR_B := Color(0.92, 0.32, 0.26)

## Slice 4: the live match runs as a net session — an authoritative host
## plus two clients (A = this UI, B = the AI buyer) over the loopback
## transport. `client` is session.client_a; it exposes the same read API
## as MatchClient, so everything below renders off the client's replica.
var session: NetSession
var client # NetClient (session.client_a)
var replay_client: MatchClient # non-null while watching a replay
var replay_ticks_left: int = 0
var replay_finished: bool = false
var last_match_log: Array = []
var last_match_ticks: int = 0
var ai_difficulty: String = "normal"
var replay_button: Button
var tick_accum: float = 0.0
var unit_nodes: Dictionary = {}
var staging_cells: Array = []
var staging_previews: Dictionary = {}
var staging_root: Node3D
var staging_preview_root: Node3D
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
@onready var minerals_label: Label = $HUDLayer/HUD/MineralsLabel
@onready var trickle_label: Label = $HUDLayer/HUD/TrickleLabel
@onready var build_timer_label: Label = $HUDLayer/HUD/BuildTimerLabel
@onready var role_buttons_container: HBoxContainer = $HUDLayer/HUD/RoleButtons
@onready var row_buttons_container: HBoxContainer = $HUDLayer/HUD/RowButtons
@onready var buy_gas_button: Button = $HUDLayer/HUD/BuyGasButton

var role_buttons: Dictionary = {} # role -> Button
var row_buttons: Array = [] # Button, index = row
var selected_row: int = 1 # default centered row — matches Host's default placement
var difficulty_picker: OptionButton

func _start_live_session() -> void:
	session = NetSession.loopback(ai_difficulty)
	session.wait_connected()
	client = session.client_a

func _ready() -> void:
	_start_live_session()
	_build_environment()
	_build_terrain()
	_build_bases()
	_build_staging_board()
	_configure_camera()
	_configure_lighting()
	_build_role_buttons()
	_build_row_buttons()
	_build_difficulty_picker()
	_build_replay_button()
	buy_gas_button.pressed.connect(_on_buy_gas_pressed)
	_update_hud()

func _build_replay_button() -> void:
	replay_button = Button.new()
	replay_button.name = "WatchReplayButton"
	replay_button.text = "Watch Replay"
	replay_button.visible = false
	replay_button.pressed.connect(_on_replay_pressed)
	$HUDLayer/HUD.add_child(replay_button)

## "Watch replay" of the last finished match: the host session's recorded
## command log, replayed into a fresh host and rendered exactly like the
## live game. Stopping the replay starts a fresh live session.
func _on_replay_pressed() -> void:
	if replay_client != null:
		_stop_replay()
		return
	if last_match_log.is_empty():
		return
	replay_client = MatchClient.new(false)
	replay_client.load_replay_log(last_match_log)
	replay_ticks_left = last_match_ticks
	replay_finished = false
	_clear_all_unit_visuals()
	replay_button.text = "Stop Replay"

func _stop_replay() -> void:
	replay_client = null
	replay_ticks_left = 0
	replay_finished = false
	last_match_log = []
	last_match_ticks = 0
	_start_live_session()
	_clear_all_unit_visuals()
	replay_button.text = "Watch Replay"
	replay_button.visible = false

func _step_replay() -> void:
	if replay_finished:
		return
	replay_client.step()
	_apply_events(replay_client.drain_new_events())
	replay_ticks_left -= 1
	if replay_ticks_left <= 0:
		replay_finished = true

func _capture_finished_match() -> void:
	if not last_match_log.is_empty():
		return
	if client.get_state()["match_over"]:
		last_match_log = session.get_command_log()
		last_match_ticks = session.host_tick()
		replay_button.visible = true

func _active_client():
	return replay_client if replay_client != null else client

func _build_role_buttons() -> void:
	for role in Host.ROLE_ORDER:
		var spec: Dictionary = Host.ROLE_STATS[role]
		var b := Button.new()
		b.name = "Buy_%s" % role
		b.text = "%s (%d)" % [role.capitalize(), int(spec["cost"])]
		b.pressed.connect(_on_buy_role_pressed.bind(role))
		role_buttons_container.add_child(b)
		role_buttons[role] = b

func _build_row_buttons() -> void:
	var labels := ["Front", "Mid", "Back"]
	for row in range(Host.STAGING_ROWS):
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = row == selected_row
		b.text = labels[row] if row < labels.size() else "Row %d" % row
		b.pressed.connect(_on_row_selected.bind(row))
		row_buttons_container.add_child(b)
		row_buttons.append(b)

func _build_difficulty_picker() -> void:
	difficulty_picker = OptionButton.new()
	difficulty_picker.name = "AIDifficulty"
	for label in ["Easy", "Normal", "Hard"]:
		difficulty_picker.add_item("AI: " + label)
	difficulty_picker.select(1)
	difficulty_picker.item_selected.connect(_on_ai_difficulty_selected)
	$HUDLayer/HUD.add_child(difficulty_picker)

func _on_ai_difficulty_selected(index: int) -> void:
	ai_difficulty = ["easy", "normal", "hard"][index]
	if session != null:
		session.set_ai_difficulty(ai_difficulty)

func _on_row_selected(row: int) -> void:
	selected_row = row
	for i in range(row_buttons.size()):
		row_buttons[i].button_pressed = i == row
	_refresh_staging_highlight()

## Buying and placing are two separate commands through the same interface,
## issued back-to-back: the buy queues the unit, the placement assigns it a
## formation cell before it ever spawns. queue_index is read from state
## BEFORE submitting the buy, since that's the ordinal the new purchase will
## land on in this side's queue (see Host._do_buy_unit/_do_place_unit).
func _on_buy_role_pressed(role: String) -> void:
	if replay_client != null:
		return
	var queue_index: int = client.get_state()["queued_units"]["A"]
	client.submit_command("A", "BUY_UNIT", {"role": role})
	client.submit_command("A", "PLACE_UNIT", {"queue_index": queue_index, "row": selected_row})

func _on_buy_gas_pressed() -> void:
	if replay_client != null:
		return
	client.submit_command("A", "BUY_GAS", {})

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

## An explicit presentation board in the player's half. It is intentionally
## larger/brighter than the simulation's spawn offsets: this is a readable
## staging affordance, not gameplay geometry.
func _build_staging_board() -> void:
	staging_root = Node3D.new()
	staging_root.name = "VisibleStagingBoard"
	# Presentation only: lowered side platform, entirely clear of lane/pathing.
	staging_root.position = Vector3(7.0, -0.5, 9.5)
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(10.6, 0.35, 5.1)
	deck.mesh = deck_mesh
	deck.position = Vector3(8.0, -0.175, 0.0)
	staging_root.add_child(deck)
	_apply_mat(deck, Color(0.12, 0.17, 0.24), 0.55, 0.5)
	add_child(staging_root)
	staging_preview_root = Node3D.new()
	staging_root.add_child(staging_preview_root)
	for row in range(Host.STAGING_ROWS):
		var label := Label3D.new()
		label.text = ["FRONT", "MID", "BACK"][row]
		label.font_size = 64
		label.pixel_size = 0.008
		label.outline_size = 8
		label.modulate = Color(0.55, 0.8, 1.0)
		label.position = Vector3(4.0, 0.18, _staging_z(row))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		staging_root.add_child(label)
		for col in range(6):
			var cell := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.0, 0.08, 1.15)
			cell.mesh = mesh
			cell.position = Vector3(_staging_x(col), 0.06, _staging_z(row))
			staging_root.add_child(cell)
			staging_cells.append({"row": row, "node": cell})
	_refresh_staging_highlight()

func _staging_x(col: int) -> float:
	return 6.0 + col * 1.25

func _staging_z(row: int) -> float:
	return (row - 1) * 1.55

func _refresh_staging_highlight() -> void:
	for cell_data in staging_cells:
		var row: int = cell_data["row"]
		var mat := StandardMaterial3D.new()
		var active := row == selected_row
		mat.albedo_color = Color(0.08, 0.45, 0.9, 0.92) if active else Color(0.08, 0.14, 0.24, 0.72)
		mat.metallic = 0.25
		mat.roughness = 0.28
		mat.emission_enabled = true
		mat.emission = Color(0.15, 0.75, 1.0) if active else Color(0.06, 0.16, 0.3)
		mat.emission_energy_multiplier = 3.0 if active else 0.6
		cell_data["node"].material_override = mat

func _sync_staging_previews(state: Dictionary) -> void:
	var purchases: Array = state["queued_purchases"]["A"]
	var placements: Dictionary = state["queued_placements"]["A"]
	for idx in range(purchases.size()):
		if staging_previews.has(idx):
			continue
		var cell: Dictionary = placements.get(idx, {"row": 1, "col": idx})
		var marker := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.28
		capsule.height = 1.1
		marker.mesh = capsule
		marker.position = Vector3(_staging_x(int(cell["col"]) % 6), 0.62, _staging_z(int(cell["row"])))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLOR_A
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.8, 1.0)
		mat.emission_energy_multiplier = 4.0
		marker.material_override = mat
		staging_preview_root.add_child(marker)
		staging_previews[idx] = marker
	for idx in staging_previews.keys():
		if idx >= purchases.size():
			staging_previews[idx].queue_free()
			staging_previews.erase(idx)

func _configure_camera() -> void:
	cam.fov = 58.0
	cam.position = Vector3(15.615, 19.170, 23.232)
	cam.look_at(Vector3(18.0, 0.0, 0.0), Vector3.UP)

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
		if replay_client != null:
			_step_replay()
		else:
			session.pump()
			_apply_events(client.drain_new_events())
			_capture_finished_match()
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
	var state: Dictionary = _active_client().get_state()
	_sync_staging_previews(state)
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
	rig.build(u["role"], color, float(id % 7))
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
	var state: Dictionary = _active_client().get_state()
	base_a_label.text = "Base A HP: %d" % int(state["base_hp"]["A"])
	base_b_label.text = "Base B HP: %d" % int(state["base_hp"]["B"])
	wave_label.text = "Waves — A: %d   B: %d" % [state["wave_count"]["A"], state["wave_count"]["B"]]
	if replay_client != null:
		if replay_finished:
			status_label.text = "REPLAY OVER — Winner: %s   (Stop Replay to play again)" % state["winner"]
		else:
			status_label.text = "REPLAY — Tick: %d / %d" % [state["tick"], last_match_ticks]
	elif state["match_over"]:
		status_label.text = "MATCH OVER — Winner: %s   (press R to restart)" % state["winner"]
	else:
		status_label.text = "Tick: %d   (press R to restart)" % state["tick"]
	minerals_label.text = "Minerals A: %d   Queued for next wave: %d" % [int(state["minerals"]["A"]), state["queued_units"]["A"]]
	var controller: String = state["middle_controller"]
	var control_text: String = "A (you)" if controller == "A" else ("B (enemy)" if controller == "B" else "—")
	trickle_label.text = "Trickle A: %.1f/s   Gases: %d/%d   Middle control: %s" % [state["trickle_rate"]["A"], state["gas_count"]["A"], Host.MAX_GASES, control_text]
	var seconds_left: float = max(0.0, state["ticks_until_next_wave"]) / 30.0
	build_timer_label.text = "Next wave in: %.1fs" % seconds_left

	var tier2_unlocked: bool = state["tier2_unlocked"]["A"]
	for role in Host.ROLE_ORDER:
		var spec: Dictionary = Host.ROLE_STATS[role]
		var b: Button = role_buttons[role]
		if spec["tier"] == 2 and not tier2_unlocked:
			b.disabled = true
			b.text = "%s (%d) [tier 2 @ %d spend]" % [role.capitalize(), int(spec["cost"]), int(Host.TIER2_UNLOCK_THRESHOLD)]
		else:
			b.disabled = state["minerals"]["A"] < spec["cost"]
			b.text = "%s (%d)" % [role.capitalize(), int(spec["cost"])]

	var gas_idx: int = state["gas_count"]["A"]
	if gas_idx >= Host.MAX_GASES:
		buy_gas_button.disabled = true
		buy_gas_button.text = "Buy Gas — MAX (G)"
	else:
		var gas_cost: float = Host.GAS_COSTS[gas_idx]
		buy_gas_button.disabled = state["minerals"]["A"] < gas_cost
		buy_gas_button.text = "Buy Gas — %d minerals (G)" % int(gas_cost)

func _unhandled_input(event: InputEvent) -> void:
	if replay_client != null:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			client.submit_command("owner", "RESTART", {})
			# A restarted match becomes the new "last match" when it ends.
			last_match_log = []
			last_match_ticks = 0
			replay_button.visible = false
		elif event.keycode == KEY_G:
			client.submit_command("A", "BUY_GAS", {})
