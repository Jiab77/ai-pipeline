#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/animate.sh — Terminal animation and spinner primitive
# ==============================================================================
# Provides source-only non-blocking background spinners with customizable
# frames (emojis, ASCII) and message prefix.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract:
#   start_anim [anim_type] [text_prefix] [delay]
#     Starts a background animation loop.
#     $1: Animation name (default: "earth")
#     $2: Optional text displayed before the animation (default: "")
#     $3: Optional frame delay in seconds (default: 0.1)
#
#   stop_anim
#     Stops the background animation loop, clears the line, and restores cursor.
#
#   is_anim_running
#     Returns 0 if an animation is currently running, 1 otherwise.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${ANIMATE_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'animate.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

ANIMATE_SH_LOADED=1

# Global animation PID tracker
ANIM_PID=""

# Animation frames definitions
ANIM_FRAMES_EARTH=(🌍 🌎 🌏)
ANIM_FRAMES_MOON=(🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘)
ANIM_FRAMES_CLOCK=(🕐 🕜 🕑 🕝 🕒 🕞 🕓 🕟 🕔 🕠 🕕 🕡 🕖 🕢 🕗 🕣 🕘 🕤 🕙 🕥 🕚 🕦 🕛 🕧)
ANIM_FRAMES_DIAMOND=(🔸 🔶 🔷 🔹)
ANIM_FRAMES_SQUARE=(🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜)
ANIM_FRAMES_CIRCLE=(🔴 🟠 🟡 🟢 🔵 🟣 🟤 ⚫ ⚪)
ANIM_FRAMES_HEART=(🧡 💛 💚 💙 💜 🤎 🖤 🤍)
ANIM_FRAMES_MONKEYS=(🙈 🙉 🙊)
ANIM_FRAMES_ARROWS=(⬆️  ↗️  ➡️  ↘️  ⬇️  ↙️  ⬅️  ↖️ )
ANIM_FRAMES_DIGITS=(0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟)
ANIM_FRAMES_FINGERS=(👉 👇 👈 👆)
ANIM_FRAMES_SMILEY=(😌 😊 😄 😆 😁)
ANIM_FRAMES_SLASHES=("/" "|" "\\" "-")
ANIM_FRAMES_DOTS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

is_anim_running() {
  [[ -n "${ANIM_PID:-}" ]] && kill -0 "$ANIM_PID" 2>/dev/null
}

start_anim() {
  local anim_type="${1:-earth}"
  local text="${2:-}"
  local delay="${3:-0.1}"
  local -a frames ; frames=()

  # Rewrite animation name in lowercase
  anim_type=$(tr '[:upper:]' '[:lower:]' <<< "$anim_type")

  # Stop any previously running animation to avoid orphan background processes
  stop_anim

  # Animation selector
  case "$anim_type" in
    earth)    frames=("${ANIM_FRAMES_EARTH[@]}") ;;
    moon)     frames=("${ANIM_FRAMES_MOON[@]}") ;;
    clock)    frames=("${ANIM_FRAMES_CLOCK[@]}") ;;
    diamond)  frames=("${ANIM_FRAMES_DIAMOND[@]}") ;;
    square)   frames=("${ANIM_FRAMES_SQUARE[@]}") ;;
    circle)   frames=("${ANIM_FRAMES_CIRCLE[@]}") ;;
    heart)    frames=("${ANIM_FRAMES_HEART[@]}") ;;
    monkeys)  frames=("${ANIM_FRAMES_MONKEYS[@]}") ;;
    arrows)   frames=("${ANIM_FRAMES_ARROWS[@]}") ;;
    digits)   frames=("${ANIM_FRAMES_DIGITS[@]}") ;;
    fingers)  frames=("${ANIM_FRAMES_FINGERS[@]}") ;;
    smiley)   frames=("${ANIM_FRAMES_SMILEY[@]}") ;;
    slashes)  frames=("${ANIM_FRAMES_SLASHES[@]}") ;;
    dots)     frames=("${ANIM_FRAMES_DOTS[@]}") ;;
    *)        frames=("${ANIM_FRAMES_EARTH[@]}") ;;
  esac

  # Hide cursor
  printf '\033[?25l'

  # Launch asynchronous spinner loop in background subshell
  (
    local i=0
    local total=${#frames[@]}
    while true; do
      # \r = back to col 0, \033[K = erase to end of line
      # Displays: [text] [frame]
      printf '\r\033[K%s%s' "${text:+$text }" "${frames[i]}"
      i=$(( (i + 1) % total ))
      sleep "$delay"
    done
  ) &
  ANIM_PID=$!
}

stop_anim() {
  if [[ -n "${ANIM_PID:-}" ]] && kill -0 "$ANIM_PID" 2>/dev/null; then
    kill "$ANIM_PID" 2>/dev/null
    wait "$ANIM_PID" 2>/dev/null 2>&1
    unset ANIM_PID
    # Clear line and restore cursor
    printf '\r\033[K\033[?25h'
  fi
}