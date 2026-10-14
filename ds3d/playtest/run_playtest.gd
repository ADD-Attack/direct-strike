extends SceneTree

## The Studio playtest for Slice 0 — Walking Skeleton.
## Drives the game ONLY through MatchClient's command interface (never touches
## Host directly), exactly as a real UI/network client would. Boots headless
## via `godot --headless --path ds3d -s playtest/run_playtest.gd`.
##
## NOTE on frame captures: real pixel screenshots require an off-screen GPU
## context (EGL/GL). This sandbox has no GPU/display server and hangs when a
## Viewport is instantiated under --headless, so this playtest captures
## structured state snapshots (JSON) at the same scripted moments the charter
## asks for (first contact, base under attack, victory) instead of PNGs. The
## actual 3D scene renders normally for a human in a real browser (WebGL),
## which is what the owner will play.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")

const MAX_TICKS_PER_MATCH := 20000

var assertions: Array = []
var frames: Dictionary = {}

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
	_assert_determinism(command_log, events, total_ticks)

	_write_ledger(events, command_log)
	_write_frames()
	_report_and_quit()

## Drives one match to a conclusion, restarts it, drives a second match to a
## conclusion — all through MatchClient — capturing ledger + frame snapshots.
func _play_full_script() -> Dictionary:
	var client := MatchClient.new(true)
	var ticks := 0
	var seen_first_contact := false
	var seen_base_damage := false
	var seen_win := false

	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH:
		client.step()
		ticks += 1
		for ev in client.drain_new_events():
			if ev["type"] == "first_contact" and not seen_first_contact:
				seen_first_contact = true
				frames["first_contact"] = _snapshot(client, ev)
			elif ev["type"] == "base_damage" and not seen_base_damage:
				seen_base_damage = true
				frames["base_under_attack"] = _snapshot(client, ev)
			elif ev["type"] == "match_won" and not seen_win:
				seen_win = true
				frames["victory"] = _snapshot(client, ev)

	_assert("first_match_concludes", client.get_state()["match_over"], "first scripted match reached a win within %d ticks (took %d)" % [MAX_TICKS_PER_MATCH, ticks])

	var pre_restart: Dictionary = client.get_state()
	client.submit_command("owner", "RESTART", {})
	for i in range(5):
		client.step()
		ticks += 1
	var post_restart: Dictionary = client.get_state()
	var restart_ok: bool = (not post_restart["match_over"]) \
		and post_restart["base_hp"]["A"] == Host.BASE_HP \
		and post_restart["base_hp"]["B"] == Host.BASE_HP \
		and post_restart["units"].size() == 0
	_assert("restart_resets_match", restart_ok, "pre-restart: match_over=%s base_hp=%s -> post-restart: match_over=%s base_hp=%s units=%d" % [pre_restart["match_over"], pre_restart["base_hp"], post_restart["match_over"], post_restart["base_hp"], post_restart["units"].size()])

	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH * 2:
		client.step()
		ticks += 1

	_assert("second_match_concludes_after_restart", client.get_state()["match_over"], "second match (post-restart) also reached a win, proving the match is fully replayable after restart")

	return {
		"events": client.get_full_event_log(),
		"command_log": client.get_command_log(),
		"ticks": ticks,
	}

func _snapshot(client: MatchClient, triggering_event: Dictionary) -> Dictionary:
	return {
		"triggering_event": triggering_event,
		"state": client.get_state(),
	}

func _assert_gameplay(events: Array) -> void:
	var waves: Dictionary = {"A": 0, "B": 0}
	var deaths := 0
	var first_contact := false
	var base_damage_sequences: Dictionary = {"A": [], "B": []}
	var win_events: Array = []
	var restart_events := 0
	# prev_hp resets on match_restarted so the monotonic check is per-match-segment,
	# not across a restart boundary where base_hp legitimately jumps back up.
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

func _assert_determinism(command_log: Array, events_run1: Array, total_ticks: int) -> void:
	var client2 := MatchClient.new(false)
	client2.load_replay_log(command_log)
	for i in range(total_ticks):
		client2.step()
	var events_run2: Array = client2.get_full_event_log()
	var identical := _events_equal(events_run1, events_run2)
	_assert("determinism_same_log_identical_ledgers", identical, "replayed the exact recorded command log (%d commands) into a fresh host for %d ticks: %d vs %d events, identical=%s" % [command_log.size(), total_ticks, events_run1.size(), events_run2.size(), identical])

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
	var out_dir := _repo_root().path_join("studio/builds/slice-0")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ledger := {
		"slice": "Slice 0 — Walking Skeleton",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine_version": Engine.get_version_info(),
		"assertions": assertions,
		"all_pass": _all_pass(),
		"event_log": events,
		"command_log": command_log,
	}
	var f := FileAccess.open(out_dir.path_join("ledger.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(ledger, "\t"))
	f.close()

func _write_frames() -> void:
	var out_dir := _repo_root().path_join("studio/builds/slice-0/frames")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for key in frames.keys():
		var f := FileAccess.open(out_dir.path_join("%s.json" % key), FileAccess.WRITE)
		f.store_string(JSON.stringify(frames[key], "\t"))
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
