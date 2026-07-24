#!/usr/bin/env bash
#
# ==============================================================================
# showcast.sh — asciinema recorder wrapper for the AI pipeline
# ==============================================================================
# Simple wrapper for the 'asciinema' binary.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (deepseek)
#
# Version: 0.0.0
# ==============================================================================
#
# Usage: /run ./tools/showcast.sh [options]
#        Or directly:         ./tools/showcast.sh [options]
#
# Options:
#   --title "Demo Title"          Title embedded in recording metadata
#   --output path/to/demo.cast    Output file (default: data/demo-YYYYMMDD-HHMMSS.cast)
#   --idle 2                      Idle time cap in seconds (default: 2)
#   --command "bash script.sh"    Run a specific command instead of interactive shell
#   --headless                    Record without hijacking the terminal
#   --stop                        Kill any currently running asciinema recording

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x
set -o pipefail

# Config
TITLE="${TITLE:-Asciinema Record}"
OUTPUT="${OUTPUT:-}"
IDLE_LIMIT="${IDLE_LIMIT:-2}"
COMMAND="${COMMAND:-}"
HEADLESS="${HEADLESS:-false}"

# Parse Options
STOP_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   TITLE="$2"; shift 2 ;;
    --output)  OUTPUT="$2"; shift 2 ;;
    --idle)    IDLE_LIMIT="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --headless) HEADLESS=true; shift ;;
    --stop)    STOP_MODE=true; shift ;;
    -h|--help)
      echo "Usage: ./tools/showcast.sh [--title TITLE] [--output FILE.cast] [--idle SECS] [--command CMD] [--headless] [--stop]"
      exit 0
      ;;
    *) echo "⚠️  Unknown option: $1"; shift ;;
  esac
done

# ── Stop mode: kill any running asciinema recording ──────────────────
if [[ $STOP_MODE == true ]]; then
  ASCIINEMA_PID=$(pgrep -f 'asciinema rec' 2>/dev/null || true)
  if [[ -n $ASCIINEMA_PID ]]; then
    echo "⏹️  Killing asciinema recording (PID $ASCIINEMA_PID)..."
    kill "$ASCIINEMA_PID" 2>/dev/null || true
    sleep 0.5
    # Force kill if still alive
    kill -9 "$ASCIINEMA_PID" 2>/dev/null || true
    echo "✅ Recording stopped."
  else
    echo "⚠️  No running asciinema recording found."
  fi
  exit 0
fi

# ── Pre-flight checks ────────────────────────────────────────────────
if ! command -v asciinema &>/dev/null; then
  echo "❌ asciinema not found. Install it first."
  exit 1
fi

# ── Auto-generate output path ────────────────────────────────────────
if [[ -z $OUTPUT ]]; then
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  OUTPUT="data/demo-${TIMESTAMP}.cast"
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")"

# ── Build the asciinema command ──────────────────────────────────────
ASCIINEMA_ARGS=(
  rec
  --idle-time-limit "$IDLE_LIMIT"
  --title "$TITLE"
)

[[ $HEADLESS == true ]] && ASCIINEMA_ARGS+=(--headless)
[[ -n $COMMAND ]] && ASCIINEMA_ARGS+=(--command "$COMMAND")

ASCIINEMA_ARGS+=("$OUTPUT")

# ── Go ───────────────────────────────────────────────────────────────
echo "🎬 Recording asciinema session..."
echo "   Title:   $TITLE"
echo "   Output:  $OUTPUT"
echo "   Idle cap: ${IDLE_LIMIT}s"
[[ -n $COMMAND ]] && echo "   Command: $COMMAND" || echo "   Mode:    interactive shell"
echo ""
echo "   Press Ctrl+D or type 'exit' to stop recording."
echo "─────────────────────────────────────────────────────"
echo ""

asciinema "${ASCIINEMA_ARGS[@]}"

echo ""
echo "─────────────────────────────────────────────────────"
echo "✅ Recording saved: $OUTPUT"
echo "   Replay:  asciinema play $OUTPUT"
echo "   Upload:  asciinema upload $OUTPUT"
