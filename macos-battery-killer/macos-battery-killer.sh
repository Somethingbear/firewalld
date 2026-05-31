#!/usr/bin/env bash
set -euo pipefail

THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-5}"
RUN_SECONDS="${RUN_SECONDS:-600}"
CINEBENCH_BIN="${CINEBENCH_BIN:-/Applications/Cinebench.app/Contents/MacOS/benchmark}"
CINEBENCH_ARGS=(g_CinebenchCpuXTest=true)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_FILE="${AUDIO_FILE:-$SCRIPT_DIR/yahaha.wav}"

cinebench_pid=""

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./macos-battery-killer.sh

Environment overrides:
  THRESHOLD_PERCENT=5
  RUN_SECONDS=600
  CINEBENCH_BIN=/Applications/Cinebench.app/Contents/MacOS/benchmark
  AUDIO_FILE=<path to wav file, default: ./yahaha.wav next to this script>
USAGE
}

validate_number() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer, got: $value"
}

get_battery_percent() {
  local output
  local percent

  if ! output="$(pmset -g batt 2>/dev/null)"; then
    die "failed to read battery status with pmset"
  fi

  percent="$(printf '%s\n' "$output" | sed -nE 's/.*[[:space:]]([0-9]{1,3})%;.*/\1/p' | head -n 1)"
  [[ "$percent" =~ ^[0-9]+$ ]] || die "could not parse battery percentage from pmset output"

  printf '%s\n' "$percent"
}

terminate_cinebench() {
  if [[ -n "${cinebench_pid:-}" ]] && kill -0 "$cinebench_pid" 2>/dev/null; then
    log "Stopping Cinebench pid=$cinebench_pid"
    kill "$cinebench_pid" 2>/dev/null || true

    for _ in {1..10}; do
      if ! kill -0 "$cinebench_pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done

    if kill -0 "$cinebench_pid" 2>/dev/null; then
      log "Cinebench did not exit after SIGTERM; sending SIGKILL"
      kill -9 "$cinebench_pid" 2>/dev/null || true
    fi

    wait "$cinebench_pid" 2>/dev/null || true
  fi

  cinebench_pid=""
}

cleanup() {
  terminate_cinebench
}

run_cinebench_once() {
  local elapsed=0

  [[ -x "$CINEBENCH_BIN" ]] || die "Cinebench binary is not executable: $CINEBENCH_BIN"

  log "Starting Cinebench for up to ${RUN_SECONDS}s"
  "$CINEBENCH_BIN" "${CINEBENCH_ARGS[@]}" &
  cinebench_pid="$!"

  while kill -0 "$cinebench_pid" 2>/dev/null; do
    if (( elapsed >= RUN_SECONDS )); then
      terminate_cinebench
      return
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$cinebench_pid" 2>/dev/null || true
  cinebench_pid=""
  log "Cinebench exited before ${RUN_SECONDS}s"
}

play_audio() {
  if [[ ! -r "$AUDIO_FILE" ]]; then
    log "Audio file is not readable: $AUDIO_FILE"
    return 1
  fi

  if command -v afplay >/dev/null 2>&1; then
    afplay "$AUDIO_FILE" || true
  else
    log "afplay not found; cannot play audio"
  fi
}

main() {
  local percent

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  validate_number "THRESHOLD_PERCENT" "$THRESHOLD_PERCENT"
  validate_number "RUN_SECONDS" "$RUN_SECONDS"

  trap cleanup EXIT
  trap 'trap - EXIT; cleanup; exit 130' INT
  trap 'trap - EXIT; cleanup; exit 143' TERM

  while true; do
    percent="$(get_battery_percent)"
    log "Battery: ${percent}%"

    if (( percent <= THRESHOLD_PERCENT )); then
      log "Battery is at or below ${THRESHOLD_PERCENT}%; stopping"
      play_audio || true
      exit 0
    fi

    run_cinebench_once
  done
}

main "$@"
