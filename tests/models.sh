#!/bin/sh
# models.sh — download, verify, select, persist. A local HTTP server stands
# in for Hugging Face (GEIST_MODEL_BASE_URL) and serves the engine's real
# SmolLM2 fixture, so the SHA pin in Models.swift is checked for real.
set -eu
cd "$(dirname "$0")/.."
FIX=${GEIST_TEST_MODEL_DIR:-$HOME/workspace/geistlib/gguf_artifacts}
[ -f "$FIX/smollm2-360m-instruct-q8_0.gguf" ] || { echo "models: no fixture in $FIX — skipped"; exit 0; }
APP=build/Geist.app/Contents/MacOS/Geist
HOME_T=$(mktemp -d); LOG=$(mktemp); BAD=$(mktemp -d)
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
wait_log() { i=0; while [ $i -lt "$2" ]; do grep -q "$1" "$LOG" && return 0; sleep 1; i=$((i+1)); done; return 1; }
wait_for() { i=0; while [ $i -lt "$2" ]; do curl -sf "$1" >/dev/null 2>&1 && return 0; sleep 1; i=$((i+1)); done; return 1; }
quit_app() { osascript -e 'tell application id "com.geisten.geist" to quit' >/dev/null 2>&1 || kill "$1" 2>/dev/null || true
             i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done; kill -9 "$1" 2>/dev/null || true; }
defaults delete com.geisten.geist.test >/dev/null 2>&1 || true
python3 -m http.server 28120 --bind 127.0.0.1 --directory "$FIX" >/dev/null 2>&1 & SRV=$!
head -c 1000000 /dev/zero > "$BAD/smollm2-360m-instruct-q8_0.gguf"
python3 -m http.server 28122 --bind 127.0.0.1 --directory "$BAD" >/dev/null 2>&1 & SRV2=$!
trap 'kill $SRV $SRV2 2>/dev/null || true; wait $SRV $SRV2 2>/dev/null || true; pkill -f "geist-serve .*--port 2812[13]" 2>/dev/null || true; rm -rf "$HOME_T" "$BAD" "$LOG"; defaults delete com.geisten.geist.test >/dev/null 2>&1 || true' EXIT
sleep 1

# 1. download → verify → select → server starts with it
GEIST_HOME="$HOME_T" GEIST_PORT=28121 GEIST_MODEL_BASE_URL=http://127.0.0.1:28120 GEIST_AUTO_DOWNLOAD=smollm2-360m "$APP" 2>"$LOG" & PID=$!
wait_log "downloaded and verified" 180 && ok "download verified against the SHA pin" || bad "download: $(tail -2 "$LOG")"
F="$HOME_T/models/smollm2-360m-instruct-q8_0.gguf"
[ -f "$F" ] && [ ! -f "$F.part" ] && ok "file in GEIST_HOME/models, no .part left" || bad "file placement"
[ "$(shasum -a 256 "$F" | cut -d' ' -f1)" = "48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201" ] && ok "on-disk sha matches" || bad "on-disk sha"
wait_for "http://127.0.0.1:28121/api/tags" 60 && ok "server started with the downloaded model" || bad "server after download"
curl -s http://127.0.0.1:28121/api/tags | grep -q smollm2 && ok "/api/tags names it" || bad "/api/tags"
quit_app $PID

# 2. relaunch without hooks: the selection persisted, server starts by itself
: > "$LOG"
GEIST_HOME="$HOME_T" GEIST_PORT=28121 "$APP" 2>"$LOG" & PID=$!
wait_for "http://127.0.0.1:28121/health" 60 && ok "selection persisted across launches" || bad "persisted selection"
quit_app $PID

# 3. wrong bytes under the right name → discarded, reported, nothing selected
# (fresh defaults too: the test suite is shared across GEIST_HOMEs)
defaults delete com.geisten.geist.test >/dev/null 2>&1 || true
HOME2=$(mktemp -d); : > "$LOG"
GEIST_HOME="$HOME2" GEIST_PORT=28123 GEIST_MODEL_BASE_URL=http://127.0.0.1:28122 GEIST_AUTO_DOWNLOAD=smollm2-360m "$APP" 2>"$LOG" & PID=$!
wait_log "checksum mismatch" 60 && ok "corrupt download reported" || bad "corrupt download: $(tail -2 "$LOG")"
sleep 1
[ ! -f "$HOME2/models/smollm2-360m-instruct-q8_0.gguf" ] && [ ! -f "$HOME2/models/smollm2-360m-instruct-q8_0.gguf.part" ] && ok "corrupt file discarded" || bad "corrupt file kept"
[ -z "$(pgrep -f 'geist-serve .*--port 28123')" ] && ok "no server on a corrupt model" || bad "server started on corrupt model"
quit_app $PID; rm -rf "$HOME2"

[ $fail -eq 0 ] && echo "models: all passed"
exit $fail
