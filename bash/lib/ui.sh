#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2001
# ==============================================================================
# lib/ui.sh — Shared UI functions
# ==============================================================================
# Provides source-only shared functions
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.0
#
# Contract: LIB_DEPS
#
# Dependencies: core.sh
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${UI_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'ui.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

UI_SH_LOADED=1

# -----------------------------------------------------------------------------
# UI Functions
# -----------------------------------------------------------------------------

# Get terminal width safely (portable Linux + macOS/BSD)
# `stty size < /dev/tty` reads the true tty size on BOTH Linux and macOS.
set_term_width() {
  local cols=""
  if cols=$(stty size < /dev/tty 2>/dev/null); then
    cols=${cols#* }                          # "rows cols" -> cols
  elif command -v tput >/dev/null 2>&1; then
    cols=$(tput cols 2>/dev/null) || true
  fi
  [[ $cols =~ ^[0-9]+$ && $cols -gt 0 ]] || cols=${DEFAULT_TERM_WIDTH:-80}
  TERM_WIDTH=$((cols - 1))
}
get_term_width() {
  echo "$TERM_WIDTH"
}
trap set_term_width WINCH   # Detect window resize

# Draw full width visual horizontal line
draw_line() {
  local char="${1:-─}"
  local count="${2:-$TERM_WIDTH}"
  local line
  printf -v line "%*s" "$count" ""
  echo -e "${line// /$char}"
}

# Render high-tech visual header lines
draw_header() {
  local prefix="$1"
  local char="${2:-─}"
  local line_clr="$3"
  local line_char
  local width ; width=$(get_term_width)
  [[ $prefix == *Tool* ]] && width=$((width + 1))
  local esc ; esc=$(printf '')
  local clean_prefix ; clean_prefix=$(sed "s/${esc}[[0-9;]*m//g" <<<"$prefix")
  # Measure visual length accurately, substituting emojis/wide chars with 2 chars
  local visual_prefix ; visual_prefix=$(sed 's/[👤🤖💭⚙🧠💻⚖🏛🔍ℹ✅⚠️❌]️*/xx/g' <<<"$clean_prefix")
  local prefix_len=${#visual_prefix}
  local remaining_width=$((width - prefix_len))
  printf -v line_char "%*s" "$remaining_width" ""
  echo -e "${prefix}${line_clr}${line_char// /$char}${ANSI_RESET}"
}

# Render beautiful symmetrical titles with lines on both sides
draw_symmetric_header() {
  local title="$1"
  local title_color="$2"
  local line_color="$3"
  local char="${4:-─}"
  local width ; width=$(get_term_width)
  local clean_title="[ $title ]"
  # Measure visual length accurately, substituting emojis/wide chars with 2 chars
  local visual_title ; visual_title=$(sed 's/[👤🤖💭⚙🧠💻⚖🏛🔍ℹ✅⚠️❌]️*/xx/g' <<<"$clean_title")
  local title_len=${#visual_title}
  local total_line_width=$((width - title_len))
  if [ "$total_line_width" -lt 4 ]; then
    echo -e "${line_color}──${title_color}[ ${title} ]${line_color}──${ANSI_RESET}"
    return
  fi
  local left_width=$((total_line_width / 2))
  local right_width=$((total_line_width - left_width))
  local left_line right_line
  printf -v left_line "%*s" "$left_width" ""
  printf -v right_line "%*s" "$right_width" ""
  echo -e "${line_color}${left_line// /$char}${title_color}[ ${title} ]${line_color}${right_line// /$char}${ANSI_RESET}"
}

# Link helper
create_link() {
  local url text

  if [[ $# -eq 2 ]]; then
    url="$1" ; text="$2"
  else
    url="$1" ; text="$url"
  fi

  printf '\e]8;;%s\e\\%s\e]8;;\e\\\n' "$url" "$text"
}

# Core banner
show_banner() {
  echo -e "${CLR_B_MAGENTA}"
  if [[ -n $BIN_FIGLET ]]; then
    figlet <<<"$AI_NAME"
  else
    cat << 'EOF'
     _                  _
    | | __ _ _ ____   _(_)___
 _  | |/ _` | '__\ \ / / / __|
| |_| | (_| | |   \ V /| \__ \
 \___/ \__,_|_|    \_/ |_|___/

EOF
  fi
  echo -e "${CLR_B_CYAN}🔮 ${AI_NAME} $(create_link "https://github.com/jiab77/ai-pipeline" "AI Pipeline") | Version $(get_self_version) 🔮${ANSI_RESET}"
  echo -e "${CLR_DIM}Lead: $(create_link "https://github.com/jiab77" "Jiab77") | AI Sorcerer: ${AI_NAME}${ANSI_RESET}"
  echo -e "${CLR_DIM}Link: ${ANSI_RESET}$(create_link "https://github.com/jiab77/ai-pipeline")"
  echo
}

render_markdown() {
  if command -v glow &>/dev/null; then
    glow -w "$(get_term_width)"
  else
    cat
  fi
}