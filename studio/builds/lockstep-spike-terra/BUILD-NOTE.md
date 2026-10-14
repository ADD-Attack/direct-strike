# Early lockstep spike — `builder2/lockstep-spike-terra`

Base: `origin/main` at `6ccf266` (Slice 2). This is an early technical
spike, not a Slice 4 delivery or acceptance claim.

## Transport and topology

- **Transport:** raw loopback TCP using Godot 4's `TCPServer` and
  `StreamPeerTCP`, bound to `127.0.0.1:19447`.
- **Why TCP:** this probes real process-to-process socket ordering while
  keeping the protocol visible and minimal: newline-delimited JSON only.
  It avoids coupling this proof to a Godot scene tree or UI multiplayer API.
- **Processes:** one `host` and two independent clients (`client_a`,
  `client_b`), all Godot headless instances. Each participant constructs its
  own `Host` simulation. The clients submit different complete scripts made
  of `BUY_UNIT`, `BUY_GAS`, and `PLACE_UNIT`; the host sorts by
  `(tick, player_id, source_seq)` and broadcasts the resulting per-tick
  command batch. The host-owned phase clock likewise broadcasts its
  `SPAWN_WAVE` commands rather than letting clients infer them from time.
- **Launch:** `cd ds3d && bash playtest/run_lockstep_spike.sh`. The script
  launches the host, then both clients with `godot --headless --script
  res://playtest/lockstep_loopback.gd -- <role>` and waits for all three.

## Result — PASS for this narrow proof

The completed run reached a B-side win at simulation tick **4,409**.
All three independent ledgers (event log plus final state) hash to:

```
8e1e6e52459b7bee1f2654e112ad2725d497dfdaeb2c9567fb47a610fa69a2f6
```

| participant | ledger hash | commands applied | events | final base HP |
|---|---|---:|---:|---|
| host | `8e1e…a2f6` | 166 | 365 | A 0 / B 150 |
| client A | `8e1e…a2f6` | 166 | 365 | A 0 / B 150 |
| client B | `8e1e…a2f6` | 166 | 365 | A 0 / B 150 |

Raw participant results are versioned beside this note as `host.json`,
`client_a.json`, and `client_b.json`. No divergence occurred.

## Measured shape

- **Simulation:** 4,409 fixed ticks at the existing 30 Hz rate (about 147.0
  simulated seconds); the host does not yield per tick, so advancement is not
  coupled to render frames.
- **Commands:** 99 scripted commands from each client were offered (198
  planned); 166 total commands were applied before match end, including the
  host-broadcast wave commands.
- **Wire:** client A sent 9,970 bytes; client B 10,132 bytes. Each client
  received 202,197 bytes; the host received 20,102 bytes and sent 402,322
  bytes total. This uncompressed proof broadcasts a JSON batch every tick,
  including empty batches: about 1.37 KB/s downstream per client at 30 Hz
  (roughly 46 bytes/tick), plus command-bearing frames.

## What this retires for Slice 4

It retires the basic unknown of whether the current deterministic `Host` can
be run independently in one host and two clients while real loopback sockets
carry ordered command batches. It also demonstrates that the existing
`BUY_UNIT` / `BUY_GAS` / `PLACE_UNIT` command seam supports different remote
command sources without simulation divergence in one complete match.

## Open risks deliberately left open

- TCP head-of-line blocking, packet loss/reordering, reconnects, and latency
  policy (the loopback TCP transport is reliable and local).
- Input delay, late-command handling, tick acknowledgements, catch-up, and
  host/client clock synchronization.
- Join-in-progress, host migration, disconnect authority, authentication,
  anti-cheat, and any internet/NAT behavior.
- Bandwidth efficiency: this sends an empty JSON frame every tick; batching,
  binary encoding, compression, and state-resync are unproven.
- Replay recording/replay-hash acceptance and render-rate tests as formal
  Slice 4 playtest assertions; this spike does not implement the replay UI.
- Broader determinism surfaces (engine/platform versions, floating-point
  differences, random sources, and a soak/fuzz test corpus).

## Source-plan note

The dispatched filename `studio/PLAN.md` was not present in the fetched
repository. `studio/SLICE-PLAN.md` contains the relevant Amendment 1/Slice 4
criteria and was used with `studio/REFERENCE.md` and `studio/CHARTER.md`.
