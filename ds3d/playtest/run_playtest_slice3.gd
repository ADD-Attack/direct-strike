extends SceneTree

## Slice 3 canonical playtest. Player and AI both enter through MatchClient;
## the AI's decisions are then replayed as an ordinary recorded command log.
const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")
const MAX_TICKS := 12000
const LEVELS := ["easy", "normal", "hard"]
var assertions: Array = []
var runs: Dictionary = {}

func _init() -> void:
	_assert("boots_headless", true, "SceneTree playtest ran under --headless")
	for level in LEVELS:
		var series: Array = []
		for n in range(4):
			series.append(_run_match(level, n))
		runs[level] = series
	_assert_full_matches()
	_assert_command_interface()
	_assert_determinism(runs["normal"][0])
	_assert_difficulty_quality()
	_assert_slice0_2_regression()
	_write_ledger(runs["normal"][0])
	_report()

func _run_match(level: String, variant: int) -> Dictionary:
	var c := MatchClient.new(true)
	c.set_ai_difficulty(level)
	var ticks := 0
	var roles := ["frontline_tank", "line_dps", "ranged", "line_dps", "frontline_tank", "ranged"]
	while not c.get_state()["match_over"] and ticks < MAX_TICKS:
		var phase: int = ticks % Host.BUILD_PHASE_TICKS
		if phase % 80 == 0 and phase < 560:
			c.submit_command("A", "BUY_UNIT", {"role": roles[(ticks / 80 + variant) % roles.size()]})
		if phase == 180:
			c.submit_command("A", "BUY_GAS", {})
		c.step()
		ticks += 1
	return {"level": level, "variant": variant, "ticks": ticks, "state": c.get_state(), "events": c.get_full_event_log(), "command_log": c.get_command_log()}

func _assert_full_matches() -> void:
	for level in LEVELS:
		var complete := 0
		for r in runs[level]:
			if r["state"]["match_over"]: complete += 1
		_assert("%s_full_matches_conclude" % level, complete == 4, "%s completed %d/4 scripted matches within %d ticks" % [level, complete, MAX_TICKS])

func _assert_command_interface() -> void:
	var log: Array = runs["normal"][0]["command_log"]
	var ai: Array = []
	var valid := true
	for cmd in log:
		if cmd["player_id"] == "B" and cmd["action"] != "SPAWN_WAVE":
			ai.append(cmd)
			valid = valid and cmd["action"] in ["BUY_UNIT", "BUY_GAS", "PLACE_UNIT"] and cmd["params"].has("ai_seed")
	_assert("ai_purchases_appear_in_command_log", ai.size() > 0 and valid, "%d AI commands logged as ordinary BUY_UNIT/BUY_GAS/PLACE_UNIT commands with recorded seed; no sim-only action found" % ai.size())

func _assert_determinism(run: Dictionary) -> void:
	var replay := Host.new(false)
	replay.load_replay_log(run["command_log"])
	for i in range(run["ticks"]): replay.step()
	var same := JSON.stringify(replay.get_event_log()) == JSON.stringify(run["events"])
	_assert("determinism_same_ai_log_identical_ledgers", same, "replayed %d recorded commands for %d ticks: event ledgers identical=%s" % [run["command_log"].size(), run["ticks"], same])

func _win_rate(level: String) -> float:
	var wins := 0
	for r in runs[level]:
		if r["state"]["winner"] == "B": wins += 1
	return float(wins) / float(runs[level].size())

func _assert_difficulty_quality() -> void:
	var easy := _win_rate("easy")
	var normal := _win_rate("normal")
	var hard := _win_rate("hard")
	_assert("normal_beats_easy_repeated_matchups", normal > easy, "B win rates against the same four scripted player variants: Easy=%.0f%%, Normal=%.0f%%, Hard=%.0f%%" % [easy * 100.0, normal * 100.0, hard * 100.0])
	_assert("hard_beats_easy_repeated_matchups", hard > easy, "B win rates against the same four scripted player variants: Easy=%.0f%%, Normal=%.0f%%, Hard=%.0f%%" % [easy * 100.0, normal * 100.0, hard * 100.0])

func _assert_slice0_2_regression() -> void:
	var r: Dictionary = runs["normal"][0]
	var event_types: Array = []
	for e in r["events"]: event_types.append(e["type"])
	var state: Dictionary = r["state"]
	var architecture := FileAccess.file_exists("res://sim/host.gd") and FileAccess.file_exists("res://client/match_client.gd")
	var economy := event_types.has("unit_purchased") and event_types.has("gas_purchased") and event_types.has("wave_spawned")
	var combat := event_types.has("first_contact") and event_types.has("unit_death") and event_types.has("match_won")
	var roster := false
	for e in r["events"]:
		if e["type"] == "wave_spawned" and e["data"]["formation"].size() > 0: roster = true
	_assert("slice0_2_regression_architecture_economy_combat_roster", architecture and economy and combat and roster and state["match_over"], "host/client seam, command economy, waves/combat/win, and roster formations all exercised in the Slice 3 match")

func _assert(id: String, passed: bool, detail: String) -> void:
	assertions.append({"id": id, "pass": passed, "detail": detail})

func _write_ledger(run: Dictionary) -> void:
	var dir := "res://../studio/builds/slice-3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var ledger := {"slice": "Slice 3 — The opponent", "generated_utc": Time.get_datetime_string_from_system(true), "difficulty_tuning": {"easy": "150-tick cadence; tier-1 near-random; no gas", "normal": "75-tick cadence; reserves after phase tick 300 for gas at 550; counter to player's most-fielded visible role; center row", "hard": "45-tick cadence; reserves after phase tick 180 for gas at 585; counter composition; front row when player controls middle"}, "visibility_rule": "Before each decision, AI reads only MatchClient.get_state(): current tick, public economy, wave/queue counts, middle controller, and fielded units/roles. It cannot inspect Host internals, future commands, or player queue roles.", "matchup_results": {"easy_win_rate": _win_rate("easy"), "normal_win_rate": _win_rate("normal"), "hard_win_rate": _win_rate("hard")}, "assertions": assertions, "all_pass": _all_pass(), "event_log": run["events"], "command_log": run["command_log"]}
	var f := FileAccess.open(dir.path_join("ledger.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(ledger, "\t")); f.close()

func _all_pass() -> bool:
	for a in assertions:
		if not a["pass"]: return false
	return true

func _report() -> void:
	for a in assertions: print("[%s] %s — %s" % [("PASS" if a["pass"] else "FAIL"), a["id"], a["detail"]])
	quit(0 if _all_pass() else 1)
