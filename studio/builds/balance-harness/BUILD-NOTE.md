# Balance-harness build note

- **Order:** `op-studio-balance-harness-20261014-1812`
- **Branch:** `builder2/balance-harness`, fast-forwarded against the locally
  cached `origin/main` at `90893db`. `git fetch origin` was attempted first
  but the host's CA bundle rejected GitHub's certificate; no unverified TLS
  bypass was used.
- **Model run:** Codex (GPT-5).
- **Sample status:** **pre-approval sample data** — it is not a balance
  approval or a Slice verdict.

## Inputs and seam

`ds3d/data/roster_stats.json` is the sole authoritative source for Slice 2
unit combat stats. `Host` loads it at startup; it contains no duplicated
per-unit stat table. `ds3d/balance/comps.slice2.json` supplies both matchup
compositions and seeds. The harness turns seeds into ordinary `PLACE_UNIT`
commands, so they affect the command log and formation rather than merely
annotating a result. Each pairing reports A wins, A losses, draws, and average
match length in ticks.

Run the sample without changing simulation code:

```bash
godot --headless --path ds3d -s playtest/run_balance_sweep.gd -- \
  --config res://balance/comps.slice2.json \
  --output res://balance/pre_approval_sample_results.json
```

## Data-only proof

`ds3d/balance/run_data_flip_proof.sh` runs the sample, changes only ranged
damage in `roster_stats.json` from `8.0` to `1.0`, reruns the identical config,
and restores the data file with a shell trap. It compares outputs with the
timestamp removed and fails if the sweep result did not move. Evidence:

- baseline: `ds3d/balance/proof_baseline.json` — ranged vs tank: **5/0/0**,
  average **3081.6** ticks;
- data flip: `ds3d/balance/proof_ranged_damage_1.json` — ranged vs tank:
  **0/5/0**, average **2107.0** ticks.

No simulation-code edit occurs between those two runs.

## Verification

- `godot --headless --path ds3d -s playtest/run_playtest_slice2.gd` — all
  Slice 2 assertions passed, including stats, counters, and determinism.
- inaugural sweep executed successfully; results live in
  `ds3d/balance/pre_approval_sample_results.json`.
