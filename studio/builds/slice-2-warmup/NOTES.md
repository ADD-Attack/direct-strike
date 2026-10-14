# Slice 2 warm-up — build notes

Builder: studio-builder-2. Order: op-studio-slice2-warmup-20261014-1701.
Branch: `builder2/slice2-warmup`, based on `studio-slice0-ds3d` (the branch
Builder 1's slice chain is on — `main` in this repo is an unrelated prior
project's history, "Return to Eden"). This is a parallel warm-up, not the
canonical Slice 2 build; Builder 1 owns the slice chain and this branch is
not merged anywhere.

## Correction to the dispatch brief

The order said to read `studio/REFERENCE.md`. That file doesn't exist — I
checked every branch and the live working trees. What exists is **THE
REFERENCE**, a ruling embedded in `studio/SLICE-PLAN.md` (the SC2 Direct
Strike visual/structural bar, added at the Slice 0 checkpoint). I also could
not find the "two design questions" (formation placement in a staging area;
the roster itself) written anywhere in the repo — not in SLICE-PLAN.md's
Slice 2 section, not in CHARTER.md. I've treated the order's own description
of deliverable 1 as the working spec rather than inventing a design doctrine
to match a document that isn't there. Flagging this for the owner/dispatcher
to confirm or correct before Slice 2 is actually ordered.

## 1. Formation placement prototype

**What it proves:** a bought-but-unspawned unit can be assigned a cell in a
staging grid behind the base via a command in the command log, the next
`SPAWN_WAVE` arranges units according to those cells, and the match stays
fully deterministic with placement commands mixed into the log — all without
adding any new path between UI and sim. This is additive to `ds3d/sim/host.gd`
only; `scenes/main.gd`, `Main.tscn`, and the client interface are untouched.

**Command shape:**
```
{tick, player_id, action: "PLACE_UNIT", params: {queue_index, row, col}}
```
- `queue_index` is the purchase's ordinal position in the *current* build
  phase's queue for that side (0-based) — the same ordinal `SPAWN_WAVE`
  already uses to size the wave. There's no unit id yet at placement time
  (units don't exist until spawn), so this is the only stable handle a
  placement command has. The dispatch brief's tuple said "(player, tick,
  unit, cell)" — `queue_index` is what "unit" means here; worth the owner
  confirming this mapping before Slice 2 proper, since the real roster slice
  may want to place units by type/role instead of raw buy order.
- `row` (0..`STAGING_ROWS-1`, default 3 rows) sets lateral spread —
  `lane_offset = (row - 1) * STAGING_ROW_SPACING`, a new field on the spawned
  unit's state dict. **This is cosmetic/formation-tracking only** — combat
  resolution (`_find_engageable_enemy`, base-damage) still runs on the
  existing 1D lane `pos` scalar and does not read `lane_offset`. Whether
  formation should affect engagement (e.g., front-row units soak hits first)
  is a real design question for the Slice 2 gate, not something I decided
  here.
- `col` sets depth-of-stagger along the lane axis, replacing the old
  implicit `queue_index * 0.5` stagger — defaulting `col` to `queue_index`
  reproduces the exact old spacing when unspecified.
- Invalid placements (`queue_index` not currently queued, or `row` out of
  range) emit a `placement_rejected` event and are dropped, same rejection
  pattern as `buy_rejected`.

**Backward compatibility:** with no `PLACE_UNIT` commands issued, every
default (`row` → centered row → `lane_offset = 0`, `col` → `queue_index`)
reproduces Slice 0/1's spawn behavior exactly. Confirmed by re-running
`playtest/run_playtest.gd` and `playtest/run_playtest_slice1.gd` against the
modified `host.gd`: identical tick counts and event counts to the
pre-change baseline (Slice 1: 20/20 PASS, same 3584/7168-tick timings, same
125 events both runs). One pre-existing, unrelated failure: Slice 0's own
`run_playtest.gd` fails `first_contact_fires`/`unit_deaths_recorded` on
*both* the modified and the untouched `e3c7ed7` host.gd — Slice 1's own
commit message already flags this ("that script no longer reflects how the
game is supposed to behave" after wave size became purchase-driven). Not
something this warm-up touched or fixed; flagging it since it's still sitting
there.

**Proof:** `playtest/run_playtest_slice2_warmup.gd` — buys 5 units for side
A, places them in a wedge (`row` pattern 2,1,0,1,2 — reads as an arrow down
the lane), submits one invalid placement, runs the match to a conclusion,
then replays the exact recorded command log into a fresh host and diffs
event ledgers. **11/11 assertions PASS**, including the formation matching
the commanded cells exactly, the invalid placement rejected (not silently
dropped), and determinism holding (49 commands, 67 events, identical on
replay). Ledger: `studio/builds/slice-2-warmup/ledger.json`. Reproduce:
```
godot --headless --path ds3d -s playtest/run_playtest_slice2_warmup.gd
```

## 2. Roster models

Six low-poly rigs for the Slice 2 roles named in `SLICE-PLAN.md`: frontline
tank, line DPS, ranged, splash, fast flanker, siege. Same box-primitive +
`StandardMaterial3D` + team-color technique as the existing
`scenes/unit_visual.gd`/`base_visual.gd` (Slice 0 revision 1's approved
look) — no new art pipeline, same engine-native construction.

- `ds3d/units/roster_models.json` — single source of truth: each role is a
  list of boxes (size, position, color key). `colors.team_a`/`team_b` match
  `scenes/main.gd`'s `COLOR_A`/`COLOR_B` exactly.
- `ds3d/units/roster_visuals.gd` — `RosterUnitVisual`, a `Node3D` that loads
  the JSON and builds the rig for a given role + team color. Not wired into
  `main.gd`/`host.gd` — stats, roles-as-gameplay, and live spawning are the
  real Slice 2 build's job, not this warm-up's.
- Silhouette choices (SC2-readability at a glance): tank = widest/lowest
  with a frontal shield plate; DPS = the existing baseline rig unchanged;
  ranged = tallest/thinnest with a long rifle barrel; splash = a bulbous
  launcher pod on the back; flanker = low and horizontally elongated with
  side blades; siege = biggest footprint, vehicle-like chassis, longest
  cannon.
- Verified in-engine (not just on paper): the warm-up playtest instantiates
  all 6 roles via `RosterUnitVisual.build()` under headless Godot and
  asserts each produces a non-empty mesh rig (`roster_declares_six_roles`,
  `every_roster_role_builds_a_nonempty_rig`, both PASS).

**Contact sheet — why it's an SVG, not a screenshot.** This sandbox's Godot
binary only has the "dummy" rendering driver under `--headless`: confirmed
directly (`get_viewport().get_texture().get_image()` returns null), the same
limitation Slice 0's build notes already documented. Slice 0 worked around
it by loading the *published* GitHub Pages build in a browser — this
warm-up's hard rules explicitly forbid publishing. No Xvfb/software-GL is
installed and I didn't install one (a system package change is outside this
task's scope to decide unilaterally). Instead,
`studio/builds/slice-2-warmup/render_contact_sheet.py` reads the *same*
`roster_models.json` the live rig loads and draws an isometric box
projection per role in both team colors — geometry-accurate, not hand-drawn,
and provably in sync with the real model data since there's only one data
file. Output: `studio/builds/slice-2-warmup/roster_contact_sheet.svg`.
Reproduce: `python3 studio/builds/slice-2-warmup/render_contact_sheet.py`
(stdlib only, no dependencies). A real in-engine screenshot is still owed
once Slice 2 is actually ordered and published — this is a stand-in, not a
substitute for the owner's own glance test.

## Decisions for the owner at the Slice 2 gate

1. Confirm the "REFERENCE flags two design questions" framing — I couldn't
   find that text in the repo; see the correction above.
2. `queue_index`-addressed placement vs. a more durable handle (unit type,
   or a real unit id reserved at buy time instead of at spawn time) — my
   choice was the minimal one that fits today's buy→queue→spawn flow.
3. Whether formation `row`/`lane_offset` should affect combat (front units
   screen back units) or stay purely cosmetic, as it is in this prototype.
4. `STAGING_ROWS = 3`, `STAGING_ROW_SPACING = 0.6`, `STAGING_COL_SPACING =
   0.5` are placeholder tuning, not balanced values.
5. The pre-existing Slice 0 playtest regression (now stale/misleading since
   Slice 1) — not fixed here, flagged for whoever next touches `run_playtest.gd`.

## How to reproduce everything in this note

```
cd ds3d
godot --headless --path . -s playtest/run_playtest_slice2_warmup.gd
cd ../studio/builds/slice-2-warmup
python3 render_contact_sheet.py
```
