# Slice 3 revision 2 — camera and staging presentation only

Order: `op-studio-slice3-rev2-20261015-1414`. Base: `90893db`.

- Camera: position `(15.615, 19.170, 23.232)`, looks at `(18, 0, 0)`, FOV 58.
  Position/look-at is the owner-authorized equivalent; distance rounds to 30.215.
- Staging: the presentation root moves by `(7, -0.5, 9.5)`. A 10.6 × 5.1
  metal deck supports the cells, with its upper surface at y = -0.5.
  Its nearest z edge is 6.95, clear of the lane plating (z ±3.2).
  FRONT / MID / BACK labels are enlarged and all remain inside the frame.
- No sim, client, AI, roster, balance, collision or pathing files changed.

## Verification

`godot --headless --path ds3d -s playtest/run_playtest_slice3.gd`: **11/11 PASS**.
Same-log deterministic replay: 90 commands, 2402 ticks, identical event ledgers.
The former rev-1 camera string check now checks the ordered camera/FOV/target
and visual-only staging offset. The full existing match checks remain intact.
Web release export completes with Godot 4.7.2.

## Render evidence

Actual Godot WebGL renders in Chromium, 1600 × 1000 (not synthetic diagrams):

- [Normal AI, frozen tick 747, wave 1 marching](tick-747-normal-wave1.png).
- [Staging at tick 300, three rows populated](staging-tick-300.png).

The evidence-only script `ds3d/playtest/capture_slice3_rev2.gd` extends the
production scene and drives MatchClient through ordinary commands. It freezes
physics after advancing to the specified tick, then syncs the normal visuals/HUD.
Default purchases follow canonical Slice 3 Normal variant 0. `?staging` freezes
at tick 300 and additionally places purchases in the three different rows.

Reproduce in a temporary project copy: change Main.tscn's script to the capture
script, clear that copy's export `playtest/*` exclusion, export Web, serve locally,
open at 1600 × 1000, and capture after `CAPTURE_READY`. The production scene and
export do NOT include the freeze harness; the live game remains playable.

Hand-off: published implementation/evidence for producer verification and owner
playtest; no slice acceptance or next-slice work is claimed.
