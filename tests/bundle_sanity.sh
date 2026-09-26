#!/bin/sh
# The bundle is what ships: check its shape, not the Swift code.
set -eu
cd "$(dirname "$0")/.."
APP=build/Geist.app
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
[ -x "$APP/Contents/MacOS/Geist" ] && ok "app executable" || bad "app executable"
[ -x "$APP/Contents/MacOS/geistd" ] && ok "geistd bundled" || bad "geistd bundled"
[ -x "$APP/Contents/MacOS/geist-app" ] && ok "C23 app bundled" || bad "C23 app bundled"
! otool -L "$APP/Contents/MacOS/geist-app" | grep -q homebrew && ok "app has no Homebrew deps" || bad "app links Homebrew"
"$APP/Contents/MacOS/geistd" >/dev/null 2>&1 || [ $? -eq 2 ] && ok "server runs (usage exit 2)" || bad "server runs"
plutil -lint "$APP/Contents/Info.plist" >/dev/null && ok "Info.plist valid" || bad "Info.plist"
grep -q '<key>LSUIElement</key>' "$APP/Contents/Info.plist" && ok "menu bar only (LSUIElement)" || bad "LSUIElement"
! grep -q '__VERSION__' "$APP/Contents/Info.plist" && ok "version substituted" || bad "version placeholder left"
! otool -L "$APP/Contents/MacOS/geistd" | grep -q homebrew && ok "server has no Homebrew deps" || bad "server links Homebrew"
codesign -dv "$APP" 2>&1 | grep -q 'Signature' && ok "signed (ad-hoc or better)" || bad "unsigned"
codesign --verify --deep --strict "$APP" && ok "bundle signature verifies" || bad "invalid bundle signature"
(cd "$APP/Contents" && shasum -a 256 -c Resources/RUNTIME-SHA256SUMS) && ok "signed runtime hashes match" || bad "runtime hashes mismatch"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] && ok "app icon bundled" || bad "AppIcon.icns missing"
[ -f "$APP/Contents/Resources/MenuBarIcon@2x.png" ] && ok "menu bar glyph bundled" || bad "MenuBarIcon missing"
plutil -extract CFBundleIconFile raw "$APP/Contents/Info.plist" 2>/dev/null | grep -q AppIcon && ok "CFBundleIconFile" || bad "CFBundleIconFile"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] && ok "Sparkle.framework bundled" || bad "Sparkle.framework missing"
otool -l "$APP/Contents/MacOS/Geist" | grep -q '@executable_path/../Frameworks' && ok "rpath to Contents/Frameworks" || bad "rpath"
[ -n "$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist" 2>/dev/null)" ] && ok "SUPublicEDKey set" || bad "SUPublicEDKey"
plutil -extract SUFeedURL raw "$APP/Contents/Info.plist" 2>/dev/null | grep -q 'releases/latest/download/appcast.xml' && ok "SUFeedURL on releases" || bad "SUFeedURL"
[ $fail -eq 0 ] && echo "bundle: all passed"
exit $fail
