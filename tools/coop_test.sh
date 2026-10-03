#!/usr/bin/env bash
# Two headless bots play co-op against a relay. Usage: tools/coop_test.sh [server] [seconds] [players]
# Start a local relay first (see README) or pass the production server URL.
set -u
cd "$(dirname "$0")/.."
SERVER=${1:-http://127.0.0.1:8792}
SECS=${2:-60}
N=${3:-2}
HOST_LOG=$(mktemp); GUEST_LOGS=()
timeout "$SECS" godot4 --headless --path . -- --coop=host --players="$N" --autoplay --speed=2 --char=matt --server="$SERVER" > "$HOST_LOG" 2>&1 &
for i in $(seq 1 40); do CODE=$(grep -o '\[room\] [A-Z0-9]\{4\}' "$HOST_LOG" | head -1 | cut -d' ' -f2); [ -n "$CODE" ] && break; sleep 0.5; done
echo "room: ${CODE:-none}"
CHARS=(alex jon joe)
for g in $(seq 2 "$N"); do
  L=$(mktemp); GUEST_LOGS+=("$L")
  timeout "$((SECS - 2))" godot4 --headless --path . -- --coop=join --room="$CODE" --autoplay --speed=2 --char="${CHARS[$(( (g - 2) % 3 ))]}" --server="$SERVER" > "$L" 2>&1 &
done
wait
echo "== host"; grep -E "^\[|SCRIPT ERROR|ERROR:" "$HOST_LOG" | grep -v X509 | tail -8
for L in "${GUEST_LOGS[@]}"; do echo "== guest"; grep -E "^\[|SCRIPT ERROR|ERROR:" "$L" | grep -v X509 | tail -8; done
