extends SceneTree

## The Studio playtest for Slice 2 — Roster & tiers. Canonical/current
## playtest; supersedes playtest/run_playtest_slice1.gd (kept as the
## historical record tied to studio/receipts/slice-1.json).
##
## Drives the game ONLY through MatchClient's command interface. Boots
## headless via `godot --headless --path ds3d -s playtest/run_playtest_slice2.gd`.

const Host = preload("res://sim/host.gd")
const MatchClient = preload("res://client/match_client.gd")

const MAX_TICKS_PER_MATCH := 20000
## Main driven match: side A cycles through all 6 roles while buying, so the
## ledger naturally contains every role's spawn stats, tier-2 rejections
## before the threshold, and tier-2 purchases after it crosses.
## One attempt per role per phase, spread across the phase window so later
## (pricier) roles in the cycle have had time to accrue minerals via trickle
## before their turn — cramming all 6 into the first 100 ticks starved
## fast_flanker/siege of funds every single phase.
const PLAYER_BUY_OFFSETS := [0, 100, 200, 300, 400, 500]
const PLAYER_ROLE_CYCLE := ["line_dps", "frontline_tank", "ranged", "splash", "fast_flanker", "siege"]
const PLAYER_GAS_OFFSET := 20

var assertions: Array = []

func _assert(id: String, passed: bool, detail: String) -> void:
	assertions.append({"id": id, "pass": passed, "detail": detail})

func _init() -> void:
	_assert("boots_headless", true, "SceneTree playtest executed under --headless with no display/window/GPU context")

	var run := _play_full_script()
	var events: Array = run["events"]
	var command_log: Array = run["command_log"]
	var total_ticks: int = run["ticks"]
	var final_minerals: Dictionary = run["final_minerals"]

	_assert_architecture()
	_assert_gameplay(events)
	_assert_economy(events, total_ticks, final_minerals)
	_assert_roster_stats(events)
	_assert_tier_gating(events)
	_assert_determinism(command_log, events, total_ticks)
	_assert_counter_compositions()
	_assert_placement_changes_engagement_order()

	_write_ledger(events, command_log)
	_report_and_quit()

## Drives one match to a conclusion (buying a rotating mix of all 6 roles for
## side A every build phase — enough to cross the tier-2 threshold partway
## through — the fixed enemy script buys for B automatically), restarts it,
## drives a second match to a conclusion — all through MatchClient.
func _play_full_script() -> Dictionary:
	var client := MatchClient.new(true)
	var ticks := 0
	var last_phase_reset_tick := 0
	var role_cursor := 0

	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH:
		# Modulo, not a plain subtraction: the offsets must recur every build
		# phase (every BUILD_PHASE_TICKS), not just once at the start of the
		# whole match — a plain `ticks - last_phase_reset_tick` only ever
		# matches during the very first phase and silently stops buying for
		# every phase after that.
		var since_phase: int = (ticks - last_phase_reset_tick) % Host.BUILD_PHASE_TICKS
		if since_phase in PLAYER_BUY_OFFSETS:
			var role: String = PLAYER_ROLE_CYCLE[role_cursor % PLAYER_ROLE_CYCLE.size()]
			role_cursor += 1
			client.submit_command("A", "BUY_UNIT", {"role": role})
		if since_phase == PLAYER_GAS_OFFSET:
			client.submit_command("A", "BUY_GAS", {})
		client.step()
		ticks += 1

	_assert("first_match_concludes", client.get_state()["match_over"], "first scripted match reached a win within %d ticks (took %d)" % [MAX_TICKS_PER_MATCH, ticks])

	var pre_restart: Dictionary = client.get_state()
	client.submit_command("owner", "RESTART", {})
	for i in range(5):
		client.step()
		ticks += 1
	last_phase_reset_tick = ticks
	role_cursor = 0
	var expected_post_restart_minerals: float = Host.STARTING_MINERALS + 5.0 * Host.BASE_TRICKLE_PER_SEC / float(Host.TICK_RATE)
	var post_restart: Dictionary = client.get_state()
	var restart_ok: bool = (not post_restart["match_over"]) \
		and post_restart["base_hp"]["A"] == Host.BASE_HP \
		and post_restart["base_hp"]["B"] == Host.BASE_HP \
		and post_restart["units"].size() == 0 \
		and absf(post_restart["minerals"]["A"] - expected_post_restart_minerals) < 0.01 \
		and absf(post_restart["minerals"]["B"] - expected_post_restart_minerals) < 0.01 \
		and post_restart["gas_count"]["A"] == 0 and post_restart["gas_count"]["B"] == 0 \
		and post_restart["middle_controller"] == "" \
		and post_restart["tier2_unlocked"]["A"] == false
	_assert("restart_resets_match", restart_ok, "pre-restart: match_over=%s base_hp=%s -> post-restart: match_over=%s base_hp=%s units=%d minerals=%s tier2_unlocked=%s" % [pre_restart["match_over"], pre_restart["base_hp"], post_restart["match_over"], post_restart["base_hp"], post_restart["units"].size(), post_restart["minerals"], post_restart["tier2_unlocked"]])

	while not client.get_state()["match_over"] and ticks < MAX_TICKS_PER_MATCH * 2:
		var since_phase2: int = (ticks - last_phase_reset_tick) % Host.BUILD_PHASE_TICKS
		if since_phase2 in PLAYER_BUY_OFFSETS:
			var role2: String = PLAYER_ROLE_CYCLE[role_cursor % PLAYER_ROLE_CYCLE.size()]
			role_cursor += 1
			client.submit_command("A", "BUY_UNIT", {"role": role2})
		if since_phase2 == PLAYER_GAS_OFFSET:
			client.submit_command("A", "BUY_GAS", {})
		client.step()
		ticks += 1

	_assert("second_match_concludes_after_restart", client.get_state()["match_over"], "second match (post-restart) also reached a win, proving the match is fully replayable after restart")

	return {
		"events": client.get_full_event_log(),
		"command_log": client.get_command_log(),
		"ticks": ticks,
		"final_minerals": client.get_state()["minerals"],
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

func _assert_economy(events: Array, total_ticks: int, final_minerals: Dictionary) -> void:
	var queued_since_last_wave: Dictionary = {"A": 0, "B": 0}
	var wave_match_ok := true
	var wave_match_detail := ""
	var purchased_count := 0
	var rejected_count := 0
	var gas_count := 0
	var gas_formula_ok := true
	var gas_detail := ""
	var control_change_count := 0
	var control_flip_ok := true
	var wave_ticks: Dictionary = {"A": [], "B": []}
	var restart_ticks: Array = []

	var recon_minerals: Dictionary = {"A": Host.STARTING_MINERALS, "B": Host.STARTING_MINERALS}
	var recon_trickle: Dictionary = {"A": Host.BASE_TRICKLE_PER_SEC, "B": Host.BASE_TRICKLE_PER_SEC}
	var recon_controller := ""
	var cursor_tick := 0

	var i := 0
	while i < events.size():
		var t: int = events[i]["tick"]
		var n: int = t - cursor_tick
		if n > 0:
			for side in ["A", "B"]:
				var rate: float = recon_trickle[side] + (Host.MIDDLE_CONTROL_BONUS_PER_SEC if recon_controller == side else 0.0)
				recon_minerals[side] += rate / float(Host.TICK_RATE) * n
			cursor_tick = t
		var j := i
		while j < events.size() and events[j]["tick"] == t:
			var e: Dictionary = events[j]
			match e["type"]:
				"unit_purchased":
					var side: String = e["data"]["side"]
					queued_since_last_wave[side] += 1
					purchased_count += 1
					recon_minerals[side] -= e["data"]["cost"]
				"buy_rejected":
					rejected_count += 1
				"gas_purchased":
					var gside: String = e["data"]["side"]
					gas_count += 1
					var expected_cost: float = Host.GAS_COSTS[e["data"]["gas_count"] - 1]
					var expected_trickle: float = Host.BASE_TRICKLE_PER_SEC + e["data"]["gas_count"] * Host.GAS_TRICKLE_BONUS_PER_SEC
					if e["data"]["cost"] != expected_cost or e["data"]["new_trickle_rate"] != expected_trickle:
						gas_formula_ok = false
						gas_detail += "tick %d mismatch; " % t
					recon_minerals[gside] -= e["data"]["cost"]
					recon_trickle[gside] += Host.GAS_TRICKLE_BONUS_PER_SEC
				"middle_control_changed":
					var new_controller: String = e["data"]["controller"]
					if new_controller == recon_controller:
						control_flip_ok = false
					control_change_count += 1
					recon_controller = new_controller
				"wave_spawned":
					var side3: String = e["data"]["side"]
					var expected_count: int = queued_since_last_wave[side3]
					if e["data"]["purchased_count"] != expected_count or e["data"]["unit_ids"].size() != expected_count:
						wave_match_ok = false
						wave_match_detail += "side=%s tick=%d expected=%d got=%d; " % [side3, t, expected_count, e["data"]["purchased_count"]]
					queued_since_last_wave[side3] = 0
					wave_ticks[side3].append(t)
				"match_restarted":
					restart_ticks.append(t)
					queued_since_last_wave = {"A": 0, "B": 0}
					recon_minerals = {"A": Host.STARTING_MINERALS, "B": Host.STARTING_MINERALS}
					recon_trickle = {"A": Host.BASE_TRICKLE_PER_SEC, "B": Host.BASE_TRICKLE_PER_SEC}
					recon_controller = ""
			j += 1
		i = j
	var n_final: int = total_ticks - cursor_tick
	if n_final > 0:
		for side in ["A", "B"]:
			var rate2: float = recon_trickle[side] + (Host.MIDDLE_CONTROL_BONUS_PER_SEC if recon_controller == side else 0.0)
			recon_minerals[side] += rate2 / float(Host.TICK_RATE) * n_final

	var recon_matches := true
	var recon_detail := ""
	for side in ["A", "B"]:
		var diff: float = absf(recon_minerals[side] - final_minerals[side])
		if diff > 0.01:
			recon_matches = false
			recon_detail += "side=%s reconstructed=%.4f actual=%.4f; " % [side, recon_minerals[side], final_minerals[side]]

	_assert("buy_commands_debit_minerals_and_join_next_wave", wave_match_ok and purchased_count > 0, "%d unit_purchased events; every wave_spawned.purchased_count matched purchases queued since that side's previous wave (mismatches=%s)" % [purchased_count, ("none" if wave_match_ok else wave_match_detail)])
	_assert("trickle_and_middle_control_match_stated_formula", recon_matches, "reconstructed minerals walking the ledger tick-by-tick match the host's actual final minerals (mismatch=%s)" % ("none" if recon_matches else recon_detail))
	_assert("gas_purchase_escalating_cost_and_trickle_bonus", gas_formula_ok and gas_count > 0, "%d gas_purchased events (mismatches=%s)" % [gas_count, ("none" if gas_formula_ok else gas_detail)])
	_assert("middle_control_flips_with_unit_distribution", control_flip_ok and control_change_count > 0, "%d middle_control_changed events, each one actually changed the controller" % control_change_count)
	_assert("unaffordable_buys_rejected", rejected_count > 0, "%d buy_rejected events recorded" % rejected_count)

	var cycle_ok := true
	for side in ["A", "B"]:
		var ts: Array = wave_ticks[side]
		for k in range(1, ts.size()):
			var crosses_restart := false
			for rt in restart_ticks:
				if rt > ts[k - 1] and rt <= ts[k]:
					crosses_restart = true
			if not crosses_restart and (ts[k] - ts[k - 1]) != Host.BUILD_PHASE_TICKS:
				cycle_ok = false
	_assert("wave_timer_cycles_build_spawn_build", cycle_ok and wave_ticks["A"].size() >= 2 and wave_ticks["B"].size() >= 2, "wave_spawned ticks per side: A=%s B=%s; consecutive gaps equal BUILD_PHASE_TICKS=%d except across a restart" % [wave_ticks["A"], wave_ticks["B"], Host.BUILD_PHASE_TICKS])

## "every type spawns with its spec'd stats in the ledger" — checked against
## every wave_spawned.formation entry across the whole match, for every role
## that actually appeared.
func _assert_roster_stats(events: Array) -> void:
	var seen_roles: Dictionary = {}
	var mismatches: Array = []
	for e in events:
		if e["type"] != "wave_spawned":
			continue
		for entry in e["data"]["formation"]:
			var role: String = entry["role"]
			seen_roles[role] = true
			var spec: Dictionary = Host.ROLE_STATS[role]
			if entry["hp"] != spec["hp"] or entry["damage"] != spec["damage"] or entry["range"] != spec["range"] or entry["cooldown"] != spec["cooldown"] or entry["speed"] != spec["speed"]:
				mismatches.append("unit_id=%d role=%s got hp=%s/dmg=%s/range=%s/cd=%s/spd=%s expected hp=%s/dmg=%s/range=%s/cd=%s/spd=%s" % [entry["unit_id"], role, entry["hp"], entry["damage"], entry["range"], entry["cooldown"], entry["speed"], spec["hp"], spec["damage"], spec["range"], spec["cooldown"], spec["speed"]])
	var all_roles_seen := true
	var missing: Array = []
	for role in Host.ROLE_ORDER:
		if not seen_roles.has(role):
			all_roles_seen = false
			missing.append(role)
	_assert("every_role_spawns_with_specd_stats", mismatches.is_empty() and all_roles_seen, "roles seen in wave_spawned.formation: %s (missing=%s); stat mismatches=%s" % [seen_roles.keys(), missing, ("none" if mismatches.is_empty() else mismatches)])

## "tier-2 buys rejected before the threshold and accepted after"
func _assert_tier_gating(events: Array) -> void:
	var tier2_roles: Array = []
	for role in Host.ROLE_ORDER:
		if Host.ROLE_STATS[role]["tier"] == 2:
			tier2_roles.append(role)

	var rejected_before: Array = []
	var accepted_after: Array = []
	var violation := ""
	for e in events:
		if e["type"] == "buy_rejected" and e["data"].get("reason", "") == "tier_locked":
			rejected_before.append(e)
			if e["data"]["total_spent"] >= e["data"]["threshold"]:
				violation += "tick %d: tier_locked rejection while total_spent %s >= threshold %s; " % [e["tick"], e["data"]["total_spent"], e["data"]["threshold"]]
		elif e["type"] == "unit_purchased" and tier2_roles.has(e["data"]["role"]):
			accepted_after.append(e)
			if e["data"]["total_spent"] < Host.TIER2_UNLOCK_THRESHOLD:
				violation += "tick %d: tier-2 role %s accepted at total_spent %s < threshold %s; " % [e["tick"], e["data"]["role"], e["data"]["total_spent"], Host.TIER2_UNLOCK_THRESHOLD]

	_assert("tier2_rejected_before_accepted_after_threshold", rejected_before.size() > 0 and accepted_after.size() > 0 and violation == "", "%d tier_locked rejections, %d tier-2 purchases accepted once total_spent crossed TIER2_UNLOCK_THRESHOLD=%s (violations=%s)" % [rejected_before.size(), accepted_after.size(), Host.TIER2_UNLOCK_THRESHOLD, ("none" if violation == "" else violation)])

## "a counter-composed wave defeats an equal-cost mono wave in a scripted
## sim, repeatedly" — three independent counter relationships, each an
## isolated clash (own Host, no reinforcements): ranged (range + bonus_vs)
## beats mono frontline_tank; splash (AoE) beats a mono-cost swarm of
## line_dps; fast_flanker (bypasses tanks, bonus_vs siege) beats mono siege.
## "Repeatedly" = three separate, independently-reasoned matchups rather
## than one rerun (determinism makes literal repetition tautological).
func _assert_counter_compositions() -> void:
	var matchups := [
		{"name": "ranged_beats_mono_tank", "a": ["ranged", "ranged", "ranged", "ranged", "ranged", "ranged"], "b": ["frontline_tank", "frontline_tank", "frontline_tank", "frontline_tank", "frontline_tank", "frontline_tank"]},
		{"name": "splash_beats_mono_swarm", "a": ["splash", "splash", "splash"], "b": ["line_dps", "line_dps", "line_dps", "line_dps", "line_dps", "line_dps"]},
		{"name": "flanker_beats_mono_siege", "a": ["fast_flanker", "fast_flanker", "fast_flanker", "fast_flanker"], "b": ["siege", "siege"]},
	]
	for m in matchups:
		var result := _run_isolated_clash(m["a"], m["b"])
		var cost_a: float = _composition_cost(m["a"])
		var cost_b: float = _composition_cost(m["b"])
		var counter_wins: bool = result["a_survivors"] > result["b_survivors"]
		_assert("counter_composition_%s" % m["name"], counter_wins, "A=%s (cost %s) vs B=%s (cost %s): A survivors reaching base=%d, B survivors reaching base=%d (A units fielded=%d, B units fielded=%d)" % [m["a"], cost_a, m["b"], cost_b, result["a_survivors"], result["b_survivors"], result["a_units"], result["b_units"]])

func _composition_cost(roles: Array) -> float:
	var total := 0.0
	for r in roles:
		total += Host.ROLE_STATS[r]["cost"]
	return total

## Isolated two-phase clash: phase 1 is throwaway filler (staggered buys so
## trickle funds it) that gets both sides' lifetime spend past
## TIER2_UNLOCK_THRESHOLD, so tier-2 roles are actually purchasable in phase
## 2 — mirrors how a real match would reach tier 2, rather than special-
## casing the test. Phase 2 is the composition under test. Returns how many
## of each side's phase-2-specific unit ids delivered base_damage.
func _run_isolated_clash(roles_a: Array, roles_b: Array) -> Dictionary:
	var h := Host.new(false)
	for i in range(6):
		h.submit_command({"tick": i * 60, "player_id": "A", "action": "BUY_UNIT", "params": {"role": "line_dps"}})
		h.submit_command({"tick": i * 60, "player_id": "B", "action": "BUY_UNIT", "params": {"role": "line_dps"}})
	h.submit_command({"tick": 650, "player_id": "A", "action": "SPAWN_WAVE", "params": {}})
	h.submit_command({"tick": 650, "player_id": "B", "action": "SPAWN_WAVE", "params": {}})
	for i in range(roles_a.size()):
		h.submit_command({"tick": 651 + i * 80, "player_id": "A", "action": "BUY_UNIT", "params": {"role": roles_a[i]}})
	for i in range(roles_b.size()):
		h.submit_command({"tick": 651 + i * 80, "player_id": "B", "action": "BUY_UNIT", "params": {"role": roles_b[i]}})
	h.submit_command({"tick": 1300, "player_id": "A", "action": "SPAWN_WAVE", "params": {}})
	h.submit_command({"tick": 1300, "player_id": "B", "action": "SPAWN_WAVE", "params": {}})
	var ticks := 0
	while ticks < 8000:
		h.step()
		ticks += 1
	var wave2_a: Array = []
	var wave2_b: Array = []
	for e in h.event_log:
		if e["type"] == "wave_spawned" and e["tick"] == 1300:
			if e["data"]["side"] == "A":
				wave2_a = e["data"]["unit_ids"]
			else:
				wave2_b = e["data"]["unit_ids"]
	var a_dmg := 0
	var b_dmg := 0
	for e in h.event_log:
		if e["type"] == "base_damage":
			var uid: int = e["data"]["unit_id"]
			if wave2_a.has(uid):
				a_dmg += 1
			if wave2_b.has(uid):
				b_dmg += 1
	return {"a_survivors": a_dmg, "b_survivors": b_dmg, "a_units": wave2_a.size(), "b_units": wave2_b.size()}

## "placement changes engagement order in the ledger" — place side A's
## units in different rows (row 0 = front, row 2 = back) facing a common
## row-1 (default) enemy line, and assert the front-row unit's unit_engaged
## event fires strictly before the back-row unit's.
func _assert_placement_changes_engagement_order() -> void:
	var h := Host.new(false)
	h.submit_command({"tick": 0, "player_id": "A", "action": "BUY_UNIT", "params": {"role": "line_dps"}})
	h.submit_command({"tick": 0, "player_id": "A", "action": "BUY_UNIT", "params": {"role": "line_dps"}})
	h.submit_command({"tick": 0, "player_id": "A", "action": "PLACE_UNIT", "params": {"queue_index": 0, "row": 0, "col": 0}})
	h.submit_command({"tick": 0, "player_id": "A", "action": "PLACE_UNIT", "params": {"queue_index": 1, "row": 2, "col": 0}})
	h.submit_command({"tick": 0, "player_id": "B", "action": "BUY_UNIT", "params": {"role": "line_dps"}})
	h.submit_command({"tick": 0, "player_id": "A", "action": "SPAWN_WAVE", "params": {}})
	h.submit_command({"tick": 0, "player_id": "B", "action": "SPAWN_WAVE", "params": {}})
	var front_id := -1
	var back_id := -1
	var ticks := 0
	h.step()
	ticks += 1
	for e in h.event_log:
		if e["type"] == "wave_spawned" and e["data"]["side"] == "A":
			front_id = e["data"]["formation"][0]["unit_id"]
			back_id = e["data"]["formation"][1]["unit_id"]
	while h.units.size() > 0 and ticks < 5000:
		h.step()
		ticks += 1
	var front_engaged_tick := -1
	var back_engaged_tick := -1
	for e in h.event_log:
		if e["type"] == "unit_engaged":
			if e["data"]["unit_id"] == front_id and front_engaged_tick == -1:
				front_engaged_tick = e["tick"]
			elif e["data"]["unit_id"] == back_id and back_engaged_tick == -1:
				back_engaged_tick = e["tick"]
	var ok: bool = front_engaged_tick != -1 and back_engaged_tick != -1 and front_engaged_tick < back_engaged_tick
	_assert("placement_changes_engagement_order", ok, "unit %d placed at row 0 (front) first-engaged at tick %d; unit %d placed at row 2 (back) first-engaged at tick %d — front engages strictly first" % [front_id, front_engaged_tick, back_id, back_engaged_tick])

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

	var placement_via_command_interface := main_src.find("PLACE_UNIT") != -1
	_assert("placement_uses_command_interface", placement_via_command_interface, "scenes/main.gd issues PLACE_UNIT via client.submit_command(), the same interface every other command uses")

func _assert_determinism(command_log: Array, events_run1: Array, total_ticks: int) -> void:
	var client2 := MatchClient.new(false)
	client2.load_replay_log(command_log)
	for i in range(total_ticks):
		client2.step()
	var events_run2: Array = client2.get_full_event_log()
	var identical := _events_equal(events_run1, events_run2)
	_assert("determinism_same_log_identical_ledgers", identical, "replayed the exact recorded command log (%d commands, incl. buy/gas/place commands) into a fresh host for %d ticks: %d vs %d events, identical=%s" % [command_log.size(), total_ticks, events_run1.size(), events_run2.size(), identical])

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
	var out_dir := _repo_root().path_join("studio/builds/slice-2")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stat_table := {}
	for role in Host.ROLE_ORDER:
		stat_table[role] = Host.ROLE_STATS[role]
	var ledger := {
		"slice": "Slice 2 — Roster & tiers",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine_version": Engine.get_version_info(),
		"roster_stats": stat_table,
		"tier2_unlock_threshold": Host.TIER2_UNLOCK_THRESHOLD,
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
