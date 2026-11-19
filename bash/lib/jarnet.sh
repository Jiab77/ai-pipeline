#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/jarnet.sh — Shared JarNet functions
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
[[ -n "${JARNET_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'jarnet.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

JARNET_SH_LOADED=1

# -----------------------------------------------------------------------------
# JarNet Functions
# -----------------------------------------------------------------------------

jarnet_start() {
  local jarnet_bin="$NET_HANDLER"

  # Check / Start JarNet transport stack
  if [[ -x "$jarnet_bin" ]]; then
    log_info "Checking JarNet service..."
    # 'up' makes sure that hidden service Tor and local listener are active
    "$jarnet_bin" up &>/dev/null

    # Get hidden service address and onboarding token
    local who_json ; who_json=$("$jarnet_bin" who 2>/dev/null)
    local my_addr ; my_addr=$(jq -r '.onion // empty' <<< "$who_json" 2>/dev/null)
    local my_onboarding ; my_onboarding=$(jq -r '.share // empty' <<< "$who_json" 2>/dev/null)

    # Show hidden service address and onboarding token
    if [[ -n $my_addr ]]; then
      log_success "JarNet online: ${CLR_B_YELLOW}${my_addr}.onion${ANSI_RESET}"
      log_info "Onboarding token: ${ANSI_BOLD}${CLR_B_WHITE}${my_onboarding}${ANSI_RESET} (copy/paste to peer)"
    else
      log_warn "JarNet offline: Please run './${PLUG_DIR##*/}/${jarnet_bin##*/} doctor' to find out why."
      return 1
    fi
  else
    log_warn "Plugin JarNet not found (${jarnet_bin}), P2P listening disabled."
    return 1
  fi
}