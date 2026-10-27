#!/usr/bin/env bash
# Boots a headless host and headless clients that play full co-op matches over the real
# ENet stack, then checks both peers reached the same result and checksum. Not part of run.sh
# (it needs live processes); run it directly to verify networking.
#   Scenario 1: host + client play a match.
#   Scenario 2: the client crashes in the lobby and rejoins; it must come back as player 2 of 2
#               (the v0.1.0 playtest bug made it player 3, with a ghost holding player 2's soldiers).
#   Scenario 3: host + client play a whole roguelike run (route votes, nodes, fights) to the end.
#   Scenario 4: the host cuts the client off mid-match; the client must reconnect by itself, get
#               its slot back and finish in step with the host.
#   Scenario 5: host and client each ping and draw on their first turn; each must see the other's.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT=${PORT:-24690}
LOG=$(mktemp -d)
fail=0

# Waits for the host and client of a scenario, but kills them after SCENARIO_TIMEOUT seconds so a hung
# peer fails the scenario instead of hanging CI for hours.
SCENARIO_TIMEOUT=${SCENARIO_TIMEOUT:-240}
wait_peers() {
  local t=0
  while kill -0 $H 2>/dev/null || kill -0 $C 2>/dev/null; do
    sleep 1; t=$((t + 1))
    if [ $t -ge $SCENARIO_TIMEOUT ]; then
      echo "FAIL: scenario timed out after ${SCENARIO_TIMEOUT}s, killing peers"; fail=1
      kill -9 $H $C 2>/dev/null; break
    fi
  done
  wait $H $C 2>/dev/null
}

check() {  # name hostlog clientlog
  local hsum csum
  hsum=$(grep -o "checksum [-0-9]*" "$2" | tail -1)
  csum=$(grep -o "checksum [-0-9]*" "$3" | tail -1)
  if grep -q "SCRIPT ERROR\|Parse Error" "$2" "$3"; then
    echo "FAIL [$1]: script errors"; fail=1
    for f in "$2" "$3"; do  # show each error with the lines leading up to it and its stack
      grep -q "SCRIPT ERROR\|Parse Error" "$f" || continue
      echo "---- $(basename "$f") ----"
      grep -B 8 -A 6 "SCRIPT ERROR\|Parse Error" "$f" | head -120
    done
  fi
  if [ -n "$hsum" ] && [ "$hsum" = "$csum" ]; then echo "OK   [$1]: host and client agree ($hsum)"
  else echo "FAIL [$1]: host=[$hsum] client=[$csum]"; fail=1; fi
  if ! grep -q "I am player 2 of 2" "$3"; then echo "FAIL [$1]: client was not player 2 of 2: $(grep '\[net\] match' "$3")"; fail=1; fi
}

# Scenario 1
"$GODOT" --headless -- --host=$PORT --name=Host --autostart=2 --autoplay >"$LOG/h1.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT --name=Client --autoplay >"$LOG/c1.txt" 2>&1 & C=$!
wait_peers
check "play a match" "$LOG/h1.txt" "$LOG/c1.txt"

# Scenario 2
PORT2=$((PORT + 1))
"$GODOT" --headless -- --host=$PORT2 --name=Host --autostart=2 --autoplay >"$LOG/h2.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT2 --name=Client >"$LOG/dead.txt" 2>&1 & DEAD=$!
sleep 1; kill -9 $DEAD 2>/dev/null; wait $DEAD 2>/dev/null
"$GODOT" --headless -- --join=127.0.0.1:$PORT2 --name=Client --autoplay >"$LOG/c2.txt" 2>&1 & C=$!
wait_peers
check "crash and rejoin in lobby" "$LOG/h2.txt" "$LOG/c2.txt"

# Scenario 3
PORT3=$((PORT + 2))
"$GODOT" --headless -- --host=$PORT3 --name=Host --autostart=2 --autostart-run --autoplay >"$LOG/h3.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT3 --name=Client --autoplay >"$LOG/c3.txt" 2>&1 & C=$!
wait_peers
check "play a run" "$LOG/h3.txt" "$LOG/c3.txt"
grep -q "run finished" "$LOG/h3.txt" || { echo "FAIL [play a run]: the run did not finish"; tail -5 "$LOG/h3.txt"; fail=1; }

# Scenario 4
PORT4=$((PORT + 3))
"$GODOT" --headless -- --host=$PORT4 --name=Host --autostart=2 --autoplay --drop-client-at=6 >"$LOG/h4.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT4 --name=Client --autoplay >"$LOG/c4.txt" 2>&1 & C=$!
wait_peers
check "drop and reconnect mid-match" "$LOG/h4.txt" "$LOG/c4.txt"
grep -q "cutting off player 2" "$LOG/h4.txt" || { echo "FAIL [drop and reconnect mid-match]: the host never cut the client off"; fail=1; }
grep -q "reconnected at action" "$LOG/c4.txt" || { echo "FAIL [drop and reconnect mid-match]: the client did not reconnect"; grep "\[net\]" "$LOG/c4.txt" | tail -5; fail=1; }
grep -q "\[notice\] Client disconnected" "$LOG/h4.txt" || { echo "FAIL [drop and reconnect mid-match]: the host showed no disconnect message"; fail=1; }
grep -q "\[notice\] Client rejoined" "$LOG/h4.txt" || { echo "FAIL [drop and reconnect mid-match]: the host showed no rejoin message"; fail=1; }
grep -q "\[notice\] Connection lost. Reconnecting" "$LOG/c4.txt" || { echo "FAIL [drop and reconnect mid-match]: the client showed no reconnecting message"; fail=1; }

# Scenario 5
PORT5=$((PORT + 4))
"$GODOT" --headless -- --host=$PORT5 --name=Host --autostart=2 --autoplay --autoplay-marks >"$LOG/h5.txt" 2>&1 & H=$!
sleep 2
"$GODOT" --headless -- --join=127.0.0.1:$PORT5 --name=Client --autoplay --autoplay-marks >"$LOG/c5.txt" 2>&1 & C=$!
wait_peers
check "pings and drawing" "$LOG/h5.txt" "$LOG/c5.txt"
for want in "player 1 sees a ping from player 2" "player 1 sees a stroke from player 2"; do
  grep -q "$want" "$LOG/h5.txt" || { echo "FAIL [pings and drawing]: host log lacks '$want'"; fail=1; }
done
for want in "player 2 sees a ping from player 1" "player 2 sees a stroke from player 1"; do
  grep -q "$want" "$LOG/c5.txt" || { echo "FAIL [pings and drawing]: client log lacks '$want'"; fail=1; }
done

rm -rf "$LOG"
exit $fail
