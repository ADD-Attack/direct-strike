# SELL_UNIT build note

Branch: `builder2/bakeoff-sol`
Base: `origin/main` at `6ccf266c6a72acc1431da763bd776d4f9e796121`

## Built

- Added `{tick, player_id, action: "SELL_UNIT", params: {queue_index}}` to the authoritative host's existing command-log dispatch.
- A valid queued purchase is removed and its role's full purchase cost is refunded. Placement entries for later queue indices shift with their purchases.
- Missing, out-of-range, and already-deployed indices emit `sell_rejected` with no refund or queue mutation.
- Added a headless playtest and committed JSON ledger at `studio/builds/sell-unit/ledger.json`.

## Assertions

- SELL_UNIT playtest: **10/10 PASS**, including exact refund, absence from the next wave, invalid/deployed rejection without refund, generic message-interface routing, and identical replay ledger.
- Current pre-existing Slice 2 canonical suite: **30/30 PASS**.
- Pre-existing Slice 2 warm-up suite: **12/12 PASS**.
- Current applicable total: **52/52 PASS**.

The two older scripts explicitly marked superseded/historical were also attempted. The Slice 0 script reaches **14/16** because its historical scenario no longer creates symmetric combat under the current Slice 2 host; the Slice 1 script does not parse because it still references the removed pre-roster `Host.UNIT_COST`. Neither issue is touched by SELL_UNIT; the current canonical suite supersedes both scripts.

## Rework / reruns

- The first new playtest invocation stopped at parse time because Godot 4.7 could not infer four compound-expression local types. I added explicit `bool` annotations and reran it: **10/10 PASS**.
- The task named `studio/PLAN.md`, which is absent at the requested base commit. I used the signed `studio/SLICE-PLAN.md` referenced by `studio/CHARTER.md`, and also read `studio/REFERENCE.md` before implementation.
