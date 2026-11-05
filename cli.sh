#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034,SC2001
# ==============================================================================
# cli.sh — Interactive terminal client for the AI pipeline
# ==============================================================================
# Provides the interactive chat loop, persistent history, slash commands,
# reasoning display, and composition of the core and media engines.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.8.0
# ==============================================================================

# Options
[[ -e $HOME/.debug ]] && set -x

# -----------------------------------------------------------------------------
# Core Engine Sourcing
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENG_DIR="${SCRIPT_DIR}/engines"
CORE_LIB="${SCRIPT_DIR}/core.sh"

# Import sovereign cognitive core library
if [[ -r "$CORE_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$CORE_LIB"
else
  error "Sovereign Cognitive Core library not found at: ${CORE_LIB}"
fi

# Import engines files
load_engines

# Set the 'trap' to the right place
trap cleanup_the_mess EXIT INT TERM

# Override default RUN_MODE to start in chat mode by default
RUN_MODE="chat"

# -----------------------------------------------------------------------------
# Voice Handling Features
# -----------------------------------------------------------------------------

# Voice recording state variables
VOICE_RECORD_ACTIVE=false
VOICE_RECORD_PID=""
VOICE_RECORD_FILE=""

# -----------------------------------------------------------------------------
# High-Fidelity Interactive Conversational Loop
# -----------------------------------------------------------------------------

run_chat() {
  local backend_upper ; backend_upper=$(to_upper "$BACKEND")
  local provider_upper ; provider_upper=$(to_upper "$PROVIDER")
  local model_upper ; model_upper=$(to_upper "$CHAT_MODEL")

  set_console_title "${SCRIPT_FILE}: Interactive Chat Mode."
  show_banner

  if [[ $START_JARNET == true ]]; then
    jarnet_start ; log  # Empty line
  fi

  log_info "Initializing chat context..."
  log_info "Active Backend: ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"
  [[ $BACKEND == "external" ]] && log_info "Active Provider: ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET}"
  if [[ -n $FALLBACK_PROVIDER ]]; then
    local fallback_upper ; fallback_upper=$(to_upper "$FALLBACK_PROVIDER")
    log_info "Active Fallback: ${CLR_B_YELLOW}${fallback_upper}${ANSI_RESET}"
  fi
  log_info "Active Model: ${CLR_B_YELLOW}${model_upper}${ANSI_RESET}"
  if [[ $IMAGE_ENABLED == true ]]; then
    log_info "Active Image Provider: ${CLR_B_YELLOW}$(to_upper "${IMAGE_PROVIDER:-$PROVIDER}")${ANSI_RESET}"
  else
    log_info "Image Generation: ${CLR_B_RED}OFF${ANSI_RESET} on ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET} — pollinations fallback"
  fi
  if [[ $VIDEO_ENABLED == true ]]; then
    log_info "Active Video Provider: ${CLR_B_YELLOW}$(to_upper "${VIDEO_PROVIDER:-$PROVIDER}")${ANSI_RESET}"
  else
    log_info "Video Generation: ${CLR_B_RED}OFF${ANSI_RESET} on ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET} — no fallback"
  fi
  if [[ $VOICE_ENABLED == true ]]; then
    log_info "Active Voice Provider: ${CLR_B_YELLOW}$(to_upper "${VOICE_PROVIDER:-$PROVIDER}")${ANSI_RESET}"
  else
    log_info "Voice Generation: ${CLR_B_RED}OFF${ANSI_RESET} on ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET} — no fallback"
  fi
  if [[ $SPEECH_ENABLED == true ]]; then
    log_info "Active Speech Provider: ${CLR_B_YELLOW}$(to_upper "${SPEECH_PROVIDER:-$PROVIDER}")${ANSI_RESET}"
  else
    log_info "Speech Capture: ${CLR_B_RED}OFF${ANSI_RESET} on ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET} — no fallback"
  fi
  if [[ ! $DETECT_MODE == "off" ]]; then
    log_info "Automatic Detection: ${CLR_B_YELLOW}$(to_upper "${DETECT_MODE}")${ANSI_RESET}"
  else
    log_info "Automatic Detection: ${CLR_B_RED}OFF${ANSI_RESET}"
  fi
  if [[ ! $RUN_MODE == "chat" ]]; then
    log_info "Working Mode: ${CLR_B_YELLOW}$(to_upper "${RUN_MODE}")${ANSI_RESET}"
  fi
  log_info "Memory Structure: ${CLR_B_YELLOW}$(to_upper "$(get_memory_structure)")${ANSI_RESET}"

  log_info "Conversation online. Type ${CLR_B_GREEN}/help${ANSI_RESET} to view commands."

  # Enable voice keyboard shortcuts in interactive TTY sessions
  # FIXME: Should probably move that to a dedicated function at some point
  if [[ -t 0 ]]; then
    bind -x '"\C-x\C-v": voice_toggle_record' 2>/dev/null
    bind '"\ev": "\C-x\C-v"' 2>/dev/null
    bind -x '"\C-x\C-s": voice_replay_last_audio' 2>/dev/null
    bind '"\es": "\C-x\C-s"' 2>/dev/null
  fi

  # Custom user prompt
  local custom_prompt ; custom_prompt="$(printf '\n\001%s\002%sUser\001%s\002 \001%s\002❯\001%s\002 ' "${CLR_B_GREEN}" "${ICON_USER}" "${ANSI_RESET}" "${CLR_B_BLACK}" "${ANSI_RESET}")"

  # Magic loop :P
  while true; do
    # Handle user message and keys with the custom prompt
    read -e -p "$custom_prompt" -r USER_MSG

    # Skip processing if empty input
    [[ -z $USER_MSG ]] && continue

    # Save into history
    [[ $- == *i* ]] && history -s "$USER_MSG"

    # Handle slash commands
    case $USER_MSG in
      "/help")
        cat <<EOF

${CLR_B_CYAN}✨ Available Commands ✨${ANSI_RESET}
  ${CLR_B_GREEN}/help${ANSI_RESET}                          • Show this help menu
  ${CLR_B_GREEN}/debug [boolean]${ANSI_RESET}               • Enable / disable debug mode
  ${CLR_B_GREEN}/setup${ANSI_RESET}                         • Change / set user settings
  ${CLR_B_GREEN}/mode [type]${ANSI_RESET}                   • Change / set working mode
  ${CLR_B_GREEN}/lang [code]${ANSI_RESET}                   • Change / set audio language
  ${CLR_B_GREEN}/backend [type]${ANSI_RESET}                • Change / set active backend
  ${CLR_B_GREEN}/provider [name]${ANSI_RESET}               • Change / set active provider
  ${CLR_B_GREEN}/fallback [provider]${ANSI_RESET}           • Change / set fallback provider
  ${CLR_B_GREEN}/image [provider]${ANSI_RESET}              • Change / set image provider
  ${CLR_B_GREEN}/video [provider]${ANSI_RESET}              • Change / set video provider
  ${CLR_B_GREEN}/voice [provider]${ANSI_RESET}              • Change / set voice provider
  ${CLR_B_GREEN}/speech [provider]${ANSI_RESET}             • Change / set speech provider
  ${CLR_B_GREEN}/model [name]${ANSI_RESET}                  • Change / set active model
  ${CLR_B_GREEN}/thinking [boolean]${ANSI_RESET}            • Change / set active model reasoning display
  ${CLR_B_GREEN}/effort [level]${ANSI_RESET}                • Change / set active model reasoning effort (none, minimal, low, medium, high, xhigh, max) -- default: $REASONING_EFFORT
  ${CLR_B_GREEN}/memory [type]${ANSI_RESET}                 • Change / set active memory structure (full, index) -- default: $MEMORY_STRUCTURE_TYPE
  ${CLR_B_GREEN}/detect [mode]${ANSI_RESET}                 • Change / set visual feedback auto-detection (images, videos, all, off) -- default: $DETECT_MODE
  ${CLR_B_GREEN}/jarnet [action]${ANSI_RESET}               • Control JarNet service (who, status, doctor, up, down)
  ${CLR_B_GREEN}/balance${ANSI_RESET}                       • Show available credits for all or active provider
  ${CLR_B_GREEN}/models${ANSI_RESET}                        • Show available models in active provider
  ${CLR_B_GREEN}/save${ANSI_RESET}                          • Save current settings permanently
  ${CLR_B_GREEN}/reload${ANSI_RESET}                        • Reload user settings
  ${CLR_B_GREEN}/clear${ANSI_RESET}                         • Clear current conversation context and memory
  ${CLR_B_GREEN}/commit${ANSI_RESET}                        • Consolidate active context to permanent disk
  ${CLR_B_GREEN}/heartbeat [count]${ANSI_RESET}             • Define after N messages to trigger the memory consolidation process
  ${CLR_B_GREEN}/draw [prompt] [options]${ANSI_RESET}       • Generate images (--ratio, --size, --model, --provider)
  ${CLR_B_GREEN}/imagine [prompt] [options]${ANSI_RESET}    • Generate videos (--ratio, --resolution, --image, --model, --provider, --duration, --fps, --frames)
  ${CLR_B_GREEN}/keys${ANSI_RESET}                          • Manage your encrypted cloud provider API keys
  ${CLR_B_GREEN}/migrate [--apply]${ANSI_RESET}             • Migrate master key file to new format
  ${CLR_B_GREEN}/replay${ANSI_RESET}                        • Resend the last message
  ${CLR_B_GREEN}/launch [app] [path]${ANSI_RESET}           • Launch app with prepared environment variables
  ${CLR_B_GREEN}/load <file>${ANSI_RESET}                   • Load file in the chat context
  ${CLR_B_GREEN}/run <cmd>${ANSI_RESET}                     • Execute a shell command locally in the session
  ${CLR_B_GREEN}/unload${ANSI_RESET}                        • Unload previously loaded file from the chat context
  ${CLR_B_GREEN}/start${ANSI_RESET}                         • Switch active context to multi-agent pipeline
  ${CLR_B_GREEN}/quit|/exit|/bye${ANSI_RESET}               • Terminate session gracefully
EOF
      ;;
      "/debug")
        if [[ -n $DEBUG ]]; then
          log_step "Debug mode enabled: ${CLR_B_YELLOW}${DEBUG}${ANSI_RESET}"
        else
          log_step "Debug mode disabled.${ANSI_RESET}"
        fi
        log_info "Toggle debug mode with ${CLR_B_YELLOW}/debug <true|false>${ANSI_RESET}"
      ;;
      "/debug "*)
        unset DEBUG   # Remove initially defined threshold
        DEBUG="${USER_MSG#"/debug "}"
        if [[ -n $DEBUG ]]; then
          if [[ $DEBUG == true ]]; then
            log_step "Debug mode: ${CLR_B_GREEN}enabled${ANSI_RESET}"
            touch "$HOME/.debug"
          else
            log_step "Debug mode: ${CLR_B_YELLOW}disabled${ANSI_RESET}"
            rm -f "$HOME/.debug"
          fi
        else
          log_warn "Debug mode disabled."
        fi
      ;;
      "/mode")
        log_step "Current working mode: ${CLR_B_YELLOW}${RUN_MODE}${ANSI_RESET}"
        log_info "Set working mode with ${CLR_B_YELLOW}/mode <chat|auto>${ANSI_RESET}"
      ;;
      "/mode "*)
        local target_mode="${USER_MSG#"/mode "}"
        target_mode="${target_mode#" "}"
        if [[ "$target_mode" == "auto" ]]; then
          RUN_MODE="auto"
          set_state   # Update new state
          log_step "Moving to Autonomous Mode..."
          return 0   # Leaving 'run_chat' to hand up control to main loop
        elif [[ "$target_mode" == "chat" ]]; then
          RUN_MODE="chat"
          set_state   # Update new state
          log_step "Chat Mode already active."
        else
          log_warn "Unknown mode: $target_mode (use 'chat' or 'auto')"
        fi
      ;;
      "/lang")
        if [[ -n $AUDIO_LANG ]]; then
          log_step "Current audio language: ${CLR_B_YELLOW}${AUDIO_LANG}${ANSI_RESET}"
        else
          log_step "Audio language not disabled.${ANSI_RESET}"
        fi
        log_info "Set audio language with ${CLR_B_YELLOW}/lang <code>${ANSI_RESET}"
        log_info "Example for the French language: ${CLR_B_YELLOW}/lang fr${ANSI_RESET}"
        log_info "For automatic detection: ${CLR_B_YELLOW}/lang auto${ANSI_RESET}"
      ;;
      "/lang "*)
        unset AUDIO_LANG   # Remove initially defined threshold
        AUDIO_LANG="${USER_MSG#"/lang "}"
        [[ -z $AUDIO_LANG ]] && AUDIO_LANG="auto"
        log_step "New audio language: ${CLR_B_GREEN}${AUDIO_LANG}${ANSI_RESET}"
        set_state   # Update new state
      ;;
      "/setup"|"/save"|"/reload")
        log_warn "Not implemented yet, coming soon!"
      ;;
      "/balance")
        log ; log_info "Gathering providers balance..."
        list_provider_balance
      ;;
      "/models")
        log ; log_info "Gathering provider models..."
        list_provider_models
      ;;
      "/draw"|"/draw "*)
        local draw_input="${USER_MSG#"/draw"}"
        draw_input="${draw_input# }"
        if [[ $draw_input == --* ]]; then
          # Options only — generate_image will use its default prompt
          # shellcheck disable=SC2086  # Intentional word-splitting into separate args
          generate_image $draw_input
        elif [[ $draw_input == *" --"* ]]; then
          # Split the prompt (before the first option) from the options (after it)
          local draw_prompt="${draw_input%% --*}"
          local draw_flags="${draw_input#*" --"}"
          # shellcheck disable=SC2086  # Intentional word-splitting into separate args
          generate_image "$draw_prompt" --${draw_flags}
        elif [[ -n $draw_input ]]; then
          generate_image "$draw_input"
        else
          generate_image
        fi
      ;;
      "/imagine"|"/imagine "*)
        local video_input="${USER_MSG#"/imagine"}"
        video_input="${video_input# }"
        if [[ $video_input == --* ]]; then
          # Options only — generate_video will use its default prompt
          # shellcheck disable=SC2086  # Intentional word-splitting into separate args
          generate_video $video_input
        elif [[ $video_input == *" --"* ]]; then
          # Split the prompt (before the first option) from the options (after it)
          local video_prompt="${video_input%% --*}"
          local video_flags="${video_input#*" --"}"
          # shellcheck disable=SC2086  # Intentional word-splitting into separate args
          generate_video "$video_prompt" --${video_flags}
        elif [[ -n $video_input ]]; then
          generate_video "$video_input"
        else
          generate_video
        fi
      ;;
      "/image")
        local effective_image_provider="${IMAGE_PROVIDER:-$PROVIDER}"
        local img_cap
        img_cap=$(jq -r --arg p "$effective_image_provider" '.[$p].default.image // false' "$PROVIDERS_CONFIG" 2>/dev/null)
        if [[ -n $IMAGE_PROVIDER ]]; then
          log_step "Current image provider: ${CLR_B_YELLOW}${IMAGE_PROVIDER}${ANSI_RESET}"
        else
          log_step "No image provider defined — using active chat provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}"
        fi
        if [[ $img_cap == "true" ]]; then
          log_info "Image generation: ${CLR_B_GREEN}available${ANSI_RESET} on ${CLR_B_YELLOW}${effective_image_provider}${ANSI_RESET}"
        else
          log_info "Image generation: ${CLR_B_YELLOW}unavailable${ANSI_RESET} on ${CLR_B_YELLOW}${effective_image_provider}${ANSI_RESET} — keyless pollinations fallback"
        fi
        log_info "Set image provider with ${CLR_B_YELLOW}/image <provider>${ANSI_RESET}"
      ;;
      "/image "*)
        local image_value="${USER_MSG#"/image "}"
        IMAGE_PROVIDER="$image_value"
        IMAGE_ENABLED=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].default.image // false' "$PROVIDERS_CONFIG" 2>/dev/null)
        log_step "New image provider defined: ${CLR_B_YELLOW}${image_value}${ANSI_RESET}"
        set_state   # Update new state
      ;;
      "/video")
        local effective_video_provider="${VIDEO_PROVIDER:-$PROVIDER}"
        local vid_cap
        vid_cap=$(jq -r --arg p "$effective_video_provider" '.[$p].default.video // false' "$PROVIDERS_CONFIG" 2>/dev/null)
        if [[ -n $VIDEO_PROVIDER ]]; then
          log_step "Current video provider: ${CLR_B_YELLOW}${VIDEO_PROVIDER}${ANSI_RESET}"
        else
          log_step "No video provider defined — using active chat provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}"
        fi
        if [[ $vid_cap == "true" ]]; then
          log_info "Video generation: ${CLR_B_GREEN}available${ANSI_RESET} on ${CLR_B_YELLOW}${effective_video_provider}${ANSI_RESET}"
        else
          log_info "Video generation: ${CLR_B_YELLOW}unavailable${ANSI_RESET} on ${CLR_B_YELLOW}${effective_video_provider}${ANSI_RESET} — no fallback"
        fi
        log_info "Set video provider with ${CLR_B_YELLOW}/video <provider>${ANSI_RESET}"
      ;;
      "/video "*)
        local video_value="${USER_MSG#"/video "}"
        VIDEO_PROVIDER="$video_value"
        VIDEO_ENABLED=$(jq -r --arg p "$VIDEO_PROVIDER" '.[$p].default.video // false' "$PROVIDERS_CONFIG" 2>/dev/null)
        log_step "New video provider defined: ${CLR_B_YELLOW}${video_value}${ANSI_RESET}"
        set_state   # Update new state
      ;;
      "/voice")
        local effective_voice_provider="${VOICE_PROVIDER:-$PROVIDER}"
        local voc_cap
        voc_cap=$(jq -r --arg p "$effective_voice_provider" '.[$p].default.voice // false' "$PROVIDERS_CONFIG" 2>/dev/null)
        if [[ -n $VOICE_PROVIDER ]]; then
          log_step "Current voice provider: ${CLR_B_YELLOW}${VOICE_PROVIDER}${ANSI_RESET}"
        else
          log_step "No voice provider defined — using active chat provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}"
        fi
        if [[ $voc_cap == "true" ]]; then
          log_info "Voice generation: ${CLR_B_GREEN}available${ANSI_RESET} on ${CLR_B_YELLOW}${effective_voice_provider}${ANSI_RESET}"
        else
          log_info "Voice generation: ${CLR_B_YELLOW}unavailable${ANSI_RESET} on ${CLR_B_YELLOW}${effective_voice_provider}${ANSI_RESET} — no fallback"
        fi
        log_info "Set voice provider with ${CLR_B_YELLOW}/voice <provider>${ANSI_RESET}"
        log_info "Use local voice provider with ${CLR_B_YELLOW}/voice local${ANSI_RESET}"
        log_info "Disable voice output with ${CLR_B_YELLOW}/voice off${ANSI_RESET}"
      ;;
      "/voice "*)
        local voice_value="${USER_MSG#"/voice "}"
        # TODO: Add missing logic for 'local'
        if [[ $voice_value == "off" || $voice_value == "OFF" ]]; then
          unset VOICE_PROVIDER
          VOICE_ENABLED=false
          log_step "Voice output: ${CLR_B_YELLOW}${voice_value}${ANSI_RESET}"
          set_state   # Update new state
        elif [[ $voice_value == "local" ]]; then
          VOICE_PROVIDER="$voice_value"
          VOICE_ENABLED=true
          log_step "New voice provider defined: ${CLR_B_YELLOW}${voice_value}${ANSI_RESET}"
          set_state   # Update new state
        else
          VOICE_PROVIDER="$voice_value"
          VOICE_ENABLED=$(jq -r --arg p "$VOICE_PROVIDER" '.[$p].default.voice // false' "$PROVIDERS_CONFIG" 2>/dev/null)
          log_step "New voice provider defined: ${CLR_B_YELLOW}${voice_value}${ANSI_RESET}"
          set_state   # Update new state
        fi
      ;;
      "/speech")
        local effective_speech_provider="${SPEECH_PROVIDER:-$PROVIDER}"
        local spe_cap
        spe_cap=$(jq -r --arg p "$effective_speech_provider" '.[$p].default.speech // false' "$PROVIDERS_CONFIG" 2>/dev/null)
        if [[ -n $SPEECH_PROVIDER ]]; then
          log_step "Current speech provider: ${CLR_B_YELLOW}${SPEECH_PROVIDER}${ANSI_RESET}"
        else
          log_step "No speech provider defined — using active chat provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}"
        fi
        if [[ $spe_cap == "true" ]]; then
          log_info "Speech capture: ${CLR_B_GREEN}available${ANSI_RESET} on ${CLR_B_YELLOW}${effective_speech_provider}${ANSI_RESET}"
        else
          log_info "Speech capture: ${CLR_B_YELLOW}unavailable${ANSI_RESET} on ${CLR_B_YELLOW}${effective_speech_provider}${ANSI_RESET} — no fallback"
        fi
        log_info "Set speech provider with ${CLR_B_YELLOW}/speech <provider>${ANSI_RESET}"
        log_info "Use local speech provider with ${CLR_B_YELLOW}/speech local${ANSI_RESET}"
        log_info "Disable speech capture with ${CLR_B_YELLOW}/speech off${ANSI_RESET}"
      ;;
      "/speech "*)
        local speech_value="${USER_MSG#"/speech "}"
        # TODO: Add missing logic for 'local'
        if [[ $speech_value == "off" || $speech_value == "OFF" ]]; then
          unset SPEECH_PROVIDER
          SPEECH_ENABLED=false
          log_step "Speech capture: ${CLR_B_YELLOW}${speech_value}${ANSI_RESET}"
          set_state   # Update new state
        elif [[ $speech_value == "local" ]]; then
          SPEECH_PROVIDER="$speech_value"
          SPEECH_ENABLED=true
          log_step "New speech provider defined: ${CLR_B_YELLOW}${speech_value}${ANSI_RESET}"
          set_state   # Update new state
        else
          SPEECH_PROVIDER="$speech_value"
          SPEECH_ENABLED=$(jq -r --arg p "$SPEECH_PROVIDER" '.[$p].default.speech // false' "$PROVIDERS_CONFIG" 2>/dev/null)
          log_step "New speech provider defined: ${CLR_B_YELLOW}${speech_value}${ANSI_RESET}"
          set_state   # Update new state
        fi
      ;;
      "/detect")
        log_step "Visual feedback auto-detection: ${CLR_B_YELLOW}${DETECT_MODE}${ANSI_RESET}"
        log_info "Set detection mode with ${CLR_B_YELLOW}/detect <images|videos|all|off>${ANSI_RESET}"
      ;;
      "/detect "*)
        local detect_value="${USER_MSG#"/detect "}"
        case $detect_value in
          images|videos|all|off)
            DETECT_MODE="$detect_value"
            log_step "New detection mode defined: ${CLR_B_YELLOW}${DETECT_MODE}${ANSI_RESET}"
            set_state   # Update new state
          ;;
          *) log_warn "Unknown detection mode '${detect_value}' — supported: images, videos, all, off" ;;
        esac
      ;;
      "/replay")
        if [[ -z $LAST_USER_MSG ]]; then
          log_warn "No previous message to replay!"
        else
          log_step "Replaying last message: ${CLR_B_YELLOW}${LAST_USER_MSG}${ANSI_RESET}"
          send_message "$LAST_USER_MSG"
        fi
      ;;
      "/jarnet")
        if [[ $START_JARNET == true ]]; then
          log_step "JarNet service active: ${CLR_B_YELLOW}${START_JARNET}${ANSI_RESET}"
        else
          log_warn "JarNet service inactive."
        fi
        log_info "Supported actions: ${CLR_B_YELLOW}who${CLR_B_WHITE}, ${CLR_B_YELLOW}status${CLR_B_WHITE}, ${CLR_B_YELLOW}doctor${ANSI_RESET}, ${CLR_B_YELLOW}up${ANSI_RESET}, ${CLR_B_YELLOW}down${ANSI_RESET}"
        log_info "Control JarNet service with ${CLR_B_YELLOW}/jarnet <action>${ANSI_RESET}"
      ;;
      "/jarnet "*)
        local action_value="${USER_MSG#"/jarnet "}"
        case $action_value in
          who|status|doctor|up|down)
            unset START_JARNET ; START_JARNET=true
            "$NET_HANDLER" "$action_value" | jq .
            set_state   # Update new state
          ;;
          *) log_warn "Unsupported action given: $action_value" ;;
        esac
      ;;
      "/backend")
        if [[ -n $BACKEND ]]; then
          log_step "Current backend defined: ${CLR_B_YELLOW}${BACKEND}${ANSI_RESET}"
        else
          log_warn "No backend defined."
        fi
        log_info "Supported backends: ${CLR_B_YELLOW}ollama${CLR_B_WHITE}, ${CLR_B_YELLOW}llamacpp${CLR_B_WHITE}, ${CLR_B_YELLOW}external${ANSI_RESET}"
        log_info "Set backend with ${CLR_B_YELLOW}/backend <type>${ANSI_RESET}"
      ;;
      "/backend "*)
        local backend_value="${USER_MSG#"/backend "}"
        case $backend_value in
          ollama|llamacpp|external)
            unset BACKEND ; BACKEND="$backend_value"
            log_step "New backend defined: ${CLR_B_YELLOW}${backend_value}${ANSI_RESET}"
            set_state   # Update new state
          ;;
          *) log_warn "Unsupported backend given: $backend_value" ;;
        esac
      ;;
      "/fallback")
        if [[ -n $FALLBACK_PROVIDER ]]; then
          log_step "Current fallback provider: ${CLR_B_YELLOW}${FALLBACK_PROVIDER}${ANSI_RESET}"
        else
          log_step "No fallback provider currently defined.${ANSI_RESET}"
        fi
        log_info "Set fallback provider with ${CLR_B_YELLOW}/fallback <provider>${ANSI_RESET}"
      ;;
      "/fallback "*)
        local fallback_value="${USER_MSG#"/fallback "}"
        if [[ $fallback_value == "off" || $fallback_value == "OFF" ]]; then
          unset FALLBACK_PROVIDER
          log_step "Fallback provider: ${CLR_B_YELLOW}${fallback_value}${ANSI_RESET}"
          set_state   # Update new state
        else
          FALLBACK_PROVIDER="$fallback_value"
          log_step "New fallback provider: ${CLR_B_YELLOW}${fallback_value}${ANSI_RESET}"
          set_state   # Update new state
        fi
      ;;
      "/provider")
        if [[ -n $PROVIDER ]]; then
          log_step "Current provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}"
        else
          log_step "No external provider currently defined.${ANSI_RESET}"
        fi
        log_info "Set new provider with ${CLR_B_YELLOW}/provider <name>${ANSI_RESET}"
      ;;
      "/provider "*)
        unset USER_MODEL          # Remove initially defined model
        unset PROVIDER_API_KEY    # Remove previous provider API key
        local active_provider="${USER_MSG#"/provider "}"
        if [[ $active_provider == "groq" ]]; then
          USE_TOR=false
          log_warn "Tor privacy tunnel disabled for Groq."
        fi
        change_provider "$active_provider"
      ;;
      "/model")
        if [[ -n $CHAT_MODEL ]]; then
          log_step "Current model: ${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET}"
        else
          log_step "No model currently defined.${ANSI_RESET}"
        fi
        log_info "Set new model with ${CLR_B_YELLOW}/model <name>${ANSI_RESET}"
      ;;
      "/model "*)
        unset USER_MODEL    # Remove initially defined model
        # local active_model="${USER_MSG#"/model "}" ; CHAT_MODEL="$active_model"
        # log_step "New active model: ${CLR_B_YELLOW}${active_model}${ANSI_RESET}"
        USER_MODEL="${USER_MSG#"/model "}"
        log_step "New active model: ${CLR_B_YELLOW}${USER_MODEL}${ANSI_RESET}"
        set_chat_model      # Update corresponding chat model
        set_vision_model    # Update corresponding vision model
        set_system_prompt   # Update system prompt with new active model
        set_state           # Update new state
      ;;
      "/thinking")
        if [[ -n $SHOW_THINKING ]]; then
          log_step "Model reasoning display enabled: ${CLR_B_YELLOW}${SHOW_THINKING}${ANSI_RESET}"
        else
          log_step "Model reasoning display disabled.${ANSI_RESET}"
        fi
        log_info "Toggle model reasoning display with ${CLR_B_YELLOW}/thinking <true|false>${ANSI_RESET}"
      ;;
      "/thinking "*)
        unset SHOW_THINKING   # Remove initially defined threshold
        SHOW_THINKING="${USER_MSG#"/thinking "}"
        if [[ -n $SHOW_THINKING ]]; then
          if [[ $SHOW_THINKING == true ]]; then
            log_step "Model reasoning display: ${CLR_B_GREEN}enabled${ANSI_RESET}"
          else
            log_step "Model reasoning display: ${CLR_B_YELLOW}disabled${ANSI_RESET}"
          fi
        else
          log_warn "Model reasoning display disabled."
        fi
      ;;
      "/effort")
        if [[ -n $REASONING_EFFORT ]]; then
          log_step "Current reasoning effort: ${CLR_B_YELLOW}${REASONING_EFFORT}${ANSI_RESET}"
        else
          log_step "No model reasoning effort defined.${ANSI_RESET}"
        fi
        log_info "Set new model reasoning effort with ${CLR_B_YELLOW}/effort <level>${ANSI_RESET}"
      ;;
      "/effort "*)
        unset REASONING_EFFORT    # Remove initially defined reasoning effort
        local active_effort="${USER_MSG#"/effort "}" ; REASONING_EFFORT="$active_effort"
        log_step "New active model reasoning effort: ${CLR_B_YELLOW}${active_effort}${ANSI_RESET}"
        set_state   # Update new state
      ;;
      "/memory")
        if [[ -n $MEMORY_STRUCTURE_TYPE ]]; then
          log_step "Current memory structure type: ${CLR_B_YELLOW}${MEMORY_STRUCTURE_TYPE}${ANSI_RESET}"
        else
          log_step "No memory structure type defined.${ANSI_RESET}"
        fi
        log_info "Set new memory structure type with ${CLR_B_YELLOW}/memory <type>${ANSI_RESET}"
      ;;
      "/memory "*)
        unset MEMORY_STRUCTURE_TYPE    # Remove initially defined reasoning effort
        local active_type="${USER_MSG#"/memory "}" ; MEMORY_STRUCTURE_TYPE="$active_type"
        log_step "New active memory structure type: ${CLR_B_YELLOW}${active_type}${ANSI_RESET}"
        set_state   # Update new state
      ;;
      "/launch")
        local -a tested_apps ; tested_apps=(aider claude copilot crush cyberneurova neurova hf openai)
        local tested_str=""
        local tested_index=0
        for app in "${tested_apps[@]}"; do
          tested_str+="${CLR_B_YELLOW}${app}${CLR_B_WHITE}" ; ((tested_index++))
          [[ $tested_index -ne "${#tested_apps[@]}" ]] && tested_str+=", "
        done
        log_info "Supported applications: ${tested_str}${ANSI_RESET}"
        log_info "To launch an application: ${CLR_B_YELLOW}/launch <app>${ANSI_RESET}"
      ;;
      "/launch "*)
        local launch_args="${USER_MSG#"/launch "}"
        local user_app ; user_app=$(cut -d " " -f1 <<< "$launch_args")
        local user_path ; user_path=$(cut -d " " -f2 <<< "$launch_args")
        [[ $user_path == "$user_app" ]] && user_path=$(pwd)
        launch_ext_app "$user_app" "$user_path"   # Does the app should exit here?
      ;;
      "/load") log_warn "Missing command arguments. Usage: /load <file>" ;;
      "/load "*)
        local file="${USER_MSG#"/load "}"
        local filename="${file##*/}"
        local fileext="${file##*.}"
        local max_preview_lines=100

        if [[ -r $file ]]; then
          EXTERNAL_FILE_LOADED="$file"    # Bind to core global state
          log_step "Loading file: ${CLR_B_YELLOW}${filename}${ANSI_RESET}"
          echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
          if ! is_image_file "$file" || ! is_video_file "$file"; then
            echo -e "Loaded file: ${filename}\n\n\`\`\`${fileext}\n$(head -n$max_preview_lines "$file")\n\`\`\`" | render_markdown
          else
            echo -e "Loaded media: ${filename}"
          fi
          echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
        else
          log_warn "Unable to load file: ${CLR_B_RED}${file}${ANSI_RESET} (File not found or missing required permissions)"
        fi
      ;;
      "/unload")
        if [[ -n $EXTERNAL_FILE_LOADED ]]; then
          log_step "Unloading external file: ${CLR_B_YELLOW}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET}"
          unset EXTERNAL_FILE_LOADED
        else
          log_warn "No file currently loaded."
        fi
      ;;
      "/run") log_warn "Missing command arguments. Usage: /run <command>" ;;
      "/run "*)
        local cmd="${USER_MSG#"/run "}"
        log_step "Locally executing: ${CLR_B_YELLOW}${cmd}${ANSI_RESET}"
        echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
        eval "$cmd"
        echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
      ;;
      "/clear") unset LAST_USER_MSG ; clear_memory ;;
      "/commit") check_and_trigger_heartbeat "true" ;;
      "/heartbeat")
        if [[ -n $HEARTBEAT_THRESHOLD ]]; then
          log_step "Current threshold: ${CLR_B_YELLOW}${HEARTBEAT_THRESHOLD}${ANSI_RESET}"
        else
          log_step "No threshold currently defined.${ANSI_RESET}"
        fi
        log_info "Set new threshold with ${CLR_B_YELLOW}/heartbeat <count>${ANSI_RESET}"
      ;;
      "/heartbeat "*)
        unset HEARTBEAT_THRESHOLD   # Remove initially defined threshold
        HEARTBEAT_THRESHOLD="${USER_MSG#"/heartbeat "}"
        if [[ -n $HEARTBEAT_THRESHOLD ]]; then
          log_step "New memory consolidation threshold: ${CLR_B_YELLOW}${HEARTBEAT_THRESHOLD}${ANSI_RESET}"
        else
          log_warn "No threshold defined."
        fi
      ;;
      "/start")
        echo -en "\n${CLR_B_CYAN}🎯 Enter your pipeline prompt:${ANSI_RESET} "
        read -r PIPELINE_PROMPT
        if [[ -n $PIPELINE_PROMPT ]]; then
          USER_PROMPT="$PIPELINE_PROMPT"
          RUN_MODE="multi"
          run_one_shot_pipeline
          RUN_MODE="chat"  # Revert back to chat loop
        fi
      ;;
      "/keys") manage_keys ;;
      "/migrate"|"/migrate "*)
        local arg="${USER_MSG#"/migrate"}" ; arg="${arg#" "}"
        migrate_key_chest "$arg"
      ;;
      "/quit"|"/exit"|"/bye") break ;;
      *)
        LAST_USER_MSG="$USER_MSG" ; send_message "$USER_MSG"
      ;;
    esac
  done

  echo -e "\n${CLR_B_MAGENTA}🔮 Bye then, see you soon! Have fun! :P${ANSI_RESET}\n"
  exit 0
}

# -----------------------------------------------------------------------------
# Initialization & Bootstrap Sequence
# -----------------------------------------------------------------------------

# Load existing config file
load_config_file

# Parse command line overrides
parse_cli_args "$@"

# Bootstrap core configurations and model settings
init_core

# Launch Interactive Loop, Pipeline or Agent-2-Agent mode depending on runtime state
while true; do
  case $RUN_MODE in
    chat)
      run_chat
      [[ $RUN_MODE == "auto" ]] && continue
      break
    ;;
    auto)
      run_agent
      [[ $RUN_MODE == "chat" ]] && continue
      break
    ;;
    multi|simple) run_one_shot_pipeline ; break ;;
    server) serve ; break ;;
    *) error "Unsupported run mode given: $RUN_MODE" ;;
  esac
done
