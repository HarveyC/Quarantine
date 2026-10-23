#!/usr/bin/env bash
# Exports Windows, macOS and Linux builds and zips each with HOW-TO-PLAY.txt into build/dist/.
# Usage: release/build.sh [path-to-godot] [version-label]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-godot}"
VERSION="${2:-dev}"
rm -rf build && mkdir -p build/windows build/linux build/mac build/dist
"$GODOT" --headless --import >/dev/null 2>&1 || true
for preset in Windows Linux macOS; do
  out=$(case $preset in Windows) echo build/windows/Quarantine.exe;; Linux) echo build/linux/Quarantine.x86_64;; macOS) echo build/mac/Quarantine.zip;; esac)
  "$GODOT" --headless --export-release "$preset" "$out" 2>&1 | grep -v "^$" | tail -3
  [ -s "$out" ] || { echo "Export failed for $preset"; exit 1; }
done
cp release/HOW-TO-PLAY.txt build/windows/ && (cd build/windows && zip -qr "../dist/Quarantine-$VERSION-windows.zip" .)
cp release/HOW-TO-PLAY.txt build/linux/ && chmod +x build/linux/Quarantine.x86_64 && (cd build/linux && zip -qr "../dist/Quarantine-$VERSION-linux.zip" .)
# Godot's macOS export is already a zip holding Quarantine.app; add the instructions to it.
cp build/mac/Quarantine.zip "build/dist/Quarantine-$VERSION-mac.zip"
(cd release && zip -q "../build/dist/Quarantine-$VERSION-mac.zip" HOW-TO-PLAY.txt)
ls -lh build/dist
