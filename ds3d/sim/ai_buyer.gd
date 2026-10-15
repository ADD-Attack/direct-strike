class_name AIBuyer
extends RefCounted

## Slice 3 AI command source. It observes only MatchClient's read-only state
## snapshot, then returns ordinary BUY_UNIT / BUY_GAS / PLACE_UNIT commands.
## It never holds a Host reference or mutates simulation state.

const Host = preload("res://sim/host.gd")

const TUNING := {
	"easy": {"cadence": 150, "gas_phase": -1, "seed": 101, "counter": false, "middle": false},
	"normal": {"cadence": 75, "gas_phase": 550, "seed": 202, "counter": true, "middle": false},
	"hard": {"cadence": 45, "gas_phase": 585, "seed": 303, "counter": true, "middle": true},
}
const COUNTER := {"frontline_tank": "ranged", "line_dps": "splash", "ranged": "frontline_tank", "splash": "siege", "fast_flanker": "line_dps", "siege": "fast_flanker"}

var difficulty := "normal"
var rng_state := 202
var last_gas_phase := -1

func _init(level: String = "normal") -> void:
	set_difficulty(level)

func set_difficulty(level: String) -> void:
	difficulty = level if TUNING.has(level) else "normal"
	rng_state = TUNING[difficulty]["seed"]
	last_gas_phase = -1

func decide(state: Dictionary) -> Array:
	var out: Array = []
	var tuning: Dictionary = TUNING[difficulty]
	var tick: int = state["tick"]
	var phase_tick: int = tick % Host.BUILD_PHASE_TICKS
	if tuning["gas_phase"] >= 0 and phase_tick == tuning["gas_phase"] and last_gas_phase != tick / Host.BUILD_PHASE_TICKS:
		last_gas_phase = tick / Host.BUILD_PHASE_TICKS
		if state["gas_count"]["B"] < Host.MAX_GASES and state["minerals"]["B"] >= Host.GAS_COSTS[state["gas_count"]["B"]]:
			out.append(_command(tick, "BUY_GAS", {"ai_seed": rng_state, "difficulty": difficulty}))
	# Hard reserves late-phase minerals for its deliberate first gas rather
	# than spending every last tick of income on units.
	var reserve_from := 300 if difficulty == "normal" else 180
	if difficulty != "easy" and state["gas_count"]["B"] == 0 and phase_tick >= reserve_from and phase_tick < tuning["gas_phase"]:
		return out
	if phase_tick <= 0 or phase_tick % tuning["cadence"] != 0:
		return out
	var role := _choose_role(state, tuning)
	var spec: Dictionary = Host.ROLE_STATS[role]
	if spec["tier"] == 2 and state["total_spent"]["B"] < Host.TIER2_UNLOCK_THRESHOLD:
		role = "line_dps"
		spec = Host.ROLE_STATS[role]
	if state["minerals"]["B"] < spec["cost"]:
		return out
	var idx: int = state["queued_units"]["B"]
	var row := 1
	if tuning["middle"]:
		row = 0 if state["middle_controller"] == "A" else 1
	out.append(_command(tick, "BUY_UNIT", {"role": role, "ai_seed": rng_state, "difficulty": difficulty}))
	out.append(_command(tick, "PLACE_UNIT", {"queue_index": idx, "row": row, "ai_seed": rng_state, "difficulty": difficulty}))
	return out

func _choose_role(state: Dictionary, tuning: Dictionary) -> String:
	var roles: Dictionary = {}
	for id in state["units"]:
		var u: Dictionary = state["units"][id]
		if u["side"] == "A":
			roles[u["role"]] = int(roles.get(u["role"], 0)) + 1
	var most := "line_dps"
	var count := -1
	for role in Host.ROLE_ORDER:
		if int(roles.get(role, 0)) > count:
			most = role
			count = int(roles.get(role, 0))
	if tuning["counter"] and count > 0:
		return COUNTER[most]
	return Host.ROLE_ORDER[_next_random() % 3] # Easy and opening buys remain tier-1, near-random.

func _next_random() -> int:
	rng_state = int((rng_state * 1103515245 + 12345) & 0x7fffffff)
	return rng_state

func _command(tick: int, action: String, params: Dictionary) -> Dictionary:
	return {"tick": tick, "player_id": "B", "action": action, "params": params}
