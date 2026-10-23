#!/usr/bin/env bash
# Boots a headless host and a headless client that play a full co-op match over the
# real ENet stack, then checks both reached the same result and checksum. Not part of
# run.sh (it needs two live processes); run it directly to verify networking.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT=${PORT:-24690}
LOG=$(mktemp -d)
"$GODOT" --headless -- --host=$PORT --name=Host --autostart=2 --autoplay >"$LOG/host.txt" 2>&1 &
HOST=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT --name=Client --autoplay >"$LOG/client.txt" 2>&1 &
CLIENT=$!
wait $HOST; wait $CLIENT
echo "--- host ---";   grep -i "autoplay\|error\|drift\|resync" "$LOG/host.txt"   | tail -6
echo "--- client ---"; grep -i "autoplay\|error\|drift\|resync" "$LOG/client.txt" | tail -6
hsum=$(grep -o "checksum [-0-9]*" "$LOG/host.txt"   | tail -1)
csum=$(grep -o "checksum [-0-9]*" "$LOG/client.txt" | tail -1)
fail=0
grep -q "SCRIPT ERROR\|Parse Error" "$LOG/host.txt" "$LOG/client.txt" && { echo "FAIL: script errors"; fail=1; }
[ -z "$hsum" ] && { echo "FAIL: host did not finish"; fail=1; }
[ -z "$csum" ] && { echo "FAIL: client did not finish"; fail=1; }
if [ -n "$hsum" ] && [ "$hsum" = "$csum" ]; then echo "OK: host and client agree ($hsum)"; else echo "MISMATCH: host=[$hsum] client=[$csum]"; fail=1; fi
rm -rf "$LOG"
exit $fail
