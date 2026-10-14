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
