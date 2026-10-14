#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$root_dir/../studio/builds/lockstep-spike-terra"
mkdir -p "$out_dir"
godot --headless --path "$root_dir" --script res://playtest/lockstep_loopback.gd -- host >"$out_dir/host.log" 2>&1 &
host_pid=$!
sleep 0.4
godot --headless --path "$root_dir" --script res://playtest/lockstep_loopback.gd -- client_a >"$out_dir/client_a.log" 2>&1 &
a_pid=$!
godot --headless --path "$root_dir" --script res://playtest/lockstep_loopback.gd -- client_b >"$out_dir/client_b.log" 2>&1 &
b_pid=$!
wait "$host_pid"
wait "$a_pid"
wait "$b_pid"
test -s "$out_dir/host.json"
test -s "$out_dir/client_a.json"
test -s "$out_dir/client_b.json"
