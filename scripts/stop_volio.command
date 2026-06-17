#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT/.volio/volio.pid"

echo "Stopping Volio..."

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ "$PID" = "screen:volio" ]; then
    /usr/bin/screen -S volio -X quit >/dev/null 2>&1 || true
  elif [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    kill "$PID" >/dev/null 2>&1 || true
    sleep 0.5
  fi
  rm -f "$PID_FILE"
fi

/usr/bin/pkill -f "uvicorn server.main:app" >/dev/null 2>&1 || true

echo "Volio stopped."
sleep 1
