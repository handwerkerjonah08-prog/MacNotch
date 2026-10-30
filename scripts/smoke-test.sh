#!/bin/bash
# Launches the packaged app in demo mode, screenshots each state and checks it never crashes.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/screens
APP_BIN="build/MacNotch.app/Contents/MacOS/MacNotch"
"$APP_BIN" --demo --reset > build/app.log 2>&1 &
PID=$!

shoot() {
  sleep "$1"
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "::error::MacNotch exited before '$2'"
    cat build/app.log
    exit 1
  fi
  screencapture -x "build/screens/$2.png" 2>/dev/null || echo "screencapture unavailable for $2"
}

shoot 2.0 screen-1-compact
shoot 3.5 screen-2-charging
shoot 3.5 screen-3-expanded-glass
shoot 3.0 screen-4-expanded-black
shoot 4.0 screen-5-settings-general
shoot 3.0 screen-6-settings-web-pages
shoot 3.0 screen-7-settings-appearance

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
