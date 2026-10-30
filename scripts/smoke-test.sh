#!/bin/bash
# Launches the packaged app in demo mode, screenshots each state and checks it never crashes.
# The demo changes state at 1s, 5s, 9s ... so each shot lands 2 seconds into a step.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/screens
APP_BIN="build/MacNotch.app/Contents/MacOS/MacNotch"
now() { python3 -c 'import time; print(time.time())'; }

# CI Macs often run with Reduce Transparency on, which flattens all glass. Try to turn it off.
echo "Reduce Transparency before: $(defaults read com.apple.universalaccess reduceTransparency 2>&1)"
defaults write com.apple.universalaccess reduceTransparency -bool false 2>&1 || echo "could not change Reduce Transparency"
echo "Reduce Transparency after: $(defaults read com.apple.universalaccess reduceTransparency 2>&1)"

START=$(now)
"$APP_BIN" --demo --reset > build/app.log 2>&1 &
PID=$!

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

shoot_at 3  screen-01-compact
shoot_at 7  screen-02-charging
shoot_at 11 screen-03-expanded-glass
shoot_at 15 screen-04-expanded-glass-clear
shoot_at 19 screen-05-expanded-glass-tinted
shoot_at 23 screen-06-expanded-glass-light-wallpaper
shoot_at 27 screen-07-expanded-black-light-wallpaper
shoot_at 31 screen-08-settings-general
shoot_at 35 screen-09-settings-widgets
shoot_at 39 screen-10-settings-web-pages
shoot_at 43 screen-11-settings-appearance

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

echo "==> Pointer test: hover the notch, leave, then click the gear"
swiftc -O scripts/mouse.swift -o build/mouse
read -r SCREEN_W SCREEN_H < <(build/mouse screen)
MID=$((SCREEN_W / 2))
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
build/mouse move "$MID" 4
sleep 1.5
# With the default widgets the island is 856 pt wide; the gear sits 43 pt in from its right edge.
GEAR_X=$((MID + 856 / 2 - 43))
build/mouse click "$GEAR_X" 15
sleep 2.5
screencapture -x build/screens/pointer-3-clicked-gear.png 2>/dev/null || true
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
