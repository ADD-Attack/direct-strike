#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stats="data/roster_stats.json"
backup="$(mktemp)"
trap 'mv "$backup" "$stats"' EXIT
cp "$stats" "$backup"
godot --headless --path . -s playtest/run_balance_sweep.gd -- --config res://balance/comps.slice2.json --output res://balance/proof_baseline.json
sed -i '0,/"damage": 8.0/s//"damage": 1.0/' "$stats"
godot --headless --path . -s playtest/run_balance_sweep.gd -- --config res://balance/comps.slice2.json --output res://balance/proof_ranged_damage_1.json
baseline_summary="$(mktemp)"
changed_summary="$(mktemp)"
trap 'mv "$backup" "$stats"; rm -f "$baseline_summary" "$changed_summary"' EXIT
sed '/"generated_utc"/d' balance/proof_baseline.json > "$baseline_summary"
sed '/"generated_utc"/d' balance/proof_ranged_damage_1.json > "$changed_summary"
if cmp -s "$baseline_summary" "$changed_summary"; then
  echo "ERROR: data flip produced identical sweep output" >&2
  exit 1
fi
echo "Data-flip proof written: balance/proof_baseline.json and balance/proof_ranged_damage_1.json"
