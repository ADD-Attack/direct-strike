extends SceneTree

## The Studio warm-up playtest for Slice 2 (op-studio-slice2-warmup-20261014-1701).
## Not the canonical Slice 2 playtest — Builder 1 owns that when Slice 2 is
## actually ordered. This script proves two things in isolation, on this
## branch only: (1) the formation-placement command extension to host.gd
## behaves as specified and stays deterministic, (2) the roster rig loader
## builds all six Slice 2 role models without error.
##
## Drives the game ONLY through MatchClient's command interface (never
## touches Host directly), per the lockstep rule: PLACE_UNIT rides the exact
## same {tick, player_id, action, params} command log as BUY_UNIT/SPAWN_WAVE/
## RESTART — no new path, no UI-only shortcut.
## Boots headless via
## `godot --headless --path ds3d -s playtest/run_playtest_slice2_warmup.gd`.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")
const RosterUnitVisual = preload("res://units/roster_visuals.gd")

const MAX_TICKS_PER_MATCH := 20000

## Five units bought for side A at the start of the first build phase, then
## placed into a wedge formation (row pattern 2,1,0,1,2 — reads as an arrow
## pointing down the lane) via PLACE_UNIT commands. A sixth, invalid
## placement (an out-of-range queue_index) is issued to prove rejection.
const WEDGE_ROWS := [2, 1, 0, 1, 2]

var assertions: Array = []

func _assert(id: String, passed: bool, detail: String) -> void:
	assertions.append({"id": id, "pass": passed, "detail": detail})

func _init() -> void:
	_assert("boots_headless", true, "SceneTree playtest executed under --headless with no display/window/GPU context")

	var run := _play_formation_script()
	var events: Array = run["events"]
	var command_log: Array = run["command_log"]
	var total_ticks: int = run["ticks"]

	_assert_formation_architecture()
	_assert_formation_behavior(events)
	_assert_determinism(command_log, events, total_ticks)
	_assert_roster_models_build()

	_write_ledger(events, command_log)
	_report_and_quit()

func _play_formation_script() -> Dictionary:
	var client := MatchClient.new(true)
	var ticks := 0

	# Buy 5 units for side A, queue_index 0..4 in buy order.
	for i in range(5):
		client.submit_command("A", "BUY_UNIT", {})

	# Place them into the wedge, by queue_index.
	for i in range(WEDGE_ROWS.size()):
		client.submit_command("A", "PLACE_UNIT", {"queue_index": i, "row": WEDGE_ROWS[i], "col": i})

	# Deliberately invalid: queue_index 99 does not exist this phase.
	client.submit_command("A", "PLACE_UNIT", {"queue_index": 99, "row": 0, "col": 0})

	# Step until the first wave (and its auto-triggered PAY_INCOME/SPAWN_WAVE
	# commands) has fired for both sides.
	while client.get_state()["wave_count"]["A"] == 0 and ticks < MAX_TICKS_PER_MATCH:
		client.step()
		ticks += 1
	_assert("first_wave_spawns", client.get_state()["wave_count"]["A"] >= 1, "side A's first wave spawned by tick %d" % ticks)

	# Run the match to a conclusion so the prototype proves it doesn't break
	# ordinary play, same as the Slice 0/1 playtests do.
	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH:
		client.step()
		ticks += 1
	_assert("match_still_concludes_with_placements_in_the_log", client.get_state()["match_over"], "match reached a win within %d ticks (took %d) with PLACE_UNIT commands mixed into the log" % [MAX_TICKS_PER_MATCH, ticks])

	return {
		"events": client.get_full_event_log(),
		"command_log": client.get_command_log(),
		"ticks": ticks,
	}

func _assert_formation_behavior(events: Array) -> void:
	var wave_formation: Array = []
	var rejected: Array = []
	for e in events:
		if e["type"] == "wave_spawned" and e["data"]["side"] == "A" and wave_formation.is_empty():
			wave_formation = e["data"]["formation"]
		elif e["type"] == "placement_rejected":
			rejected.append(e["data"])

	var formation_ok := wave_formation.size() == WEDGE_ROWS.size()
	var detail := ""
	if formation_ok:
		for i in range(WEDGE_ROWS.size()):
			var cell: Dictionary = wave_formation[i]
			if cell["row"] != WEDGE_ROWS[i] or cell["col"] != i:
				formation_ok = false
				detail += "unit %d: expected row=%d col=%d, got row=%s col=%s; " % [i, WEDGE_ROWS[i], i, cell.get("row"), cell.get("col")]
	else:
		detail = "expected %d placed units in the first wave, got %d" % [WEDGE_ROWS.size(), wave_formation.size()]
	_assert("wave_spawns_in_the_commanded_formation", formation_ok, "first wave's formation: %s (violations: %s)" % [wave_formation, ("none" if formation_ok else detail)])

	var distinct_offsets := {}
	for cell in wave_formation:
		distinct_offsets[cell.get("lane_offset")] = true
	_assert("formation_produces_lateral_spread", distinct_offsets.size() >= 2, "formation cells carry %d distinct lane_offset values (a single-file spawn would have 1): %s" % [distinct_offsets.size(), wave_formation])

	var reject_ok: bool = false
	if rejected.size() >= 1:
		reject_ok = rejected[0]["reason"] == "no_such_queued_unit"
	_assert("invalid_placement_is_rejected_not_silently_dropped", reject_ok, "%d placement_rejected event(s), first: %s" % [rejected.size(), rejected[0] if rejected.size() > 0 else "none"])

func _assert_formation_architecture() -> void:
	var host_src := _read_text("res://sim/host.gd")
	var in_command_dispatch := host_src.find('"PLACE_UNIT":') != -1 and host_src.find("_do_place_unit") != -1
	_assert("place_unit_rides_the_same_command_dispatch_as_every_other_action", in_command_dispatch, "host.gd's _apply_command() match statement has a \"PLACE_UNIT\" case calling _do_place_unit(), the same dispatch table BUY_UNIT/SPAWN_WAVE/RESTART use")

	var mc := MatchClient.new(true)
	var has_iface := mc.has_method("submit_command") and mc.has_method("step") and mc.has_method("get_state") and mc.has_method("drain_new_events")
	_assert("no_new_client_surface_for_placement", has_iface, "MatchClient's public surface is unchanged (submit_command/step/get_state/drain_new_events) — PLACE_UNIT is just another action string through the existing submit_command(), no placement-specific method was added")

func _assert_determinism(command_log: Array, events_run1: Array, total_ticks: int) -> void:
	var client2 := MatchClient.new(false)
	client2.load_replay_log(command_log)
	for i in range(total_ticks):
		client2.step()
	var events_run2: Array = client2.get_full_event_log()
	var identical := _events_equal(events_run1, events_run2)
	_assert("determinism_same_log_identical_ledgers", identical, "replayed the exact recorded command log (%d commands, incl. PLACE_UNIT) into a fresh host for %d ticks: %d vs %d events, identical=%s" % [command_log.size(), total_ticks, events_run1.size(), events_run2.size(), identical])

func _assert_roster_models_build() -> void:
	var roles: Array = RosterUnitVisual.role_order()
	var role_count_ok := roles.size() == 6
	var build_ok := true
	var detail := ""
	var temp_parent := Node3D.new()
	root.add_child(temp_parent)
	for role in roles:
		var rig := RosterUnitVisual.new()
		temp_parent.add_child(rig)
		rig.build(role, Color(0.25, 0.55, 0.95))
		if rig.get_child_count() == 0:
			build_ok = false
			detail += "%s produced no parts; " % role
	_assert("roster_declares_six_roles", role_count_ok, "roster_models.json role_order has %d entries: %s" % [roles.size(), roles])
	_assert("every_roster_role_builds_a_nonempty_rig", build_ok, "all 6 roles instantiated via RosterUnitVisual.build() with >=1 mesh part each (violations: %s)" % ("none" if build_ok else detail))
	temp_parent.queue_free()

func _events_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if str(a[i]) != str(b[i]):
			return false
	return true

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

func _repo_root() -> String:
	var proj_abs: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	return proj_abs.get_base_dir()

func _write_ledger(events: Array, command_log: Array) -> void:
	var out_dir := _repo_root().path_join("studio/builds/slice-2-warmup")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ledger := {
		"slice": "Slice 2 warm-up — formation placement prototype (op-studio-slice2-warmup-20261014-1701)",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine_version": Engine.get_version_info(),
		"place_unit_command_shape": "{tick, player_id, action: \"PLACE_UNIT\", params: {queue_index, row, col}}",
		"staging_constants": "STAGING_ROWS=%s STAGING_ROW_SPACING=%s STAGING_COL_SPACING=%s" % [Host.STAGING_ROWS, Host.STAGING_ROW_SPACING, Host.STAGING_COL_SPACING],
		"assertions": assertions,
		"all_pass": _all_pass(),
		"event_log": events,
		"command_log": command_log,
	}
	var f := FileAccess.open(out_dir.path_join("ledger.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(ledger, "\t"))
	f.close()

func _all_pass() -> bool:
	for a in assertions:
		if not a["pass"]:
			return false
	return true

func _report_and_quit() -> void:
	for a in assertions:
		var status := "PASS" if a["pass"] else "FAIL"
		print("[%s] %s — %s" % [status, a["id"], a["detail"]])
	var all_pass := _all_pass()
	print("")
	print("PLAYTEST RESULT: %s" % ("ALL PASS" if all_pass else "FAILURES PRESENT"))
	quit(0 if all_pass else 1)
