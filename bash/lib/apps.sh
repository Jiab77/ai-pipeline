#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/apps.sh — Shared apps functions
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
[[ -n "${APPS_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'apps.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

APPS_SH_LOADED=1

# -----------------------------------------------------------------------------
# Experimental app launcher (only handle API Keys for the moment)
# -----------------------------------------------------------------------------

launch_ext_app() {
  local ext_app="$1"
  local ext_path="$2"

  if [[ -n $ext_app ]]; then
    # Set required env vars
    case $ext_app in
      aider)
        export AIDER_OPENAI_API_BASE="$PROVIDER_API_URL"
        export AIDER_OPENAI_API_KEY="$PROVIDER_API_KEY"
        export AIDER_MODEL="$CHAT_MODEL"
      ;;
      claude)
        export ANTHROPIC_AUTH_TOKEN="$PROVIDER_API_KEY"
        export ANTHROPIC_BASE_URL="$PROVIDER_API_URL"
        export ANTHROPIC_MODEL="${CHAT_MODEL}[1m]"
        export ANTHROPIC_DEFAULT_FABLE_MODEL="${CHAT_MODEL}[1m]"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="${CHAT_MODEL}[1m]"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="${CHAT_MODEL}[1m]"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="${CHAT_MODEL}[1m]"
        export CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
        export CLAUDE_CODE_EFFORT_LEVEL="max"
        export CLAUDE_CODE_SUBAGENT_MODEL="${CHAT_MODEL}[1m]"
      ;;
      copilot)
        export COPILOT_PROVIDER_TYPE="anthropic"
        export COPILOT_PROVIDER_BASE_URL="$PROVIDER_API_URL"
        export COPILOT_PROVIDER_API_KEY="$PROVIDER_API_KEY"
        export COPILOT_MODEL="$CHAT_MODEL"
        # export COPILOT_OFFLINE=true
      ;;
      crush)
        local crush_config=~/.config/crush/crush.json
        local provider_name ; provider_name=$(jq -rc ".${PROVIDER}.name // \"$PROVIDER\"" "$PROVIDERS_CONFIG" 2>/dev/null)
        [[ ! -e "${crush_config}.bak" && -e $crush_config ]] && cp -a "$crush_config" "${crush_config}.bak"
        jq -rc -n \
           --arg provider "$PROVIDER" \
           --arg name "$provider_name" \
           --arg url "${PROVIDER_API_URL//"/chat/completions"/}" \
           --arg key "$PROVIDER_API_KEY" \
           '{
             providers: {
               $provider: {
                 id: $provider,
                 name: $name,
                 base_url: $url,
                 api_key: $key
               }
             }
           }' > "$crush_config" 2>/dev/null
          [[ $DEBUG == true ]] && jq . "$crush_config"
      ;;
      cyberneurova|neurova)
        export CYBERNEUROVA_API_KEY="$PROVIDER_API_KEY"
      ;;
      hf)
        export HF_INFERENCE_ENDPOINT="$PROVIDER_API_URL"    # Will be removed if it creates issues
        export HF_TOKEN="$PROVIDER_API_KEY"
        export HF_HUB_DISABLE_TELEMETRY=1
      ;;
      openai)
        export OPENAI_API_BASE="$PROVIDER_API_URL"
        export OPENAI_API_KEY="$PROVIDER_API_KEY"
      ;;
      *) log_error "Unsupported app given: $ext_app" ;;
    esac

    # Exec requested app
    cd "$ext_path" && exec "$ext_app"
  else
    log_error "Missing external app argument."
  fi
}