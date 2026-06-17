#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="$ROOT/.volio"
LOG_DIR="$RUN_DIR/logs"
PID_FILE="$RUN_DIR/volio.pid"
LOG_FILE="$LOG_DIR/volio.log"
PORT="${VOLIO_PORT:-8001}"

if /usr/bin/which screen >/dev/null 2>&1; then
  /usr/bin/screen -S volio -X quit >/dev/null 2>&1 || true
fi

while /usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
  PORT=$((PORT + 1))
done

URL="http://127.0.0.1:$PORT"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

is_volio_up() {
  /usr/bin/curl -fsS "$URL/api/state" >/dev/null 2>&1
}

echo "Starting Volio..."

PYTHON="${VOLIO_PYTHON:-/Library/Frameworks/Python.framework/Versions/3.13/bin/python3}"
if [ ! -x "$PYTHON" ]; then
  PYTHON="$(/usr/bin/which python3 2>/dev/null || true)"
fi

if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
  echo "Python 3 was not found. Install Python 3, then open Volio again."
  read -k 1 "?Press any key to close."
  exit 1
fi

cd "$ROOT" || exit 1

"$PYTHON" - <<'PY' >/dev/null 2>&1
import fastapi, uvicorn, PIL, requests, multipart
PY
if [ $? -ne 0 ]; then
  echo "Installing local dependencies. This only happens when packages are missing..."
  "$PYTHON" -m pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r "$ROOT/requirements.txt" >> "$LOG_FILE" 2>&1
fi

echo "Launching server..."
if /usr/bin/which screen >/dev/null 2>&1; then
  /usr/bin/screen -dmS volio /bin/zsh -lc "cd '$ROOT' && export VOLIO_PORT='$PORT' && exec '$PYTHON' -m uvicorn server.main:app --host 0.0.0.0 --port '$PORT' >> '$LOG_FILE' 2>&1"
  echo "screen:volio" > "$PID_FILE"
else
  VOLIO_PORT="$PORT" nohup "$PYTHON" -m uvicorn server.main:app --host 0.0.0.0 --port "$PORT" </dev/null >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  disown
fi

for _ in {1..60}; do
  if is_volio_up; then
    echo "Volio is ready: $URL"
    /usr/bin/open "$URL"
    sleep 1
    exit 0
  fi
  /bin/sleep 0.25
done

echo "Volio did not start. Log:"
echo "$LOG_FILE"
tail -40 "$LOG_FILE" 2>/dev/null || true
read -k 1 "?Press any key to close."
exit 1
