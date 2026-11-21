#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2001
# ==============================================================================
# lib/history.sh — Shared history functions
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
[[ -n "${HISTORY_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'history.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

HISTORY_SH_LOADED=1

# -----------------------------------------------------------------------------
# History Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# History normalization — the persisted history is the SINGLE source of truth, so
# it must stay PROTOCOL-NEUTRAL. chat/completions is the smallest common denominator
# of every provider; each handler translates to its own wire protocol on the fly
# (api_call_type_responses / build_tool_result / handle_response do exactly that).
#
# This is the safety net for history already poisoned ON DISK by a
# protocol-aware build (incident 2026-09-11: openai items written to messages.json,
# then /provider deepseek -> "messages[25]: missing field `role`"). It heals:
#   {type:"function_call_output",...} -> {role:"tool", tool_call_id, name, content}
#   {type:"function_call",...}        -> {role:"assistant", content:null, tool_calls:[...]}
#   anthropic {role:"assistant", content:[{type:"tool_use",...}]}
#                                     -> {role:"assistant", tool_calls:[...]}
#   anthropic {role:"user", content:[{type:"tool_result",...}]}
#                                     -> one {role:"tool",...} per result
#   tool result with no matching tool_calls id -> dropped (every chat/completions
#   provider rejects it: "must be a response to a preceding tool_calls")
#   consecutive assistant tool_calls turns -> merged
#   non-object / unknown items -> dropped
# Idempotent: normalize_history(normalize_history(x)) == normalize_history(x)
# -----------------------------------------------------------------------------
normalize_history() {
  jq -rc '
    def as_text: [ .[]? | select(type == "object" and .type == "text") | .text ] | join("");
    # argstr: tool arguments MUST be a stringified JSON object on the wire (Cohere:
    # "tool arguments must be a stringified JSON object"). Idempotent by construction:
    # a string is returned untouched, so re-running on a healed history is a no-op.
    def argstr: if type == "string" then . else ((. // {}) | tostring) end;
    def canon_items:
      if type != "object" then []
      elif (.role == "assistant") and ((.content | type) == "array")
           and ([.content[]? | select(.type == "tool_use")] | length > 0) then
        [{ role: "assistant",
           content: ((.content | as_text) | if . == "" then null else . end),
           tool_calls: [ .content[] | select(.type == "tool_use")
                         | { id: (.id // ""), type: "function",
                             function: { name: (.name // "tool"), arguments: ((.input // {}) | argstr) } } ] }]
      elif (.role == "user") and ((.content | type) == "array")
           and ([.content[]? | select(.type == "tool_result")] | length > 0) then
        [ .content[] | select(.type == "tool_result")
          | { role: "tool", tool_call_id: (.tool_use_id // ""), name: "tool",
              content: (if (.content | type) == "string" then .content else (.content | tostring) end) } ]
      elif has("role") then
        if .role == "assistant" then
          . as $m | ((($m.tool_calls // []) | length) > 0) as $tc |
          [ ({ role: "assistant",
               content: (if $tc and (($m.content // "") | length) == 0 then null
                          else ($m.content // null) end) }
             + (if $tc then
                  { tool_calls: [ $m.tool_calls[] | { id: .id, type: "function",
                      function: { name: .function.name,
                        arguments: (if ((.function.arguments // null) | type) == "string"
                                    then .function.arguments
                                    else ((.function.arguments // {}) | tostring) end) } } ] }
                else {} end)) ]
        elif .role == "tool" then
          [ { role: "tool", tool_call_id: (.tool_call_id // ""),
              name: (.name // "tool"),
              content: (if (.content | type) == "string" then .content
                        else (.content | tostring) end) } ]
        elif (.role == "user") or (.role == "system") or (.role == "developer") then
          [ { role: .role, content: .content } ]
        else [] end
      elif .type == "function_call_output" then
        [{ role: "tool", tool_call_id: (.call_id // ""), name: (.name // "tool"), content: (.output // "") }]
      elif .type == "function_call" then
        [{ role: "assistant", content: null,
           tool_calls: [{ id: (.call_id // ""), type: "function",
                          function: { name: (.name // "tool"), arguments: (.arguments | argstr) } }] }]
      else [] end;
    if type == "array" then
      reduce (.[] | canon_items[]) as $c (
        [];
        if ($c.role == "assistant")
             and ((($c.tool_calls // []) | length) > 0)
             and (length > 0)
             and (.[-1].role == "assistant")
             and (((.[-1].tool_calls // []) | length) > 0)
        then .[:-1] + [.[-1] + {tool_calls: (.[-1].tool_calls + $c.tool_calls)}]
        elif ($c.role == "tool")
        then (if (([.[] | select(.role == "assistant") | (.tool_calls // [])[] | .id] | index($c.tool_call_id)) != null)
              then . + [$c] else . end)
        else . + [$c] end
      )
    else empty end' <<< "${1:-[]}" 2>/dev/null
}

# Heal the persisted history on disk (called on provider switch + before each turn).
# Never touches a file that is not valid JSON, never rewrites when nothing changed.
heal_history_file() {
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local current normalized
  [[ -r $messages_path ]] || return 0
  current=$(<"$messages_path")
  [[ -z $current ]] && return 0
  jq -e . >/dev/null 2>&1 <<< "$current" || { log_warn "Persisted history is not valid JSON — left untouched." ; return 0 ; }
  normalized=$(normalize_history "$current")
  [[ -z $normalized ]] && return 0
  # Semantic comparison — a formatting difference must not trigger a rewrite.
  # ⚠️ NEVER feed the documents through argv (--arg / --argjson): a SINGLE argument is
  # capped at 128 KB on Linux (MAX_ARG_STRLEN) → E2BIG → jq fails → this test would
  # ALWAYS conclude "different". Observed 2026-09-11 21:33 on a 550 KB history: the
  # warning fired although the history was already canonical (false positive).
  # One temp file, both documents inside, jq reads a FILE (no argv payload at all).
  printf '[%s,%s]' "$current" "$normalized" > "${messages_path}.cmp"
  if ! jq -e -c '.[0] == .[1]' "${messages_path}.cmp" >/dev/null 2>&1; then
    log_warn "Protocol-tagged history detected on disk — normalizing it before the next turn."
    printf '%s' "$normalized" > "${messages_path}.tmp" && mv -f "${messages_path}.tmp" "$messages_path"
  fi
  rm -f "${messages_path}.cmp"
}

# Persist the conversation history WITHOUT ever destroying a valid one.
# Rationale (audit 2026-09-11): a failing jq command returns an EMPTY string — and the
# former `echo "$doc" > file` wrote that emptiness straight to disk. Two reachable ways
# to get there: `--arg` on a value > 128 KB (E2BIG, MAX_ARG_STRLEN) for the assistant
# answer or for a pasted prompt. Result: the whole conversation silently wiped.
# This helper refuses to replace a valid history with an empty/invalid document.
persist_history() {
  local doc="$1"
  local target="$2"
  local tmp="${target}.tmp"
  if [[ -z $doc ]]; then
    log_error "Refusing to persist an EMPTY history — ${target##*/} left untouched."
    return 1
  fi
  if ! printf '%s' "$doc" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    log_error "Refusing to persist an invalid history (not a non-empty JSON array) — ${target##*/} left untouched."
    return 1
  fi
  printf '%s' "$doc" > "$tmp" || { log_error "Unable to write ${tmp##*/} — ${target##*/} left untouched." ; return 1 ; }
  mv -f "$tmp" "$target"
}