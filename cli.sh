#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2001
# ==============================================================================
# cli.sh — High-Fidelity Interactive Terminal Client
# ==============================================================================
# The user-interactive chat loop portal. Sources core.sh, handles persistent
# history, slash commands (/keys, /replay, /load), and reasoning HUD streams.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (Gemini)
#
# Version: 1.2.1
# ==============================================================================

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x

# -----------------------------------------------------------------------------
# Core Engine Sourcing
# -----------------------------------------------------------------------------
CLI_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="${CLI_SELF_DIR}/core.sh"

if [[ -r "$CORE_LIB" ]]; then
  # Import sovereign cognitive core library
  # shellcheck source=/dev/null
  source "$CORE_LIB"
else
  error "Sovereign Cognitive Core library not found at: ${CORE_LIB}"
fi

# Override default RUN_MODE to start in chat mode by default
RUN_MODE="chat"

# -----------------------------------------------------------------------------
# High-Fidelity Interactive Conversational Loop
# -----------------------------------------------------------------------------

run_chat() {
  local backend_upper ; backend_upper=$(to_upper "$BACKEND")
  local provider_upper ; provider_upper=$(to_upper "$PROVIDER")

  set_console_title "${SCRIPT_FILE}: Interactive Chat Mode."
  show_banner
  log_info "Initializing chat context..."
  log_info "Active Backend: ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"
  [[ $BACKEND == "external" ]] && log_info "Active Provider: ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET}"
  log_info "Active Model: ${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET}"
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
        echo -e "  ${CLR_B_GREEN}/clear${ANSI_RESET}                    • Clear current conversation context and memory"
        echo -e "  ${CLR_B_GREEN}/commit${ANSI_RESET}                   • Consolidate active context to permanent disk"
        echo -e "  ${CLR_B_GREEN}/draw [ratio] [prompt]${ANSI_RESET}    • Generate images"
        echo -e "  ${CLR_B_GREEN}/keys${ANSI_RESET}                     • Manage your encrypted cloud provider API keys"
        echo -e "  ${CLR_B_GREEN}/replay${ANSI_RESET}                   • Resend the last message"
        echo -e "  ${CLR_B_GREEN}/provider <name>${ANSI_RESET}          • Change active provider"
        echo -e "  ${CLR_B_GREEN}/model <name>${ANSI_RESET}             • Change active model"
        echo -e "  ${CLR_B_GREEN}/load <file>${ANSI_RESET}              • Load file in the chat context"
        echo -e "  ${CLR_B_GREEN}/run <cmd>${ANSI_RESET}                • Execute a shell command locally in the session"
        echo -e "  ${CLR_B_GREEN}/unload${ANSI_RESET}                   • Unload previously loaded file from the chat context"
        echo -e "  ${CLR_B_GREEN}/start${ANSI_RESET}                    • Switch active context to multi-agent pipeline"
        echo -e "  ${CLR_B_GREEN}/quit${ANSI_RESET}                     • Terminate session gracefully"
      ;;
      # TODO: Finish the code for the '/draw' command
      "/draw") log_warn "Coming soon. Stay tuned!" ;;
      "/replay")
        if [[ -z $LAST_USER_MSG ]]; then
          log_warn "No previous message to replay!"
        else
          log_step "Replaying last message: ${CLR_B_WHITE}${LAST_USER_MSG}${ANSI_RESET}"
          send_message "$LAST_USER_MSG"
        fi
      ;;
      "/provider") log_warn "Missing command arguments. Usage: /provider <command>" ;;
      "/provider "*)
        local active_provider="${USER_MSG#"/provider "}" ; PROVIDER="$active_provider"
        log_step "New active provider: ${CLR_B_WHITE}${active_provider}${ANSI_RESET}"
        set_api_provider    # Reflect new active provider
        load_provider_key   # Load corresponding provider key
        set_vision_model    # Update corresponding vision model for new provider
      ;;
      "/model") log_warn "Missing command arguments. Usage: /model <command>" ;;
      "/model "*)
        local active_model="${USER_MSG#"/model "}" ; CHAT_MODEL="$active_model"
        log_step "New active model: ${CLR_B_WHITE}${active_model}${ANSI_RESET}"
        set_system_prompt   # Update system prompt with new active model
      ;;
      "/load") log_warn "Missing command arguments. Usage: /load <file>" ;;
      "/load "*)
        local file="${USER_MSG#"/load "}"
        local filename="${file##*/}"
        local fileext="${file##*.}"
        local max_preview_lines=100

        if [[ -r $file ]]; then
          EXTERNAL_FILE_LOADED="$file"    # Bind to core global state
          log_step "Loading file: ${CLR_B_WHITE}${filename}${ANSI_RESET}"
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
          log_step "Unloading file: ${CLR_B_WHITE}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET}"
          unset EXTERNAL_FILE_LOADED
        else
          log_warn "No file currently loaded."
        fi
      ;;
      "/run") log_warn "Missing command arguments. Usage: /run <command>" ;;
      "/run "*)
        local cmd="${USER_MSG#"/run "}"
        log_step "Locally executing: ${CLR_B_WHITE}${cmd}${ANSI_RESET}"
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
