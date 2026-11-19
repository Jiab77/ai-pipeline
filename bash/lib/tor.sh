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