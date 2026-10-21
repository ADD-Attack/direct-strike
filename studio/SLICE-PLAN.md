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

**Design inputs:** this plan, `studio/CHARTER.md`, the owner's
checkpoint verdicts, and **`studio/REFERENCE.md`** (added 2026-10-14) —
the sourced breakdown of the real SC2 Direct Strike: structure,
economy, tiers, roster, counters, pacing, plus the demo's adaptation
decisions and divergences. Where this plan and the reference conflict,
the reference names it and the owner rules.

**THE REFERENCE (owner checkpoint ruling, 2026-10-14):** the visual and
structural reference is **StarCraft II's Direct Strike** — a real 3D
RTS battlefield: modeled 3D units and substantial base structures,
terrain with depth, team colors, an angled RTS camera, lighting and
shadows. It is **not** the 2D Direct Strike game's look, and not
diagrams of primitives. The glance test for every slice: a screenshot
reads as a 3D RTS tug-of-war. (Slice 0's first build passed every sim
assertion but read as the 2D version; the owner redirected at the
checkpoint and a presentation revision was ordered — sim untouched.
That is the checkpoint working as designed.)

## Feature bar — what "all features" means for this demo

In: timed build phase · mineral economy (fixed trickle + purchasable
gases + middle-control bonus, per `studio/REFERENCE.md`; the original
income-on-spend line was corrected by research and an owner ruling,
2026-10-14) · unit purchasing with a roster of distinct roles · tier unlocks ·
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
- **Progress:** built + playtest 16/16 PASS 2026-10-14 (commit
  `4f0ab342`). Owner checkpoint verdict 2026-10-14: **CHANGES
  REQUESTED** — presentation reads as the 2D game, not SC2 Direct
  Strike (see THE REFERENCE). Presentation revision built same day
  (commit `b2ad68c`, playtest re-verified 16/16 incl. determinism,
  rendered screenshots in `studio/builds/slice-0/screenshots/`).
  Owner verdict on revision 1, 2026-10-14: **APPROVED as the
  foundation** — the look matures at Slice 5. **Receipt written:**
  `studio/receipts/slice-0.json`. Slice closed.

### Slice 1 — The economy (size: M)
Build phase with a countdown; minerals; a buy menu for the player
(units queue for the next wave); the **real Direct Strike economy**
(per `studio/REFERENCE.md`, owner ruling 2026-10-14): a fixed mineral
trickle, up to 4 purchasable gases that raise the trickle (escalating
cost), and a middle-control bonus paid to the side holding more units
on the enemy half. The enemy buys from a fixed script. Rates are demo
tuning (the real numbers are undocumented) and are stated in the
Builder's build notes.
- Playtest asserts: buy commands debit minerals and appear in the next
  wave's composition; the trickle accrues at the stated rate; a gas
  purchase debits its escalating price and raises the trickle by the
  stated bonus; middle control flips with unit distribution and pays
  only the controlling side; unaffordable buys are rejected; wave
  timer cycles build → spawn → build.
- Playable: you play the economy; your purchases visibly change waves.
- **Progress:** original build (income-on-spend, commit `e3c7ed7`)
  superseded before the gate by the owner's economy pivot ruling;
  rework built same day (commit `4b00fd0`): trickle 3.0/s, gases
  60/120/240/480 at +1.5/s each, middle-control bonus 3.0/s. Playtest
  23/23 PASS incl. determinism, producer-verified. Owner checkpoint
  verdict 2026-10-14: **APPROVED — "Wow perfect."** **Receipt
  written:** `studio/receipts/slice-1.json`. Slice closed.

### Slice 2 — Roster & tiers (size: L)
Six unit types across roles (frontline tank, line DPS, ranged,
splash, fast flanker, siege) with explicit counters; tier-2 units
unlock at a spend threshold.
- Playtest asserts: every type spawns with its spec'd stats in the
  ledger; tier-2 buys are rejected before the threshold and accepted
  after; a counter-composed wave defeats an equal-cost mono wave in a
  scripted sim, repeatedly.
- Playable: composition choices matter and are visible.
- **Progress:** Owner-played **APPROVED** 2026-10-14 18:10 CDT —
  “perfect. Great.” Commit `6ccf266`; playtest 31/31 PASS
  (`all_pass=true`). Receipt: `studio/receipts/slice-2.json`. Slice closed.

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
- **Progress:** built (Slice 3 + rev1, commits `883971f`, `90893db`). Owner playtest 2026-10-20: played the live web build, beat Normal, found Hard genuinely hard. Owner checkpoint verdict 2026-10-20: **APPROVED** — Slice 3 CLOSED; Slice 4 dispatched the same minute (producer-side per Decision 22).

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
- **Progress:** built 2026-10-20 (branch `slice-4-lockstep-loopback`,
  commits `ff679f9`, `a28ea65`, `1a5dc83`, `3a71b6e`). Playtest 6/6
  PASS: full match over real TCP on 127.0.0.1 with both clients
  driving their own sides (provenance-verified), client ledgers
  identical to the host's, replay hash identical, pacing-disturbed
  rerun bit-identical — ledger hash `10ed8c7c49e324327b2bb4cfd835d6c8`,
  the same hash as Slice 3's recorded Normal match. Web export
  refreshed in `ds3d/`. **Awaiting owner checkpoint** — no receipt
  until the owner plays it (charter).

### Slice 5 — Presentation & demo finish (size: M)
HUD (minerals, income, wave timer, both base HP bars), camera
pan/zoom along the lane, menu → match → victory/defeat screens, a demo
page that presents the game and its controls — and **real audio, not
placeholder sound** (amended 2026-10-20): an original music loop plus
combat and UI sound effects produced with the producer's Python music
studio (the music-process pipeline), mixed at game-appropriate levels
with a mute control. Rationale: Star Swarm's value audit (2026-10-20)
found sound is the single largest perceived-value gap in a shipped
game; a demo meant to be shown — and a candidate future product —
does not ship on beeps.
- Playtest asserts: every HUD value matches the sim state it displays
  at sampled moments; menu → match → conclusion → restart loop
  completes via commands; the demo page serves the final build at a
  stable URL; audio events fire on their game events (wave spawn,
  first contact, base under attack, victory/defeat stingers) and the
  music loop runs under the match.
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
      fifteen). Provisioning ordered 2026-10-14. *(Slices 0–3 were built
      by that seat. AMENDED 2026-10-20: per Cadre Decision 22
      (2026-10-16), Studio builds run producer-side with the producer's
      own workers from Slice 4 onward; the fleet's studio builders are
      not the bench. This line is superseded as operative text and kept
      as history.)*
- [ ] Then: Slice 0 is ordered under Step 0 discipline, and the board
      goes up.

## Amendments

- **2026-10-20 (owner-approved in chat):** (1) Builder assignment
  superseded — Studio builds are producer-side from Slice 4 onward
  (Cadre Decision 22); the original `studio-builder` line stands as
  history. (2) Slice 5 audio expanded from "basic sound" to a real
  music loop + SFX scope produced via the Python music studio, with a
  matching playtest assert.
