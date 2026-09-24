#!/bin/sh
# settings.sh — command line tool detection/installation and the network
# switch, through the real app. The login item is deliberately untested:
# registering one on the test machine is a side effect, and the app never
# does it under GEIST_HOME.
set -eu
cd "$(dirname "$0")/.."
MODEL=${GEIST_TEST_MODEL:-$HOME/workspace/geistlib/gguf_artifacts/smollm2-360m-instruct-q8_0.gguf}
[ -f "$MODEL" ] || { echo "settings: no model at $MODEL — skipped"; exit 0; }
APP=build/Geist.app/Contents/MacOS/Geist
T=$(mktemp -d); LOG=$(mktemp)
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
wait_log() { i=0; while [ $i -lt "$2" ]; do grep -q "$1" "$LOG" && return 0; sleep 1; i=$((i+1)); done; return 1; }
quit_app() { osascript -e 'tell application id "com.geisten.geist" to quit' >/dev/null 2>&1 || kill "$1" 2>/dev/null || true
             i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done; kill -9 "$1" 2>/dev/null || true; }
defaults delete com.geisten.geist.test >/dev/null 2>&1 || true
trap 'pkill -f "geist-serve .*--port 2814[01]" 2>/dev/null || true; rm -rf "$T" "$LOG"; defaults delete com.geisten.geist.test >/dev/null 2>&1 || true' EXIT

# 1. a Homebrew geist-serve on PATH is recognised and left alone
mkdir -p "$T/opt/homebrew/Cellar/geist-serve/9.9/bin" "$T/opt/homebrew/bin" "$T/cli"
printf '#!/bin/sh\nexit 2\n' > "$T/opt/homebrew/Cellar/geist-serve/9.9/bin/geist-serve"; chmod +x "$T/opt/homebrew/Cellar/geist-serve/9.9/bin/geist-serve"
ln -s ../Cellar/geist-serve/9.9/bin/geist-serve "$T/opt/homebrew/bin/geist-serve"
PATH="$T/opt/homebrew/bin:$PATH" GEIST_HOME="$T/home" GEIST_PORT=28140 GEIST_CLI_DIR="$T/cli" GEIST_MODEL="$MODEL" "$APP" 2>"$LOG" & PID=$!
wait_log "cli: homebrew at $T/opt/homebrew/bin/geist-serve" 15 && ok "homebrew install detected" || bad "homebrew detection: $(grep cli "$LOG")"
quit_app $PID

# 2. no brew: install creates the symlink into the bundle; a second launch sees it
: > "$LOG"
GEIST_HOME="$T/home" GEIST_PORT=28140 GEIST_CLI_DIR="$T/cli" GEIST_AUTO_CLI=1 GEIST_MODEL="$MODEL" "$APP" 2>"$LOG" & PID=$!
wait_log "cli: installed" 15 && ok "symlink installed" || bad "symlink install: $(grep cli "$LOG")"
[ -L "$T/cli/geist-serve" ] && ok "link exists" || bad "link missing"
"$T/cli/geist-serve" >/dev/null 2>&1 || [ $? -eq 2 ] && ok "link runs the bundled server" || bad "link does not run"
case "$(readlink "$T/cli/geist-serve")" in *Geist.app/Contents/MacOS/geist-serve) ok "link points into the bundle" ;; *) bad "link target $(readlink "$T/cli/geist-serve")" ;; esac
quit_app $PID
: > "$LOG"
GEIST_HOME="$T/home" GEIST_PORT=28140 GEIST_CLI_DIR="$T/cli" GEIST_MODEL="$MODEL" "$APP" 2>"$LOG" & PID=$!
wait_log "cli: installed" 15 && ok "existing link recognised on next launch" || bad "recognise link"
quit_app $PID

# 3. a link pointing elsewhere is reported stale
ln -sfn /usr/bin/true "$T/cli/geist-serve"; : > "$LOG"
GEIST_HOME="$T/home" GEIST_PORT=28140 GEIST_CLI_DIR="$T/cli" GEIST_MODEL="$MODEL" "$APP" 2>"$LOG" & PID=$!
wait_log 'cli: stale' 15 && ok "stale link reported" || bad "stale link: $(grep cli "$LOG")"
quit_app $PID

# 4. network switch persisted in defaults → server launched with --host 0.0.0.0
defaults write com.geisten.geist.test network -bool true
: > "$LOG"
GEIST_HOME="$T/home" GEIST_PORT=28141 GEIST_CLI_DIR="$T/cli" GEIST_MODEL="$MODEL" "$APP" 2>"$LOG" & PID=$!
wait_log "launched pid" 30
sleep 1
ps -o args= -p "$(pgrep -f 'geist-serve .*--port 28141' | head -1)" | grep -q -- '--host 0.0.0.0' && ok "network switch → --host 0.0.0.0" || bad "network flag: $(ps -o args= -p "$(pgrep -f 'geist-serve .*--port 28141' | head -1)")"
quit_app $PID
defaults write com.geisten.geist.test network -bool false
: > "$LOG"
GEIST_HOME="$T/home" GEIST_PORT=28141 GEIST_CLI_DIR="$T/cli" GEIST_MODEL="$MODEL" "$APP" 2>"$LOG" & PID=$!
wait_log "launched pid" 30; sleep 1
ps -o args= -p "$(pgrep -f 'geist-serve .*--port 28141' | head -1)" | grep -q -- '--host 127.0.0.1' && ok "default stays loopback" || bad "loopback default"
quit_app $PID

[ $fail -eq 0 ] && echo "settings: all passed"
exit $fail
