#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034,SC2089
# ==============================================================================
# lib/backend.sh — Shared backend functions
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
[[ -n "${BACKEND_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'backend.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

BACKEND_SH_LOADED=1

# -----------------------------------------------------------------------------
# API Transport Layer
# -----------------------------------------------------------------------------

api_call_type_completions() {
  local payload="$1"
  local url="$2"
  local -a curl_opts ; curl_opts=("-sSL")

  # Add required arguments when TOR is enabled
  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  # Override URL when necessary
  [[ -z $url ]] && url="$PROVIDER_API_URL"

  # -----------------------------------------------------------------------------
  # Canonical reasoning translation (upstream)
  # Internal payload carries "reasoning": {enabled: true|false} (core.sh).
  # OpenAI-compatible chat completions endpoints expect a top-level
  # "reasoning_effort" string instead (none|low|medium|high).
  # Translate ONCE here, then let specific provider cases adjust or remove.
  # -----------------------------------------------------------------------------
  local reasoning_enabled ; reasoning_enabled=$(jq -rc '.reasoning.enabled // false' <<< "$payload" 2>/dev/null)
  if [[ $reasoning_enabled == true ]]; then
    payload=$(jq -rc --arg effort "${REASONING_EFFORT:-low}" '
      del(.reasoning)
      | .reasoning_effort = (
          if   $effort == "none"    then "none"
          elif $effort == "minimal" then "low"
          elif $effort == "xhigh"   then "high"
          elif $effort == "max"     then "high"
          else                           $effort
          end
        )' <<< "$payload" 2>/dev/null)

    [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} reasoning.enabled -> reasoning_effort: ${CLR_B_WHITE}${REASONING_EFFORT}${ANSI_RESET}"
  else
    # Reasoning disabled: drop internal object, explicitly disable thinking
    payload=$(jq -rc 'del(.reasoning) | .reasoning_effort = "none"' <<< "$payload" 2>/dev/null)
  fi

  # Provider selector
  case $PROVIDER in
    # Vercel / Vercel Free
    vercel*)
      # Apply ZDR policy when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention payload injection enforced for Vercel AI Gateway."
        payload=$(jq -rc '.providerOptions.gateway.zeroDataRetention = true' <<< "$payload" 2>/dev/null)
      fi

      # Disallow prompt training by default
      payload=$(jq -rc '.providerOptions.gateway.disallowPromptTraining = true' <<< "$payload" 2>/dev/null)

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -H "http-referer: ${ATTRIBUTION_REFERER}" \
            -H "x-title: ${ATTRIBUTION_TITLE}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Infomaniak
    infomaniak)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not implemented for Infomaniak." ; log
      fi

      # Get user product id
      if [[ -z $IFM_PID_CACHE ]]; then
        local prod_id ; prod_id=$(get_infomaniak_product_id)

        # Store gathered product id in memory
        IFM_PID_CACHE="$prod_id"
      fi

      # Check product id
      [[ -z $IFM_PID_CACHE || $IFM_PID_CACHE == "null" ]] && error "Returned Infomaniak product ID is invalid or empty."

      # Rewrite URL with gathered product id
      url="${url//product_id/$IFM_PID_CACHE}"

      # Send generic payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Mistral AI
    mistral)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not applied: https://docs.mistral.ai/admin/monitor-comply/zero-data-retention" ; log
      fi

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Proton Lumo
    # FIXME: Add automatic Tor exit IP address rotation if necessary
    proton)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not necessary for Proton." ; log
      fi

      # Disable reasoning / reasoning_effort (not supported)
      payload=$(jq -rc 'del(.reasoning, .reasoning_effort)' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter removed explicitely for Proton Lumo."

      # Add client type to the payload
      payload=$(jq -rc '.lumo.client_type = "frontend"' <<< "$payload" 2>/dev/null)

      # Enable their external tools
      #
      # FIXME: Might be probably better to recreate the same tools on our own...
      #
      # Available tools: weather, stock, cryptocurrency, proton_info,
      #                  web_extract, web_search
      #
      # Available tools (streaming): generate_image, describe_image, edit_image
      #
      # Enabled tools: see 'config/tools-lumo.json'
      local proton_tools   ; proton_tools=$(<"$LUMO_TOOLS")
      local pipeline_tools ; pipeline_tools=$(<"$BASE_TOOLS")
      local combined_tools ; combined_tools=$(jq -rc -n \
        --argjson proton "$proton_tools" \
        --argjson pipeline "$pipeline_tools" \
        '[$proton, $pipeline] | flatten' 2>/dev/null)

      # Combine all the tools in the received payload
      payload=$(jq -rc --argjson tools "$combined_tools" '.tools = $tools' <<< "$payload" 2>/dev/null)

      # Enable automatic tools selection
      payload=$(jq -rc '.tool_choice = "auto"' <<< "$payload" 2>/dev/null)

      # Lumo transport-failure handling (ENHANCE_YOUR_CALM) -- same bounded retry
      # pattern as the Groq rate-limiter loop. Unlike Groq the block is seen at
      # TRANSPORT level (curl rc 92 HTTP/2 reset, rc 52 empty reply, HTTP 000):
      # no JSON body, no server-provided wait time -> local exponential backoff.
      local response curl_rc attempt=1 max_attempts=10 wait_time=5
      while (( attempt <= max_attempts )); do
        # Send payload (stderr discarded: curl prints the reset there)
        response=$(curl_wrapper "${curl_opts[@]}" "${url}" \
          -H "Content-Type: application/json" \
          -H "Accept: application/json" \
          -H "x-pm-appversion: web-lumo@5.0.0" \
          -A "$USER_AGENT" \
          -d @- <<< "$payload" 2>/dev/null)
        curl_rc=$?

        # Transport-level failure: HTTP/2 stream reset (92) or empty reply (52)
        if (( curl_rc == 92 || curl_rc == 52 )); then
          if (( attempt == ( max_attempts / 2 ) )); then
            echo -n " - " >&2 ; log_warn "${CLR_B_YELLOW}[TRANSPORT]${ANSI_RESET} Lumo: ENHANCE_YOUR_CALM, (attempt ${attempt}/${max_attempts}) -- Changing Tor exit IP address..."
            get_new_exit_ip
            sleep "$wait_time"
            wait_time=$(( wait_time / 2 ))
            ((attempt++))
            continue
          fi
          if (( attempt < max_attempts )); then
            echo -n " - " >&2 ; log_warn "${CLR_B_YELLOW}[TRANSPORT]${ANSI_RESET} Lumo: ENHANCE_YOUR_CALM, retry in ${wait_time}s (attempt ${attempt}/${max_attempts})"
            sleep "$wait_time"
            wait_time=$(( wait_time * 2 ))
            ((attempt++))
            continue
          fi
          # Last attempt failed: return an OpenAI-shaped error object, never empty
          jq -nc --arg msg "Lumo: ENHANCE_YOUR_CALM after ${max_attempts} attempts (HTTP/2 reset, likely Tor exit reputation)" \
            '{error:{message:$msg,type:"transport_error",code:"enhance_your_calm"}}'
          return 0
        fi

        # Empty response (other curl failure, e.g. timeout) -- same contract
        if [[ -z $response ]]; then
          jq -nc --arg msg "Lumo: transport failure (curl rc ${curl_rc})" \
            '{error:{message:$msg,type:"transport_error",code:"transport_failed"}}'
          return 0
        fi

        # Success or non-transport error: pass body through and exit loop
        jq -rc . <<<"$response"
        return 0
      done
    ;;

    # Hugging Face
    huggingface)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not supported for Hugging Face." ; log
      fi

      # Disable reasoning / reasoning_effort (not supported)
      payload=$(jq -rc 'del(.reasoning, .reasoning_effort)' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter removed explicitely for Hugging Face."

      # Get current model
      local current_model ; current_model=$(jq -rc .model <<< "$payload" 2>/dev/null)

      # Apply fastest provider selector on the current model
      payload=$(jq -rc '.model = "'"$current_model"':fastest"' <<< "$payload" 2>/dev/null)

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Venice AI
    venice)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not applied, you need to go in your settings -> General -> 'Disable Telemetry Collection' -> On." ; log
      fi

      # Remove Venice AI System Prompt by default
      payload=$(jq -rc '.venice_parameters.include_venice_system_prompt = false' <<< "$payload" 2>/dev/null)

      # Force E2EE calls by default (not enabled yet -- need to be sure it won't block everything)
      # payload=$(jq -rc '.venice_parameters.enable_e2ee = true' <<< "$payload" 2>/dev/null)

      # Force parallel tool calls by default
      payload=$(jq -rc '.parallel_tool_calls = true' <<< "$payload" 2>/dev/null)

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -w "%output{$VENICE_BALANCE_FILE}balance: %header{x-venice-balance-usd}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # CyberNeurova (same as generic but rate-limited)
    cyberneurova)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not implemented for CyberNeurova." ; log
      fi

      # Add minor delay to avoid triggering the rate limiter
      sleep 1

      # Send generic payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Groq (free-tier / paid -- rate-limited unfortunately)
    groq)
      # Warn that ZDR policy is not implemented yet for Groq
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not implemented yet for Groq."
      fi

      # Disable reasoning / reasoning_effort (not supported)
      payload=$(jq -rc 'del(.reasoning, .reasoning_effort)' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter removed explicitely for Groq."

      # Remove 'reasoning_content' from history messages in payload (causes issues)
      payload=$(jq -rc '
        .messages |= map(
          if .role == "assistant"
          then del(.reasoning_content)
          else .
          end
        )
      ' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning content removed explicitely for Groq."

      # Groq rate-limiter handling code
      local response attempt=1 max_attempts=3
      while (( attempt <= max_attempts )); do
        # Send custom payload and capture the output
        response=$(curl_wrapper "${curl_opts[@]}" "${url}" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
          -A "$USER_AGENT" \
          -d @- <<< "$payload" 2>/dev/null)

        # Parse potential errors from the response
        local error_code error_msg wait_time
        error_code=$(jq -r '.error.code // empty' <<<"$response" 2>/dev/null)
        error_msg=$(jq -r '.error.message // empty' <<<"$response" 2>/dev/null)
        wait_time=""

        # Check if we triggered a rate limit (TPM/RPM/TPD exceeded) and
        # extract seconds (s) from the wait message
        if [[ $error_code == "rate_limit_exceeded" && \
              $error_msg =~ try[[:space:]]again[[:space:]]in[[:space:]]([0-9]+([.][0-9]+)?)s ]]; then

          # Convert duration to total seconds and add 1s security padding
          wait_time=$(( ${BASH_REMATCH[1]%.*} + 1 ))

          # Waiting time too long: Leaving the loop
          if (( wait_time > 60 )); then
            jq -rc . <<<"$response"
            return 0
          fi

          echo -n " - " >&2 ; log_warn "${CLR_B_YELLOW}[RATE LIMIT]${ANSI_RESET} Groq: ${wait_time}s (attempt ${attempt}/${max_attempts})"
          sleep "$wait_time"
          ((attempt++))
          continue
        fi

        # Success or non-rate-limit error, return output and exit loop
        jq -rc . <<<"$response"
        return 0
      done

      # If all retries failed, return last response
      jq -rc . <<<"$response"
    ;;

    # DeepSeek AI / Moonshot AI (Kimi) / Z.AI
    deepseek|kimi|zai*)
      # Warn that ZDR policy does not exist on DeepSeek
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not supported on this provider."
      fi

      # Get current reasoning value before removing it (for compatibility reason)
      local reasoning_effort ; reasoning_effort=$(jq -rc '.reasoning_effort // empty' <<< "$payload" 2>/dev/null)
      if [[ -n $reasoning_effort && ! $reasoning_effort == "none" ]]; then
        payload=$(jq -rc '.thinking.type = "enabled"' <<< "$payload" 2>/dev/null)
      fi

      # Disable reasoning / reasoning_effort (not supported)
      payload=$(jq -rc 'del(.reasoning, .reasoning_effort)' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter converted to Thinking parameter for this provider."

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # OpenRouter
    openrouter)
      # Apply ZDR policy when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention payload injection enforced for OpenRouter."
        payload=$(jq -rc '.provider.zdr = true' <<< "$payload" 2>/dev/null)
      fi

      # Force OpenRouter to route the request to the right provider / model for given parameters
      payload=$(jq -rc '.provider.require_parameters = true' <<< "$payload" 2>/dev/null)

      # Disallow prompt training by default
      payload=$(jq -rc '.provider.data_collection = "deny"' <<< "$payload" 2>/dev/null)

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -H "HTTP-Referer: ${ATTRIBUTION_REFERER}" \
            -H "X-OpenRouter-Title: ${ATTRIBUTION_TITLE}" \
            -H "X-OpenRouter-Categories: ${ATTRIBUTION_CATEGORIES}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # OpenRouter Free
    openrouter_free)
      # Apply ZDR policy when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention payload injection enforced for OpenRouter."
        payload=$(jq -rc '.provider.zdr = true' <<< "$payload" 2>/dev/null)
      fi

      # Force OpenRouter to route the request to the right provider / model for given parameters
      payload=$(jq -rc '.provider.require_parameters = true' <<< "$payload" 2>/dev/null)

      # Disallow prompt training by default (except for analyzing images in free mode)
      # Required because there is no providers on OpenRouter that accepts to process image
      # without keeping data for training purposes for free.
      # Let's see if an acceptable trade-off for the 'openrouter_free' provider...
      # Note: check the messages only — tool schemas may mention "image_url"
      # without any actual image being sent
      if ! jq -e '[.messages[]? | .content[]? | objects | select(.type? == "image_url")] | length > 0' <<< "$payload" >/dev/null 2>&1; then
        payload=$(jq -rc '.provider.data_collection = "deny"' <<< "$payload" 2>/dev/null)
      else
        log_warn "🔒 ${CLR_B_CYAN}[DPT]${ANSI_RESET} Disallow Prompt Training policy disabled temporary during image processing." ; log
      fi

      # Send custom payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -H "HTTP-Referer: ${ATTRIBUTION_REFERER}" \
            -H "X-OpenRouter-Title: ${ATTRIBUTION_TITLE}" \
            -H "X-OpenRouter-Categories: ${ATTRIBUTION_CATEGORIES}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Any other supported providers
    *)
      # Send generic payload
      curl_wrapper "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;
  esac
}

api_call_type_responses() {
  local payload="$1"
  local url="$2"
  local -a curl_opts ; curl_opts=("-sSL")

  # Add required arguments when TOR is enabled
  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  # Override URL when necessary (providers.json already points to /v1/responses for openai)
  [[ -z $url ]] && url="$PROVIDER_API_URL"

  # Reshape Chat Completions payload into Responses shape
  # 1. messages -> input, converting content blocks to Responses types
  #    (text -> input_text, image_url -> input_image)
  payload=$(jq -rc '
    def to_responses_content:
      if type == "string" then .
      else map(
        if .type == "image_url" then { type: "input_image", image_url: .image_url.url }
        elif .type == "text" then { type: "input_text", text: .text }
        else . end
      ) end;
    def chat_to_responses_items:
      del(.reasoning_content)
      | if .role == "tool" then
          [{ type: "function_call_output", call_id: .tool_call_id, output: (.content | tostring) }]
        elif .role == "assistant" and ((.tool_calls // []) | length) > 0 then
          ([ if (.content != null and .content != "") then { role: "assistant", content: (.content | to_responses_content) } else empty end ]
           + [ .tool_calls[] | { type: "function_call", call_id: .id, name: .function.name, arguments: .function.arguments } ])
        else
          [ if has("content") then .content = (.content | to_responses_content) else . end ]
        end;
    { input: ([ .messages[]? | chat_to_responses_items ] | add // []) } + del(.messages)
  ' <<< "$payload" 2>/dev/null)

  # 2. tools: external tag -> internal tag
  if [[ $(jq -rc '(.tools // [] | length)' <<< "$payload" 2>/dev/null) -gt 0 ]]; then
    payload=$(jq -rc '.tools = [.tools[] | {type: "function", name: .function.name, description: .function.description, parameters: .function.parameters}]' <<< "$payload" 2>/dev/null)
  else
    payload=$(jq -rc 'del(.tools)' <<< "$payload" 2>/dev/null)
  fi

  # 3. reasoning.enabled -> reasoning.effort
  local reasoning_enabled ; reasoning_enabled=$(jq -rc '.reasoning.enabled // false' <<< "$payload" 2>/dev/null)
  if [[ $reasoning_enabled == true ]]; then
    payload=$(jq -rc --arg effort "$REASONING_EFFORT" '.reasoning = {effort: $effort, summary: "auto"}' <<< "$payload" 2>/dev/null)
  else
    payload=$(jq -rc 'del(.reasoning)' <<< "$payload" 2>/dev/null)
  fi

  # 4. ZDR / stateless replay
  # ⚠️ DECISION (2026-09-11, incident "2 erreurs d'un coup") : the previous_response_id
  # chaining is ABANDONED. The context sent in 'input' is self-sufficient from now on
  # (the assistant turn is replayed as 'function_call' items by chat_to_responses_items,
  # the tool results as 'function_call_output'), which:
  #   (a) kills the orphan error "No tool call found for function call output with
  #       call_id ..." — prev_response_id was reset at every turn while the history,
  #       itself, survives on disk (repro: data/jq-orphan-check.sh);
  #   (b) kills the duplicate-history risk (server state + disk state both injected);
  #   (c) makes ZDR (store:false) a non-issue instead of a dead end.
  # if [[ $ZDR_ENFORCED == true ]]; then
  #   [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention enforced for OpenAI Responses (store: false)."
  #   payload=$(jq -rc '.store = false' <<< "$payload" 2>/dev/null)
  # fi

  # Enforcing ZDR by default (just for testing)
  [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention enforced for OpenAI Responses (store: false)."
  payload=$(jq -rc '.store = false' <<< "$payload" 2>/dev/null)

  # Send custom payload
  curl_wrapper "${curl_opts[@]}" "${url}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
        -A "$USER_AGENT" \
        -d @- <<< "$payload" | jq -rc .
}

api_call_type_messages() {
  local payload="$1"
  local url="$2"
  local -a curl_opts ; curl_opts=("-sSL")
  local version

  # Add required arguments when TOR is enabled
  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  # Override URL when necessary
  [[ -z $url ]] && url="$PROVIDER_API_URL"

  # Get defined version from config
  version=$(jq -rc ".${PROVIDER}.version // empty" "$PROVIDERS_CONFIG" 2>/dev/null)

  # Hardcode version if not found in config
  [[ -z $version ]] && version="2023-06-01"

  # Extract system prompt from system-role messages
  local system_prompt ; system_prompt=$(jq -rc '[.messages[]? | select(.role=="system") | .content] | join("\n")' <<< "$payload" 2>/dev/null)

  # Resolve max_tokens: read from config (provider-specific), fallback to global default
  local max_tokens ; max_tokens=$(jq -rc ".${PROVIDER}.default.max_tokens // empty" "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $max_tokens || $max_tokens == "null" ]] && max_tokens="$MAX_OUTPUT_TOKENS"

  # Reshape payload (jq defs are local to this program)
  # E2BIG (2026-09-12): the system prompt (memory index + skills + rules) travels by
  # FILE + --rawfile — a heavy bootstrap can approach the 128 KB argv ceiling.
  printf '%s' "$system_prompt" > "$TEMP_PAYLOAD_SYSTEM"
  payload=$(jq -rc \
    --rawfile system "$TEMP_PAYLOAD_SYSTEM" \
    --argjson max_tokens "$max_tokens" \
    'def to_anthropic_content:
       if type == "string" then .
       else map(
         if .type == "image_url" then
           ( .image_url.url as $u
           | if ($u | startswith("data:")) then
               { type: "image",
                 source: { type: "base64",
                           media_type: ($u | split(",")[0] | sub("data:"; "") | sub(";base64"; "")),
                           data: ($u | split(",")[1]) } }
             else
               { type: "image", source: { type: "url", url: $u } }
             end )
         else . end
       ) end;
     {
       model: .model,
       max_tokens: $max_tokens
     }
     + (if ($system | length) > 0 then {system: $system} else {} end)
     + { messages: [.messages[]? | select(.role != "system") | {role: .role, content: (.content | to_anthropic_content)}] }
     + (if (.tools // [] | length) > 0 then
          { tools: [.tools[] | {name: .function.name, description: .function.description, input_schema: .function.parameters}] }
        else {} end)
    ' <<< "$payload" 2>/dev/null)

  # Show ZDR policy warning when enabled
  if [[ $ZDR_ENFORCED == true ]]; then
    log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not implemented for this provider." ; log
  fi

  # Send request with Anthropic-specific auth headers
  curl_wrapper "${curl_opts[@]}" "${url}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${PROVIDER_API_KEY}" \
        -H "anthropic-version: ${version}" \
        -A "$USER_AGENT" \
        -d @- <<< "$payload" | jq -rc .
}

api_call() {
  local payload="$1"
  local url="$2"
  local -a curl_opts ; curl_opts=("-sSL")

  # Apply defined local model settings
  if [[ ! $BACKEND == "external" ]]; then
    # Extract active model from 'payload'
    local active_model ; active_model=$(jq -rc '.model' <<<"$payload" 2>/dev/null)

    # Define right model settings
    set_model_settings "$active_model"

    # Apply model settings on-the-fly — ONE jq pass, and tolerant to undefined values.
    # PREVIOUS BEHAVIOUR (bug, fixed 2026-09-11): the four assignments were chained
    # separately, so an empty value produced an invalid jq program (`.min_p = `)
    # whose error was swallowed by 2>/dev/null → stdout empty → **the whole payload
    # was WIPED**. `MODEL_MIN_P` has no `.default` fallback, so it was empty for every
    # local model except LiquidAI/LFM2.5-VL-1.6B-GGUF.
    payload=$(jq -rc \
      --argjson t "${MODEL_TEMP:-null}" \
      --argjson k "${MODEL_TOP_K:-null}" \
      --argjson p "${MODEL_MIN_P:-null}" \
      --argjson r "${MODEL_REP_PENALTY:-null}" \
      'if $t != null then .temperature        = $t else . end
     | if $k != null then .top_k              = $k else . end
     | if $p != null then .min_p              = $p else . end
     | if $r != null then .repetition_penalty = $r else . end' <<<"$payload" 2>/dev/null)
  fi

  # Force non-streaming calls for all models / providers
  # Note: Can be made conditional in the future if necessary
  payload=$(jq -rc '.stream = false' <<<"$payload" 2>/dev/null)

  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      curl_wrapper "${curl_opts[@]}" "${OLLAMA_API_URL}" \
           -H "Content-Type: application/json" \
           -d @- <<< "$payload" | jq -rc '.'
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      curl_wrapper "${curl_opts[@]}" "${LLAMA_CPP_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer no-key" \
           -d @- <<< "$payload" | jq -rc '.'
    ;;

    # External Backend: OpenRouter, Vercel, Mammouth AI
    external)
        # Call handler selector
        case $PROVIDER in
          openai|xai) api_call_type_responses "$payload" "$url" ;;
          anthropic) api_call_type_messages "$payload" "$url" ;;
          *) api_call_type_completions "$payload" "$url" ;;
        esac
    ;;
    *) error "Unsupported backend given: $BACKEND" ;;
  esac
}

handle_errors() {
  local raw_res="$1"

  if jq -e '.error' <<<"$raw_res" &>/dev/null; then
    err_msg=$(jq -rc '.error // .error.message // .error.message.message' <<<"$raw_res" 2>/dev/null)
    err_meta=$(jq -rc '.error.metadata // empty' <<<"$raw_res" 2>/dev/null)
    err_code=$(jq -rc '.error.code // .error.param.statusCode' <<<"$raw_res" 2>/dev/null)
    if [[ -n $err_meta && ! $err_meta == "null" ]]; then
      err_string_meta="\n\nDetails:\n\n$(jq -rc '.raw // "N/A"' <<<"$err_meta" 2>/dev/null)"
    fi
    if [[ -n $err_code && ! $err_code == "null" ]]; then
      err_string_code=" (Code: ${err_code})"
    fi
    log_error "Unexpected API error${err_string_code}.\n\n${err_msg}${err_string_meta}\n"
    ((loop_errors++))
    return $loop_errors
  fi
}

handle_response() {
  local raw_res="$1"

  # Reset per-iteration globals (avoid residue across provider changes mid-session)
  refusal=""
  assistant_msg=""
  history_assistant_msg=""    # canonical (chat/completions) form persisted to disk

  case $PROVIDER in
    # /v1/responses — the assistant turn is REPLAYED as items by the reshape
    # (chat_to_responses_items: assistant + tool_calls -> 'function_call' items), so it is
    # persisted in canonical form as well. NO server-side chaining (see api_call_type_responses).
    openai)
      reasoning=$(jq -rc '[.output[] | select(.type=="reasoning") | .summary[]?.text] | join("")' <<<"$raw_res" 2>/dev/null)
      content=$(jq -rc '[.output[] | select(.type=="message") | .content[]? | select(.type=="output_text") | .text] | join("")' <<<"$raw_res" 2>/dev/null)
      tools=$(jq -rc '([.output[]? | select(.type=="function_call")] | if length > 0 then map({id: .call_id, name: .name, args: .arguments}) else empty end)' <<<"$raw_res" 2>/dev/null)
      # Canonical assistant turn (chat/completions shape), kept so that the tool cycle
      # stays PAIRABLE turn after turn, whatever the active provider is. Without this,
      # only the 'function_call_output' was persisted -> orphan on the next turn.
      assistant_msg=$(jq -rc '
        ([.output[]? | select(.type=="function_call")]) as $fc
        | if ($fc | length) > 0 then
            { role: "assistant",
              content: ([.output[]? | select(.type=="message") | .content[]? | select(.type=="output_text") | .text]
                        | join("") | if . == "" then null else . end),
              tool_calls: [ $fc[] | { id: .call_id, type: "function",
                                      function: { name: .name, arguments: (if (.arguments | type) == "string" then .arguments else ((.arguments // {}) | tostring) end) } } ] }
          else empty end' <<<"$raw_res" 2>/dev/null)
    ;;

    # /v1/messages — re-inject the full assistant turn (text + tool_use blocks) before tool results
    anthropic)
      # WIRE shape: the full assistant turn (text + tool_use blocks) must be replayed as-is
      assistant_msg=$(jq -rc '{role:"assistant", content: .content}' <<<"$raw_res" 2>/dev/null)
      # CANONICAL shape (chat/completions) for the persisted history — same rationale as
      # openai: protocol-specific blocks (tool_use) must never reach messages.json.
      history_assistant_msg=$(jq -rc '
        ([.content[]? | select(.type=="tool_use")]) as $tu
        | if ($tu | length) > 0 then
            { role: "assistant",
              content: ([.content[]? | select(.type=="text") | .text] | join("") | if . == "" then null else . end),
              tool_calls: [ $tu[] | { id: .id, type: "function",
                                      function: { name: .name, arguments: (if (.input | type) == "string" then .input else ((.input // {}) | tostring) end) } } ] }
          else empty end' <<<"$raw_res" 2>/dev/null)
      reasoning=$(jq -rc '.content[] | select(.type=="thinking") | .thinking' <<<"$raw_res" 2>/dev/null)
      content=$(jq -rc '[.content[] | select(.type=="text") | .text] | join("")' <<<"$raw_res" 2>/dev/null)
      tools=$(jq -rc '([.content[]? | select(.type=="tool_use")] | if length > 0 then map({id: .id, name: .name, args: (.input | tostring)}) else empty end)' <<<"$raw_res" 2>/dev/null)
    ;;

    # /v1/chat/completions — default for other providers
    *)
      # Canonical form only (2026-11-21): persisting .choices[0].message VERBATIM
      # leaked provider-specific keys into messages.json (reasoning_content,
      # annotations, audio, refusal, name:null) -> poisoned on the NEXT provider
      # switch (Infomaniak 400 / 56 pydantic errors on messages[25]).
      assistant_msg=$(jq -rc '
        (.choices[0].message // {}) as $m
        | ((($m.tool_calls // []) | length) > 0) as $tc
        | { role: "assistant",
            content: (if $tc and (($m.content // "") | length) == 0 then null
                         else ($m.content // null) end) }
        + (if $tc then
             { tool_calls: [ $m.tool_calls[] | { id: .id, type: "function",
                 function: { name: .function.name,
                   arguments: (if ((.function.arguments // null) | type) == "string"
                               then .function.arguments
                               else ((.function.arguments // {}) | tostring) end) } } ] }
           else {} end)' <<<"$raw_res" 2>/dev/null)
      reasoning=$(jq -rc '.choices[0].message.reasoning // .choices[0].message.reasoning_content' <<<"$raw_res" 2>/dev/null)
      content=$(jq -rc '.choices[0].message.content' <<<"$raw_res" 2>/dev/null)
      refusal=$(jq -rc '.choices[0].message.refusal' <<<"$raw_res" 2>/dev/null)
      tools=$(jq -rc '([.choices[0].message.tool_calls[]?] | if length > 0 then map({id: .id, name: .function.name, args: .function.arguments}) else empty end)' <<<"$raw_res" 2>/dev/null)
    ;;
  esac
}

build_tool_result() {
  local id="$1"
  local name="$2"
  local content_file="$3"
  # Build the tool result message in TWO shapes, each written to a temp file and read
  # back with --rawfile. The tool output can be huge; --arg would blow past the OS
  # argv limit. Nothing here uses --arg for content anymore (2026-09-12: the degraded
  # fallback path was the last one and now sanitises into a FILE instead).
  #
  #   $TEMP_TOOLS_OUTPUT  -> WIRE shape, protocol-specific (what the API expects)
  #   $TEMP_TOOLS_HISTORY -> CANONICAL shape, chat/completions (what lands on disk)
  #
  case $PROVIDER in
    # /v1/responses
    openai)
      jq -rc -n \
         --arg id "$id" \
         --rawfile content "$content_file" \
         '{type:"function_call_output", call_id: $id, output: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null
    ;;
    # /v1/messages — tool_result lives INSIDE a user message content array
    anthropic)
      jq -rc -n \
         --arg id "$id" \
         --rawfile content "$content_file" \
         '{role:"user", content:[{type:"tool_result", tool_use_id: $id, content: $content}]}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null
    ;;
    # /v1/chat/completions
    *)
      jq -rc -n \
         --arg id "$id" \
         --arg name "$name" \
         --rawfile content "$content_file" \
         '{role:"tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null
    ;;
  esac

  # Fallback: the primary --rawfile pass produced nothing (unreadable/invalid content
  # file). E2BIG (2026-09-12): this rescue path used --arg, capped at 128 KB — so it was
  # itself broken for EXACTLY the case it exists for (a huge tool output = the bigger the
  # output, the more certain the rescue, the more certain it died EMPTY). The content now
  # goes through a sanitised FILE + --rawfile: no --arg carries content anymore, anywhere.
  if [[ ! -s $TEMP_TOOLS_OUTPUT ]]; then
    log_warn "Unable to parse tool output with rawfile, retrying after sanitisation"
    local safe_content="${TOOLS_OUTPUT}.safe"
    iconv -f UTF-8 -t UTF-8 -c "$content_file" > "$safe_content" 2>/dev/null || cp "$content_file" "$safe_content" 2>/dev/null
    [[ -s $safe_content ]] || printf '%s' "(Error reading tool output)" > "$safe_content"
    case $PROVIDER in
      # /v1/responses
      openai)
        jq -rc -n \
           --arg id "$id" \
           --rawfile content "$safe_content" \
           '{type:"function_call_output", call_id: $id, output: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null
      ;;
      # /v1/messages
      anthropic)
        jq -rc -n \
           --arg id "$id" \
           --rawfile content "$safe_content" \
           '{role:"user", content:[{type:"tool_result", tool_use_id: $id, content: $content}]}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null
      ;;
      # /v1/chat/completions
      *)
        jq -rc -n \
           --arg id "$id" \
           --arg name "$name" \
           --rawfile content "$safe_content" \
           '{role:"tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null
      ;;
    esac
    rm -f "$safe_content"
  fi

  # Canonical history shape — protocol-neutral, this is what gets persisted in
  # messages.json and replayed to every provider. Kept separate from the wire shape so
  # that a provider switch can never inject protocol-tagged items into the history
  # (2026-09-11 incident: "messages[25]: missing field `role`" on deepseek).
  jq -rc -n \
     --arg id "$id" \
     --arg name "$name" \
     --rawfile content "$content_file" \
     '{role:"tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_HISTORY" 2>/dev/null

  if [[ ! -s $TEMP_TOOLS_HISTORY ]]; then
    # E2BIG (2026-09-12): same rescue, same rule — sanitise to a FILE, keep --rawfile.
    local safe_history="${TOOLS_OUTPUT}.safe"
    iconv -f UTF-8 -t UTF-8 -c "$content_file" > "$safe_history" 2>/dev/null || cp "$content_file" "$safe_history" 2>/dev/null
    [[ -s $safe_history ]] || printf '%s' "(Error reading tool output)" > "$safe_history"
    jq -rc -n \
       --arg id "$id" \
       --arg name "$name" \
       --rawfile content "$safe_history" \
       '{role:"tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_HISTORY" 2>/dev/null
    rm -f "$safe_history"
  fi
}