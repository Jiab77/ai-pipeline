#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/sha256.sh — Portable SHA-256 stream primitive
# ==============================================================================
# Provides source-only SHA-256 hashing through the first verified implementation
# available among sha256sum, shasum, and OpenSSL.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract:
#   _sha256sum — Hash binary stdin and print exactly 64 lowercase hex characters.
#
# Dependencies: sha256sum, shasum, or openssl
# Loading: source only; no output or caller shell-option changes on success.
#
# Backend order: sha256sum -> shasum -a 256 -> openssl dgst -sha256.
# Selection is capability-based, never OS-name-based. At load time, each
# available backend must correctly hash empty stdin; the first valid one is
# cached in _SHA256_BACKEND. Probes cannot consume the caller's future stream.
#
# The payload goes directly from stdin to the selected process. Only its small
# ASCII result enters a shell variable, so binary data and NUL bytes are safe.
# A runtime failure is returned unchanged: retrying another backend then would
# be unsafe because the original input stream cannot be rewound.
#
# LOADING: no output on success, no colors, no caller shell-option changes.
# Loading fails loudly when no backend passes the empty-input probe.
# ==============================================================================

# Idempotent re-sourcing guard (project's composition-root pattern)
[[ -n "${SHA256_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'sha256.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Resolve a real implementation, not merely a name present in PATH. The known
# empty digest also rejects incompatible commands and malformed output.
_SHA256_BACKEND=''
_sha256_empty='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
for _sha256_candidate in sha256sum shasum openssl; do
    command -v "$_sha256_candidate" >/dev/null 2>&1 || continue

    case "$_sha256_candidate" in
        sha256sum)
            if _sha256_output=$(sha256sum </dev/null 2>/dev/null); then
                _sha256_rc=0
            else
                _sha256_rc=$?
            fi
            ;;
        shasum)
            if _sha256_output=$(shasum -a 256 </dev/null 2>/dev/null); then
                _sha256_rc=0
            else
                _sha256_rc=$?
            fi
            ;;
        openssl)
            if _sha256_output=$(openssl dgst -sha256 </dev/null 2>/dev/null); then
                _sha256_rc=0
            else
                _sha256_rc=$?
            fi
            ;;
    esac

    (( _sha256_rc == 0 )) || continue
    if [[ $_sha256_output =~ (^|[^0-9a-f])([0-9a-f]{64})([^0-9a-f]|$) ]] \
        && [[ ${BASH_REMATCH[2]} == "$_sha256_empty" ]]; then
        _SHA256_BACKEND="$_sha256_candidate"
        break
    fi
done
unset _sha256_candidate _sha256_output _sha256_rc _sha256_empty

if [[ -z $_SHA256_BACKEND ]]; then
    unset _SHA256_BACKEND
    printf 'sha256.sh: no usable SHA-256 backend (sha256sum / shasum / openssl)\n' >&2
    return 1
fi

SHA256_SH_LOADED=1

# Hash stdin once. Separate assignment/status handling prevents a failed backend
# from being mistaken for a successful empty digest.
_sha256sum() {
    local output rc

    case "$_SHA256_BACKEND" in
        sha256sum)
            if output=$(sha256sum 2>/dev/null); then rc=0; else rc=$?; fi
            ;;
        shasum)
            if output=$(shasum -a 256 2>/dev/null); then rc=0; else rc=$?; fi
            ;;
        openssl)
            if output=$(openssl dgst -sha256 2>/dev/null); then rc=0; else rc=$?; fi
            ;;
        *)
            printf 'sha256.sh: invalid cached backend: %s\n' "$_SHA256_BACKEND" >&2
            return 1
            ;;
    esac

    if (( rc != 0 )); then
        printf 'sha256.sh: %s failed (rc=%d)\n' "$_SHA256_BACKEND" "$rc" >&2
        return "$rc"
    fi
    if [[ $output =~ (^|[^0-9a-f])([0-9a-f]{64})([^0-9a-f]|$) ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    else
        printf 'sha256.sh: malformed output from %s\n' "$_SHA256_BACKEND" >&2
        return 1
    fi
}
