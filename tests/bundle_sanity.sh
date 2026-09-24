#!/bin/sh
# The bundle is what ships: check its shape, not the Swift code.
set -eu
cd "$(dirname "$0")/.."
APP=build/Geist.app
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
[ -x "$APP/Contents/MacOS/Geist" ] && ok "app executable" || bad "app executable"
[ -x "$APP/Contents/MacOS/geist-serve" ] && ok "server bundled" || bad "server bundled"
"$APP/Contents/MacOS/geist-serve" >/dev/null 2>&1 || [ $? -eq 2 ] && ok "server runs (usage exit 2)" || bad "server runs"
plutil -lint "$APP/Contents/Info.plist" >/dev/null && ok "Info.plist valid" || bad "Info.plist"
grep -q '<key>LSUIElement</key>' "$APP/Contents/Info.plist" && ok "menu bar only (LSUIElement)" || bad "LSUIElement"
! grep -q '__VERSION__' "$APP/Contents/Info.plist" && ok "version substituted" || bad "version placeholder left"
! otool -L "$APP/Contents/MacOS/geist-serve" | grep -q homebrew && ok "server has no Homebrew deps" || bad "server links Homebrew"
codesign -dv "$APP" 2>&1 | grep -q 'Signature' && ok "signed (ad-hoc or better)" || bad "unsigned"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] && ok "Sparkle.framework bundled" || bad "Sparkle.framework missing"
otool -l "$APP/Contents/MacOS/Geist" | grep -q '@executable_path/../Frameworks' && ok "rpath to Contents/Frameworks" || bad "rpath"
[ -n "$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist" 2>/dev/null)" ] && ok "SUPublicEDKey set" || bad "SUPublicEDKey"
plutil -extract SUFeedURL raw "$APP/Contents/Info.plist" 2>/dev/null | grep -q 'releases/latest/download/appcast.xml' && ok "SUFeedURL on releases" || bad "SUFeedURL"
[ $fail -eq 0 ] && echo "bundle: all passed"
exit $fail
