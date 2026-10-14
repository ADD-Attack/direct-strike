extends SceneTree

## Early Slice 4 spike: three real headless Godot processes over loopback TCP.
## Host receives each source's complete scripted command log, orders commands by
## (tick, player_id, source sequence), and broadcasts one batch per fixed sim tick.
## Every process owns a Host sim and advances it only after that tick's batch.

const HostSim = preload("res://sim/host.gd")
const PORT := 19447
const MAX_TICKS := 10000
const OUTPUT_DIR := "res://../studio/builds/lockstep-spike-terra"

var role := ""
var sim: HostSim
var received_bytes := 0
var sent_bytes := 0

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	match role:
		"host":
			await _run_host()
		"client_a", "client_b":
			await _run_client("A" if role == "client_a" else "B")
		_:
			printerr("usage: -- host | client_a | client_b")
	quit()

func _script_for(side: String) -> Array:
	# Different build/formation scripts: A fields line DPS + ranged; B fields
	# tanks + splash attempt. Both include BUY_UNIT, BUY_GAS, and PLACE_UNIT.
	var roles := ["line_dps", "ranged", "line_dps", "ranged", "line_dps"] if side == "A" else ["frontline_tank", "frontline_tank", "ranged", "frontline_tank", "ranged"]
	var commands: Array = []
	var seq := 0
	for phase in range(9):
		var base := phase * 650
		for i in range(roles.size()):
			commands.append({"tick": base + 20 + i * 20, "player_id": side, "action": "BUY_UNIT", "params": {"role": roles[(i + phase) % roles.size()]}, "source_seq": seq})
			seq += 1
			commands.append({"tick": base + 25 + i * 20, "player_id": side, "action": "PLACE_UNIT", "params": {"queue_index": i, "row": i % 3, "col": i}, "source_seq": seq})
			seq += 1
		# Gas timing is intentionally late enough for the current demo economy.
		commands.append({"tick": base + 500, "player_id": side, "action": "BUY_GAS", "params": {}, "source_seq": seq})
		seq += 1
	return commands

func _run_host() -> void:
	var server := TCPServer.new()
	if server.listen(PORT, "127.0.0.1") != OK:
		_fail("host_listen_failed")
		return
	var peers: Dictionary = {}
	var buffers: Dictionary = {}
	var logs: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 15000
	while logs.size() < 2 and Time.get_ticks_msec() < deadline:
		if server.is_connection_available():
			var peer := server.take_connection()
			var id := "pending_%d" % peers.size()
			peers[id] = peer
			buffers[id] = ""
		for id in peers.keys():
			for message in _receive(peers[id], buffers, id):
				if message.get("type", "") == "hello":
					var side: String = message.get("player_id", "")
					if side in ["A", "B"]:
						peers[side] = peers[id]
						buffers[side] = buffers[id]
						peers.erase(id)
						buffers.erase(id)
				elif message.get("type", "") == "commands":
					logs[message.get("player_id", "")] = message.get("commands", [])
		await process_frame
	if logs.size() != 2 or not peers.has("A") or not peers.has("B"):
		_fail("host_handshake_timeout")
		return
	sim = HostSim.new(false)
	var by_tick := {}
	for side in ["A", "B"]:
		for command in logs[side]:
			# JSON parsing returns numeric values as floats; normalize the key so
			# the integer fixed-tick loop finds its scheduled command batch.
			var command_tick := int(command["tick"])
			command["tick"] = command_tick
			if not by_tick.has(command_tick): by_tick[command_tick] = []
			by_tick[command_tick].append(command)
	# The phase clock is host-owned. It issues the same SPAWN_WAVE commands to
	# both sides, then broadcasts them like player commands; clients never infer
	# a spawn locally from wall-clock time.
	for spawn_tick in range(650, 650 * 9, 650):
		if not by_tick.has(spawn_tick): by_tick[spawn_tick] = []
		for side in ["A", "B"]:
			by_tick[spawn_tick].append({"tick": spawn_tick, "player_id": side, "action": "SPAWN_WAVE", "params": {}, "source_seq": -1})
	for tick in range(MAX_TICKS):
		var batch: Array = by_tick.get(tick, [])
		batch.sort_custom(func(a, b): return a["player_id"] < b["player_id"] or (a["player_id"] == b["player_id"] and a["source_seq"] < b["source_seq"]))
		for command in batch: sim.submit_command(command)
		sim.step()
		var frame := {"type": "tick", "tick": tick, "commands": batch}
		for side in ["A", "B"]: _send(peers[side], frame)
		if sim.match_over: break
	var result := _result("host", sim, logs, sent_bytes, received_bytes)
	for side in ["A", "B"]: _send(peers[side], {"type": "done", "result": result})
	_write_result("host", result)
	server.stop()

func _run_client(side: String) -> void:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", PORT) != OK:
		_fail("client_connect_failed_%s" % side)
		return
	var deadline := Time.get_ticks_msec() + 15000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		peer.poll()
		await process_frame
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_fail("client_connect_timeout_%s" % side)
		return
	_send(peer, {"type": "hello", "player_id": side})
	var commands := _script_for(side)
	_send(peer, {"type": "commands", "player_id": side, "commands": commands})
	sim = HostSim.new(false)
	var buffer := {"main": ""}
	deadline = Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		for message in _receive(peer, buffer, "main"):
			if message.get("type", "") == "tick":
				for command in message.get("commands", []): sim.submit_command(command)
				sim.step()
			elif message.get("type", "") == "done":
				var result := _result("client_" + side.to_lower(), sim, {side: commands}, sent_bytes, received_bytes)
				result["host_hash"] = message["result"]["ledger_hash"]
				_write_result("client_" + side.to_lower(), result)
				return
		await process_frame
	_fail("client_run_timeout_%s" % side)

func _send(peer: StreamPeerTCP, value: Dictionary) -> void:
	var bytes := (JSON.stringify(value) + "\n").to_utf8_buffer()
	peer.put_data(bytes)
	sent_bytes += bytes.size()

func _receive(peer: StreamPeerTCP, buffers: Dictionary, key: String) -> Array:
	peer.poll()
	var available := peer.get_available_bytes()
	if available > 0:
		var chunk: PackedByteArray = peer.get_data(available)[1]
		received_bytes += chunk.size()
		buffers[key] = buffers.get(key, "") + chunk.get_string_from_utf8()
	var out: Array = []
	while "\n" in buffers.get(key, ""):
		var line: String = buffers[key].get_slice("\n", 0)
		buffers[key] = buffers[key].substr(line.length() + 1)
		var json := JSON.new()
		if json.parse(line) == OK: out.append(json.data)
	return out

func _result(name: String, instance: HostSim, logs: Dictionary, tx: int, rx: int) -> Dictionary:
	var ledger := {"events": instance.get_event_log(), "state": instance.get_state()}
	var canonical := JSON.stringify(ledger)
	var planned_source_commands := 0
	for side in logs: planned_source_commands += logs[side].size()
	return {"participant": name, "ticks_simulated": instance.tick, "match_over": instance.match_over, "winner": instance.winner, "planned_source_commands": planned_source_commands, "commands_applied": instance.get_command_log().size(), "event_count": instance.get_event_log().size(), "ledger_hash": canonical.sha256_text(), "bytes_sent": tx, "bytes_received": rx, "final_state": instance.get_state()}

func _write_result(name: String, result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var file := FileAccess.open(OUTPUT_DIR.path_join(name + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("LOCKSTEP_RESULT " + JSON.stringify(result))

func _fail(reason: String) -> void:
	printerr("LOCKSTEP_FAILURE " + reason)
