#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/base82.sh — Base82 stream and string obfuscation primitives
# ==============================================================================
# Provides the source-only primitives of the Base82 format: Base64 followed by
# ROT13 and ROT5. This is form obfuscation, not cryptography.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract:
#   b82_enc_stream — Encode stdin to Base82 on stdout.
#   b82_dec_stream — Decode Base82 stdin to decoded bytes on stdout.
#   b82_encode     — Encode a string argument.
#   b82_decode     — Decode a string argument.
#
# Source: Jiab77's `base82` project — https://codeberg.org/Jiab77/base82 (2023)
#         (original credit kept: Skyper / THC, for stdin handling in the CLI)
#
# Dependencies: lib/base64.sh, tr
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard (project's composition-root pattern)
[[ -n "${BASE82_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'base82.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Shared Base64 compatibility layer: resolved from THIS file, never from the
# caller's CWD. AIDE_LIB_DIR keeps sandboxed copies relocatable.
_B82_LIB_DIR="${AIDE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ ! -r "${_B82_LIB_DIR}/base64.sh" ]]; then
    printf 'base82.sh: base64.sh not found in %s (set AIDE_LIB_DIR=<dir> to override)\n' "$_B82_LIB_DIR" >&2
    unset _B82_LIB_DIR
    return 1
fi
# shellcheck source=/dev/null
source "${_B82_LIB_DIR}/base64.sh" || { unset _B82_LIB_DIR; return 1; }
unset _B82_LIB_DIR

# Hard dependency (POSIX, present on Termux / macOS / Linux) — fail LOUDLY at
# source time instead of failing mutely on first use. `command -v` is a builtin.
if ! command -v tr >/dev/null 2>&1; then
    printf 'base82.sh: missing dependency: tr\n' >&2
    return 1
fi

BASE82_SH_LOADED=1

# ------------------------------------------------------------------------------
# Primitives
# ------------------------------------------------------------------------------

# ROT13 (A-Za-z) + ROT5 (0-9) = ROT18, involutive: rot(rot(x)) == x.
# `+`, `/` and `=` are left UNTOUCHED, so the base64 alphabet is preserved and
# the output still looks like base64 (that is the whole trick).
b82_rot() { tr 'A-Za-z0-9' 'N-ZA-Mn-za-m5-90-4'; }

# Encode through the shared single-line Base64 helper (never `-w0`, never `<<<`).
b82_enc_stream() { b64e | b82_rot; }

# Decode: inverse ROT, then the shared Base64 decoder. GNU/BSD flag probing
# and its cache live in lib/base64.sh rather than being duplicated here.
b82_dec_stream() { b82_rot | b64d; }

# String API (convenience). For binary payloads — or anything carrying a NUL
# byte — use the *stream* variants: no shell variable can hold a \0.
b82_encode() { printf '%s' "$1" | b82_enc_stream; }
b82_decode() { printf '%s' "$1" | b82_dec_stream; }
