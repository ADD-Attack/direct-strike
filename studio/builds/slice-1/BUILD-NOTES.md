# Slice 1 — The Economy — build notes

Builder: studio-builder. Order: op-studio-slice1-20261014-1555.

## What's here

- `sim/host.gd` — extended with the economy: minerals, spend tracking, a
  fixed deterministic enemy buy script, and a build-phase cycle that pays
  income and spawns waves from purchased counts instead of a fixed size.
  Everything else (combat, base damage, win, restart) is unchanged.
- `scenes/main.gd` + `scenes/Main.tscn` — added a buy button + `B` keybind
  (both call `client.submit_command("A", "BUY_UNIT", {})`, the same
  interface every other command uses) and HUD fields for minerals, total
  spent, next income, and the build-phase countdown. No other presentation
  work this slice, per the order — the rev-1 look stands until Slice 5.
- `playtest/run_playtest_slice1.gd` — the new canonical playtest; supersedes
  `playtest/run_playtest.gd` (Slice 0's script, kept only as the historical
  record tied to the already-written `studio/receipts/slice-0.json` — Slice
  0's "both sides auto-spawn a fixed wave size" behavior was intentionally
  replaced this slice by purchase-driven composition, so running the old
  script against the current sim would now fail: side A would never buy
  anything and would field empty waves forever).
- `studio/builds/slice-1/ledger.json` — full event ledger + command log +
  all 20 assertions, PASS.

## The economy, as implemented

- **Minerals.** Each side starts with `STARTING_MINERALS = 50`.
- **Unit cost.** `UNIT_COST = 10` minerals per unit (the existing unit
  type — no new roster this slice).
- **Income formula** (paid once per build-phase boundary, before that
  phase's purchases, same formula both sides):
  `income = BASE_INCOME + floor(total_spent * INCOME_RATE)`
  with `BASE_INCOME = 10`, `INCOME_RATE = 0.15`. `total_spent` is each
  side's lifetime mineral spend (resets to 0 on restart). Verified by the
  playtest against every `income_paid` event in the ledger — 20/20 matched
  exactly.
- **Build phase.** `BUILD_PHASE_TICKS = 650` (~21.7s at the sim's 30
  ticks/sec) — the same cadence Slice 0 tuned for combat pacing, reused
  deliberately so wave timing that was already proven to let survivors
  reach the base didn't need re-validating from scratch. At every boundary:
  pay income (both sides) → spawn a wave per side sized to whatever that
  side queued since its last wave → reset the queue. This is a direct,
  minimal evolution of Slice 0's fixed-interval auto-spawn: same timer,
  now driven by purchases instead of a constant.
- **Enemy fixed buy script.** Deterministic, no RNG: side B issues one
  `BUY_UNIT` command at ticks `phase_start + 30`, `+90`, `+150` every
  phase — 3 units/phase if affordable. This is "the enemy buys from a
  fixed script" per the order; it is a command source behind the same
  interface a human or (Slice 3) an AI would use, not a special code path.
- **Rejection.** `BUY_UNIT` debits `UNIT_COST` only if
  `minerals[side] >= UNIT_COST`; otherwise it emits `buy_rejected` and
  changes nothing. Checked authoritatively in the host at application
  time, not trusted from the submitter.
- **All purchases are commands.** `{tick, player_id, action: "BUY_UNIT",
  params: {}}`, applied and logged exactly like `SPAWN_WAVE`/`RESTART`
  always were. `PAY_INCOME` and the economy-aware `SPAWN_WAVE` are also
  generated as logged commands (same pattern Slice 0 used for the old
  auto-wave timer), so the whole economy is replayable from the command
  log — nothing about it lives outside the log.

## A consequence worth flagging: wave sizes are now asymmetric by design

With the player (playtest) buying up to 5/phase and the fixed script
buying exactly 3/phase, waves are no longer equal-sized. This turned out
to strengthen Slice 0's survivor mechanism rather than compete with it:
the side with more units in a given clash gets automatic unengaged
survivors (nothing left on the other side to pair against), on top of the
ascending-id tie-break noted in the Slice 0 build notes. Both winners were
observed across playtest runs (A won in the Slice 0 regression tuning run,
B won in the committed ledger's run) depending on exactly how the economy
plays out — this is economy-driven variance, not a bug; nothing here is
balance-tuned yet (that's explicitly Slice 2/3 territory).

## Playtest bug caught and fixed before this ledger

The first playtest run failed `buy_commands_debit_minerals_and_join_next_wave`
across the restart boundary — not a sim bug. The assertion's own purchase
tracker didn't reset on `match_restarted`, so a purchase stranded right
before a restart (queued but never spawned, because match_over gates the
phase cycle) got wrongly carried over and blamed on the first wave of the
next match segment. `Host._do_restart()` already discards unspawned queues
and resets `total_spent` correctly; the playtest tracker now mirrors that
on `match_restarted`. Left both the failure and the fix in the ledger
history's spirit — documented here rather than silently rewritten.

## Playtest result

All 20 assertions PASS (see `ledger.json`), including the full Slice 0
regression suite (architecture, first contact, deaths, strictly-decreasing
base HP, win, restart) plus Slice 1's four: buys debit minerals and match
the next wave's composition exactly; income matches the formula on every
payment; unaffordable buys are rejected (and never incorrectly, i.e. never
rejected while actually affordable); the build→spawn→build timer holds a
constant `BUILD_PHASE_TICKS` cadence except across the one restart
boundary. Determinism replay: the recorded command log (89 commands, now
including buys/income) replayed into a fresh host reproduces an identical
125-event ledger.

## How to reproduce

```
godot --headless --path ds3d -s playtest/run_playtest_slice1.gd
cd ds3d && godot --headless --path . --export-release "Web" index.html
```

## Rework: pivot to the real Direct Strike economy (same-day)

Everything above this line describes the **first** Slice 1 build
(commit `e3c7ed7`, income-on-spend). While it was in flight, the producer
researched the real SC2 Direct Strike mod and found the signed plan's
economy ("income scales with total minerals spent") doesn't match it —
written up in `studio/REFERENCE.md`, escalated as DECISION PENDING, and
ruled on by the owner same day: **pivot to the real system, income-on-spend
dropped** (`studio/SLICE-PLAN.md`, divergence #1, DECIDED). I only learned
of this by checking git in response to a producer status prod, since no
dispatch for the rework had reached this session directly — see that
prod's reply in the session transcript for the full account. Everything
below replaces the formula and assertions above; the rest of Slice 1 (buy
command interface, wave-from-purchases, command-log determinism) was
already built correctly and didn't need touching.

**New formula** (real rates are undocumented per REFERENCE.md — these are
stated demo tuning):
- **Fixed trickle.** Continuous, not paid per-wave:
  `minerals[side] += trickle_rate[side] / TICK_RATE(30)` every single
  tick. `trickle_rate` starts at `BASE_TRICKLE_PER_SEC = 3.0`/s.
- **Up to 4 gases**, escalating cost `GAS_COSTS = [60, 120, 240, 480]`;
  each successful `BUY_GAS` adds `GAS_TRICKLE_BONUS_PER_SEC = 1.5`/s to
  that side's trickle permanently. A 5th attempt is rejected
  (`reason: "max_gases_reached"`), not just unaffordable.
- **Middle-control bonus**, `MIDDLE_CONTROL_BONUS_PER_SEC = 3.0`/s (set to
  `2 × GAS_TRICKLE_BONUS_PER_SEC`, matching REFERENCE.md's cited forum-guide
  estimate of "worth ~2 gases"). Recomputed every tick, authoritatively, by
  counting each side's alive units on the *enemy* half of the lane
  (`pos > LANE_LENGTH/2` for A, `pos < LANE_LENGTH/2` for B); whichever
  side has strictly more gets the bonus added to its per-tick accrual that
  tick, the other gets none. A `middle_control_changed` event is emitted
  only when the controller actually changes (ledger breadcrumb, not the
  authoritative source — the host recomputes fresh every tick).
- **`PAY_INCOME` is gone.** Income is no longer a discrete per-wave
  command; it's continuous state mutation alongside unit movement, gated
  the same way (`not match_over`), and — importantly — **not** gated
  behind `auto_source_enabled`, so it still runs correctly during
  deterministic replay (it's not an externally-sourced command, just a
  pure function of tick/state, same category as combat resolution).
- **Enemy script extended**: still 3 unit buys/phase at fixed offsets, plus
  one `BUY_GAS` every 3rd phase at a fixed offset — still fully
  deterministic, no RNG, so it doesn't out-economy the player (and the
  player's AI opponent in Slice 3 will need real tuning, not this).
- **Unaffordable rejection** unchanged in spirit: checked authoritatively
  against the live balance at application time, two reasons now
  (`insufficient_minerals`, `max_gases_reached`).

**Verifying "trickle accrues at the stated rate" + "middle control...pays
only the controlling side" together.** Rather than spot-sampling a quiet
window, the playtest **reconstructs the entire match's minerals from the
public ledger alone** — walking every `unit_purchased` / `gas_purchased` /
`middle_control_changed` / `match_restarted` event in tick order, applying
the stated formula tick-by-tick between events — and asserts the
reconstruction matches the host's actual final `minerals` state (within
0.01, for float accumulation). This is a stronger proof than a sampled
window: it's the whole match's economy, independently re-derived from
nothing but what a real client could observe, matching exactly. It passed
on the first run of the new formula.

**HUD/buy menu changes to match:** "Total spent / Next income" replaced
with "Trickle A: X/s · Gases: N/4 · Middle control: —/A (you)/B (enemy)";
added a second buy button for gas. Keybinds: unit buy is `U`, gas buy is
`G`, restart stays `R`. No other presentation work, per the order.

**Playtest result (rework):** all 22 assertions PASS — the prior 20 minus
`income_per_wave_matches_formula` (removed, the mechanic it tested no
longer exists) plus five new ones: the ledger-reconstruction match, gas
cost/trickle-bonus correctness, middle-control flip correctness, the
updated `buy_commands_debit_minerals_and_join_next_wave` (unit-purchase
path, unchanged logic), and `restart_resets_match` adjusted to expect
~50.5 minerals (not exactly 50) after the 5 post-restart ticks the
playtest steps before sampling — trickle is continuous now, so a few
ticks of accrual between the reset and the sample is correct, not a bug.
Determinism replay still holds with the new commands in the log.
