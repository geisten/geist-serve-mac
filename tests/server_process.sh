#!/bin/sh
# server_process.sh — the app really owns its server: starts it, restarts it
# once after a crash, gives up after the second, stops it on quit, and
# reports a busy port instead of stealing it. Needs a GGUF (GEIST_TEST_MODEL,
# default: the engine's SmolLM2 fixture); skips without one.
set -eu
cd "$(dirname "$0")/.."
MODEL=${GEIST_TEST_MODEL:-$HOME/workspace/geistlib/gguf_artifacts/smollm2-360m-instruct-q8_0.gguf}
[ -f "$MODEL" ] || { echo "server_process: no model at $MODEL — skipped"; exit 0; }
APP=build/Geist.app/Contents/MacOS/Geist
PORT=28111
LOG=$(mktemp)
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
wait_for() { # $1 = url, $2 = seconds
    i=0; while [ $i -lt "$2" ]; do curl -sf "$1" >/dev/null 2>&1 && return 0; sleep 1; i=$((i+1)); done; return 1
}
wait_log() { # $1 = pattern, $2 = seconds
    i=0; while [ $i -lt "$2" ]; do grep -q "$1" "$LOG" && return 0; sleep 1; i=$((i+1)); done; return 1
}
serve_pid() { pgrep -f "geist-serve .*--port $PORT" | head -1; }

GEIST_MODEL="$MODEL" GEIST_PORT=$PORT "$APP" 2>"$LOG" &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true; pkill -f "geist-serve .*--port $PORT" 2>/dev/null || true; rm -f "$LOG"' EXIT

wait_for "http://127.0.0.1:$PORT/api/tags" 60 && ok "app starts the server" || bad "app starts the server"
[ -n "$(serve_pid)" ] && ok "child geist-serve on port $PORT" || bad "child geist-serve"

kill -9 "$(serve_pid)"; sleep 1
wait_log "restarting once" 10 && ok "crash → restart once" || bad "crash → restart once"
wait_for "http://127.0.0.1:$PORT/health" 60 && ok "server back after restart" || bad "server back after restart"

kill -9 "$(serve_pid)"; sleep 3
[ "$(grep -c 'launched pid' "$LOG")" = 2 ] && ok "second crash: no third launch" || bad "second crash: launches=$(grep -c 'launched pid' "$LOG")"
grep -q "exited unexpectedly" "$LOG" && ok "failure logged" || bad "failure logged"

osascript -e 'tell application id "com.geisten.geist" to quit' >/dev/null 2>&1 || kill "$APP_PID"
i=0; while kill -0 $APP_PID 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
! kill -0 $APP_PID 2>/dev/null && ok "app quits on AppleScript quit" || bad "app still running"
[ -z "$(serve_pid)" ] && ok "no orphan geist-serve" || bad "orphan geist-serve $(serve_pid)"

# --- busy port: something else answers → state says so, no second server --
PORT2=28112
python3 - $PORT2 >/dev/null 2>&1 <<'PY' &
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self): self.send_response(200); self.end_headers(); self.wfile.write(b'{"version":"0.0.0"}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
PY_PID=$!
sleep 1
: > "$LOG"
GEIST_MODEL="$MODEL" GEIST_PORT=$PORT2 "$APP" 2>"$LOG" &
APP_PID=$!
wait_log "already answers" 15 && ok "busy port detected, not stolen" || bad "busy port"
[ -z "$(pgrep -f "geist-serve .*--port $PORT2")" ] && ok "no server launched on busy port" || bad "server launched on busy port"
osascript -e 'tell application id "com.geisten.geist" to quit' >/dev/null 2>&1 || kill "$APP_PID"
kill $PY_PID 2>/dev/null; wait $PY_PID 2>/dev/null || true

[ $fail -eq 0 ] && echo "server_process: all passed"
exit $fail
