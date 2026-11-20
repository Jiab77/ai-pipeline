#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/tor.sh — Shared Tor functions
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
[[ -n "${TOR_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'tor.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

TOR_SH_LOADED=1

# -----------------------------------------------------------------------------
# Tor Functions
# -----------------------------------------------------------------------------

kill_tor_svc() {
  pkill -f "tor -f $TOR_CONFIG" &>/dev/null
}

# A background child inherits the CLI's process group when job control is off:
# Ctrl+C then signals Tor as well as the client. Keep job control local to this
# subshell and let Tor create its OWN process group. No setsid/nohup dependency;
# stdin and logs remain detached exactly as before (Linux/macOS/Termux).
start_tor_detached() (
  set -m
  tor -f "$TOR_CONFIG" </dev/null &>"$TOR_LOG" &
)

load_tor_config() {
  # Check Tor config
  [[ ! -r $TOR_CONFIG ]] && error "Missing Tor config file."

  # Parse and set Tor config
  TOR_HOST="127.0.0.1"
  TOR_PORT=$(grep -v "#" "$TOR_CONFIG" | grep -m1 "SOCKSPort" | cut -d' ' -f2)
  # CTRL_PORT=$(grep -m1 "ControlPort" "$TOR_CONFIG" | cut -d' ' -f2)
  TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"
  # TOR_PROXY_MOBILE="socks4a://${TOR_HOST}:${TOR_PORT}"
  # SOCKS_PROXY="socks5://${TOR_HOST}:${TOR_PORT}"
  TOR_LOG="/tmp/tor.log"
}

detect_tor() {
  log_info "Detecting Tor Network proxy interface..."
  if ! _timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
    log_error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is Tor running?"
    return 1
  else
    log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
    return 0
  fi
}

wait_for_tor() {
  for _ in {1..10}; do
    if _timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
      log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
      return 0
    fi
    sleep 1
  done
  error "Tor proxy ($TOR_PROXY) is configured but unreachable after 10 retries. Is Tor running?"
}

check_tor() {
  log_info "Checking Tor Network proxy interface..."
  if ! _timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
    error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is Tor running?"
  else
    log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
    return 0
  fi
}

handle_tor() {
  local tor_status

  detect_tor ; tor_status=$?
  [[ $tor_status -eq 0 ]] && return $tor_status

  if is_termux; then
    if [[ -n $BIN_TOR ]]; then
      log_info "Starting Tor privacy tunnel..."
      start_tor_detached
    else
      error "Missing required 'tor' binary. Please install it."
    fi
  else
    if [[ -n $BIN_SYSTEMCTL ]]; then
      if [[ ! $(systemctl is-active tor.service) == "active" ]]; then
        if [[ -n $BIN_TOR ]]; then
          log_info "Starting Tor privacy tunnel..."
          start_tor_detached
        else
          error "Missing required 'tor' binary or service. Please install it."
        fi
        # error "Tor service not started. Please run: sudo systemctl start tor.service"
      fi
    elif [[ -n $BIN_TOR ]]; then
      log_info "Starting Tor privacy tunnel..."
      start_tor_detached
    else
      error "Missing required 'tor' binary or service. Please install it."
    fi
  fi

  wait_for_tor || check_tor
}

# Helper: get real exit IP (without Tor)
get_real_exit_ip() {
  local out ; out=$(curl -sSL --max-time 12 "https://ipinfo.io/json" \
    | jq -rc .ip 2>/dev/null) || return 0
  printf '%s' "$out"
}

# Helper: current Tor exit IP through the SOCKS port (empty string on failure)
get_tor_exit_ip() {
  local out ; out=$(curl -x "${TOR_PROXY}" \
    -sS --max-time 12 "https://check.torproject.org/api/ip" 2>/dev/null) || return 0
  printf '%s' "$out" | sed -n 's/.*"IP"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Helper: get new Tor exit IP
get_new_exit_ip() {
  # Tor context is already loaded by the dispatcher bootstrap (TOR_CONFIG/TOR_HOST/TOR_PORT)
  [[ -n ${TOR_CONFIG:-} && -r $TOR_CONFIG ]] || die "Missing Tor config file (torrc)."

  # ControlPort from torrc (source of truth) — zero-fork parse
  local line ctrl_port=""
  while IFS= read -r line; do
    line=${line%%#*}
    case $line in
      ControlPort\ *) ctrl_port=${line#ControlPort } ; ctrl_port=${ctrl_port//[\" ]/} ;;
    esac
  done < "$TOR_CONFIG"
  [[ -n $ctrl_port ]] || die "ControlPort not found in $TOR_CONFIG."

  # 10s client-side rotation guard
  local state="${TMPDIR:-/tmp}/aide-newnym.last"
  local now ; now=$(date +%s)
  local last=0 ; [[ -r $state ]] && last=$(<"$state")
  if (( now - last < 10 )); then
    die "Rotation guard: last request was $(( now - last ))s ago (min 10s)."
  fi

  # Cookie auth (PROTOCOLINFO -> cookie -> hex, jarnet/statusbar proven pattern)
  local cf ; cf=$( ( printf 'PROTOCOLINFO 1\r\nQUIT\r\n'; sleep 0.4 ) \
      | socat -T 5 - "TCP:${TOR_HOST:-127.0.0.1}:${ctrl_port}" 2>/dev/null \
      | sed -n 's/.*COOKIEFILE="\([^"]*\)".*/\1/p' | tr -d '\r')
  [[ -n $cf && -r $cf ]] || die "ControlPort auth cookie unavailable."
  local hex ; hex=$(od -An -tx1 -v "$cf" | tr -d ' \n')

  # Exit IP before rotation
  local old_ip ; old_ip=$(get_tor_exit_ip)

  # AUTHENTICATE + SIGNAL NEWNYM in one session
  local out ; out=$( ( printf 'AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\n' "$hex"; sleep 0.9 ) \
      | socat -T 5 - "TCP:${TOR_HOST:-127.0.0.1}:${ctrl_port}" 2>/dev/null)
  grep -qE '^5[0-9]{2}' <<<"$out" && die "Tor rejected: $(grep -E '^5[0-9]{2}' <<<"$out" | head -n 1)"
  [[ $(grep -c '^250' <<<"$out") -ge 2 ]] || die "Unexpected ControlPort reply."
  printf '%s\n' "$now" > "$state"

  # Exit IP after — retry while exits rotate
  local new_ip="" _try
  for _try in 1 2 3 4 5; do
    sleep 2
    new_ip=$(get_tor_exit_ip)
    [[ -n $new_ip && $new_ip != "$old_ip" ]] && break
  done

  printf '%s' "$new_ip"
}
