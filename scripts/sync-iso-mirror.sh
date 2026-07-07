#!/usr/bin/env bash
# Start host ISO mirror (openresty cannot read /mnt symlinks).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO_DIR="${STRAWWU_ISO_DIR:-/mnt/data/code/project/StrawCoding/StrawWU/os-image/output}"
PORT="${STRAWWU_ISO_PORT:-9105}"
PID_FILE="${STRAWWU_ISO_PID_FILE:-/tmp/strawwu-iso-mirror.pid}"
LOG_FILE="${STRAWWU_ISO_LOG:-/tmp/strawwu-iso-mirror.log}"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "ISO mirror already running (pid $(cat "$PID_FILE"))"
  exit 0
fi

nohup env STRAWWU_ISO_DIR="$ISO_DIR" STRAWWU_ISO_PORT="$PORT" \
  node "$ROOT/scripts/serve-iso-mirror.mjs" >>"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
sleep 0.5
curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null
echo "ISO mirror started on 127.0.0.1:${PORT} (log: $LOG_FILE)"

