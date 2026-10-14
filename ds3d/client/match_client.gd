class_name MatchClient
extends RefCounted

## The ONLY thing UI/render code is allowed to talk to. Wraps a Host over a
## message interface (commands in, state/events out) so that swapping this
## local loopback for a real network transport later touches nothing upstream.

const Host = preload("res://sim/host.gd")

var host: Host
var _event_cursor: int = 0

func _init(auto_source: bool = true) -> void:
	host = Host.new(auto_source)

func load_replay_log(log: Array) -> void:
	host.load_replay_log(log)
	_event_cursor = 0

## Commands in. player_id identifies the command source (a human, an AI, or
## in Slice 0 a side's auto-scheduler); the sim is agnostic to which.
func submit_command(player_id: String, action: String, params: Dictionary = {}) -> void:
	host.submit_command({"tick": host.tick, "player_id": player_id, "action": action, "params": params})

func step() -> void:
	host.step()

## State out: a read-only snapshot, never an internal reference.
func get_state() -> Dictionary:
	return host.get_state()

## Events out: only the events since the last drain (for render/VFX code).
func drain_new_events() -> Array:
	var full: Array = host.event_log
	var out: Array = []
	for i in range(_event_cursor, full.size()):
		out.append(full[i])
	_event_cursor = full.size()
	return out

## The full ledger (for playtest / replay comparison), independent of drain state.
func get_full_event_log() -> Array:
	return host.get_event_log()

func get_command_log() -> Array:
	return host.get_command_log()
