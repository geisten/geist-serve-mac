#!/bin/sh
# update.sh — Sparkle end to end with a throwaway key: an appcast signed for
# a copy of the app that carries the throwaway public key, served locally,
# found by the app's update probe. No secret needed, so CI runs it too.
set -eu
cd "$(dirname "$0")/.."
BIN=.build/artifacts/sparkle/Sparkle/bin
[ -x "$BIN/generate_keys" ] || { echo "update: Sparkle tools missing (swift package resolve)"; exit 1; }
# Not mktemp: Sparkle cannot issue a sandbox extension for a bundle under
# /var/folders and then never reports anything. build/ works.
T=$PWD/build/test-update; rm -rf "$T"; mkdir -p "$T"; LOG=$(mktemp); ACCT="geist-serve-mac-test-$$"
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
wait_log() { i=0; while [ $i -lt "$2" ]; do grep -q "$1" "$LOG" && return 0; sleep 1; i=$((i+1)); done; return 1; }
quit_app() { osascript -e 'tell application id "com.geisten.geist" to quit' >/dev/null 2>&1 || kill "$1" 2>/dev/null || true
             i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done; kill -9 "$1" 2>/dev/null || true; }
trap 'kill ${SRV:-} 2>/dev/null || true; wait ${SRV:-} 2>/dev/null || true; security delete-generic-password -a "$ACCT" -s https://sparkle-project.org >/dev/null 2>&1 || true; rm -rf "$T" "$LOG"' EXIT

# throwaway key pair, private key exported to a file, then removed from the keychain by the trap
PUB=$("$BIN/generate_keys" --account "$ACCT" 2>&1 | grep -oE '[A-Za-z0-9+/=]{40,}' | head -1)
"$BIN/generate_keys" --account "$ACCT" -x "$T/key" >/dev/null 2>&1
[ -n "$PUB" ] && [ -s "$T/key" ] && ok "throwaway key pair" || bad "key generation"

# the app under test: our bundle with the throwaway public key
cp -R build/Geist.app "$T/Geist.app"
plutil -replace SUPublicEDKey -string "$PUB" "$T/Geist.app/Contents/Info.plist"
codesign --force --sign - --deep "$T/Geist.app" >/dev/null 2>&1 || true
# the "new version": same app, build 999
mkdir -p "$T/feed" "$T/new"; cp -R "$T/Geist.app" "$T/new/Geist.app"
plutil -replace CFBundleVersion -string 999 "$T/new/Geist.app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 9.9.9 "$T/new/Geist.app/Contents/Info.plist"
# every plist edit breaks the seal: generate_appcast rejects an app whose
# code signature does not verify, so re-sign (ad-hoc) after editing
codesign --force --sign - --deep "$T/new/Geist.app" >/dev/null 2>&1
(cd "$T/new" && ditto -c -k --keepParent Geist.app "$T/feed/Geist-9.9.9.zip")
"$BIN/generate_appcast" --ed-key-file "$T/key" --download-url-prefix "http://127.0.0.1:28150/" "$T/feed" >/dev/null 2>&1 \
    && ok "appcast generated and signed" || bad "generate_appcast"
grep -q 'sparkle:edSignature=' "$T/feed/appcast.xml" && ok "appcast carries an EdDSA signature" || bad "no signature in appcast"
python3 -m http.server 28150 --bind 127.0.0.1 --directory "$T/feed" >/dev/null 2>&1 & SRV=$!
sleep 1

GEIST_HOME="$T/home" GEIST_PORT=28151 GEIST_FEED_URL=http://127.0.0.1:28150/appcast.xml GEIST_UPDATE_PROBE=1 \
    "$T/Geist.app/Contents/MacOS/Geist" 2>"$LOG" & PID=$!
if wait_log "update available: 9.9.9" 45; then ok "app finds the 9.9.9 update in the local appcast"; else
    bad "update probe"
    echo "--- app log:"; cat "$LOG"
    echo "--- appcast:"; cat "$T/feed/appcast.xml"
    echo "--- app version: $(plutil -extract CFBundleVersion raw "$T/Geist.app/Contents/Info.plist")"
    echo "--- sparkle os_log (last 2 min):"; log show --last 2m --predicate 'subsystem == "org.sparkle-project.Sparkle" OR process == "Geist"' --style compact 2>/dev/null | grep -viE 'cli: none' | tail -30
fi
quit_app $PID

# same app again, a feed with no items → "no update", not an error
# (generate_appcast keeps old items, so the empty feed is written by hand)
: > "$LOG"
cat > "$T/feed/appcast.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Geist</title></channel></rss>
XML
GEIST_HOME="$T/home" GEIST_PORT=28151 GEIST_FEED_URL=http://127.0.0.1:28150/appcast.xml GEIST_UPDATE_PROBE=1 \
    "$T/Geist.app/Contents/MacOS/Geist" 2>"$LOG" & PID=$!
wait_log "no update\|update check failed" 30 && ok "empty feed → no update, app keeps running" || bad "empty feed: $(tail -2 "$LOG")"
kill -0 $PID 2>/dev/null && ok "app alive after probe" || bad "app died"
quit_app $PID

[ $fail -eq 0 ] && echo "update: all passed"
exit $fail
