# Slice 0 — Walking Skeleton — build notes

Builder: studio-builder. Order: op-studio-slice0-20261014-1435.

## What's here

- `ds3d/` — the Godot 4.7 project (3D). `sim/host.gd` is the authoritative
  host module (pure data simulation, no scene-tree dependency). `client/match_client.gd`
  is the only thing UI/render code is allowed to call — a local-loopback
  wrapper over Host's command interface. `scenes/Main.tscn` + `main.gd` is the
  render/UI layer: lane, two bases, capsule units, HUD, camera; it calls only
  `MatchClient` methods, never `host.` directly (the playtest asserts this by
  grepping the source). `playtest/run_playtest.gd` is the scripted playtest.
- `studio/builds/slice-0/ledger.json` — the full event ledger + command log +
  every assertion with PASS/FAIL and a one-line detail, from the last playtest
  run.
- `studio/builds/slice-0/frames/*.json` — structured state snapshots at
  first contact, first base damage, and victory (see "Frame captures" below
  for why these are JSON, not PNG).

## Architecture (per charter)

- **Host/client split, live in Slice 0.** `Host` (RefCounted, no Node) holds
  all gameplay state and exposes exactly one write path — `step()` plus
  commands queued via `submit_command()` — and read-only snapshots via
  `get_state()` / `get_event_log()` / `get_command_log()`. `MatchClient` wraps
  a `Host` as a local loopback and is the sole interface the 3D scene talks
  to. There is no code path from `scenes/main.gd` into `Host`.
- **Command-log simulation.** Every game-changing input — including the
  auto-spawned waves — is a `{tick, player_id, action, params}` command
  appended to `command_log`. The "auto-source" that spawns waves on a timer
  is just another command source (`player_id` = the side's name), exactly
  the seam a human or a future remote peer occupies later.
- **Determinism.** No RNG anywhere in the sim. Fixed-tick `step()`, no
  wall-clock reads. The playtest proves it by recording a full run's
  `command_log`, replaying that exact log into a *fresh* `Host` in replay
  mode, and diffing the two event ledgers — asserted identical.
- **Sim/render separation.** `main.gd` reads `get_state()` snapshots and
  diffs them against its own visual-node bookkeeping; it holds no gameplay
  truth itself.

## A design choice worth flagging: combat tie-breaking

Units are identical (one unit type, per the slice), so a perfectly
simultaneous clash of equal-sized waves would in principle annihilate both
sides with zero survivors — which would make "survivors damage the enemy
base" impossible to ever observe. Combat resolution iterates units in
ascending id order each tick; when two units are both off cooldown on the
same tick, the lower-id unit's attack lands and is checked for a kill before
the higher-id unit gets its turn. This produces a consistent (not random)
survivor pattern instead of mutual-annihilation lockstep, which is what lets
survivors reliably break through to the base. It is a deliberate simplicity
choice for the walking skeleton, not a balance claim — Slice 2 introduces
real unit roles and counters, where this will need revisiting.

Wave interval was tuned to 650 ticks (~21.7s at 30 ticks/sec): shorter
intervals (tried 180 ticks) cause reinforcements to arrive faster than a
clash can resolve and march to the enemy base, producing an endless
mid-lane meat-grinder that never lets anyone reach a base — verified by a
standalone dry run that ran 50k ticks with zero `base_damage` events before
the fix.

## Frame captures: JSON snapshots, not PNG

The charter asks for frame captures at scripted moments. In this sandbox,
instantiating any Godot Viewport/3D scene under `--headless` hangs
indefinitely (no GPU, no EGL/X11 display — confirmed via a throwaway smoke
test before building). Real pixel capture isn't available to the playtest
process here. `frames/*.json` instead hold the full sim-state snapshot
(`triggering_event` + `get_state()`) at the same three moments (first
contact, base under attack, victory) — a human can reconstruct exactly what
was on screen from `units`, `base_hp`, `tick`. The real 3D scene renders
normally for an actual player in a real browser (WebGL) — that part isn't
affected by this sandbox's limitation, only the playtest's own screenshot
step is.

Separately: this environment's own sandboxed browser tool reports
`webgl: unavailable_software` and blocked localhost navigation, so the build
could not be visually smoke-tested in a browser from here either. The
headless playtest exercises the exact same `sim/`+`client/` code the 3D
scene calls, so gameplay logic is verified; the owner's own browser is the
first real visual check, consistent with the charter's checkpoint.

## How to reproduce

```
# run the playtest (writes ledger.json + frames/*.json)
godot --headless --path ds3d -s playtest/run_playtest.gd

# re-export the web build (writes ds3d/index.html, .js, .wasm, .pck)
cd ds3d && godot --headless --path . --export-release "Web" index.html
```

## Playtest result

All 15 assertions PASS (see `ledger.json`). Covers: boots headless, both
matches conclude, restart resets state, host/client separation + message
interface + fixed-tick + no-direct-UI-to-sim checks, ≥2 waves per side,
first contact, deaths, strictly-decreasing base HP once survivors arrive
(reset correctly across the restart boundary), win event, restart event
recorded in the ledger, and the determinism replay match.
