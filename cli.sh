#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2001
# ==============================================================================
# cli.sh — High-Fidelity Interactive Terminal Client
# ==============================================================================
# The user-interactive chat loop portal. Sources core.sh, handles persistent
# history, slash commands (/keys, /replay, /load), and reasoning HUD streams.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (GLM-5.3)
#
# Version: 1.7.0
# ==============================================================================

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x

# -----------------------------------------------------------------------------
# Core Engine Sourcing
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="${SCRIPT_DIR}/core.sh"
IMG_LIB="${SCRIPT_DIR}/image.sh"

# Import sovereign cognitive core library
if [[ -r "$CORE_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$CORE_LIB"
else
  error "Sovereign Cognitive Core library not found at: ${CORE_LIB}"
fi

# Import image rendering library
if [[ -r "$IMG_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$IMG_LIB"
else
  error "Image Rendering library not found at: ${IMG_LIB}"
fi

# Set the 'trap' to the right place
trap cleanup_the_mess EXIT INT TERM

# Override default RUN_MODE to start in chat mode by default
RUN_MODE="chat"

# -----------------------------------------------------------------------------
# High-Fidelity Interactive Conversational Loop
# -----------------------------------------------------------------------------

run_chat() {
  local backend_upper ; backend_upper=$(to_upper "$BACKEND")
  local provider_upper ; provider_upper=$(to_upper "$PROVIDER")
  local model_upper ; model_upper=$(to_upper "$CHAT_MODEL")

  set_console_title "${SCRIPT_FILE}: Interactive Chat Mode."
  show_banner
  log_info "Initializing chat context..."
  log_info "Active Backend: ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"
  [[ $BACKEND == "external" ]] && log_info "Active Provider: ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET}"
  if [[ -n $FALLBACK_PROVIDER ]]; then
    local fallback_upper ; fallback_upper=$(to_upper "$FALLBACK_PROVIDER")
    log_info "Active Fallback: ${CLR_B_YELLOW}${fallback_upper}${ANSI_RESET}"
  fi
  log_info "Active Model: ${CLR_B_YELLOW}${model_upper}${ANSI_RESET}"
  if [[ $IMAGE_ENABLED == true ]]; then
    log_info "Active Image Engine: ${CLR_B_YELLOW}$(to_upper "${IMAGE_PROVIDER:-$PROVIDER}")${ANSI_RESET}"
  else
    log_info "Image Generation: ${CLR_B_RED}OFF${ANSI_RESET} on ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET} — pollinations fallback"
  fi
  log_info "Memory Structure: ${CLR_B_YELLOW}$(to_upper "$(get_memory_structure)")${ANSI_RESET}"

  log_info "Conversation online. Type ${CLR_B_GREEN}/help${ANSI_RESET} to view commands."

  while true; do
    echo -en "\n${CLR_B_GREEN}${ICON_USER}User${ANSI_RESET} ${CLR_B_BLACK}❯${ANSI_RESET} "
    read -r USER_MSG

    # Skip processing if empty input
    [[ -z $USER_MSG ]] && continue

    case $USER_MSG in
      "/help")
        echo -e "\n${CLR_B_CYAN}✨ Available Commands ✨${ANSI_RESET}"
        echo -e "  ${CLR_B_GREEN}/help${ANSI_RESET}                     • Show this help menu"
        echo -e "  ${CLR_B_GREEN}/setup${ANSI_RESET}                    • Change / set user settings"
        echo -e "  ${CLR_B_GREEN}/mode [type]${ANSI_RESET}              • Change / set working mode"
        echo -e "  ${CLR_B_GREEN}/backend [type]${ANSI_RESET}           • Change / set active backend"
        echo -e "  ${CLR_B_GREEN}/provider [name]${ANSI_RESET}          • Change / set active provider"
        echo -e "  ${CLR_B_GREEN}/fallback [name]${ANSI_RESET}          • Change / set fallback provider"
        echo -e "  ${CLR_B_GREEN}/image [provider]${ANSI_RESET}         • Change / set image provider"
        echo -e "  ${CLR_B_GREEN}/model [name]${ANSI_RESET}             • Change / set active model"
        echo -e "  ${CLR_B_GREEN}/effort [level]${ANSI_RESET}           • Change / set active model reasoning effort (none, minimal, low, medium, high, xhigh, max) -- default: $REASONING_EFFORT"
        echo -e "  ${CLR_B_GREEN}/memory [type]${ANSI_RESET}            • Change / set active memory structure (full, index) -- default: $MEMORY_STRUCTURE_TYPE"
        echo -e "  ${CLR_B_GREEN}/models${ANSI_RESET}                   • Show available models in active provider"
        echo -e "  ${CLR_B_GREEN}/save${ANSI_RESET}                     • Save current settings permanently"
        echo -e "  ${CLR_B_GREEN}/reload${ANSI_RESET}                   • Reload user settings"
        echo -e "  ${CLR_B_GREEN}/clear${ANSI_RESET}                    • Clear current conversation context and memory"
        echo -e "  ${CLR_B_GREEN}/commit${ANSI_RESET}                   • Consolidate active context to permanent disk"
        echo -e "  ${CLR_B_GREEN}/draw [prompt] [options]${ANSI_RESET}  • Generate images (--ratio, --size, --model, --provider)"
        echo -e "  ${CLR_B_GREEN}/keys${ANSI_RESET}                     • Manage your encrypted cloud provider API keys"
        echo -e "  ${CLR_B_GREEN}/replay${ANSI_RESET}                   • Resend the last message"
        echo -e "  ${CLR_B_GREEN}/launch [app] [path]${ANSI_RESET}      • Launch app with prepared environment variables"
        echo -e "  ${CLR_B_GREEN}/load <file>${ANSI_RESET}              • Load file in the chat context"
        echo -e "  ${CLR_B_GREEN}/run <cmd>${ANSI_RESET}                • Execute a shell command locally in the session"
        echo -e "  ${CLR_B_GREEN}/unload${ANSI_RESET}                   • Unload previously loaded file from the chat context"
        echo -e "  ${CLR_B_GREEN}/start${ANSI_RESET}                    • Switch active context to multi-agent pipeline"
        echo -e "  ${CLR_B_GREEN}/quit${ANSI_RESET}                     • Terminate session gracefully"
      ;;
      "/setup"|"/mode"|"/save"|"/reload")
        log_warn "Not implemented yet, coming soon!"
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
        set_state
      ;;
      "/replay")
        if [[ -z $LAST_USER_MSG ]]; then
          log_warn "No previous message to replay!"
        else
          log_step "Replaying last message: ${CLR_B_YELLOW}${LAST_USER_MSG}${ANSI_RESET}"
          send_message "$LAST_USER_MSG"
        fi
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
            BACKEND="$backend_value"
            log_step "New backend defined: ${CLR_B_YELLOW}${backend_value}${ANSI_RESET}"
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
        else
          FALLBACK_PROVIDER="$fallback_value"
          log_step "New fallback provider: ${CLR_B_YELLOW}${fallback_value}${ANSI_RESET}"
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
        local active_model="${USER_MSG#"/model "}" ; CHAT_MODEL="$active_model"
        log_step "New active model: ${CLR_B_YELLOW}${active_model}${ANSI_RESET}"
        set_vision_model    # Update corresponding vision model
        set_system_prompt   # Update system prompt with new active model
        set_state           # Update new state
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
      ;;
      "/launch")
        local tested_apps=(aider claude copilot crush cyberneurova neurova hf openai)
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
          if ! is_image_file "$file"; then
            echo -e "Loaded file: ${filename}\n\n\`\`\`${fileext}\n$(head -n$max_preview_lines "$file")\n\`\`\`" | render_markdown
          else
            echo -e "Loaded image: ${filename}"
          fi
          echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
        else
          log_warn "Unable to load file: ${CLR_B_RED}${file}${ANSI_RESET} (File not found or missing required permissions)"
        fi
      ;;
      "/unload")
        if [[ -n $EXTERNAL_FILE_LOADED ]]; then
          log_step "Unloading file: ${CLR_B_YELLOW}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET}"
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

# Parse command line overrides
parse_cli_flags "$@"

# Bootstrap core configurations and model settings
init_core

# Launch Interactive Loop or Pipeline depending on runtime state
case $RUN_MODE in
  chat) run_chat ;;
  multi|simple) run_one_shot_pipeline ;;
  server) serve ;;
  *) error "Unsupported run mode given: $RUN_MODE" ;;
esac
