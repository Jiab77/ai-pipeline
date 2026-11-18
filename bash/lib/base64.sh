#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/base64.sh — Portable Base64 stream primitives
# ==============================================================================
# Provides source-only Base64 encoding and decoding across GNU and BSD userlands.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract:
#   b64e — Encode stdin as unwrapped Base64 on stdout.
#   b64d — Decode Base64 stdin to decoded bytes on stdout.
#
# Dependencies: base64, tr
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard (project's composition-root pattern)
[[ -n "${BASE64_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'base64.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Hard dependencies (POSIX, present on Termux / macOS / Linux)
for _b64_dep in base64 tr; do
    if ! command -v "$_b64_dep" >/dev/null 2>&1; then
        printf 'base64.sh: missing dependency: %s\n' "$_b64_dep" >&2
        return 1
    fi
done
unset _b64_dep

BASE64_SH_LOADED=1

# Encode as one line without relying on GNU -w0. The subshell keeps pipefail
# local and prevents tr from masking an encoder/read failure.
b64e() (
    set -o pipefail
    base64 | tr -d '\r\n'
)

# Decode using the first supported spelling, probed on demand. Input remains a
# stream; in particular, no command substitution can truncate decoded NUL bytes.
b64d() {
    if [[ -z "${_BASE64_DEC_FLAG:-}" ]]; then
        if base64 --decode </dev/null >/dev/null 2>&1; then
            _BASE64_DEC_FLAG="--decode"
        elif base64 -d </dev/null >/dev/null 2>&1; then
            _BASE64_DEC_FLAG="-d"
        elif base64 -D </dev/null >/dev/null 2>&1; then
            _BASE64_DEC_FLAG="-D"
        else
            printf 'base64.sh: no usable base64 decode flag (--decode / -d / -D)\n' >&2
            return 1
        fi
    fi
    base64 "$_BASE64_DEC_FLAG"
}
