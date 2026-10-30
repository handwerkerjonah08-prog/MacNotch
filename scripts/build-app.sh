#!/bin/bash
# Builds MacNotch.app (Apple Silicon) and MacNotch.dmg into ./build.
# Usage: scripts/build-app.sh [version] [build-number]
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
BUILD_DIR="build"
APP="$BUILD_DIR/MacNotch.app"

echo "==> Compiling release build"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacNotch" "$APP/Contents/MacOS/MacNotch"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "==> Building icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Creating DMG"
STAGING="$BUILD_DIR/dmg"
rm -rf "$STAGING" "$BUILD_DIR/MacNotch.dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MacNotch" -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/MacNotch.dmg" >/dev/null
rm -rf "$STAGING"

echo "==> Done"
ls -lh "$BUILD_DIR/MacNotch.dmg"
