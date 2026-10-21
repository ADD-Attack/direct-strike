# Slice 4 — Lockstep over loopback: two clients, one host — build notes

The match now runs in its networked shape, minus the network. New code
lives in `ds3d/net/`; `sim/` and the Slice 3 gameplay/economy code are
untouched, and Slice 3's own playtest still passes 11/11 unchanged.

## The shape

- **`NetHostSession`** owns the one authoritative `Host` (auto_source
  on, exactly as Slice 3's live game ran it) plus the host's transport
  endpoint. It is the only sim whose state is truth.
- **`NetClient`** is one participant bound to one side. It never touches
  the host. It holds a **replica** `Host` (auto_source off) fed
  exclusively by host tick bundles, and exposes the same read API as
  `MatchClient` (`get_state` / `drain_new_events` / `get_command_log`),
  so render code cannot tell it apart from the old client. Commands for
  a foreign side are refused at the client seam; the match-level
  `RESTART` is the one exception, as before.
- **Rounds are barrier-synchronized.** Each round: both clients
  generate their commands (from their command source, reading only
  their own replica's public state snapshot — the Slice 3 visibility
  rule, unchanged), flush them to the host, and signal `round_ready`.
  Only then does the host step — exactly once — and broadcast a **tick
  bundle**: the commands it actually applied that step, in applied
  order. Each client feeds the bundle into its replica and steps once.
  One round = one fixed tick (1/30 s) everywhere, however the pumps are
  paced.
- **Canonical command order.** Before stepping, the host sorts the
  round's collected commands by (tick, player_id, action, params). The
  applied order is therefore a deterministic function of the round's
  command *set*, never of wire arrival order — intra-round sort keeps
  `BUY_UNIT` ahead of its `PLACE_UNIT`, and exact duplicates are
  interchangeable, so the sort is unobservable beyond determinism.
- **Provenance.** The host records, parallel to its command log, which
  endpoint each applied command arrived from (`client_a`, `client_b`,
  or `host` for sim-generated `SPAWN_WAVE`). The playtest asserts it.
- **Closing the match.** The host broadcasts `match_end` (final tick,
  winner, MD5 of its event ledger); each client checks it against its
  own replica's ledger hash. On TCP, polling is what moves bytes, so
  `NetSession.finish()` pumps until both clients hold the message.

## Transports (one endpoint API: `send(to_id, msg)`, `poll()`)

- **`TcpBus`** — real TCP over 127.0.0.1, star topology,
  newline-delimited JSON envelopes `{from, to, msg}`. The playtest runs
  on it (ports 42337/42338): the two clients are genuinely connected
  over localhost sockets, as the slice demands.
- **`LoopbackBus`** — in-process ordered queues with the same API. The
  playable build runs its session on it (a browser cannot listen on
  TCP); the session logic above the transport is identical.

## The playable build

`scenes/main.gd` now runs the live game as a `NetSession` over
`LoopbackBus`: client A is the UI (renders off its replica), client B
is the Slice 3 AI buyer at the picked difficulty. When a match ends,
the host's recorded command log is captured and a **Watch Replay**
button appears: the log is replayed into a fresh host via the existing
`MatchClient` replay path and rendered like the live game; **Stop
Replay** starts a fresh live session. Buys are inert during replay.

## Playtest

`playtest/run_playtest_slice4.gd` runs the full match twice over TCP —
client A driven by `playtest/scripted_buyer.gd` (the Slice 3 harness's
buying pattern as a pure function of the state snapshot), client B by
the AI buyer on Normal — the second run with disturbed pacing (extra
transport polls + a 1 ms wall-clock delay every round). All assertions
PASS; see `ledger.json` for the full evidence. Headline numbers: match
concludes in 2402 ticks, winner B, 90 commands (31 from client A, 53
from client B, 6 host `SPAWN_WAVE`), 224 events, and **one ledger hash
shared by host, both clients, the fresh-host replay, and the
disturbed-pacing rerun: `10ed8c7c49e324327b2bb4cfd835d6c8`** — the same
hash, tick count, and command counts as Slice 3's recorded Normal
match. The execution shape changed; the game didn't.

Assertions: `boots_headless`, `tcp_loopback_both_clients_connected`,
`full_match_completes_both_clients_drive_own_sides`,
`lockstep_client_ledgers_identical_to_host`,
`replay_recorded_log_reproduces_ledger_hash`,
`fixed_timestep_independent_of_pacing`.

## Reproduce

```sh
godot --headless --path ds3d -s playtest/run_playtest_slice4.gd
godot --headless --path ds3d -s playtest/run_playtest_slice3.gd # regression, 11/11
cd ds3d && godot --headless --path . --export-release "Web" index.html
```

## Notes / deviations

- None against the slice spec. Two transport facts worth recording:
  `StreamPeerTCP.put_data` only buffers — delivery needs the endpoint
  to keep polling, which is why session waits (`wait_connected`,
  `step_round`, `finish`) are all pump loops with small delays. The
  web export ships the TCP class but runs the session on LoopbackBus;
  TCP is exercised headlessly by the playtest, per the slice's
  "minus the network" shape on one machine.
