# Slice 2 — Roster & tiers — build notes

Builder: studio-builder. Order: op-studio-slice2-20261014-1740.

## What's here

- Fetched + fast-forwarded to `origin/main`, then merged
  `builder2/slice2-warmup` into the working branch (one conflict, in
  `sim/host.gd`, where both lines of work touched economy state —
  resolved by hand, keeping both: Slice 1's trickle/gas/middle-control
  economy *and* Builder 2's `PLACE_UNIT`/staging-grid prototype). The
  warm-up's roster models (`ds3d/units/roster_models.json`,
  `ds3d/units/roster_visuals.gd`) are used as-is, unmodified, as the
  actual spawned units' visuals this slice — not a reference, the real
  rig.
- `sim/host.gd` — six roles with real stats (table below), tier-2 gating,
  the counter mechanics (real range advantage, splash AoE, target
  avoidance), and row-based placement that now actually changes
  engagement order (not just cosmetic lateral offset, as it was in the
  warm-up prototype).
- `scenes/main.gd` + `Main.tscn` — one buy button per role (greyed out
  and labelled with the unlock threshold when tier-locked, or when
  unaffordable), three row buttons (Front/Mid/Back) that set where the
  *next* purchase gets placed, gas button unchanged from Slice 1. Buying
  issues `BUY_UNIT` then immediately `PLACE_UNIT` for that same
  queue_index — two commands, same interface, same pattern every other
  action uses.
- `scenes/unit_visual.gd` — rewritten to wrap a `RosterUnitVisual` rig
  (picked by the unit's `role`) instead of the one hardcoded capsule rig;
  keeps the Slice 0-revision-1 march/attack/hit animation, now flashing
  every mesh part on hit instead of just a torso (roles don't all have a
  "torso" in the same place).
- `playtest/run_playtest_slice2.gd` — new canonical playtest; supersedes
  `playtest/run_playtest_slice1.gd` (kept as the historical record tied
  to `studio/receipts/slice-1.json`).
- `studio/builds/slice-2/ledger.json` — full event ledger + command log +
  the roster stat table + all 31 assertions, PASS.

## Roster stat table (demo tuning — stated, not hidden)

| Role | Tier | Cost | HP | Damage | Range | Cooldown (ticks) | Speed (pos/tick) | Splash radius | Bonus vs |
|---|---|---|---|---|---|---|---|---|---|
| Frontline Tank | 1 | 10 | 50 | 4 | 1.0 | 20 | 0.10 | — | — |
| Line DPS | 1 | 10 | 30 | 6 | 1.2 | 20 | 0.12 | — | — |
| Ranged | 1 | 10 | 20 | 8 | 2.4 | 20 | 0.11 | — | Frontline Tank ×1.5 |
| Splash | 2 | 20 | 26 | 6 | 1.4 | 20 | 0.10 | 2.0 | — |
| Fast Flanker | 2 | 15 | 18 | 5 | 1.1 | 18 | 0.20 | — | Siege ×1.3 |
| Siege | 2 | 25 | 20 | 14 | 1.8 | 36 | 0.08 | — | Frontline Tank ×1.5 |

Line DPS is unchanged from Slice 0/1's original unit (same hp/damage/
range/cooldown/speed) — it's the baseline every other role was tuned
against, and the enemy's fixed script still buys it by default, so
Slice 0/1's combat pacing didn't need re-validating from scratch.

**Tier-2 unlock threshold:** `TIER2_UNLOCK_THRESHOLD = 35` cumulative
minerals spent (lifetime, resets on restart) — demo tuning, the real
mod's tier costs are undocumented per `studio/REFERENCE.md`. Chosen so a
side reaches it within its first build phase or two of normal buying,
not instantly and not after several minutes.

## The counter matrix

Per the order's examples and `studio/REFERENCE.md` ("Counters are SC2
tags... + bonus damage; splash answers swarms... many ground units
cannot hit air" — we have no air this slice, so the counters below are
the subset that maps onto a single ground lane):

1. **Ranged outranges Frontline Tank.** This isn't just flavor text: a
   unit now acquires a target the moment an enemy enters *its own*
   range, and if it isn't yet in the target's range back, it closes the
   distance specifically toward that target instead of a generic forward
   march (see "real range advantage" below). Ranged's range (2.4) more
   than doubles Tank's (1.0), so Ranged gets several free hits while
   Tank closes in — on top of the explicit ×1.5 damage bonus. Verified:
   `counter_composition_ranged_beats_mono_tank` (6 Ranged, cost 60, beat
   6 Tank, cost 60 — 4 Ranged survivors reached the enemy base vs 0 Tank
   survivors).
2. **Splash answers swarms.** `splash_radius = 2.0`: every Splash attack
   also damages every other enemy within that radius of the primary
   target, so a cluster of cheap units (which bunch tightly at ~0.5
   lane-units apart) can all take damage from one swing. Verified:
   `counter_composition_splash_beats_mono_swarm` (3 Splash, cost 60, beat
   6 Line DPS, cost 60, despite being outnumbered 3-to-6 — that's the
   point, AoE is what lets fewer, pricier units beat a cheap swarm).
3. **Fast Flanker bypasses the front.** `avoid_roles: ["frontline_tank"]`
   — when scanning for a target, a Flanker prefers any in-range enemy
   that isn't a Tank, and only fights a Tank if nothing else is in range.
   Combined with a ×1.3 bonus vs Siege (fast units closing before the
   slow, high-cooldown siege unit can fire enough times), Flankers
   specifically punish backline/siege compositions. Verified:
   `counter_composition_flanker_beats_mono_siege` (4 Flanker, cost 60,
   beat 2 Siege, cost 50 — the closest affordable equal-cost pairing
   given Siege's price).

All three are run as isolated two-phase clashes (phase 1 is throwaway
filler that gets both sides past the tier-2 threshold the same way a
real match would, phase 2 is the actual equal-cost composition under
test), each a different pairing — "repeatedly" is three independent
demonstrations of three different counters, not one match rerun
(determinism makes literal rerunning tautological: same log, same
result, always).

### Real range advantage (not just a bigger detection circle)

Slice 0/1's combat model: once two units got within either one's range,
both froze and traded blows — range only decided *when* a fight started,
not who got more hits in. That made "outranges" cosmetic. This slice
replaces it: a unit with a target that isn't yet within *its own* range
moves toward that specific target (not a generic forward march) instead
of standing still; it only starts dealing damage once truly in range.
A longer-range unit that spots an enemy from further away gets to attack
while the shorter-range enemy is still closing — genuine, not flavor.

## Formation placement ships — row now changes engagement order

The warm-up prototype's `row` only set a cosmetic lateral offset; `col`
(depth-of-stagger) was the only thing affecting march order, and it
already existed pre-warm-up as the old queue-index stagger. Per this
slice's order, row is now **also** a depth/engagement-order axis: row 0
(front) spawns closer to the enemy, row `STAGING_ROWS-1` (back) spawns
further away, via `ROW_DEPTH_SPACING = 3.0` lane-units per row step. The
centered row (no `PLACE_UNIT` issued) maps to zero extra offset, so an
unplaced wave still reproduces Slice 0/1's exact spawn positions —
nothing in the existing regression suite needed re-tuning for this.
Front-row units simply reach the enemy and engage first as a natural
consequence of starting closer, with no separate priority-queue logic.
Verified: `placement_changes_engagement_order` — a unit placed at row 0
first-engages strictly before a unit from the same wave placed at row 2.

The `queue_index`-addressed `PLACE_UNIT` command itself is unchanged
from the warm-up prototype, per the order ("placement handle stays
queue_index-based per the warm-up prototype").

## One race, no race pick

Per the order and the plan's divergence #4 (flagged for Slice 2, owner
call): one roster, done well, no race-selection UI this slice.

## A bug the stats work caught, twice

Initial stat guesses (Ranged +20% vs Tank, Splash radius 1.3/cooldown
26) lost every counter matchup outright — not a code bug, a tuning one,
found by actually running the isolated clashes and tracing the event log
rather than asserting on hoped-for numbers. Separately, the playtest's
own buy-offset scheduling had a real bug: `since_phase` was computed as
`ticks - last_phase_reset_tick` without a modulo, so the scripted
player's buy schedule only ever fired once, in the very first build
phase, then silently went quiet for the rest of the match (nothing in
Slice 1's assertions depended on buying every phase, so it stayed
invisible there). Fixed to `(ticks - last_phase_reset_tick) %
Host.BUILD_PHASE_TICKS`. Both are documented here rather than quietly
smoothed over.

## Playtest result

All 31 assertions PASS (see `ledger.json`): the full Slice 0+1
regression (architecture, combat, economy, determinism) plus Slice 2's
six — every role spawns with its spec'd stats, tier-2 gating rejects
then accepts correctly, the three counter compositions, and placement
changing engagement order. Determinism replay: the recorded command log
(97 commands, including buy/gas/place) replayed into a fresh host
reproduces an identical 240-event ledger.

## How to reproduce

```
godot --headless --path ds3d -s playtest/run_playtest_slice2.gd
cd ds3d && godot --headless --path . --export-release "Web" index.html
```

---

## SELL_UNIT bake-off extension — 2026-10-14

### What changed

- Added `{tick, player_id, action: "SELL_UNIT", params: {queue_index}}`
  to `sim/host.gd`'s existing action dispatch, alongside `BUY_UNIT`,
  `BUY_GAS`, and `PLACE_UNIT`; the `MatchClient` public surface is
  unchanged.
- A valid sale removes only a queued (not yet spawned) purchase, refunds
  its exact role cost, reverses the net `total_spent` contribution, and
  compacts later queue indices while retaining their placement records.
- Invalid and already-deployed indices emit `sell_rejected` and make no
  command-caused state change.
- Extended `playtest/run_playtest_slice2.gd`; the generated JSON ledger is
  `studio/builds/slice-2/ledger.json` and includes the SELL_UNIT command
  log, event log, resulting state snapshots, and assertion evidence.

### Assertion result

`godot --headless --path ds3d -s playtest/run_playtest_slice2.gd`:
**35/35 PASS**. This includes all **30/30 pre-existing assertions** plus:

1. SELL_UNIT is on the existing command-log dispatch.
2. Exact full-cost refund (10.0 minerals in the exercised roster case).
3. The sold unit is absent from the next wave; the surviving placed unit
   retained its placement after queue compaction.
4. Deployed and invalid indices reject without command-caused state change.
5. The same seven-command log including SELL_UNIT replayed identically
   (7 events in each run).

### Rework and rerun record

The first extension run did not start assertions: GDScript could not infer
three boolean predicate types in the new test. Added explicit `bool` types
and reran. The next run exposed that comparing full unit dictionaries across
two ticks incorrectly treated normal marching as a rejected-command state
change; the assertion now compares command-relevant state and explicitly
accounts for the normal 0.1 mineral tick. Final rerun passed 35/35.
