#!/bin/zsh
# Takes real screenshots of WPM with `screencapture` into ~/Desktop/wpm-screenshots.
# Needs: an unlocked screen, and Screen Recording permission for your terminal.
# Usage: scripts/screenshots.sh [--demo]   (--demo shows synthetic typing data)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$HOME/Desktop/wpm-screenshots"
mkdir -p "$OUT"
APP="build/WPM.app"
[[ -d "$APP" ]] || ./scripts/build-app.sh
swiftc -O -o build/windowid scripts/windowid.swift 2>/dev/null
hook() { swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"local.wpmbar.debug\"), object: \"$1\", userInfo: nil, deliverImmediately: true); RunLoop.main.run(until: Date().addingTimeInterval(0.3))"; }
largest() { build/windowid "$1" | awk '$4==0 || $4==101 {split($2,a,"x"); print a[1]*a[2], $1}' | sort -n | tail -1 | cut -d' ' -f2; }

pkill -x WPMBar 2>/dev/null || true; sleep 0.5
open "$APP" --args --debug-hooks --onboarding "$@"
sleep 3
PID=$(pgrep -x WPMBar)

# 1. Onboarding window
screencapture -o -x -l "$(largest $PID)" "$OUT/4-onboarding.png"
hook close-onboarding; sleep 1

# 2. Menu bar (top-right strip of the main display)
W=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
screencapture -x -R "$((W-700)),0,700,34" "$OUT/1-menubar.png"

# 3. Popover + settings: needs one real click on the menu bar item.
echo "Click the 'wpm' item in the menu bar now…"
for i in {1..60}; do
  ID=$(build/windowid $PID | awk '$4==101 || $4==25 {print $1}' | head -1)
  [[ -n "${ID:-}" ]] && break; sleep 0.5
done
sleep 0.8
screencapture -o -x -l "$ID" "$OUT/2-popover.png"
hook settings; sleep 0.8
screencapture -o -x -l "$ID" "$OUT/3-settings.png"
hook stats
echo "Saved to $OUT"
open "$OUT"
