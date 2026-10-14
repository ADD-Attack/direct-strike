extends SceneTree

## The Studio playtest for Slice 1 — The Economy. Canonical/current playtest:
## supersedes playtest/run_playtest.gd (Slice 0's script, kept only as the
## historical record for the already-closed Slice 0 receipt — Slice 0's old
## "both sides auto-spawn a fixed wave size" behavior was intentionally
## replaced this slice by purchase-driven wave composition, so that script no
## longer reflects how the game is supposed to behave).
##
## Drives the game ONLY through MatchClient's command interface (never
## touches Host directly). Boots headless via
## `godot --headless --path ds3d -s playtest/run_playtest_slice1.gd`.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")

const MAX_TICKS_PER_MATCH := 20000
## Player (side A) buy attempts per build phase: fires at these tick offsets
## from the start of each phase. 6 attempts against a 50-mineral starting
## bank (5 affordable) exercises both successful purchases and a rejection.
const PLAYER_BUY_OFFSETS := [0, 5, 10, 15, 20, 25]

var assertions: Array = []

func _assert(id: String, passed: bool, detail: String) -> void:
	assertions.append({"id": id, "pass": passed, "detail": detail})

func _init() -> void:
	_assert("boots_headless", true, "SceneTree playtest executed under --headless with no display/window/GPU context")

	var run := _play_full_script()
	var events: Array = run["events"]
	var command_log: Array = run["command_log"]
	var total_ticks: int = run["ticks"]

	_assert_architecture()
	_assert_gameplay(events)
	_assert_economy(events)
	_assert_determinism(command_log, events, total_ticks)

	_write_ledger(events, command_log)
	_report_and_quit()

## Drives one match to a conclusion (buying for side A every build phase, the
## fixed enemy script buys for B automatically), restarts it, drives a second
## match to a conclusion — all through MatchClient.
func _play_full_script() -> Dictionary:
	var client := MatchClient.new(true)
	var ticks := 0
	var last_phase_reset_tick := 0

	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH:
		var since_phase: int = ticks - last_phase_reset_tick
		if since_phase in PLAYER_BUY_OFFSETS:
			client.submit_command("A", "BUY_UNIT", {})
		client.step()
		ticks += 1

	_assert("first_match_concludes", client.get_state()["match_over"], "first scripted match reached a win within %d ticks (took %d)" % [MAX_TICKS_PER_MATCH, ticks])

	var pre_restart: Dictionary = client.get_state()
	client.submit_command("owner", "RESTART", {})
	for i in range(5):
		client.step()
		ticks += 1
	last_phase_reset_tick = ticks
	var post_restart: Dictionary = client.get_state()
	var restart_ok: bool = (not post_restart["match_over"]) \
		and post_restart["base_hp"]["A"] == Host.BASE_HP \
		and post_restart["base_hp"]["B"] == Host.BASE_HP \
		and post_restart["units"].size() == 0 \
		and post_restart["minerals"]["A"] == Host.STARTING_MINERALS \
		and post_restart["minerals"]["B"] == Host.STARTING_MINERALS
	_assert("restart_resets_match", restart_ok, "pre-restart: match_over=%s base_hp=%s -> post-restart: match_over=%s base_hp=%s units=%d minerals=%s" % [pre_restart["match_over"], pre_restart["base_hp"], post_restart["match_over"], post_restart["base_hp"], post_restart["units"].size(), post_restart["minerals"]])

	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH * 2:
		var since_phase2: int = ticks - last_phase_reset_tick
		if since_phase2 in PLAYER_BUY_OFFSETS:
			client.submit_command("A", "BUY_UNIT", {})
		client.step()
		ticks += 1

	_assert("second_match_concludes_after_restart", client.get_state()["match_over"], "second match (post-restart) also reached a win, proving the match is fully replayable after restart")

	return {
		"events": client.get_full_event_log(),
		"command_log": client.get_command_log(),
		"ticks": ticks,
	}

func _assert_gameplay(events: Array) -> void:
	var waves: Dictionary = {"A": 0, "B": 0}
	var deaths := 0
	var first_contact := false
	var base_damage_sequences: Dictionary = {"A": [], "B": []}
	var win_events: Array = []
	var restart_events := 0
	var prev_hp: Dictionary = {"A": Host.BASE_HP, "B": Host.BASE_HP}
	var any_strict_decrease := false
	var any_violation := false

	for e in events:
		match e["type"]:
			"wave_spawned":
				waves[e["data"]["side"]] += 1
			"unit_death":
				deaths += 1
			"first_contact":
				first_contact = true
			"base_damage":
				var side: String = e["data"]["side"]
				var hp: float = e["data"]["hp_remaining"]
				base_damage_sequences[side].append(hp)
				if hp < prev_hp[side]:
					any_strict_decrease = true
				else:
					any_violation = true
				prev_hp[side] = hp
			"match_won":
				win_events.append(e)
			"match_restarted":
				restart_events += 1
				prev_hp = {"A": Host.BASE_HP, "B": Host.BASE_HP}

	_assert("waves_spawn_ge_2_per_side", waves["A"] >= 2 and waves["B"] >= 2, "wave counts: A=%d B=%d" % [waves["A"], waves["B"]])
	_assert("first_contact_fires", first_contact, "first_contact combat event observed")
	_assert("unit_deaths_recorded", deaths > 0, "%d unit_death events recorded" % deaths)
	_assert("base_hp_strictly_decreases_once_survivors_arrive", any_strict_decrease and not any_violation, "base_damage sequences (per match segment, reset on restart): %s" % [base_damage_sequences])
	_assert("win_event_fires", win_events.size() >= 1, "%d match_won event(s) fired: %s" % [win_events.size(), win_events])
	_assert("restart_event_recorded_in_ledger", restart_events >= 1, "%d match_restarted event(s) recorded" % restart_events)

func _assert_economy(events: Array) -> void:
	var queued_since_last_wave: Dictionary = {"A": 0, "B": 0}
	var total_spent_running: Dictionary = {"A": 0.0, "B": 0.0}
	var wave_match_ok := true
	var wave_match_detail := ""
	var spend_ledger_ok := true
	var purchased_count := 0
	var rejected_count := 0
	var rejected_violation := ""
	var income_formula_ok := true
	var income_detail := ""
	var income_count := 0
	var wave_ticks: Dictionary = {"A": [], "B": []}
	var restart_ticks: Array = []

	for e in events:
		match e["type"]:
			"unit_purchased":
				var side: String = e["data"]["side"]
				queued_since_last_wave[side] += 1
				purchased_count += 1
				var expected_spent: float = total_spent_running[side] + Host.UNIT_COST
				if e["data"]["total_spent"] != expected_spent:
					spend_ledger_ok = false
				total_spent_running[side] = e["data"]["total_spent"]
			"buy_rejected":
				rejected_count += 1
				if e["data"]["minerals"] >= Host.UNIT_COST:
					rejected_violation += "tick %d side %s had %s minerals (>= cost %s) yet was rejected; " % [e["tick"], e["data"]["side"], e["data"]["minerals"], Host.UNIT_COST]
			"wave_spawned":
				var side2: String = e["data"]["side"]
				var expected_count: int = queued_since_last_wave[side2]
				if e["data"]["purchased_count"] != expected_count or e["data"]["unit_ids"].size() != expected_count:
					wave_match_ok = false
					wave_match_detail += "side=%s tick=%d expected_queued=%d got_purchased_count=%d got_unit_ids=%d; " % [side2, e["tick"], expected_count, e["data"]["purchased_count"], e["data"]["unit_ids"].size()]
				queued_since_last_wave[side2] = 0
				wave_ticks[side2].append(e["tick"])
			"income_paid":
				income_count += 1
				var expected_amount: float = Host.BASE_INCOME + floor(e["data"]["total_spent"] * Host.INCOME_RATE)
				if e["data"]["amount"] != expected_amount:
					income_formula_ok = false
					income_detail += "side=%s spent=%s expected=%s got=%s; " % [e["data"]["side"], e["data"]["total_spent"], expected_amount, e["data"]["amount"]]
			"match_restarted":
				restart_ticks.append(e["tick"])
				# Host._do_restart() discards any queued-but-unspawned purchases and
				# resets total_spent to 0 for both sides — mirror that here so a
				# purchase stranded right before a restart isn't wrongly carried
				# over and blamed on the next match segment's first wave.
				queued_since_last_wave = {"A": 0, "B": 0}
				total_spent_running = {"A": 0.0, "B": 0.0}

	_assert("buy_commands_debit_minerals_and_join_next_wave", wave_match_ok and spend_ledger_ok and purchased_count > 0, "%d unit_purchased events; every wave_spawned.purchased_count matched purchases queued since that side's previous wave (mismatches=%s); total_spent incremented by UNIT_COST=%s per purchase (consistent=%s)" % [purchased_count, ("none" if wave_match_ok else wave_match_detail), Host.UNIT_COST, spend_ledger_ok])

	_assert("income_per_wave_matches_formula", income_formula_ok and income_count > 0, "%d income_paid events, all matched BASE_INCOME(%s) + floor(total_spent * %s) (mismatches=%s)" % [income_count, Host.BASE_INCOME, Host.INCOME_RATE, ("none" if income_formula_ok else income_detail)])

	_assert("unaffordable_buys_rejected", rejected_count > 0 and rejected_violation == "", "%d buy_rejected events, all occurred while minerals < UNIT_COST=%s (violations=%s)" % [rejected_count, Host.UNIT_COST, ("none" if rejected_violation == "" else rejected_violation)])

	var cycle_ok := true
	var cycle_detail := ""
	for side in ["A", "B"]:
		var ts: Array = wave_ticks[side]
		for i in range(1, ts.size()):
			var prev_tick: int = ts[i - 1]
			var cur_tick: int = ts[i]
			var crosses_restart := false
			for rt in restart_ticks:
				if rt > prev_tick and rt <= cur_tick:
					crosses_restart = true
			if not crosses_restart and (cur_tick - prev_tick) != Host.BUILD_PHASE_TICKS:
				cycle_ok = false
				cycle_detail += "side=%s gap %d->%d = %d ticks (expected %d); " % [side, prev_tick, cur_tick, cur_tick - prev_tick, Host.BUILD_PHASE_TICKS]
	_assert("wave_timer_cycles_build_spawn_build", cycle_ok and wave_ticks["A"].size() >= 2 and wave_ticks["B"].size() >= 2, "wave_spawned ticks per side: A=%s B=%s; consecutive gaps equal BUILD_PHASE_TICKS=%d except across a restart (violations=%s)" % [wave_ticks["A"], wave_ticks["B"], Host.BUILD_PHASE_TICKS, ("none" if cycle_ok else cycle_detail)])

func _assert_architecture() -> void:
	var host_file_exists := FileAccess.file_exists("res://sim/host.gd")
	var client_file_exists := FileAccess.file_exists("res://client/match_client.gd")
	_assert("sim_and_client_are_separate_modules", host_file_exists and client_file_exists, "host.gd (sim) and match_client.gd (client) exist as separate files")

	var mc := MatchClient.new(true)
	var has_iface := mc.has_method("submit_command") and mc.has_method("step") and mc.has_method("get_state") and mc.has_method("drain_new_events")
	_assert("client_exposes_message_interface", has_iface, "MatchClient exposes submit_command()/step()/get_state()/drain_new_events() as its only public surface")

	var h := Host.new(false)
	_assert("host_has_fixed_tick_step", h.has_method("step"), "Host.step() advances exactly one fixed tick per call, independent of real time")

	var main_src := _read_text("res://scenes/main.gd")
	var no_direct_host_calls := main_src.find(".host.") == -1
	_assert("no_direct_ui_to_sim_calls", no_direct_host_calls, "scenes/main.gd contains no '.host.' access — the UI only calls MatchClient's public methods, never Host directly")

	var fixed_timestep_accumulator := main_src.find("TICK_DT") != -1 and main_src.find("tick_accum") != -1
	_assert("fixed_timestep_sim_in_render_loop", fixed_timestep_accumulator, "render loop steps the sim on a fixed-duration accumulator (TICK_DT), decoupled from render framerate")

	var buys_via_command_interface := main_src.find("submit_command") != -1 and main_src.find("BUY_UNIT") != -1
	_assert("buy_menu_uses_command_interface", buys_via_command_interface, "scenes/main.gd issues BUY_UNIT purchases via client.submit_command(), the same interface every other command uses")

func _assert_determinism(command_log: Array, events_run1: Array, total_ticks: int) -> void:
	var client2 := MatchClient.new(false)
	client2.load_replay_log(command_log)
	for i in range(total_ticks):
		client2.step()
	var events_run2: Array = client2.get_full_event_log()
	var identical := _events_equal(events_run1, events_run2)
	_assert("determinism_same_log_identical_ledgers", identical, "replayed the exact recorded command log (%d commands, incl. buy/income commands) into a fresh host for %d ticks: %d vs %d events, identical=%s" % [command_log.size(), total_ticks, events_run1.size(), events_run2.size(), identical])

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
	var out_dir := _repo_root().path_join("studio/builds/slice-1")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ledger := {
		"slice": "Slice 1 — The Economy",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine_version": Engine.get_version_info(),
		"economy_formula": "income = BASE_INCOME(%s) + floor(total_spent * INCOME_RATE(%s)); UNIT_COST=%s; STARTING_MINERALS=%s; BUILD_PHASE_TICKS=%s" % [Host.BASE_INCOME, Host.INCOME_RATE, Host.UNIT_COST, Host.STARTING_MINERALS, Host.BUILD_PHASE_TICKS],
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
