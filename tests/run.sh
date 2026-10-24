#!/usr/bin/env bash
# Runs the headless test suite, then the UI text overflow sweep (tests/ui_overflow_sweep.gd).
# Fails on test failures, cut text, AND on any script/parse error, since Godot keeps running
# after those.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless -s tests/run_tests.gd 2>&1)
code=$?
echo "$out"
if echo "$out" | grep -q "SCRIPT ERROR\|Parse Error\|Compile Error"; then
  echo "Script errors detected"
  exit 1
fi
[ $code -ne 0 ] && exit $code
out=$("$GODOT" --headless -s tests/ui_overflow_sweep.gd 2>&1)
code=$?
echo "$out" | grep -v "^\s*at:\|leaked\|Pages in use\|resources still\|^WARNING: ObjectDB"
if echo "$out" | grep -q "SCRIPT ERROR\|Parse Error\|Compile Error"; then
  echo "Script errors detected in the UI sweep"
  exit 1
fi
exit $code
