#!/bin/bash
# Launches the packaged app in demo mode, screenshots each state and checks it never crashes.
# The demo changes state 1s, 5s, 9s ... after it starts (it writes that moment to build/demo-start),
# so each shot lands 2 seconds into a step.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/screens
APP_BIN="build/MacNotch.app/Contents/MacOS/MacNotch"
now() { python3 -c 'import time; print(time.time())'; }

# CI Macs often run with Reduce Transparency on, which flattens all glass. Try to turn it off.
echo "Reduce Transparency before: $(defaults read com.apple.universalaccess reduceTransparency 2>&1)"
defaults write com.apple.universalaccess reduceTransparency -bool false 2>&1 || echo "could not change Reduce Transparency"
echo "Reduce Transparency after: $(defaults read com.apple.universalaccess reduceTransparency 2>&1)"

rm -f build/demo-start
MACNOTCH_DEMO_MARK="$PWD/build/demo-start" "$APP_BIN" --demo --reset > build/app.log 2>&1 &
PID=$!
for _ in $(seq 1 100); do
  [ -s build/demo-start ] && break
  sleep 0.1
done
START=$(cat build/demo-start 2>/dev/null || now)

shoot_at() {
  local target=$1 name=$2
  local wait
  wait=$(python3 -c "import time; print(max(0, $START + $target - time.time()))")
  sleep "$wait"
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "::error::MacNotch exited before '$name'"
    cat build/app.log
    exit 1
  fi
  screencapture -x "build/screens/$name.png" 2>/dev/null || echo "screencapture unavailable for $name"
}

shoot_at 3 screen-01-compact
shoot_at 7 screen-02-charging
shoot_at 11 screen-03-notch-info
shoot_at 15 screen-04-expanded-glass
shoot_at 19 screen-05-edit-mode
shoot_at 23 screen-06-expanded-glass-clear
shoot_at 27 screen-07-expanded-glass-tinted
shoot_at 31 screen-08-expanded-glass-light-wallpaper
shoot_at 35 screen-09-expanded-black-light-wallpaper
shoot_at 40 screen-10-settings-notch
shoot_at 43 screen-11-settings-notch-battery-date
shoot_at 47 screen-12-settings-widgets
shoot_at 51 screen-13-settings-web-pages
shoot_at 55 screen-14-settings-appearance

if kill -0 "$PID" 2>/dev/null; then
  echo "MacNotch ran the full demo without crashing"
  kill "$PID"
  wait "$PID" 2>/dev/null
else
  echo "::error::MacNotch exited unexpectedly"
  cat build/app.log
  exit 1
fi

echo "--- app log ---"
cat build/app.log

echo "==> Pointer test: hover, leave, edit mode, drag to reorder, remove, done, gear"
swiftc -O scripts/mouse.swift -o build/mouse
read -r SCREEN_W SCREEN_H < <(build/mouse screen)
BAR=$(build/mouse menubar)
echo "screen ${SCREEN_W}x${SCREEN_H}, menu bar ${BAR}pt"
MID=$((SCREEN_W / 2))
TOP=$((BAR / 2))
"$APP_BIN" --no-onboarding > build/app-pointer.log 2>&1 &
PID=$!
sleep 3
build/mouse move "$MID" 400
sleep 1
build/mouse move "$MID" 4
sleep 1.5
screencapture -x build/screens/pointer-1-hover-open.png 2>/dev/null || true
build/mouse move "$MID" 500
sleep 1.5
screencapture -x build/screens/pointer-2-moved-away.png 2>/dev/null || true

# Default widgets make the island 856 pt wide; cards start 28 pt in from its left edge.
HALF=428
LEFT=$((MID - HALF + 28))
CARD_Y=$((BAR + 6 + 66))
build/mouse move "$MID" 4
sleep 1.5
build/mouse click $((MID + HALF - 43 - 34)) "$TOP"
sleep 1.5
screencapture -x build/screens/pointer-3-edit-mode.png 2>/dev/null || true
# Drag Weather (second card) in front of Now Playing.
build/mouse drag $((LEFT + 298 + 75)) "$CARD_Y" $((LEFT + 30)) "$CARD_Y"
sleep 1.2
screencapture -x build/screens/pointer-4-dragged-weather-first.png 2>/dev/null || true
# Remove the File Shelf with its minus badge.
build/mouse click $((LEFT + 604 + 3)) $((BAR + 9))
sleep 1.2
screencapture -x build/screens/pointer-5-removed-shelf.png 2>/dev/null || true
# Three widgets left: the island is 650 pt wide. Tap Done.
build/mouse click $((MID + 325 - 30 - 26)) "$TOP"
sleep 1.2
screencapture -x build/screens/pointer-6-done.png 2>/dev/null || true
build/mouse click $((MID + 325 - 43)) "$TOP"
sleep 2.5
screencapture -x build/screens/pointer-7-clicked-gear.png 2>/dev/null || true
if kill -0 "$PID" 2>/dev/null; then
  echo "MacNotch survived the pointer test"
  kill "$PID"
  wait "$PID" 2>/dev/null
else
  echo "::error::MacNotch exited during the pointer test"
  cat build/app-pointer.log
  exit 1
fi
cat build/app-pointer.log
ls -la build/screens
