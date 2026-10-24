#!/usr/bin/env bash
# Boots a headless host and headless clients that play full co-op matches over the real
# ENet stack, then checks both peers reached the same result and checksum. Not part of run.sh
# (it needs live processes); run it directly to verify networking.
#   Scenario 1: host + client play a match.
#   Scenario 2: the client crashes in the lobby and rejoins; it must come back as player 2 of 2
#               (the v0.1.0 playtest bug made it player 3, with a ghost holding player 2's soldiers).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT=${PORT:-24690}
LOG=$(mktemp -d)
fail=0

check() {  # name hostlog clientlog
  local hsum csum
  hsum=$(grep -o "checksum [-0-9]*" "$2" | tail -1)
  csum=$(grep -o "checksum [-0-9]*" "$3" | tail -1)
  grep -q "SCRIPT ERROR\|Parse Error" "$2" "$3" && { echo "FAIL [$1]: script errors"; fail=1; }
  if [ -n "$hsum" ] && [ "$hsum" = "$csum" ]; then echo "OK   [$1]: host and client agree ($hsum)"
  else echo "FAIL [$1]: host=[$hsum] client=[$csum]"; fail=1; fi
  if ! grep -q "I am player 2 of 2" "$3"; then echo "FAIL [$1]: client was not player 2 of 2: $(grep '\[net\] match' "$3")"; fail=1; fi
}

# Scenario 1
"$GODOT" --headless -- --host=$PORT --name=Host --autostart=2 --autoplay >"$LOG/h1.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT --name=Client --autoplay >"$LOG/c1.txt" 2>&1 & C=$!
wait $H; wait $C
check "play a match" "$LOG/h1.txt" "$LOG/c1.txt"

# Scenario 2
PORT2=$((PORT + 1))
"$GODOT" --headless -- --host=$PORT2 --name=Host --autostart=2 --autoplay >"$LOG/h2.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT2 --name=Client >"$LOG/dead.txt" 2>&1 & DEAD=$!
sleep 1; kill -9 $DEAD 2>/dev/null; wait $DEAD 2>/dev/null
"$GODOT" --headless -- --join=127.0.0.1:$PORT2 --name=Client --autoplay >"$LOG/c2.txt" 2>&1 & C=$!
wait $H; wait $C
check "crash and rejoin in lobby" "$LOG/h2.txt" "$LOG/c2.txt"

rm -rf "$LOG"
exit $fail
