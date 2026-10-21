class_name ScriptedBuyer
extends RefCounted

## Deterministic scripted command source for side A: the same buying
## pattern the Slice 3 playtest drove through MatchClient, expressed as a
## pure function of the public state snapshot (its tick only), so it can
## sit behind a NetClient exactly like the AI buyer sits behind client B.

const Host = preload("res://sim/host.gd")
const ROLES := ["frontline_tank", "line_dps", "ranged", "line_dps", "frontline_tank", "ranged"]

var variant: int = 0

func _init(p_variant: int = 0) -> void:
	variant = p_variant

func decide(state: Dictionary) -> Array:
	var out: Array = []
	if state["match_over"]:
		return out
	var tick: int = state["tick"]
	var phase: int = tick % Host.BUILD_PHASE_TICKS
	if phase % 80 == 0 and phase < 560:
		out.append({"tick": tick, "player_id": "A", "action": "BUY_UNIT", "params": {"role": ROLES[(tick / 80 + variant) % ROLES.size()]}})
	if phase == 180:
		out.append({"tick": tick, "player_id": "A", "action": "BUY_GAS", "params": {}})
	return out
