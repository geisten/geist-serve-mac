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
[ $fail -eq 0 ] && echo "bundle: all passed"
exit $fail
