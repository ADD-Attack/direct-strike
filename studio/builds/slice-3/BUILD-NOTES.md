# Slice 3 — The opponent — build notes

The fixed-script enemy is retired. `sim/ai_buyer.gd` is a deterministic
command source owned by `MatchClient`, not `Host`: it returns only
`BUY_UNIT`, `BUY_GAS`, and `PLACE_UNIT` commands, which are appended to the
same command log as player commands. Every AI command records its seeded RNG
state and difficulty in `params`; the host has no AI decision backdoor.

## Visibility rule

Before each decision the AI may read only `MatchClient.get_state()`:
current tick, public economy, wave/queue counts, middle controller, and
fielded units/roles. It cannot inspect Host internals, future commands, or
the player's queued roles. Decisions occur on its difficulty cadence and use
the recorded deterministic LCG seed.

## Difficulty tuning

| Difficulty | Cadence | Economy | Composition / placement |
|---|---:|---|---|
| Easy | 150 ticks | No gas | Near-random tier-1 opening/buys |
| Normal | 75 ticks | Reserves after tick 300; buys gas at phase tick 550 | Counters player's most-fielded visible role; center row |
| Hard | 45 ticks | Reserves after tick 180; buys gas at phase tick 585 | Counter-comps and reinforces front row when A controls middle |

## Playtest

`playtest/run_playtest_slice3.gd` runs four fixed player variants per
difficulty. Results: Easy 0% B wins; Normal 100%; Hard 100%. It asserts full
matches for all difficulties, command-interface-only proof, same-log replay
determinism, Normal > Easy and Hard > Easy, plus architecture/economy/combat/
roster regression coverage from Slices 0–2. See `ledger.json` for the full
command/event evidence and assertion list.

## Reproduce

```sh
godot --headless --path ds3d -s playtest/run_playtest_slice3.gd
cd ds3d && godot --headless --path . --export-release "Web" index.html
```
