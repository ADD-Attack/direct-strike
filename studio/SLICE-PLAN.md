# Direct Strike 3D — Demo Slice Plan (DRAFT for owner sign-off)

Drafted 2026-10-14 under The Studio charter. The product: a playable 3D
clone of the StarCraft 2 mod **Direct Strike** — two bases at opposite
ends of a lane; a timed build phase where you spend minerals on units;
waves spawn, march, and auto-fight; income grows with what you've
invested; destroy the enemy base to win. Demo scope: **single player vs
an AI opponent; no multiplayer — but the architecture obeys the
charter's multiplayer rules from Slice 0**, so networking can be added
without a rewrite.

Engine: Godot 4, 3D, web export per slice (playable in a browser).

## Feature bar — what "all features" means for this demo

In: timed build phase · mineral economy · income-per-wave tied to total
spent · unit purchasing with a roster of distinct roles · tier unlocks ·
wave spawning and marching · automatic combat with counters · base HP
and base-destruction win · an AI opponent that buys and adapts ·
full match loop (menu → battle → victory/defeat → restart) · HUD and
camera control · command-log replay · **the multiplayer foundation:
host/client split with a loopback host in single player, deterministic
lockstep simulation, every player (human or AI) acting only through
the command interface** (amended 2026-10-14, owner's direction).

Out (demo): live multiplayer over a network · matchmaking/ladder ·
hero/commander units · cosmetics · saving/meta-progression. Anything
the owner wants moved "in" amends this plan in writing before work
starts on it.

Every slice also ends at a **human checkpoint** (charter, amended
2026-10-14): playtest passes → build publishes → the process STOPS
until the owner plays it and approves, requests changes, or redirects.
No slice auto-advances.

## The slices

Every slice ends in a published, playable web build. Acceptance items
are checked by the slice's scripted playtest against its state ledger —
plus the owner's own play session before the receipt is written.

### Slice 0 — Walking skeleton (size: M)
The lane in 3D: two bases, one unit type. Both sides auto-spawn equal
waves on a timer; units march, meet mid-lane, fight; survivors damage
the enemy base; base HP reaches zero → victory/defeat → restart.
- Playtest asserts: build boots headless; ≥2 waves spawn per side;
  first-contact combat event fires; unit deaths recorded; base HP
  strictly decreases once survivors arrive; a win event fires and the
  match state resets on restart command; **the sim runs in the host
  module with the client connected over the message interface (no
  direct UI→sim calls in the architecture checklist); the same match
  run twice from its command log produces identical event ledgers.**
- Playable: watch a full auto-battle to a conclusion.

### Slice 1 — The economy (size: M)
Build phase with a countdown; minerals; a buy menu for the player
(units queue for the next wave); income paid each wave, scaling with
total minerals spent; the enemy buys from a fixed script.
- Playtest asserts: buy commands debit minerals and appear in the next
  wave's composition; income per wave equals the plan's formula for the
  recorded spend; unaffordable buys are rejected; wave timer cycles
  build → spawn → build.
- Playable: you play the economy; your purchases visibly change waves.

### Slice 2 — Roster & tiers (size: L)
Six unit types across roles (frontline tank, line DPS, ranged,
splash, fast flanker, siege) with explicit counters; tier-2 units
unlock at a spend threshold.
- Playtest asserts: every type spawns with its spec'd stats in the
  ledger; tier-2 buys are rejected before the threshold and accepted
  after; a counter-composed wave defeats an equal-cost mono wave in a
  scripted sim, repeatedly.
- Playable: composition choices matter and are visible.

### Slice 3 — The opponent (size: L)
The enemy becomes a real AI buyer: build orders, composition reactions
(it answers your roster), three difficulty levels.
- Playtest asserts: a full match vs the AI reaches a win/lose
  conclusion inside a time bound at each difficulty; AI spend/income
  ledgers obey the same economy rules as the player's; higher
  difficulty measurably changes AI income efficiency or composition
  quality (not just HP cheats); **the AI plays exclusively through the
  player command interface — its command log is indistinguishable in
  kind from a human's (this is the seam a remote player will occupy).**
- Playable: a real game against an opponent, start to finish.

### Slice 4 — Lockstep over loopback: two clients, one host (size: M)
The multiplayer foundation's proof. The match runs as it would
networked, minus the network: one authoritative host simulation, TWO
clients connected over localhost, each issuing commands for its own
side — plus the standing replay check.
- Playtest asserts: a full match completes with both clients driving
  their own sides through the message interface; both clients' event
  ledgers are identical to the host's at match end (lockstep held);
  a recorded command log replayed into a fresh host reproduces the
  identical ledger hash; simulation advances on fixed timesteps
  independent of render rate.
- Playable: the same game, now demonstrably running in its networked
  shape on one machine — plus a working "watch replay" of your last
  match.

### Slice 5 — Presentation & demo finish (size: M)
HUD (minerals, income, wave timer, both base HP bars), camera
pan/zoom along the lane, menu → match → victory/defeat screens, basic
sound, a demo page that presents the game and its controls.
- Playtest asserts: every HUD value matches the sim state it displays
  at sampled moments; menu → match → conclusion → restart loop
  completes via commands; the demo page serves the final build at a
  stable URL.
- Playable: the demo, whole — the thing the owner shows people.

## Order of work & rules

Slices run in order; a slice's order is dispatched only when the
previous slice has a receipt (or the owner overrides in writing).
Sizes are planning signals, not promises — the playtest ledger is the
truth about what a slice actually cost.

## Sign-off

- [x] Owner approves this plan — **approved by Christopher in chat,
      2026-10-14** ("yeah new builder and let's ship it"), including the
      multiplayer-foundation and human-checkpoint amendments.
- [x] Builder assignment named — **a new dedicated agent,
      `studio-builder`**, created for this project (not one of Cadre's
      fifteen). Provisioning ordered 2026-10-14.
- [ ] Then: Slice 0 is ordered under Step 0 discipline, and the board
      goes up.
