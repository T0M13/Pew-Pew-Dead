#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

DEBUG=1
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--no-debug" ]]; then
    DEBUG=0
  else
    ARGS+=("$arg")
  fi
done

ensure_imported() {
  godot --headless --path . --import --quit >/dev/null
}

if [[ $DEBUG -eq 0 ]]; then
  ensure_imported
  exec godot "${ARGS[@]}"
fi

ENGINE_LOG_DIR="debug/engine_logs"
GAME_LOG_DIR_REL="debug/game_logs"
MAX_LOGS=10

mkdir -p "$ENGINE_LOG_DIR" "$GAME_LOG_DIR_REL"

rotate() {
  local dir="$1"
  ls -t "$dir"/*.log 2>/dev/null | tail -n +$((MAX_LOGS + 1)) | while IFS= read -r f; do
    rm -f "$f"
  done
}

TS=$(date +%Y%m%d-%H%M%S)
ENGINE_LOG="$ENGINE_LOG_DIR/$TS.log"

export GAME_LOG_DIR="$(pwd)/$GAME_LOG_DIR_REL"
export GAME_LOG_TS="$TS"

ensure_imported
godot "${ARGS[@]}" 2>&1 | tee "$ENGINE_LOG"
EXIT=${PIPESTATUS[0]}

rotate "$ENGINE_LOG_DIR"
rotate "$GAME_LOG_DIR_REL"

exit "$EXIT"
