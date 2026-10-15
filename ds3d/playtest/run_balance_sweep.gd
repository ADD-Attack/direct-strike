extends SceneTree

## Headless, config-driven balance harness. It never changes Host behavior:
## comps/seeds are input JSON and all combat stats remain in roster_stats.json.

const Host = preload("res://sim/host.gd")
const DEFAULT_CONFIG := "res://balance/comps.slice2.json"
const DEFAULT_OUTPUT := "res://balance/pre_approval_sample_results.json"
const PRIMER_ROLES := ["line_dps", "line_dps", "line_dps", "line_dps"]
const PRIMER_SPAWN_TICK := 650
const COMP_START_TICK := 651
const COMP_SPAWN_TICK := 1600
const COMP_WAVE_INTERVAL := 1000
const COMP_WAVES := 4

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var config_path := _arg(args, "--config", DEFAULT_CONFIG)
	var output_path := _arg(args, "--output", DEFAULT_OUTPUT)
	var config := _read_json(config_path)
	if config.is_empty():
		printerr("Balance sweep config could not be read: %s" % config_path)
		quit(2)
		return
	var results: Array = []
	var comps: Dictionary = {}
	for comp in config.get("compositions", []):
		comps[comp["id"]] = comp
	for pair in config.get("pairings", []):
		var a: Dictionary = comps[pair[0]]
		var b: Dictionary = comps[pair[1]]
		results.append(_run_pairing(a, b, config.get("seeds", []), int(config.get("max_ticks", 12000))))
	var output := {
		"label": config.get("label", "unlabeled"),
		"generated_utc": Time.get_datetime_string_from_system(true),
		"engine_version": Engine.get_version_info(),
		"stats_source": "res://data/roster_stats.json",
		"config_source": config_path,
		"results": results
	}
	_write_json(output_path, output)
	for result in results:
		print("%s vs %s: W/L/D %d/%d/%d, avg length %.1f ticks" % [result["a"], result["b"], result["wins"], result["losses"], result["draws"], result["average_match_length_ticks"]])
	print("BALANCE SWEEP: wrote %s" % output_path)
	quit(0)

func _run_pairing(a: Dictionary, b: Dictionary, seeds: Array, max_ticks: int) -> Dictionary:
	var wins := 0
	var losses := 0
	var draws := 0
	var total_ticks := 0
	var trials: Array = []
	for seed_value in seeds:
		var trial := _run_match(a["roles"], b["roles"], int(seed_value), max_ticks)
		trials.append(trial)
		total_ticks += trial["ticks"]
		if trial["outcome"] == "A": wins += 1
		elif trial["outcome"] == "B": losses += 1
		else: draws += 1
	return {"a": a["id"], "b": b["id"], "wins": wins, "losses": losses, "draws": draws, "average_match_length_ticks": float(total_ticks) / max(1, seeds.size()), "trials": trials}

func _run_match(roles_a: Array, roles_b: Array, seed_value: int, max_ticks: int) -> Dictionary:
	var host := Host.new(false)
	# The primer is normal game data/commands, allowing configured tier-2 comps
	# to use the same unlock path as the live game rather than a harness cheat.
	for i in range(PRIMER_ROLES.size()):
		_schedule_buy(host, "A", PRIMER_ROLES[i], i * 100)
		_schedule_buy(host, "B", PRIMER_ROLES[i], i * 100)
	host.submit_command({"tick": PRIMER_SPAWN_TICK, "player_id": "A", "action": "SPAWN_WAVE", "params": {}})
	host.submit_command({"tick": PRIMER_SPAWN_TICK, "player_id": "B", "action": "SPAWN_WAVE", "params": {}})
	for wave in range(COMP_WAVES):
		var buy_start := COMP_START_TICK + wave * COMP_WAVE_INTERVAL
		for i in range(roles_a.size()): _schedule_buy(host, "A", roles_a[i], buy_start + i * 120, seed_value, i)
		for i in range(roles_b.size()): _schedule_buy(host, "B", roles_b[i], buy_start + i * 120, seed_value, i)
		var spawn_tick := COMP_SPAWN_TICK + wave * COMP_WAVE_INTERVAL
		host.submit_command({"tick": spawn_tick, "player_id": "A", "action": "SPAWN_WAVE", "params": {}})
		host.submit_command({"tick": spawn_tick, "player_id": "B", "action": "SPAWN_WAVE", "params": {}})
	while not host.match_over and host.tick < max_ticks:
		host.step()
	var outcome := host.winner if host.match_over else "draw"
	return {"seed": seed_value, "outcome": outcome, "ticks": host.tick, "base_hp": host.base_hp.duplicate(true)}

func _schedule_buy(host: Host, side: String, role: String, tick: int, seed_value: int = 0, queue_index: int = 0) -> void:
	host.submit_command({"tick": tick, "player_id": side, "action": "BUY_UNIT", "params": {"role": role}})
	# Seeded formation rows are ordinary PLACE_UNIT commands. Thus the seed is
	# input to the played command log, not merely a label in the output.
	host.submit_command({"tick": tick, "player_id": side, "action": "PLACE_UNIT", "params": {"queue_index": queue_index, "row": (seed_value + queue_index) % 3, "col": queue_index}})

func _arg(args: Array, name: String, fallback: String) -> String:
	var index := args.find(name)
	return str(args[index + 1]) if index != -1 and index + 1 < args.size() else fallback

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
