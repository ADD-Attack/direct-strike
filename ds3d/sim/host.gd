class_name Host
extends RefCounted

## Authoritative simulation. No rendering, no scene-tree dependency.
## Consumes only Commands (Dictionaries: {tick, player_id, action, params}).
## Everything else (state reads, events) is read-only output.

const LANE_LENGTH := 40.0
const UNIT_SPEED_PER_TICK := 0.12
const UNIT_HP := 30.0
const UNIT_DAMAGE := 6.0
const UNIT_ATTACK_RANGE := 1.2
const UNIT_ATTACK_COOLDOWN_TICKS := 20
const BASE_DAMAGE_PER_UNIT := 25.0
const BASE_HP := 200.0
const SIDES := ["A", "B"]

## --- Economy (Slice 1) ---
const STARTING_MINERALS := 50.0
const UNIT_COST := 10.0
const BASE_INCOME := 10.0
const INCOME_RATE := 0.15 ## income = BASE_INCOME + floor(total_spent * INCOME_RATE)
const BUILD_PHASE_TICKS := 650 ## countdown length; wave spawns + income paid at each boundary
## Fixed, deterministic enemy (side B) buy schedule: tick offsets from the
## start of each build phase at which B issues one BUY_UNIT command each.
const ENEMY_BUY_OFFSETS := [30, 90, 150]

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
var queued_units: Dictionary = {}
var phase_start_tick: int = 0
var next_phase_tick: int = 0

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
	queued_units = {"A": 0, "B": 0}
	phase_start_tick = 0
	next_phase_tick = BUILD_PHASE_TICKS

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
	if auto_source_enabled and not match_over:
		for offset in ENEMY_BUY_OFFSETS:
			if tick == phase_start_tick + offset:
				_apply_command({"tick": tick, "player_id": "B", "action": "BUY_UNIT", "params": {}})
		if tick >= next_phase_tick:
			for side in SIDES:
				_apply_command({"tick": tick, "player_id": side, "action": "PAY_INCOME", "params": {}})
			for side in SIDES:
				_apply_command({"tick": tick, "player_id": side, "action": "SPAWN_WAVE", "params": {}})
			phase_start_tick = tick
			next_phase_tick = tick + BUILD_PHASE_TICKS
	if not match_over:
		_simulate_units()
		_resolve_base_damage()
		_check_win()
	tick += 1

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
			_do_buy_unit(cmd["player_id"])
		"PAY_INCOME":
			_do_pay_income(cmd["player_id"])
		_:
			_emit_event("unknown_command", {"action": cmd.get("action", "")})

func _do_buy_unit(side: String) -> void:
	if minerals[side] >= UNIT_COST:
		minerals[side] -= UNIT_COST
		total_spent[side] += UNIT_COST
		queued_units[side] += 1
		_emit_event("unit_purchased", {"side": side, "cost": UNIT_COST, "minerals_remaining": minerals[side], "total_spent": total_spent[side], "queued_units": queued_units[side]})
	else:
		_emit_event("buy_rejected", {"side": side, "reason": "insufficient_minerals", "minerals": minerals[side], "cost": UNIT_COST})

func _do_pay_income(side: String) -> void:
	var amount: float = BASE_INCOME + floor(total_spent[side] * INCOME_RATE)
	minerals[side] += amount
	_emit_event("income_paid", {"side": side, "amount": amount, "total_spent": total_spent[side], "new_minerals": minerals[side]})

func _do_spawn_wave(side: String) -> void:
	wave_count[side] += 1
	var count: int = queued_units[side]
	var ids: Array = []
	var start_pos: float = 0.0 if side == "A" else LANE_LENGTH
	var dir: float = 1.0 if side == "A" else -1.0
	for i in range(count):
		var id := next_unit_id
		units[id] = {
			"id": id,
			"side": side,
			"pos": start_pos - dir * (i * 0.5),
			"hp": UNIT_HP,
			"max_hp": UNIT_HP,
			"state": "marching",
			"target_id": -1,
			"cooldown": 0,
		}
		ids.append(id)
		next_unit_id += 1
	queued_units[side] = 0
	_emit_event("wave_spawned", {"side": side, "wave_number": wave_count[side], "unit_ids": ids, "purchased_count": count})

func _do_restart() -> void:
	base_hp = {"A": BASE_HP, "B": BASE_HP}
	units = {}
	wave_count = {"A": 0, "B": 0}
	match_over = false
	winner = ""
	first_contact_fired = false
	minerals = {"A": STARTING_MINERALS, "B": STARTING_MINERALS}
	total_spent = {"A": 0.0, "B": 0.0}
	queued_units = {"A": 0, "B": 0}
	phase_start_tick = tick
	next_phase_tick = tick + BUILD_PHASE_TICKS
	_emit_event("match_restarted", {})

func _simulate_units() -> void:
	var ids: Array = units.keys()
	ids.sort()
	for id in ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		if u["state"] == "marching":
			var enemy_id := _find_engageable_enemy(u)
			if enemy_id != -1:
				u["state"] = "fighting"
				u["target_id"] = enemy_id
				var other: Dictionary = units[enemy_id]
				if other["state"] == "marching":
					other["state"] = "fighting"
					other["target_id"] = id
				if not first_contact_fired:
					first_contact_fired = true
					_emit_event("first_contact", {"unit_a": id, "unit_b": enemy_id})
			else:
				var dir: float = 1.0 if u["side"] == "A" else -1.0
				u["pos"] += dir * UNIT_SPEED_PER_TICK
		elif u["state"] == "fighting":
			if u["cooldown"] > 0:
				u["cooldown"] -= 1
			else:
				var target_id: int = u["target_id"]
				if units.has(target_id):
					var target: Dictionary = units[target_id]
					target["hp"] -= UNIT_DAMAGE
					u["cooldown"] = UNIT_ATTACK_COOLDOWN_TICKS
					if target["hp"] <= 0.0:
						_emit_event("unit_death", {"unit_id": target_id, "side": target["side"], "killer_id": id})
						units.erase(target_id)
						u["state"] = "marching"
						u["target_id"] = -1
				else:
					u["state"] = "marching"
					u["target_id"] = -1

func _find_engageable_enemy(u: Dictionary) -> int:
	var ids: Array = units.keys()
	ids.sort()
	for id in ids:
		var other: Dictionary = units[id]
		if other["side"] != u["side"] and absf(other["pos"] - u["pos"]) <= UNIT_ATTACK_RANGE:
			return id
	return -1

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
		elif u["side"] == "B" and u["pos"] <= 0.0:
			_deal_base_damage("A", id)
			units.erase(id)

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
		"queued_units": queued_units.duplicate(true),
		"ticks_until_next_wave": next_phase_tick - tick,
		"build_phase_ticks": BUILD_PHASE_TICKS,
	}

func get_event_log() -> Array:
	return event_log.duplicate(true)

func get_command_log() -> Array:
	return command_log.duplicate(true)
