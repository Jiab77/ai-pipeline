#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/statusbar.sh — Pure-Bash Tor status bar (reserved bottom line)
# ==============================================================================
# Provides source-only shared functions for the CLI 2.x Tor status bar:
# realtime throughput, session totals, built circuits and bootstrap progress,
# rendered on the terminal's last line via a scroll region (tput csr pattern).
#
# Design: pure Bash, zero multiplexer. ControlPort I/O follows the JARNET
# pattern (PROTOCOLINFO -> cookie -> hex -> AUTHENTICATE via socat).
# Ports are NEVER hardcoded: config/torrc is the single source of truth.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.0
#
# Contract: LIB_DEPS
#
# Dependencies: core.sh, lib/tor.sh, lib/ui.sh (WINCH handler), lib/timeout.sh
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${STATUSBAR_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'statusbar.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

STATUSBAR_SH_LOADED=1

# -----------------------------------------------------------------------------
# Status Bar Config
# -----------------------------------------------------------------------------

SBAR_PID=""          # poller background subshell PID
SBAR_ACTIVE=false    # is the bar currently holding the last line?
SBAR_LINE=0          # terminal row reserved for the bar (last line)
SBAR_POLL="${SBAR_POLL:-1.5}"   # seconds between traffic samples
SBAR_HOLD="${SBAR_HOLD:-0.9}"   # stdin hold: tor needs time for big replies
SBAR_TMO="${SBAR_TMO:-3}"       # socat timeout (seconds)
SBAR_PAD="${SBAR_PAD:-2}"       # blank rows between the input line and the bar
# Colors resolved once at start (output captured = plain text, house doctrine)
SBAR_C_MAIN="" ; SBAR_C_ACC="" ; SBAR_C_DIM="" ; SBAR_C_RST=""

# -----------------------------------------------------------------------------
# Status Bar Internals — ControlPort I/O (torrc = source of truth)
# -----------------------------------------------------------------------------

# ControlPort endpoint "host:port" from config/torrc (jarnet.sh convention)
statusbar_ctrl() {
  local ctrl_port
  ctrl_port=$(grep -m1 "ControlPort" "$TOR_CONFIG" 2>/dev/null | cut -d' ' -f2)
  [[ -n $ctrl_port ]] || return 1
  printf '%s:%s' "${TOR_HOST:-127.0.0.1}" "$ctrl_port"
}

# Tor control cookie as hex — PROTOCOLINFO reveals the cookie file path
statusbar_cookie_hex() {
  local ctrl cookie_file
  ctrl=$(statusbar_ctrl) || return 1
  cookie_file=$( ( printf 'PROTOCOLINFO 1\r\nQUIT\r\n' ; sleep 0.4 ) \
      | _timeout "$SBAR_TMO" socat - "TCP:$ctrl" 2>/dev/null \
      | sed -n 's/.*COOKIEFILE="\([^"]*\)".*/\1/p' | tr -d '\r') || return 1
  [[ -n $cookie_file && -r $cookie_file ]] || return 1
  od -An -tx1 -v "$cookie_file" | tr -d ' \n'
}

# Batch GETINFO: AUTHENTICATE + N queries in ONE connection.
# HOLD keeps stdin open long enough for tor to answer (circuit-status is big).
statusbar_get() {  # $1=hex  $2=ctrl  $3..=GETINFO keys
  local hex=$1 ctrl=$2 key
  shift 2
  ( printf 'AUTHENTICATE %s\r\n' "$hex"
    for key in "$@"; do printf 'GETINFO %s\r\n' "$key"; done
    sleep "$SBAR_HOLD" ) | _timeout "$SBAR_TMO" socat - "TCP:$ctrl" 2>/dev/null
}

# Parse one "250[- ]key=value" line from stdin. '|' delimiter is mandatory:
# GETINFO keys contain '/' which breaks the classic 's/../../' form.
statusbar_val() {  # $1=key
  sed -n "s|^250[- ]$1=||p" | tr -d '\r' | head -n1
}

# One sample -> 4 fields: read_bytes written_bytes built_circuits progress
statusbar_sample() {  # $1=hex  $2=ctrl
  local out r w ci bp
  out=$(statusbar_get "$1" "$2" traffic/read traffic/written \
                       circuit-status status/bootstrap-phase) || return 1
  r=$(statusbar_val 'traffic/read' <<< "$out")
  w=$(statusbar_val 'traffic/written' <<< "$out")
  ci=$(grep -c ' BUILT ' <<< "$out")
  bp=$(statusbar_val 'status/bootstrap-phase' <<< "$out")
  if [[ $bp == *PROGRESS=* ]]; then
    bp=${bp##*PROGRESS=} ; bp=${bp%%[!0-9]*}
  else
    bp=0
  fi
  printf '%s %s %s %s\n' "${r:-0}" "${w:-0}" "${ci:-0}" "${bp:-0}"
}

# -----------------------------------------------------------------------------
# Status Bar Helpers — formatting & tty geometry
# -----------------------------------------------------------------------------

# Terminal rows (last usable line number), portable Linux/macOS/Termux
statusbar_tty_lines() {
  local sz ; sz=$(stty size < /dev/tty 2>/dev/null)
  sz=${sz%% *} ; sz=${sz//[!0-9]/}
  [[ -n $sz && $sz -gt 1 ]] || return 1
  printf '%s' "$sz"
}

# Terminal columns, ui.sh-conformant fallback
statusbar_tty_cols() {
  local sz ; sz=$(stty size < /dev/tty 2>/dev/null)
  sz=${sz#* } ; sz=${sz//[!0-9]/}
  [[ -n $sz && $sz -gt 0 ]] || sz=${DEFAULT_TERM_WIDTH:-80}
  printf '%s' "$sz"
}

# Human-readable bytes: "45.2 GiB" — with "/s" suffix when a duration is given
statusbar_human() {  # $1=bytes  [$2=seconds]
  awk -v b="$1" -v t="${2:-0}" 'BEGIN{
    split("B KiB MiB GiB TiB",u," "); i=1; v=b+0;
    if (t>0) v=v/t;
    while (v>=1024 && i<5) {v/=1024;i++}
    if (i==1) printf "%d %s",v,u[i]; else printf "%.2f %s",v,u[i]}'
}

# -----------------------------------------------------------------------------
# Status Bar Rendering
# -----------------------------------------------------------------------------

# Atomic draw on the reserved line: save cursor -> go to last line -> clear ->
# render segments -> restore cursor. \0337/\0338 = DECSC/DECRC (shared tty
# state: user keystrokes between the two markers keep their position).
statusbar_draw() {  # $1=down  $2=up  $3=total  $4=circuits  $5=progress%
  local dl=$1 ul=$2 sum=$3 cir=$4 prog=$5
  local glyph='⬡'
  if [[ $prog -ge 100 ]]; then glyph='⬢'; fi
  local now ; now=$(date +%H:%M)
  local cols ; cols=$(statusbar_tty_cols)
  printf '\0337\033[%d;1H\033[2K' "$SBAR_LINE"
  if [[ $cols -lt 70 ]]; then
    # Termux compact layout
    printf '%b%s%b ▼%s ▲%s │ Σ%s │ ⚡%s │ %s' \
      "$SBAR_C_MAIN" "$glyph" "$SBAR_C_RST" "$dl" "$ul" "$sum" "$cir" "$now"
  else
    # Desktop layout — segmented printf (multi-spec printf is a trap, 18/11)
    printf '%b%s TOR%b  ▼ %s/s ▲ %s/s' "$SBAR_C_MAIN" "$glyph" "$SBAR_C_RST" "$dl" "$ul"
    printf '%b │%b Σ %s'              "$SBAR_C_DIM" "$SBAR_C_RST" "$sum"
    printf '%b │%b ⚡ %s circuits'    "$SBAR_C_ACC" "$SBAR_C_RST" "$cir"
    printf '%b │%b ✅ %s%%'           "$SBAR_C_DIM" "$SBAR_C_RST" "$prog"
    printf '%b │%b %s'                "$SBAR_C_DIM" "$SBAR_C_RST" "$now"
  fi
  printf '\0338'
}

# Background poller: sample -> delta -> draw. NEVER dies on Tor hiccups
# (failed sample = skip frame, retry next poll — resilient to Tor restarts).
statusbar_poller() {  # $1=hex  $2=ctrl
  local hex=$1 ctrl=$2 s
  local prev_r=0 prev_w=0 r w ci bp dl ul sum
  s=$(statusbar_sample "$hex" "$ctrl") || return 0
  read -r prev_r prev_w _ci _bp <<< "$s"

  # Immediate first frame: no stale content left on the reserved line
  statusbar_draw "$(statusbar_human 0)" "$(statusbar_human 0)" \
                 "$(statusbar_human $(( prev_r + prev_w )))" "${_ci:-0}" "${_bp:-0}"

  # Refresh loop
  while true; do
    sleep "$SBAR_POLL"
    s=$(statusbar_sample "$hex" "$ctrl") || continue
    read -r r w ci bp <<< "$s"
    [[ -n $r && -n $w ]] || continue
    dl=$(statusbar_human "$(( r - prev_r ))" "$SBAR_POLL")
    ul=$(statusbar_human "$(( w - prev_w ))" "$SBAR_POLL")
    sum=$(statusbar_human "$(( r + w ))")
    statusbar_draw "$dl" "$ul" "$sum" "${ci:-0}" "${bp:-0}"
    prev_r=$r ; prev_w=$w
  done
}

# Static chrome: separator line just above the bar (metrics-style)
statusbar_chrome() {
  printf '\033[%d;1H' "$((SBAR_LINE - 1))"
  draw_symmetric_header "TOR" "${CLR_B_GREEN}" "${CLR_B_BLACK}"
  printf '\033[%d;1H' "$((SBAR_LINE - 1 - SBAR_PAD))"   # cursor back to prompt row
}

# -----------------------------------------------------------------------------
# Status Bar Lifecycle
# -----------------------------------------------------------------------------

# Re-position the scroll region after a terminal resize (WINCH hook).
# The next poller frame repaints the bar at the new position — no forced redraw.
statusbar_resize() {
  [[ $SBAR_ACTIVE == true ]] || return 0
  local lines
  lines=$(statusbar_tty_lines) || return 0
  SBAR_LINE=$lines
  printf '\033[1;%dr' "$((SBAR_LINE - 1 - SBAR_PAD))"
  statusbar_chrome                                      # clean separator between custom prompt and status bar
}

# Stop the poller and restore the terminal (scroll region + traps).
statusbar_stop() {
  if [[ -n ${SBAR_PID:-} ]] && kill -0 "$SBAR_PID" 2>/dev/null; then
    kill "$SBAR_PID" 2>/dev/null
    wait "$SBAR_PID" 2>/dev/null
  fi
  SBAR_PID=""
  if [[ $SBAR_ACTIVE == true ]]; then
    printf '\033[0;0r\033[s\033[1A\033[0J\033[u'
    SBAR_ACTIVE=false
  fi
  # Restore the handlers that were active before the bar (ui.sh / cli.sh)
  if command -v set_term_width >/dev/null 2>&1; then
    trap set_term_width WINCH
  fi
  if command -v cleanup_the_mess >/dev/null 2>&1; then
    trap cleanup_the_mess EXIT TERM
  fi
}

# Start the bar. SILENT DEGRADE: any precondition failure returns non-zero
# WITHOUT touching the terminal — the caller decides what to display.
# NOTE: never call load_tor_config() before checking the torrc ourselves:
# its error() handler EXITS the whole pipeline (core.sh l.324).
statusbar_start() {
  statusbar_stop                      # single instance guard (animate.sh pattern)
  [[ -t 0 && -t 1 ]] || return 1      # interactive TTY only
  [[ -r ${TOR_CONFIG:-} ]] || return 1
  load_tor_config

  local hex ctrl lines
  hex=$(statusbar_cookie_hex) || return 1
  ctrl=$(statusbar_ctrl) || return 1
  lines=$(statusbar_tty_lines) || return 1

  # Colors: resolve ONCE here — the poller subshell inherits them
  if [[ -t 1 ]]; then
    SBAR_C_MAIN=${CLR_B_GREEN:-} ; SBAR_C_ACC=${CLR_B_YELLOW:-}
    SBAR_C_DIM=${CLR_B_BLACK:-}  ; SBAR_C_RST=${ANSI_RESET:-}
  fi

  # Reserve the last line: scroll region excludes it entirely
  SBAR_LINE=$lines
  printf '\n'                                           # fresh line below the banner (scrolls once if already at bottom)
  printf '\033[1;%dr' "$((SBAR_LINE - 1 - SBAR_PAD))"   # DECSTBM: top=1, bottom=prompt row (top;bottom!)
  printf '\033[%d;1H' "$((SBAR_LINE - 1 - SBAR_PAD))"   # park cursor on the prompt row (region bottom margin)
  printf '\033[J'                                       # clear prompt row + air zone (bar not up yet)
  statusbar_chrome                                      # clean separator between custom prompt and status bar
  SBAR_ACTIVE=true

  statusbar_poller "$hex" "$ctrl" &
  SBAR_PID=$!
  return 0
}

# Start the bar AND arm the cli.sh integration traps. Single entry point for
# BOTH the boot hook and the live '/status on' toggle (DRY — the two trap
# lines live here, nowhere else). Silent degrade: returns non-zero WITHOUT
# touching traps or terminal when preconditions fail (no torrc, no TTY...).
statusbar_enable() {
  if [[ $SBAR_ACTIVE == true ]]; then
    return 0                          # already up — no restart flicker
  fi
  statusbar_start || return 1
  trap 'cleanup_the_mess ; statusbar_stop' EXIT TERM
  trap 'set_term_width ; statusbar_resize' WINCH
  return 0
}
