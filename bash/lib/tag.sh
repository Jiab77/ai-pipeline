#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# lib/tag.sh — Shared Anti-XPIA functions
# ==============================================================================
# Provides source-only shared functions
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.0
#
# Contract: LIB_DEPS
#
# Dependencies: core.sh, lib/sha256.sh
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${TAG_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'tag.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

TAG_SH_LOADED=1

# -----------------------------------------------------------------------------
# Experimental Anti-XPIA security layer
# -----------------------------------------------------------------------------

compute_device_tag() {
  local machine_id hostname session_ts
  machine_id=$(cat /etc/machine-id 2>/dev/null \
            || cat /var/lib/dbus/machine-id 2>/dev/null \
            || settings get secure android_id 2>/dev/null \
            || echo "unknown")
  hostname=$(hostname 2>/dev/null || echo "unknown")
  session_ts=$(date +%s)
  echo -n "${machine_id}:${hostname}:aide:${session_ts}" | _sha256sum | cut -c1-16
}

set_auth_tag() {
  AUTH_TAG=$(compute_device_tag)
}

strip_tag_from_display() {
  # Redact any [AUTH:hex] tag echoed by the LLM (defense-in-depth).
  # The tag is input-path only by design, but the LLM can mimic/echo it in its output.
  # Substitution (not removal) preserves surrounding markdown syntax
  # (backticks, bold, italic) — no orphan `` or **** left behind.
  # 'g' = all occurrences.
  sed -E 's/\[AUTH:[a-f0-9]{16}\]/[REDACTED]/g' <<< "$1"
}