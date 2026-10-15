class_name Host
extends RefCounted

## Authoritative simulation. No rendering, no scene-tree dependency.
## Consumes only Commands (Dictionaries: {tick, player_id, action, params}).
## Everything else (state reads, events) is read-only output.

const LANE_LENGTH := 40.0
const BASE_DAMAGE_PER_UNIT := 25.0
const BASE_HP := 200.0
const SIDES := ["A", "B"]

## --- Economy (Slice 1, per studio/REFERENCE.md — the real Direct Strike
## economy: fixed trickle + up to 4 escalating-cost gases + a middle-control
## bonus. Real rates are undocumented; these are demo tuning. ---
const TICK_RATE := 30
const STARTING_MINERALS := 50.0
const BASE_TRICKLE_PER_SEC := 3.0
const MAX_GASES := 4
const GAS_COSTS := [60.0, 120.0, 240.0, 480.0] ## escalating cost per successive gas
const GAS_TRICKLE_BONUS_PER_SEC := 1.5 ## each gas raises trickle by this much
## Side holding more units on the enemy half of the lane gets this bonus —
## REFERENCE.md cites a forum guide calling it "worth ~2 gases"; set to match.
const MIDDLE_CONTROL_BONUS_PER_SEC := 2.0 * GAS_TRICKLE_BONUS_PER_SEC
const MID_X := LANE_LENGTH * 0.5
const BUILD_PHASE_TICKS := 650 ## countdown length; wave spawns at each boundary (kept from Slice 0/1 tuning, per REFERENCE.md divergence #5)

## --- Roster & tiers (Slice 2, per studio/SLICE-PLAN.md + studio/REFERENCE.md)
## Six roles, one race. Tier 1 is available from the start; tier 2 unlocks
## once a side's lifetime spend crosses TIER2_UNLOCK_THRESHOLD (demo tuning —
## real unlock costs are undocumented per REFERENCE.md). Stats are demo
## tuning too, chosen to make the counters below real, not just flavor text.
const TIER2_UNLOCK_THRESHOLD := 35.0

## Authoritative roster data lives in data/roster_stats.json. No unit combat
## stat is duplicated in simulation code: balance changes are data-only.
static var ROLE_STATS: Dictionary = _load_roster_data()["roles"]
static var ROLE_ORDER: Array = _load_roster_data()["role_order"]
const DEFAULT_ROLE := "line_dps"

static func _load_roster_data() -> Dictionary:
	var file := FileAccess.open("res://data/roster_stats.json", FileAccess.READ)
	if file == null:
		push_error("Missing authoritative roster data: res://data/roster_stats.json")
		return {"role_order": [], "roles": {}}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary) or not parsed.has("role_order") or not parsed.has("roles"):
		push_error("Invalid authoritative roster data: expected role_order and roles")
		return {"role_order": [], "roles": {}}
	return parsed

## --- Formation staging (Slice 2) ---
## A queued-but-unspawned purchase can be assigned a cell {row, col} via
## PLACE_UNIT. col is depth-of-stagger along the lane axis (same role Slice
## 0/1's queue index played — and still the default when col is omitted).
## row is now ALSO an engagement-order axis, per the Slice 2 order: row 0 is
## the front rank and spawns closest to the enemy, row (STAGING_ROWS-1) is
## the back rank and spawns furthest away — so front-row units simply reach
## the enemy and engage first as a natural consequence of position, with no
## separate "wait your turn" logic needed. The centered row (no PLACE_UNIT
## issued) maps to zero extra depth offset, so an unplaced wave reproduces
## Slice 0/1's exact spawn positions.
const STAGING_ROWS := 3
const STAGING_ROW_SPACING := 0.6 ## lateral offset per row step (cosmetic)
const ROW_DEPTH_SPACING := 3.0 ## forward/back offset per row step (engagement order)
const STAGING_COL_SPACING := 0.5

var tick: int = 0
var base_hp: Dictionary = {}
var units: Dictionary = {}
var next_unit_id: int = 1
var wave_count: Dictionary = {}
var match_over: bool = false
var winner: String = ""
var command_log: Array = []
var event_log: Array = []
var auto_source_enabled: bool = true
var pending_log: Array = []
var pending_cursor: int = 0
var first_contact_fired: bool = false

var minerals: Dictionary = {}
var total_spent: Dictionary = {}
var queued_purchases: Dictionary = {} ## side -> Array[{"role": String}], index = queue_index
var trickle_rate: Dictionary = {}
var gas_count: Dictionary = {}
var middle_controller: String = "" ## "" (none), "A", or "B"
var queued_placements: Dictionary = {} ## side -> {queue_index: {"row": int, "col": int}}
var phase_start_tick: int = 0
var next_phase_tick: int = 0
var enemy_phase_count: int = 0

func _init(auto_source: bool = true) -> void:
	reset_match(auto_source)

func reset_match(auto_source: bool) -> void:
	tick = 0
	base_hp = {"A": BASE_HP, "B": BASE_HP}
	units = {}
	next_unit_id = 1
	wave_count = {"A": 0, "B": 0}
	match_over = false
	winner = ""
	command_log = []
	event_log = []
	auto_source_enabled = auto_source
	pending_log = []
	pending_cursor = 0
	first_contact_fired = false
	minerals = {"A": STARTING_MINERALS, "B": STARTING_MINERALS}
	total_spent = {"A": 0.0, "B": 0.0}
	queued_purchases = {"A": [], "B": []}
	trickle_rate = {"A": BASE_TRICKLE_PER_SEC, "B": BASE_TRICKLE_PER_SEC}
	gas_count = {"A": 0, "B": 0}
	middle_controller = ""
	queued_placements = {"A": {}, "B": {}}
	phase_start_tick = 0
	next_phase_tick = BUILD_PHASE_TICKS
	enemy_phase_count = 0

## Load a pre-recorded command log and run in pure replay mode (no auto-source).
func load_replay_log(log: Array) -> void:
	reset_match(false)
	pending_log = log.duplicate(true)
	pending_cursor = 0

## External command source (player, AI, playtest). cmd = {tick, player_id, action, params}.
func submit_command(cmd: Dictionary) -> void:
	pending_log.append(cmd)

## Advance the simulation by exactly one fixed tick.
func step() -> void:
	_consume_scheduled_commands()
	if auto_source_enabled and not match_over and tick >= next_phase_tick:
		# Wave cadence is match timing, not an opponent decision. The AI's only
		# decisions are BUY_UNIT / BUY_GAS / PLACE_UNIT through MatchClient.
		for side in SIDES:
			_apply_command({"tick": tick, "player_id": side, "action": "SPAWN_WAVE", "params": {}})
		phase_start_tick = tick
		next_phase_tick = tick + BUILD_PHASE_TICKS
		enemy_phase_count += 1
		if tick >= next_phase_tick:
			for side in SIDES:
				_apply_command({"tick": tick, "player_id": side, "action": "SPAWN_WAVE", "params": {}})
			phase_start_tick = tick
			next_phase_tick = tick + BUILD_PHASE_TICKS
			enemy_phase_count += 1
	if not match_over:
		_update_middle_control()
		for side in SIDES:
			var rate: float = trickle_rate[side] + (MIDDLE_CONTROL_BONUS_PER_SEC if middle_controller == side else 0.0)
			minerals[side] += rate / float(TICK_RATE)
		_simulate_units()
		_resolve_base_damage()
		_check_win()
	tick += 1

## Recomputes which side (if either) holds more units on the enemy half of
## the lane, and emits an event only when that changes — this runs every
## tick (authoritative), the event is just a ledger breadcrumb of the flips.
func _update_middle_control() -> void:
	var count_a := 0
	var count_b := 0
	for id in units:
		var u: Dictionary = units[id]
		if u["side"] == "A" and u["pos"] > MID_X:
			count_a += 1
		elif u["side"] == "B" and u["pos"] < MID_X:
			count_b += 1
	var new_controller: String = ""
	if count_a > count_b:
		new_controller = "A"
	elif count_b > count_a:
		new_controller = "B"
	if new_controller != middle_controller:
		middle_controller = new_controller
		_emit_event("middle_control_changed", {"controller": middle_controller, "units_on_enemy_half": {"A": count_a, "B": count_b}})

func _consume_scheduled_commands() -> void:
	while pending_cursor < pending_log.size() and pending_log[pending_cursor]["tick"] <= tick:
		var cmd: Dictionary = pending_log[pending_cursor]
		_apply_command(cmd)
		pending_cursor += 1

func _apply_command(cmd: Dictionary) -> void:
	command_log.append(cmd)
	match cmd.get("action", ""):
		"SPAWN_WAVE":
			_do_spawn_wave(cmd["player_id"])
		"RESTART":
			_do_restart()
		"BUY_UNIT":
			_do_buy_unit(cmd["player_id"], cmd.get("params", {}))
		"BUY_GAS":
			_do_buy_gas(cmd["player_id"])
		"PLACE_UNIT":
			_do_place_unit(cmd["player_id"], cmd.get("params", {}))
		_:
			_emit_event("unknown_command", {"action": cmd.get("action", "")})

## params: {role: String}. Tier-2 roles are rejected (reason "tier_locked")
## until total_spent[side] crosses TIER2_UNLOCK_THRESHOLD — checked
## authoritatively here, exactly like the affordability check, never trusted
## from the submitter.
func _do_buy_unit(side: String, params: Dictionary) -> void:
	var role: String = params.get("role", DEFAULT_ROLE)
	if not ROLE_STATS.has(role):
		_emit_event("buy_rejected", {"side": side, "role": role, "reason": "unknown_role"})
		return
	var spec: Dictionary = ROLE_STATS[role]
	if spec["tier"] == 2 and total_spent[side] < TIER2_UNLOCK_THRESHOLD:
		_emit_event("buy_rejected", {"side": side, "role": role, "reason": "tier_locked", "total_spent": total_spent[side], "threshold": TIER2_UNLOCK_THRESHOLD})
		return
	var cost: float = spec["cost"]
	if minerals[side] < cost:
		_emit_event("buy_rejected", {"side": side, "role": role, "reason": "insufficient_minerals", "minerals": minerals[side], "cost": cost})
		return
	minerals[side] -= cost
	total_spent[side] += cost
	queued_purchases[side].append({"role": role})
	var queue_index: int = queued_purchases[side].size() - 1
	_emit_event("unit_purchased", {"side": side, "role": role, "cost": cost, "minerals_remaining": minerals[side], "total_spent": total_spent[side], "queue_index": queue_index, "queued_units": queued_purchases[side].size()})

func _do_buy_gas(side: String) -> void:
	if gas_count[side] >= MAX_GASES:
		_emit_event("buy_rejected", {"side": side, "reason": "max_gases_reached", "gas_count": gas_count[side]})
		return
	var cost: float = GAS_COSTS[gas_count[side]]
	if minerals[side] < cost:
		_emit_event("buy_rejected", {"side": side, "reason": "insufficient_minerals", "minerals": minerals[side], "cost": cost})
		return
	minerals[side] -= cost
	total_spent[side] += cost
	gas_count[side] += 1
	trickle_rate[side] += GAS_TRICKLE_BONUS_PER_SEC
	_emit_event("gas_purchased", {"side": side, "cost": cost, "gas_count": gas_count[side], "new_trickle_rate": trickle_rate[side]})

## params: {queue_index: int, row: int, col: int}. queue_index addresses a
## purchase already queued (not yet spawned) this build phase for `side`.
## row/col are optional; the defaults applied at spawn time reproduce the
## pre-placement single-file formation exactly (see _do_spawn_wave).
func _do_place_unit(side: String, params: Dictionary) -> void:
	var idx: int = params.get("queue_index", -1)
	if idx < 0 or idx >= queued_purchases[side].size():
		_emit_event("placement_rejected", {"side": side, "queue_index": idx, "reason": "no_such_queued_unit", "queued_units": queued_purchases[side].size()})
		return
	var row: int = params.get("row", (STAGING_ROWS - 1) / 2)
	if row < 0 or row >= STAGING_ROWS:
		_emit_event("placement_rejected", {"side": side, "queue_index": idx, "reason": "row_out_of_range", "row": row})
		return
	var col: int = params.get("col", idx)
	queued_placements[side][idx] = {"row": row, "col": col}
	_emit_event("unit_placed", {"side": side, "queue_index": idx, "row": row, "col": col})

func _do_spawn_wave(side: String) -> void:
	wave_count[side] += 1
	var purchases: Array = queued_purchases[side]
	var count: int = purchases.size()
	var ids: Array = []
	var start_pos: float = 0.0 if side == "A" else LANE_LENGTH
	var dir: float = 1.0 if side == "A" else -1.0
	var placements: Dictionary = queued_placements[side]
	var formation: Array = []
	var center_row: float = (STAGING_ROWS - 1) / 2.0
	for i in range(count):
		var id := next_unit_id
		var role: String = purchases[i]["role"]
		var spec: Dictionary = ROLE_STATS[role]
		var cell: Dictionary = placements.get(i, {"row": int(center_row), "col": i})
		var row: int = cell["row"]
		var col: int = cell["col"]
		var lane_offset: float = (row - center_row) * STAGING_ROW_SPACING
		var depth_offset: float = (row - center_row) * ROW_DEPTH_SPACING
		units[id] = {
			"id": id,
			"side": side,
			"role": role,
			"pos": start_pos - dir * (col * STAGING_COL_SPACING) - dir * depth_offset,
			"lane_offset": lane_offset,
			"formation_cell": {"row": row, "col": col},
			"hp": spec["hp"],
			"max_hp": spec["hp"],
			"damage": spec["damage"],
			"range": spec["range"],
			"cooldown_max": spec["cooldown"],
			"speed": spec["speed"],
			"splash_radius": spec["splash_radius"],
			"bonus_vs": spec["bonus_vs"],
			"avoid_roles": spec["avoid_roles"],
			"state": "marching",
			"target_id": -1,
			"cooldown": 0,
		}
		ids.append(id)
		formation.append({"unit_id": id, "role": role, "row": row, "col": col, "lane_offset": lane_offset, "hp": spec["hp"], "damage": spec["damage"], "range": spec["range"], "cooldown": spec["cooldown"], "speed": spec["speed"]})
		next_unit_id += 1
	queued_purchases[side] = []
	queued_placements[side] = {}
	_emit_event("wave_spawned", {"side": side, "wave_number": wave_count[side], "unit_ids": ids, "purchased_count": count, "formation": formation})

func _do_restart() -> void:
	base_hp = {"A": BASE_HP, "B": BASE_HP}
	units = {}
	wave_count = {"A": 0, "B": 0}
	match_over = false
	winner = ""
	first_contact_fired = false
	minerals = {"A": STARTING_MINERALS, "B": STARTING_MINERALS}
	total_spent = {"A": 0.0, "B": 0.0}
	queued_purchases = {"A": [], "B": []}
	trickle_rate = {"A": BASE_TRICKLE_PER_SEC, "B": BASE_TRICKLE_PER_SEC}
	gas_count = {"A": 0, "B": 0}
	middle_controller = ""
	queued_placements = {"A": {}, "B": {}}
	phase_start_tick = tick
	next_phase_tick = tick + BUILD_PHASE_TICKS
	enemy_phase_count = 0
	_emit_event("match_restarted", {})

## A unit either has a target (acquired by scanning when it had none) or it
## doesn't. With a target: if currently within ITS OWN range, attack; if
## not yet in range, close the distance (move toward the target specifically,
## not just a generic forward march) — this is what makes a longer-range
## role (ranged) actually able to land hits before a shorter-range role
## (frontline_tank) can reach back, instead of range only changing when
## combat starts. Without a target: scan for one within range, honoring
## avoid_roles (the "bypasses the front" mechanic — prefer a non-avoided
## enemy if one is in range, otherwise fight whatever is there); if none,
## march straight toward the enemy base.
func _simulate_units() -> void:
	var ids: Array = units.keys()
	ids.sort()
	for id in ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		var dir: float = 1.0 if u["side"] == "A" else -1.0

		if u["target_id"] == -1 or not units.has(u["target_id"]):
			u["target_id"] = -1
			var enemy_id := _find_engageable_enemy(u)
			if enemy_id != -1:
				u["target_id"] = enemy_id
				var other: Dictionary = units[enemy_id]
				if other["target_id"] == -1:
					other["target_id"] = id
				if not first_contact_fired:
					first_contact_fired = true
					_emit_event("first_contact", {"unit_a": id, "unit_b": enemy_id})

		if u["target_id"] == -1:
			u["state"] = "marching"
			u["pos"] += dir * u["speed"]
			continue

		var target: Dictionary = units[u["target_id"]]
		var dist: float = absf(target["pos"] - u["pos"])
		if dist <= u["range"]:
			if u["state"] != "fighting":
				u["state"] = "fighting"
				_emit_event("unit_engaged", {"unit_id": id, "side": u["side"], "role": u["role"], "target_id": u["target_id"]})
			if u["cooldown"] > 0:
				u["cooldown"] -= 1
			else:
				_resolve_attack(id, u)
		else:
			u["state"] = "marching"
			u["pos"] += signf(target["pos"] - u["pos"]) * u["speed"]

func _resolve_attack(attacker_id: int, u: Dictionary) -> void:
	var target_id: int = u["target_id"]
	if not units.has(target_id):
		u["target_id"] = -1
		return
	var target: Dictionary = units[target_id]
	var multiplier: float = u["bonus_vs"].get(target["role"], 1.0)
	target["hp"] -= u["damage"] * multiplier
	u["cooldown"] = u["cooldown_max"]
	var killed: Array = []
	if target["hp"] <= 0.0:
		killed.append(target_id)
	if u["splash_radius"] > 0.0:
		var ids: Array = units.keys()
		ids.sort()
		for other_id in ids:
			if other_id == target_id or not units.has(other_id):
				continue
			var other: Dictionary = units[other_id]
			if other["side"] == target["side"] and absf(other["pos"] - target["pos"]) <= u["splash_radius"]:
				other["hp"] -= u["damage"] * u["bonus_vs"].get(other["role"], 1.0)
				if other["hp"] <= 0.0 and not killed.has(other_id):
					killed.append(other_id)
	for dead_id in killed:
		var dead: Dictionary = units[dead_id]
		_emit_event("unit_death", {"unit_id": dead_id, "side": dead["side"], "role": dead["role"], "killer_id": attacker_id})
		units.erase(dead_id)
		if u["target_id"] == dead_id:
			u["target_id"] = -1

func _find_engageable_enemy(u: Dictionary) -> int:
	var ids: Array = units.keys()
	ids.sort()
	var avoid: Array = u["avoid_roles"]
	var fallback_id := -1
	for id in ids:
		var other: Dictionary = units[id]
		if other["side"] != u["side"] and absf(other["pos"] - u["pos"]) <= u["range"]:
			if avoid.has(other["role"]):
				if fallback_id == -1:
					fallback_id = id
			else:
				return id
	return fallback_id

func _resolve_base_damage() -> void:
	var ids: Array = units.keys()
	ids.sort()
	for id in ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		if u["side"] == "A" and u["pos"] >= LANE_LENGTH:
			_deal_base_damage("B", id)
			units.erase(id)
			if base_hp["B"] <= 0.0:
				break
		elif u["side"] == "B" and u["pos"] <= 0.0:
			_deal_base_damage("A", id)
			units.erase(id)
			if base_hp["A"] <= 0.0:
				break

func _deal_base_damage(target_side: String, unit_id: int) -> void:
	base_hp[target_side] = maxf(0.0, base_hp[target_side] - BASE_DAMAGE_PER_UNIT)
	_emit_event("base_damage", {"side": target_side, "damage": BASE_DAMAGE_PER_UNIT, "hp_remaining": base_hp[target_side], "unit_id": unit_id})

func _check_win() -> void:
	for side in SIDES:
		if base_hp[side] <= 0.0 and not match_over:
			match_over = true
			winner = "B" if side == "A" else "A"
			_emit_event("match_won", {"winner": winner, "loser": side})

func _emit_event(type: String, data: Dictionary) -> void:
	event_log.append({"tick": tick, "type": type, "data": data})

## --- Read-only output for the client / playtest. Always copies, never internal refs. ---

func get_state() -> Dictionary:
	return {
		"tick": tick,
		"base_hp": base_hp.duplicate(true),
		"units": units.duplicate(true),
		"match_over": match_over,
		"winner": winner,
		"wave_count": wave_count.duplicate(true),
		"minerals": minerals.duplicate(true),
		"total_spent": total_spent.duplicate(true),
		"queued_units": {"A": queued_purchases["A"].size(), "B": queued_purchases["B"].size()},
		# Presentation-only read model for the visible staging board. This is a
		# deep copy; clients cannot alter purchases or placements through it.
		"queued_purchases": queued_purchases.duplicate(true),
		"queued_placements": queued_placements.duplicate(true),
		"trickle_rate": trickle_rate.duplicate(true),
		"gas_count": gas_count.duplicate(true),
		"middle_controller": middle_controller,
		"ticks_until_next_wave": next_phase_tick - tick,
		"build_phase_ticks": BUILD_PHASE_TICKS,
		"tier2_unlocked": {"A": total_spent["A"] >= TIER2_UNLOCK_THRESHOLD, "B": total_spent["B"] >= TIER2_UNLOCK_THRESHOLD},
	}

func get_event_log() -> Array:
	return event_log.duplicate(true)

func get_command_log() -> Array:
	return command_log.duplicate(true)
