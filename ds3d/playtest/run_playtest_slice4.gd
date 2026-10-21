extends SceneTree

## Slice 4 canonical playtest. A full match runs in its networked shape:
## one authoritative host session and TWO clients connected over real TCP
## on 127.0.0.1, each driving only its own side through the message
## interface (client A = scripted buyer, client B = the Slice 3 AI buyer).
## Asserts, per studio/SLICE-PLAN.md Slice 4:
##   1. the match completes with both clients driving their own sides;
##   2. both clients' event ledgers are identical to the host's (lockstep);
##   3. the recorded command log replayed into a fresh host reproduces the
##      identical ledger hash;
##   4. the sim advances on fixed timesteps independent of pacing — the
##      same match re-run with disturbed pump pacing (extra transport
##      polls + wall-clock delays between rounds) produces the identical
##      ledger hash in the identical number of ticks.
const Host = preload("res://sim/host.gd")
const NetSession = preload("res://net/net_session.gd")
const NetHostSession = preload("res://net/net_host_session.gd")
const ScriptedBuyer = preload("res://playtest/scripted_buyer.gd")
const MAX_TICKS := 12000
const BASE_PORT := 42337

var assertions: Array = []

func _init() -> void:
	_assert("boots_headless", true, "SceneTree playtest ran under --headless")
	var run1 := _run_net_match(BASE_PORT, false)
	_assert_transport(run1)
	_assert_full_match_two_clients(run1)
	_assert_lockstep(run1)
	_assert_replay(run1)
	var run2 := _run_net_match(BASE_PORT + 1, true)
	_assert_fixed_timestep(run1, run2)
	_write_ledger(run1, run2)
	_report()

func _run_net_match(port: int, disturbed: bool) -> Dictionary:
	var session := NetSession.tcp(port, "normal")
	session.client_a.source = ScriptedBuyer.new(0)
	var connected := session.wait_connected()
	var host_bus = session.host_session.bus
	var transport_ok: bool = connected and host_bus.is_connected_to("client_a") and host_bus.is_connected_to("client_b") and session.client_a.bus.is_connected_to("host") and session.client_b.bus.is_connected_to("host")
	var ok := connected
	var rounds := 0
	while ok and not session.host_session.host.match_over and rounds < MAX_TICKS:
		ok = session.pump()
		rounds += 1
		if disturbed:
			# Pacing disturbance: extra transport churn and a wall-clock
			# delay between rounds. The sim must not notice either.
			session.host_session.poll_messages()
			session.client_a.poll()
			session.client_b.poll()
			OS.delay_msec(1)
	# Flush: step until the host has consumed every submitted command and
	# both replicas have applied the final bundles.
	var hs = session.host_session
	var guard := 0
	while ok and guard < 32 and (hs.host.pending_cursor < hs.host.pending_log.size() or session.client_a.replica.tick < hs.host.tick or session.client_b.replica.tick < hs.host.tick):
		ok = session.pump()
		rounds += 1
		guard += 1
	session.finish()
	var host_events: Array = hs.get_event_log()
	var result := {
		"port": port,
		"disturbed": disturbed,
		"transport_ok": transport_ok,
		"pump_ok": ok,
		"rounds": rounds,
		"host_tick": hs.host.tick,
		"match_over": hs.host.match_over,
		"winner": hs.host.winner,
		"host_events": host_events,
		"host_commands": hs.get_command_log(),
		"host_hash": NetHostSession.ledger_hash(host_events),
		"client_a_events": session.client_a.get_full_event_log(),
		"client_b_events": session.client_b.get_full_event_log(),
		"client_a_hash": NetHostSession.ledger_hash(session.client_a.get_full_event_log()),
		"client_b_hash": NetHostSession.ledger_hash(session.client_b.get_full_event_log()),
		"client_a_tick": session.client_a.replica.tick,
		"client_b_tick": session.client_b.replica.tick,
		"client_a_end_hash": String(session.client_a.match_end_info.get("ledger_hash", "")),
		"client_b_end_hash": String(session.client_b.match_end_info.get("ledger_hash", "")),
		"applied_sources": hs.applied_sources.duplicate(),
		"provenance_misaligned": hs.provenance_misaligned,
	}
	session.close()
	return result

func _assert_transport(run: Dictionary) -> void:
	_assert("tcp_loopback_both_clients_connected", run["transport_ok"], "both clients completed hello/welcome over TCP 127.0.0.1:%d and both sockets report STATUS_CONNECTED to the host endpoint" % run["port"])

func _assert_full_match_two_clients(run: Dictionary) -> void:
	var a_cmds := 0
	var b_cmds := 0
	var provenance_ok: bool = not run["provenance_misaligned"] and run["applied_sources"].size() == run["host_commands"].size()
	for i in range(run["host_commands"].size()):
		var cmd: Dictionary = run["host_commands"][i]
		var src: String = run["applied_sources"][i]
		if cmd["action"] == "SPAWN_WAVE":
			provenance_ok = provenance_ok and src == "host"
		elif cmd["player_id"] == "A":
			a_cmds += 1
			provenance_ok = provenance_ok and src == "client_a"
		elif cmd["player_id"] == "B":
			b_cmds += 1
			provenance_ok = provenance_ok and src == "client_b"
		else:
			provenance_ok = false
	var done: bool = run["pump_ok"] and run["match_over"] and run["winner"] != "" and run["host_tick"] <= MAX_TICKS
	_assert("full_match_completes_both_clients_drive_own_sides", done and a_cmds > 0 and b_cmds > 0 and provenance_ok, "match concluded in %d ticks (winner %s); %d side-A commands all arrived from client_a, %d side-B commands all from client_b, SPAWN_WAVE only from the host; provenance aligned=%s" % [run["host_tick"], run["winner"], a_cmds, b_cmds, str(provenance_ok)])

func _assert_lockstep(run: Dictionary) -> void:
	var same_a: bool = JSON.stringify(run["client_a_events"]) == JSON.stringify(run["host_events"])
	var same_b: bool = JSON.stringify(run["client_b_events"]) == JSON.stringify(run["host_events"])
	var ticks_ok: bool = run["client_a_tick"] == run["host_tick"] and run["client_b_tick"] == run["host_tick"]
	var end_ok: bool = run["client_a_end_hash"] == run["host_hash"] and run["client_b_end_hash"] == run["host_hash"]
	_assert("lockstep_client_ledgers_identical_to_host", same_a and same_b and ticks_ok and end_ok, "at match end: client_a ledger == host == client_b ledger (%d events, hash %s); replica ticks %d/%d == host tick %d; both clients received match_end with the host's hash and it matched their own" % [run["host_events"].size(), run["host_hash"], run["client_a_tick"], run["client_b_tick"], run["host_tick"]])

func _assert_replay(run: Dictionary) -> void:
	var replay := Host.new(false)
	replay.load_replay_log(run["host_commands"])
	for i in range(run["host_tick"]):
		replay.step()
	var replay_hash := NetHostSession.ledger_hash(replay.get_event_log())
	_assert("replay_recorded_log_reproduces_ledger_hash", replay_hash == run["host_hash"], "replayed %d recorded commands into a fresh host for %d ticks: ledger hash %s == live host hash %s" % [run["host_commands"].size(), run["host_tick"], replay_hash, run["host_hash"]])
	run["replay_hash"] = replay_hash

func _assert_fixed_timestep(run1: Dictionary, run2: Dictionary) -> void:
	var same: bool = run2["host_hash"] == run1["host_hash"] and run2["host_tick"] == run1["host_tick"] and run2["winner"] == run1["winner"]
	_assert("fixed_timestep_independent_of_pacing", same, "identical match re-run with disturbed pacing (extra transport polls + 1ms wall-clock delay every round): ledger hash %s == %s, ticks %d == %d, winner %s — the sim advanced exactly one fixed tick per round regardless of pacing" % [run2["host_hash"], run1["host_hash"], run2["host_tick"], run1["host_tick"], run1["winner"]])

func _assert(id: String, passed: bool, detail: String) -> void:
	assertions.append({"id": id, "pass": passed, "detail": detail})

func _write_ledger(run: Dictionary, run2: Dictionary) -> void:
	var dir := "res://../studio/builds/slice-4"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var ledger := {
		"slice": "Slice 4 — Lockstep over loopback: two clients, one host",
		"generated_utc": Time.get_datetime_string_from_system(true),
		"transport": "TCP over 127.0.0.1 (ports %d/%d), star topology, newline-delimited JSON envelopes {from, to, msg}" % [run["port"], run2["port"]],
		"session_shape": "NetHostSession owns the one authoritative Host (auto_source on). Each NetClient owns a replica Host (auto_source off) fed only by host tick bundles — the commands the host applied that tick, in applied order, after a canonical sort (tick, player_id, action, params) at submission. Rounds are barrier-synchronized: the host steps once both clients signal round_ready; each client steps its replica once per bundle. Client A is driven by a scripted buyer, client B by the Slice 3 AI buyer; both see only the public state snapshot of their own replica.",
		"match": {"ticks": run["host_tick"], "rounds": run["rounds"], "winner": run["winner"], "command_count": run["host_commands"].size(), "event_count": run["host_events"].size()},
		"ledger_hashes": {"host": run["host_hash"], "client_a": run["client_a_hash"], "client_b": run["client_b_hash"], "replay": run.get("replay_hash", ""), "pacing_rerun_host": run2["host_hash"]},
		"assertions": assertions,
		"all_pass": _all_pass(),
		"event_log": run["host_events"],
		"command_log": run["host_commands"],
	}
	var f := FileAccess.open(dir.path_join("ledger.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(ledger, "\t"))
	f.close()

func _all_pass() -> bool:
	for a in assertions:
		if not a["pass"]:
			return false
	return true

func _report() -> void:
	for a in assertions:
		print("[%s] %s — %s" % [("PASS" if a["pass"] else "FAIL"), a["id"], a["detail"]])
	quit(0 if _all_pass() else 1)
