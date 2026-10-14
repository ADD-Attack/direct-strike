# Reference — StarCraft II "Direct Strike" (Tya), for the demo clone

Sourced 2026-10-14 from: Blizzard's Arcade announcement, the Havrlant
ultimate guide + counter guides, the Blizzard-forums Standard guide,
the dsstats units database (live), and ds-rating patch notes (current
through 2026-03-31). Where sources disagree or stay silent, this doc
says so — do not invent the missing numbers.

Direct Strike is Tya's successor to Desert Strike HotS (Blizzard
Premium Arcade, 2018; Standard free). **Do not import Desert Strike
mechanics** (the 42×26 grid, 45s rounds, temple, sudden death found in
some search results are Desert Strike 2, a different map).

## The real mod — sourced facts

**Structure.** Standard is 3v3, also 2v2/1v1 (1v1 = one lane — a
documented format). Per lane: a staging area at each end, open
battlefield with a marked middle line between. In front of each main
base stands a defensive structure (Terran "bunker," Protoss "cannon");
gas structures sit behind the staging area. **Win = destroy the enemy
bunker/cannon, then the enemy main base** (Protoss base is the Nexus).
Killing the bunker pays a mineral bounty and is a milestone, not the
win. The bunker alone kills an unopposed first wave — skipping wave 1
is a legitimate opening.

**Building & waves.** Play is continuous — no turn phases. Staged
units deploy on a timer (**every 60 s** in 3v3). You buy **individual
units** (not spawner buildings — that's Desert Strike) and **place
each one at a chosen position in your staging area**; formation is a
core skill (tanks front, DPS behind, burst units split into lines).
You cannot build while your wave is out, but **upgrades bought then
apply instantly** to fielded units. Undeployed units sell back at
**100%**; post-combat, less. Several panel icons right-click-toggle a
paired unit (Roach↔Ravager, Hydralisk↔Lurker, Cyclone↔Widow Mine,
Observer↔Oracle, High Templar↔Archon).

**Economy (corrects our plan — see Adaptations).** Minerals only, no
workers. Income = a **fixed trickle per second** + up to **4 "gases"**
(Refinery/Extractor/Assimilator behind staging — despite the name they
raise *mineral* income; each successive gas costs more for the same
bonus) + a **middle-control bonus**: the side with more units on the
enemy half gets bonus income (forum guide: worth ~2 gases). Paid
**scan costs 25 minerals** (Tier 2, all races). Starting minerals,
trickle rate, and tier unlock costs are **not documented anywhere** —
unknown, not zero.

**Tiers & roster.** Players pick a **race** (Terran/Protoss/Zerg).
**3 paid tiers** bought from the builder panel. **Tier 2 is pivotal:**
cloaked attackers (Dark Templar/Ghost/Banshee/Lurker), mobile
detectors (Observer/Raven/Overseer), and the universal scan. **Tier 4
at 25:00, Tier 5 at 30:00** (then every 5 min) are timed global
upgrades to all units — they unlock no new units. Representative
costs (dsstats, patched often — ballparks): Marine 50, Marauder 95,
Siege Tank 260, Thor 425, Battlecruiser 500 · Zealot 80, Stalker 125,
Immortal 245, Colossus 300 (explicitly T3), Carrier 475, Mothership
700 · Baneling 45, Hydralisk 100, Mutalisk 80, Lurker 310, Brood Lord
325.

**Combat.** Fully AI movement/targeting; waves meet mid-lane,
survivors push to the structures. Counters are SC2 tags (Light /
Armored / Biological / Mechanical / Massive / Psionic) + bonus damage;
splash answers swarms (Baneling, Tank, Hellbat, Colossus, Storm,
Disruptor Nova); many ground units cannot hit air; cloak is answered
by Tier 2 detection + scan. **Player agency during combat exists:**
an ability panel (F3) for autocast toggles and manual casts, instant
upgrades, scan. No heroes, commander powers, or global strikes in
Standard (those are the separate Commanders variant — different
balance, do not mix). Casters spawn at low energy and charge while
marching. Typical match ~18–22 minutes.

**Not documented (do not fabricate):** starting minerals, income/sec,
gas bonus amounts, tier unlock costs, bunker/base HP, build-grid
dimensions, a sudden-death rule.

## Adaptations for this demo (1v1, single player vs AI)

Agreements already in the plan: tug-of-war lane, auto-fighting waves,
minerals, tiers, counters, base-destruction win, full match loop.

Divergences — each is either decided or flagged for the owner:

1. **Economy — DECIDED (owner, 2026-10-14): pivot to the real
   system.** The signed plan's "income scales with total spent" is
   **not** the real mod and is dropped. Slice 1 implements: fixed
   mineral trickle + up to 4 gases (escalating cost) + middle-control
   bonus. The real rates are undocumented, so the Builder's chosen
   numbers are demo tuning, stated in its build notes as such.
2. **Win chain — ADAPT at Slice 5 or earlier slice gate.** Real:
   bunker first (bounty, first-gas trigger), then base. Our Slice 0
   has one base HP pool. Adding the bunker as a front structure is
   high-fidelity, low-cost; schedule it explicitly rather than
   discovering it late.
3. **Formation placement — FLAG for Slice 2.** Real: units are placed
   in formation in a staging area; placement is the core skill. Our
   Slice 1 queues buys into the next wave without placement. A demo
   that skips placement skips the mod's main decision; adding a
   simple staging placement step is the faithful move.
4. **Race pick — FLAG for Slice 2.** Real: three races, three
   rosters. Demo adaptation candidate: one race done well. Owner
   call at the Slice 2 gate.
5. **Continuous build vs build phase — ADAPTED, keep ours.** Our
   discrete build phase (Slice 1) is a legible simplification of the
   real continuous 60 s cycle; keep it, knowingly.
6. **In-combat agency (ability panel, mid-fight upgrades, scan) —
   OUT for now**, per the feature bar; candidate to move "in" after
   Slice 3 if the demo feels too passive.
7. **Pacing — ADAPT.** Real matches run 18–22 min on 60 s waves. A
   demo should conclude faster; wave interval and HP pools get tuned
   for a ~8–12 min match, stated in the slice that tunes them.
