extends "res://scenes/main.gd"

## Evidence-only scene script. Copy the project to a temporary directory,
## attach this to Main.tscn there, clear export's playtest exclusion and export.
## Default = Normal AI, tick 747. ?staging = tick 300 with all three rows queued.
func _ready() -> void:
	super._ready()
	set_physics_process(false)
	var staging_view := OS.has_feature("web") and "staging" in str(JavaScriptBridge.eval("window.location.search"))
	var stop_tick := 300 if staging_view else 747
	var roles := ["frontline_tank", "line_dps", "ranged", "line_dps", "frontline_tank", "ranged"]
	for tick in range(stop_tick):
		var phase: int = tick % Host.BUILD_PHASE_TICKS
		if phase % 80 == 0 and phase < 560:
			var queue_index: int = client.get_state()["queued_units"]["A"]
			client.submit_command("A", "BUY_UNIT", {"role": roles[(tick / 80) % roles.size()]})
			if staging_view:
				client.submit_command("A", "PLACE_UNIT", {"queue_index": queue_index, "row": (tick / 80) % 3})
		if phase == 180:
			client.submit_command("A", "BUY_GAS", {})
		client.step()
	_sync_visuals(0.0)
	_update_hud()
	print("CAPTURE_READY tick=", client.get_state()["tick"], " normal AI; waves=", client.get_state()["wave_count"])
