#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/timeout.sh — Portable bounded command execution primitive
# ==============================================================================
# Provides source-only bounded command execution through GNU timeout when
# available, with a Bash process-group watchdog as fallback.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract:
#   _timeout <seconds> <command> [args...]
#   Return 124 on deadline expiry; otherwise return the command status.
#
# Dependencies: mktemp, sleep, rm; optional GNU timeout
# Loading: source only; no output or caller shell-option changes on success.
#
# Execute the command with its arguments and standard streams preserved.
# Return 124 when the deadline expires; otherwise return the command's status.
# GNU timeout is used when available, with no OS-name detection or option clone.
#
# Without GNU timeout, a Bash watchdog starts the command in its own process
# group, then kills that whole group at the deadline. The fallback uses SIGKILL
# rather than GNU's default SIGTERM; deliberately detached descendants can
# still escape it. This is the project's established behavior, not a GNU clone.
#
# LOADING: definitions-only. No output, colors, or caller shell-option changes.
# GNU timeout is optional. Fallback dependencies mktemp, sleep, and rm are
# checked at source time so a missing dependency fails before any child starts.
# ==============================================================================

# Idempotent re-sourcing guard (project's composition-root pattern)
[[ -n "${TIMEOUT_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'timeout.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Fallback dependencies (available on Termux / macOS / Linux)
for _timeout_dep in mktemp sleep rm; do
    if ! command -v "$_timeout_dep" >/dev/null 2>&1; then
        printf 'timeout.sh: missing dependency: %s\n' "$_timeout_dep" >&2
        return 1
    fi
done
unset _timeout_dep

TIMEOUT_SH_LOADED=1

# Subshell isolation keeps job control, locals, and the EXIT trap out of the
# caller. The marker distinguishes a real deadline from a command's own status.
_timeout() (
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    else
        local pid wd rc marker
        marker=$(mktemp "${TMPDIR:-/tmp}/aide-timeout.XXXXXX") || return 1
        set -m
        # Preserve stdin explicitly instead of Bash's asynchronous /dev/null.
        "$@" <&0 & pid=$!
        (
            sleep "$secs"
            printf 'timeout' > "$marker"
            kill -KILL -- "-$pid" 2>/dev/null || true
        ) & wd=$!
        trap 'kill -KILL -- "-$pid" "-$wd" 2>/dev/null || true; rm -f "$marker"' EXIT
        if wait "$pid" 2>/dev/null; then rc=0; else rc=$?; fi
        # Cleanup statuses must never replace the command/deadline status.
        kill -KILL -- "-$wd" 2>/dev/null || true
        wait "$wd" 2>/dev/null || true
        [[ -s $marker ]] && rc=124
        return "$rc"
    fi
)
