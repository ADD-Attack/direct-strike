extends SceneTree

## Bounded SELL_UNIT command playtest. Drives the simulation only through
## MatchClient's existing command interface and records a JSON evidence ledger.
## Run with:
## `godot --headless --path ds3d -s playtest/run_playtest_sell_unit.gd`.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")

var assertions: Array = []

func _assert(id: String, passed: bool, detail: String) -> void:
	assertions.append({"id": id, "pass": passed, "detail": detail})

func _init() -> void:
	_assert("boots_headless", true, "SceneTree playtest executed under --headless")

	var run := _run_sell_script()
	var events: Array = run["events"]
	var command_log: Array = run["command_log"]

	_assert_architecture(command_log)
	_assert_sell_behavior(events, run["state"])
	_assert_determinism(command_log, events, run["ticks"])

	_write_ledger(events, command_log, run["state"])
	_report_and_quit()

func _run_sell_script() -> Dictionary:
	var client := MatchClient.new(false)

	# The order is intentional: queue two units, place the second, remove the
	# first, reject an invalid index, spawn, then prove the now-deployed index
	# can no longer be sold. Every action is stamped tick 0 and consumed by the
	# same dispatch pass, which makes every intermediate mineral value visible
	# in the event ledger before the tick's normal income accrual.
	client.submit_command("A", "BUY_UNIT", {"role": "ranged"})
	client.submit_command("A", "BUY_UNIT", {"role": "frontline_tank"})
	client.submit_command("A", "PLACE_UNIT", {"queue_index": 1, "row": 2, "col": 4})
	client.submit_command("A", "SELL_UNIT", {"queue_index": 0})
	client.submit_command("A", "SELL_UNIT", {"queue_index": 99})
	client.submit_command("A", "SPAWN_WAVE", {})
	client.submit_command("A", "SELL_UNIT", {"queue_index": 0})
	client.step()

	return {
		"events": client.get_full_event_log(),
		"command_log": client.get_command_log(),
		"state": client.get_state(),
		"ticks": 1,
	}

func _assert_architecture(command_log: Array) -> void:
	var host_src := _read_text("res://sim/host.gd")
	var dispatched := host_src.find('"SELL_UNIT":') != -1 and host_src.find("_do_sell_unit") != -1
	_assert("sell_unit_uses_existing_command_dispatch", dispatched, "host.gd routes SELL_UNIT through _apply_command(), alongside BUY_UNIT/BUY_GAS/PLACE_UNIT")

	var shape_ok := false
	for command in command_log:
		if command.get("action", "") == "SELL_UNIT" and command.get("params", {}).has("queue_index") and command.has("tick") and command.has("player_id"):
			shape_ok = true
			break
	_assert("sell_unit_command_shape_logged", shape_ok, "recorded command log contains {tick, player_id, action: SELL_UNIT, params: {queue_index}}")

	var client := MatchClient.new(false)
	var generic_interface := client.has_method("submit_command") and not client.has_method("sell_unit")
	_assert("no_sell_specific_client_path", generic_interface, "SELL_UNIT uses MatchClient.submit_command(); no sell-specific client method was added")

func _assert_sell_behavior(events: Array, state: Dictionary) -> void:
	var purchases: Array = []
	var sold: Array = []
	var rejected: Array = []
	var first_a_wave: Dictionary = {}
	for event in events:
		match event["type"]:
			"unit_purchased":
				if event["data"]["side"] == "A":
					purchases.append(event["data"])
			"unit_sold":
				sold.append(event["data"])
			"sell_rejected":
				rejected.append(event["data"])
			"wave_spawned":
				if event["data"]["side"] == "A" and first_a_wave.is_empty():
					first_a_wave = event["data"]

	var sold_purchase_cost: float = Host.ROLE_STATS["ranged"]["cost"]
	var refund_ok := sold.size() == 1 and purchases.size() == 2
	if refund_ok:
		refund_ok = sold[0]["role"] == "ranged" \
			and sold[0]["refund"] == sold_purchase_cost \
			and sold[0]["refund"] == purchases[0]["cost"] \
			and sold[0]["minerals_remaining"] == Host.STARTING_MINERALS - purchases[1]["cost"]
	var expected_after_tick: float = Host.STARTING_MINERALS - Host.ROLE_STATS["frontline_tank"]["cost"] + Host.BASE_TRICKLE_PER_SEC / float(Host.TICK_RATE)
	refund_ok = refund_ok and absf(state["minerals"]["A"] - expected_after_tick) < 0.0001
	_assert("sell_refunds_exact_purchase_cost", refund_ok, "ranged cost/refund=%s; minerals after retaining one %s-cost unit and one income tick: expected %.4f, actual %.4f" % [sold_purchase_cost, Host.ROLE_STATS["frontline_tank"]["cost"], expected_after_tick, state["minerals"]["A"]])

	var formation: Array = first_a_wave.get("formation", [])
	var sold_absent: bool = formation.size() == 1 and formation[0]["role"] == "frontline_tank"
	_assert("sold_unit_absent_from_next_wave", sold_absent, "first A wave contains exactly the retained frontline_tank and no sold ranged unit: %s" % [formation])

	var placement_shifted: bool = formation.size() == 1 and formation[0]["row"] == 2 and formation[0]["col"] == 4
	_assert("remaining_queue_placement_survives_index_shift", placement_shifted, "placement originally attached to queue_index 1 followed the retained unit to queue_index 0: %s" % [formation])

	var invalid_ok: bool = rejected.size() == 2 \
		and rejected[0]["queue_index"] == 99 \
		and rejected[0]["reason"] == "no_such_queued_unit" \
		and rejected[0]["queued_units"] == 1 \
		and rejected[0]["minerals"] == Host.STARTING_MINERALS - Host.ROLE_STATS["frontline_tank"]["cost"]
	_assert("invalid_queue_index_rejected_without_state_change", invalid_ok, "invalid index 99 left one queued unit and minerals unchanged; rejection=%s" % [rejected[0] if rejected.size() > 0 else "missing"])

	var deployed_ok: bool = rejected.size() == 2 \
		and rejected[1]["queue_index"] == 0 \
		and rejected[1]["reason"] == "no_such_queued_unit" \
		and rejected[1]["queued_units"] == 0 \
		and rejected[1]["minerals"] == Host.STARTING_MINERALS - Host.ROLE_STATS["frontline_tank"]["cost"] \
		and state["units"].size() == 1
	_assert("deployed_queue_index_rejected_without_refund", deployed_ok, "post-spawn index 0 found an empty queue, did not refund, and left the spawned unit present; rejection=%s" % [rejected[1] if rejected.size() > 1 else "missing"])

func _assert_determinism(command_log: Array, first_events: Array, total_ticks: int) -> void:
	var replay := MatchClient.new(false)
	replay.load_replay_log(command_log)
	for i in range(total_ticks):
		replay.step()
	var replay_events: Array = replay.get_full_event_log()
	var identical := _events_equal(first_events, replay_events)
	_assert("determinism_same_sell_log_identical_ledgers", identical, "replayed the exact %d-command log including SELL_UNIT into a fresh host for %d tick(s): %d vs %d events, identical=%s" % [command_log.size(), total_ticks, first_events.size(), replay_events.size(), identical])

func _events_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if str(a[i]) != str(b[i]):
			return false
	return true

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _repo_root() -> String:
	var project_abs: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	return project_abs.get_base_dir()

func _write_ledger(events: Array, command_log: Array, final_state: Dictionary) -> void:
	var out_dir := _repo_root().path_join("studio/builds/sell-unit")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ledger := {
		"task": "SELL_UNIT command",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine_version": Engine.get_version_info(),
		"command_shape": "{tick, player_id, action: SELL_UNIT, params: {queue_index}}",
		"assertions": assertions,
		"all_pass": _all_pass(),
		"final_state": final_state,
		"event_log": events,
		"command_log": command_log,
	}
	var file := FileAccess.open(out_dir.path_join("ledger.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(ledger, "\t"))
	file.close()

func _all_pass() -> bool:
	for assertion in assertions:
		if not assertion["pass"]:
			return false
	return true

func _report_and_quit() -> void:
	for assertion in assertions:
		var status := "PASS" if assertion["pass"] else "FAIL"
		print("[%s] %s — %s" % [status, assertion["id"], assertion["detail"]])
	var all_pass := _all_pass()
	print("")
	print("PLAYTEST RESULT: %s" % ("ALL PASS" if all_pass else "FAILURES PRESENT"))
	quit(0 if all_pass else 1)
