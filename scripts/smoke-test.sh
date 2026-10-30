#!/bin/bash
# Launches the packaged app in demo mode, screenshots each state and checks it never crashes.
# The demo changes state at 1s, 5s, 9s ... so each shot lands 2 seconds into a step.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/screens
APP_BIN="build/MacNotch.app/Contents/MacOS/MacNotch"
now() { python3 -c 'import time; print(time.time())'; }

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

shoot_at 3  screen-1-compact
shoot_at 7  screen-2-charging
shoot_at 11 screen-3-expanded-glass
shoot_at 15 screen-4-expanded-glass-clear
shoot_at 19 screen-5-expanded-black
shoot_at 23 screen-6-settings-general
shoot_at 27 screen-7-settings-widgets
shoot_at 31 screen-8-settings-web-pages
shoot_at 35 screen-9-settings-appearance

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
ls -la build/screens
