# The Studio — Charter

A process for building **one game at a time**, in playable slices, where a
slice is finished only when a scripted playtest has *played* it and the
owner has played it too. Created 2026-10-14 for the Direct Strike 3D demo,
after the Cadre evaluation showed what each existing system cannot do:

- Cadre (standing fleet) ships games, but stalls silently and grades
  itself in status reports.
- The Line (pull factory) verifies claims honestly, but its stations are
  amnesiac — a tax a stateful game codebase pays every slice — and a
  marker string cannot say whether a game is playable.

The Studio takes The Line's honesty, Cadre's one proven builder, and the
one gate neither had: **the playtest**.

## Roles

- **Owner — Christopher.** Signs the slice plan once. Plays every
  published slice; his screen is the final sensor. Kills or redirects
  slices. The only source of new slices.
- **Producer — the operator (Muse).** Keeps the board, dispatches slice
  orders, runs the watchdog, delivers receipts. Never builds, never
  grades, never carries the builder's reasoning into a verdict.
- **Builder — one persistent agent.** Owns the game repo across all
  slices and accumulates real knowledge of the codebase. Its session is
  never reset mid-project. It builds slices and writes the playtest
  scripts for them. It never declares a slice done.
- **Playtest — a script, not an agent.** Boots the exported build
  headlessly, drives it through a command log, and emits a state ledger
  (what spawned, what died, what the base HP did, which win/lose events
  fired) plus frame captures at scripted moments.
- **Verifier — a fresh session per slice.** Reviews the playtest evidence
  (ledger, frames, build hash) against the slice's acceptance list. It
  did not build the slice and cannot patch it.

## The slice lifecycle

`Planned → Ordered → Building → Playtest → Published → Owner-played → Receipt`

1. **Planned.** The slice exists in the signed slice plan with its
   acceptance list. Nothing enters the plan except through the owner.
2. **Ordered.** The producer dispatches the slice as a Step 0 order:
   one named owner (the Builder), a deadline, same-cycle acknowledgment,
   escalation set at dispatch. The watchdog watches it like any Cadre
   order; a stall pings the owner.
3. **Building.** The Builder implements the slice and its playtest
   script, and records build notes in the slice file.
4. **Playtest.** The playtest runs against the exported build. Every
   acceptance item is checked against the ledger and frames. Any failure
   returns the slice to Building with the failing evidence attached —
   once. A second playtest failure on the same slice stops the line:
   the slice was mis-cut, and it goes back to the owner as a design
   question, not a third attempt.
5. **Published.** The passing build is exported to the web and linked.
   Published is not done — it is *playable*.
6. **Owner-played.** The owner plays the slice and records a verdict
   (works / doesn't work, one line is enough). His verdict outranks the
   ledger, always.
7. **Receipt.** Only now: the producer writes the slice receipt
   (playtest ledger summary, build hash, live URL, owner verdict, both
   clocks) and the owner is pinged. No receipt, no completion —
   borrowed from The Line, kept verbatim.

## The playtest standard

- A playtest **plays the game**: it issues commands (buy, deploy,
  start wave) through the same command interface a player — or later, a
  network peer — would use, and observes the simulation's state. It
  never inspects code and calls that a test.
- The ledger is the evidence: timestamped game events, asserted against
  the slice's acceptance list, one assertion per item, PASS/FAIL each.
- Frame captures are taken at scripted moments (first contact, base
  under attack, victory screen) so a human can see what the ledger
  claims.
- Playtest scripts live in the repo beside the game, versioned with it.
  A slice whose playtest cannot run is a failed slice, not a skipped
  step.

## Architecture rules — the multiplayer foundation is BUILT, not intended

Amended 2026-10-14 at the owner's direction: retrofitting multiplayer
onto a finished single-player game is a known disaster, so the demo
stops short of full multiplayer but **builds its foundation from
Slice 0**. The network model is decided now: **deterministic lockstep**
(the model StarCraft itself uses) — every participant runs the same
simulation; only player commands cross the wire, stamped with a tick
and a player id.

1. **Host/client split, even in single player.** The simulation is an
   authoritative host module. The UI is a client that talks to it
   through a defined message interface (commands in, state/events
   out). Single player = a local loopback host. There is no code path
   where the UI touches the simulation directly.
2. **Command-log simulation.** All game-changing inputs are commands
   (player id + tick + action) in a log; the sim consumes commands and
   nothing else. Every participant in a match — local human, AI,
   future remote peer — is a *command source* behind this same
   interface.
3. **Determinism, asserted every slice.** Fixed-timestep simulation,
   independent of rendering. Every slice's playtest runs its match
   **twice from the same command log and asserts identical event
   ledgers**. A determinism failure is a slice failure, from Slice 0
   on — not a Slice 4 surprise.
4. **Sim/render separation.** Game state lives in the simulation;
   rendering only reads it. No gameplay state in scene/UI code, no
   globals that assume exactly one local player.
5. Engine: **Godot 4** (the house engine — Eden's pipeline, web export,
   3D-capable). Every slice publishes a web build.

Still out of scope (the "full-fledged" part): matchmaking, lobby UI,
internet play / NAT traversal, anti-cheat, and saved meta-progression.
The foundation means: when those are wanted, they attach to the
host/client seam and the command interface — nothing gets rewritten.

## Checkpoints — the process STOPS for human review

Amended 2026-10-14 at the owner's direction. The Studio never crosses
a checkpoint on its own:

1. **Plan checkpoint.** No slice is ordered before the owner signs the
   slice plan (and any amendment to it).
2. **Slice checkpoint (every slice).** When a slice's playtest passes
   and the build publishes, **the process halts**. The Builder does not
   start the next slice, and no receipt is written, until the owner
   plays the build and records a verdict: approve (receipt issues,
   next slice may be ordered), request changes (the slice returns to
   Building with the owner's notes as its order), or kill/redirect.
3. **Failure checkpoint.** A second playtest failure on one slice
   (already in the lifecycle below) is a checkpoint, not a retry loop.

Waiting at a checkpoint is a first-class board state — "awaiting
owner" — visibly different from a stall: the work is done, the ball is
named, and the process is *supposed* to be stopped there. The watchdog
does not escalate checkpoints; it reports them once, as designed
stops.

## What The Studio refuses

- Standing committees, producers-of-producers, status reports as
  evidence.
- Fresh-session amnesia for the builder; self-grading for anyone.
- Slices that end in documents. Every slice ends in a playable build or
  an honest stop.

## Amendment

The owner can amend this charter at any time, in writing, in the repo.
The producer records amendments as decisions, with dates, in this file's
history — the same way Cadre's DECISIONS.md works.
