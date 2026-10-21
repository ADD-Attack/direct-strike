class_name NetClient
extends RefCounted

## One participant in a Slice 4 net session, bound to exactly one side.
## It NEVER touches the authoritative host. It holds a local replica Host
## (auto_source off) that is fed exclusively by the host's tick bundles —
## the same commands, in the same order, the host applied — so the replica
## is a lockstep copy, and its event log is this client's ledger.
##
## Commands out go only through the bus, and only for this client's own
## side (the match-level RESTART is the one exception, as in MatchClient).
## The public read API mirrors MatchClient (get_state / drain_new_events /
## get_command_log) so render code cannot tell the difference.

const Host = preload("res://sim/host.gd")

var bus # LoopbackBus or TcpBus (duck-typed endpoint)
var endpoint_id: String
var side: String
var replica: Host
var source = null # optional command source: decide(state) -> Array[cmd]
var welcomed: bool = false
var match_end_info: Dictionary = {}
var bundles_applied: int = 0
var last_bundle_tick: int = -1

var _event_cursor: int = 0
var _outbox: Array = [] # UI-queued commands, flushed at the next round

func _init(p_bus, p_endpoint_id: String, p_side: String, p_source = null) -> void:
	bus = p_bus
	endpoint_id = p_endpoint_id
	side = p_side
	source = p_source
	replica = Host.new(false)

func connect_to_host() -> void:
	bus.send("host", {"type": "hello", "side": side, "endpoint": endpoint_id})

func set_ai_difficulty(level: String) -> void:
	if source != null and source.has_method("set_difficulty"):
		source.set_difficulty(level)

## Commands in — mirrors MatchClient.submit_command(player_id, action,
## params), but stamped with the replica's tick and queued for the bus,
## not handed to any sim. Foreign-side commands are refused here, at the
## seam, so a client cannot drive the other side even by accident.
func submit_command(player_id: String, action: String, params: Dictionary = {}) -> void:
	if player_id != side and action != "RESTART":
		push_warning("NetClient(%s): refused command for foreign side %s" % [side, player_id])
		return
	_outbox.append({"tick": replica.tick, "player_id": player_id, "action": action, "params": params})

## Round phase 1: generate this round's source commands and flush the UI
## outbox to the host, then signal round_ready. The host steps only when
## both clients have signaled, so every participant's commands for a tick
## are in before that tick is simulated anywhere.
func begin_round(round_idx: int) -> void:
	if source != null and not replica.match_over:
		for cmd in source.decide(replica.get_state()):
			if String(cmd.get("player_id", "")) == side:
				bus.send("host", {"type": "command", "cmd": cmd})
	for cmd in _outbox:
		bus.send("host", {"type": "command", "cmd": cmd})
	_outbox.clear()
	bus.send("host", {"type": "round_ready", "round": round_idx, "endpoint": endpoint_id})

## Drain the bus and apply any tick bundles to the replica, in order.
## One bundle = one replica step: the replica only ever advances on the
## host's word. Returns how many bundles this call applied.
func poll() -> int:
	var applied := 0
	for item in bus.poll():
		var msg: Dictionary = item["msg"]
		match String(msg.get("type", "")):
			"welcome":
				welcomed = true
			"tick_bundle":
				_apply_bundle(msg)
				applied += 1
			"match_end":
				match_end_info = msg
	return applied

func _apply_bundle(msg: Dictionary) -> void:
	for cmd in msg["commands"]:
		replica.submit_command(cmd)
	replica.step()
	bundles_applied += 1
	last_bundle_tick = int(msg["tick"])

## --- MatchClient-compatible read API (state out, events out) ---

func get_state() -> Dictionary:
	return replica.get_state()

func drain_new_events() -> Array:
	var full: Array = replica.event_log
	var out: Array = []
	for i in range(_event_cursor, full.size()):
		out.append(full[i])
	_event_cursor = full.size()
	return out

func get_full_event_log() -> Array:
	return replica.get_event_log()

func get_command_log() -> Array:
	return replica.get_command_log()

func is_match_over() -> bool:
	return replica.match_over
