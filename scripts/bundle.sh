#!/bin/sh
# bundle.sh — assemble build/Geist.app from the swift build product, the
# Info.plist template and the fetched geist-serve binary. Signing and
# notarization are release.yml's job (#6); this bundle is ad-hoc signed so
# it runs locally.
set -eu
cd "$(dirname "$0")/.."
VERSION=${VERSION:-0.0.0-dev}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
APP=build/Geist.app
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Geist" "$APP/Contents/MacOS/Geist"
cp build/geist-serve "$APP/Contents/MacOS/geist-serve"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --deep "$APP" >/dev/null 2>&1 || true
echo "built $APP ($VERSION, build $BUILD)"
