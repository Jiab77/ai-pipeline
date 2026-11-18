#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091
# ==============================================================================
# lib/nightmare.sh — Hexadecimal and Base82 obfuscation primitives
# ==============================================================================
# Provides source-only Nightmare encoding and decoding by composing hexadecimal
# transformation with Base82. This is form obfuscation, not cryptography.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract:
#   nm_enc_stream — Encode stdin to Nightmare format on stdout.
#   nm_dec_stream — Decode Nightmare stdin to decoded bytes on stdout.
#   nm_encode     — Encode a string argument.
#   nm_decode     — Decode a string argument.
#
# Source: Jiab77's `nightmare` project — https://codeberg.org/Jiab77/nightmare
#         (2024) — "Generate strings that are a nightmare to decipher".
#
# Dependencies: lib/base82.sh, od, sed
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${NIGHTMARE_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'nightmare.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Hard dependencies of THIS stage (POSIX) — fail loudly at source time
for _nm_dep in od sed; do
    if ! command -v "$_nm_dep" >/dev/null 2>&1; then
        printf 'nightmare.sh: missing dependency: %s\n' "$_nm_dep" >&2
        return 1
    fi
done
unset _nm_dep

# base82 dependency: resolved from THIS file (never from CWD nor from the
# caller's SCRIPT_DIR, which vary depending on the caller: cli.sh, tools.sh,
# specs.sh, sandbox copies). Overridable via AIDE_LIB_DIR for sandboxes whose
# core.sh copy lives outside the repo root.
_NM_LIB_DIR="${AIDE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ ! -r "${_NM_LIB_DIR}/base82.sh" ]]; then
    printf 'nightmare.sh: base82.sh not found in %s (set AIDE_LIB_DIR=<dir> to override)\n' "$_NM_LIB_DIR" >&2
    unset _NM_LIB_DIR
    return 1
fi
source "${_NM_LIB_DIR}/base82.sh" || { unset _NM_LIB_DIR; return 1; }
unset _NM_LIB_DIR

NIGHTMARE_SH_LOADED=1

# ------------------------------------------------------------------------------
# Primitives (order imposed by the original: hexify THEN basify82)
# ------------------------------------------------------------------------------

# Hex: `od` replaces `xxd` (POSIX, present on Termux / macOS / Linux).
nm_hex_enc_stream() { od -An -v -tx1 | tr -d ' \n'; }

# Unhex: `printf '%b'` expands the \xNN escapes. Odd length = loud failure
# (see the header).
nm_hex_dec_stream() {
    local h
    h=$(tr -d '[:space:]')
    if (( ${#h} % 2 != 0 )); then
        printf 'nightmare.sh: invalid hex (odd length: %d)\n' "${#h}" >&2
        return 1
    fi
    printf '%b' "$(printf '%s' "$h" | sed 's/\(..\)/\\x\1/g')"
}

# Encode: hex then base82 — the order of his `nightmarify`
nm_enc_stream() { nm_hex_enc_stream | b82_enc_stream; }
# Decode: base82 then unhex — the order of his `dreamify`
nm_dec_stream() { b82_dec_stream | nm_hex_dec_stream; }

# String API (convenience; text only, see base82's \0 warning)
nm_encode() { printf '%s' "$1" | nm_enc_stream; }
nm_decode() { printf '%s' "$1" | nm_dec_stream; }
