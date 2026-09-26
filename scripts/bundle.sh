#!/bin/sh
# bundle.sh — assemble build/Geist.app from the swift build product, the
# Info.plist template and the matching geistd binary. Signing and
# notarization are notarize.yml's job (#6); this bundle is ad-hoc signed so
# it runs locally.
set -eu
cd "$(dirname "$0")/.."
VERSION=${VERSION:-0.0.0-dev}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
APP=build/Geist.app
BIN=$(swift build -c release --show-bin-path)

# Icon set: rendered from scripts/icon.swift, cached in build/icon.
if [ ! -f build/icon/AppIcon.icns ] || [ scripts/icon.swift -nt build/icon/AppIcon.icns ]; then
    swift scripts/icon.swift build/icon >/dev/null
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/icon/AppIcon.icns build/icon/MenuBarIcon.png build/icon/MenuBarIcon@2x.png "$APP/Contents/Resources/"
cp "$BIN/Geist" "$APP/Contents/MacOS/Geist"
cp build/geistd "$APP/Contents/MacOS/geistd"
cp build/geist-app "$APP/Contents/MacOS/geist-app"
cp build/geist "$APP/Contents/MacOS/geist-cli"
# Preserve source-binary provenance separately: signing changes Mach-O bytes.
cp build/RUNTIME-SHA256SUMS "$APP/Contents/Resources/RUNTIME-SOURCE-SHA256SUMS"
# Sparkle.framework from the SwiftPM artifact (binary xcframework).
FW=$(find .build/artifacts/sparkle -path '*macos*' -name 'Sparkle.framework' -maxdepth 4 | head -1)
[ -d "$FW" ] || { echo "bundle: Sparkle.framework not found under .build/artifacts (swift package resolve?)" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
cp -R "$FW" "$APP/Contents/Frameworks/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
python3 scripts/distribution.py sign --app "$APP" --identity -
echo "built $APP ($VERSION, build $BUILD)"
