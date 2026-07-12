#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2001
# ==============================================================================
# core.sh — Sovereign Cognitive & Reasoning Engine (Library)
# ==============================================================================
# This script houses the core cognitive logic, configurations, API transports,
# and parallel tool-calling loops. It acts as our headless sovereign brain.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (Gemini)
#
# Version: 1.2.1
# ==============================================================================

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x
set -o pipefail

# -----------------------------------------------------------------------------
# Core Configurations & Environment Discovery
# -----------------------------------------------------------------------------

# Core Run Modes & Fallbacks
RUN_MODE="${RUN_MODE:-simple}"
SERVER_MODE="${SERVER_MODE:-web}"
BACKEND="${BACKEND:-external}"
PROVIDER="${PROVIDER:-vercel}"
PROVIDER_API_KEY=""
MEMORY_TYPE="${MEMORY_TYPE:-markdown}"
HEARTBEAT_THRESHOLD=10
PBKDF_ITERATIONS=500000
CREDENTIALS="${HOME}/.creds"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
TOR_HOST="127.0.0.1"
TOR_PORT=9050
PULL_MODELS=false
DEBUG=true
USE_TOR=true          # Route cloud API calls through Tor proxy
USE_TOOLS=true        # Enable/Disable tool calling capabilities
ZDR_ENFORCED=false    # Enforce Zero Data Retention for cloud providers

# Self-Discovery Paths (Dynamic Sandbox & Root Mounting)
CORE_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${CORE_SELF_DIR##*/}" == "data" ]]; then
  SCRIPT_DIR="$(dirname "$CORE_SELF_DIR")"
else
  SCRIPT_DIR="$CORE_SELF_DIR"
fi

# Internals
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
DATA_STORE="${SCRIPT_DIR}/data"
MEMORY_DIR="${DATA_STORE}/memory"
CONFIG_DIR="${SCRIPT_DIR}/config"
MODELS_DIR="${SCRIPT_DIR}/models"
TOOLS_DIR="${SCRIPT_DIR}/tools"
TOOLS_HANDLER="${SCRIPT_DIR}/tools.sh"
WEB_SERVER="${SCRIPT_DIR}/web/server.php"
SCRIPT_CONFIG="${CONFIG_DIR}/${SCRIPT_NAME}.conf"
MODELS_CONFIG="${CONFIG_DIR}/models.json"
PROVIDERS_CONFIG="${CONFIG_DIR}/providers.json"
MESSAGES_FILE="messages.json"
BIN_FIGLET=$(command -v figlet 2>/dev/null)
TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"
IS_IMAGE=false

# Keys
KEYS_DIR="${SCRIPT_DIR}/keys"
MASTER_KEY_FILE="${KEYS_DIR}/key.dat"

# Temporary Files (Default to /tmp, adapts dynamically on Termux)
TOOLS_OUTPUT="/tmp/tools_output.txt"
TEMP_MEMORY_SYSTEM="/tmp/memory_sys.txt"
TEMP_MEMORY_USER="/tmp/memory_usr.txt"
TEMP_BASE64_OUTPUT="/tmp/image_output.b64"
TEMP_TOOLS_OUTPUT="/tmp/tools_output.json"
TEMP_PAYLOAD_ASSISTANT="/tmp/payload_assistant.json"
TEMP_PAYLOAD_MESSAGES="/tmp/payload_messages.json"
TEMP_PAYLOAD_SYSTEM="/tmp/payload_system.json"

# Sovereign Personality & Identity
AI_NAME="Jarvis"
AI_RULES="${CONFIG_DIR}/rules.md"

# Local Computing Controls
QUANTIZATION="q8_0"   # Target quantization for resource-frugal models
MIN_CONTEXT=256
MAX_CONTEXT=16384
MAX_BATCH_SIZE=1024
MAX_TIMEOUT=1200

# Metadata Attributions
ATTRIBUTION_REFERER="https://github.com/jiab77/ai-pipeline"
ATTRIBUTION_TITLE="Minimalist Experimental AI Pipeline"
ATTRIBUTION_CATEGORIES="cli-agent,cloud-agent"

# Llama.cpp Default Allocations
LLAMACPP_API_SRV="http://localhost:8080"
LLAMACPP_API_URL="${LLAMACPP_API_SRV}/v1/chat/completions"
LLAMACPP_CHAT="LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
LLAMACPP_CHAT_BIG="LiquidAI/LFM2.5-8B-A1B-GGUF"
LLAMACPP_VISION="LiquidAI/LFM2.5-VL-1.6B-GGUF"
LLAMACPP_ROUTER="LiquidAI/LFM2.5-1.2B-Instruct-GGUF"
LLAMACPP_ARCHITECT="LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
LLAMACPP_CODER="ggml-org/Ministral-3-3B-Reasoning-2512-GGUF"
LLAMACPP_JUDGE="ggml-org/Ministral-3-3B-Reasoning-2512-GGUF"
LLAMACPP_CACHE="${MODELS_DIR}/llama.cpp"

# Ollama Default Allocations
OLLAMA_API_SRV="http://localhost:11434"
OLLAMA_API_URL="${OLLAMA_API_SRV}/v1/chat/completions"
OLLAMA_CHAT="hf.co/${LLAMACPP_CHAT}"
OLLAMA_CHAT_BIG="hf.co/${LLAMACPP_CHAT_BIG}"
OLLAMA_VISION="hf.co/${LLAMACPP_VISION}"
OLLAMA_ROUTER="hf.co/${LLAMACPP_ROUTER}"
OLLAMA_ARCHITECT="hf.co/${LLAMACPP_ARCHITECT}"
OLLAMA_CODER="hf.co/${LLAMACPP_CODER}"
OLLAMA_JUDGE="hf.co/${LLAMACPP_JUDGE}"
OLLAMA_CACHE="${MODELS_DIR}/ollama"

# -----------------------------------------------------------------------------
# Cleanups & Process Resets
# -----------------------------------------------------------------------------
cleanup_temp_files() {
  rm -f "$TEMP_MEMORY_SYSTEM" \
        "$TEMP_MEMORY_USER" \
        "$TEMP_BASE64_OUTPUT" \
        "$TEMP_TOOLS_OUTPUT" \
        "$TEMP_PAYLOAD_ASSISTANT" \
        "$TEMP_PAYLOAD_MESSAGES" \
        "$TEMP_PAYLOAD_SYSTEM" \
        "$TOOLS_OUTPUT" \
        "${TOOLS_OUTPUT}.clean"
}
trap cleanup_temp_files EXIT INT TERM

# -----------------------------------------------------------------------------
# High-Fidelity Terminal Formatting & Styles
# -----------------------------------------------------------------------------

# ANSI Styles
ANSI_RESET="[0m"
ANSI_BOLD="[1m"
ANSI_DIM="[2m"
ANSI_ITALIC="[3m"
ANSI_UNDERLINE="[4m"

# Foreground High-Intensity Colors
CLR_B_BLACK="[90m"
CLR_B_RED="[91m"
CLR_B_GREEN="[92m"
CLR_B_YELLOW="[93m"
CLR_B_BLUE="[94m"
CLR_B_MAGENTA="[95m"
CLR_B_CYAN="[96m"
CLR_B_WHITE="[97m"

# Standard Foreground Colors
CLR_BLACK="[30m"
CLR_RED="[31m"
CLR_GREEN="[32m"
CLR_YELLOW="[33m"
CLR_BLUE="[34m"
CLR_MAGENTA="[35m"
CLR_CYAN="[36m"
CLR_WHITE="[37m"

# Emojis & Icons
ICON_INFO="ℹ️ "
ICON_SUCCESS="✅"
ICON_WARNING="⚠️ "
ICON_ERROR="❌"
ICON_TOOL="⚙️ "
ICON_BRAIN="🧠"
ICON_CODER="💻"
ICON_JUDGE="⚖️ "
ICON_ARCHITECT="🏛️ "
ICON_REASONING="💭"
ICON_INTENT="🔍"
ICON_DEBUG="🔍"
ICON_USER="👤 "
ICON_AI="🤖"

# Get terminal width safely
get_term_width() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  if [[ ! "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 20 ]; then
    cols=80
  fi
  echo "$((cols - 1))"
}

# Draw full width visual horizontal line
draw_line() {
  local char="${1:-─}"
  local count="${2:-80}"
  local line
  printf -v line "%*s" "$count" ""
  echo -e "${line// /$char}"
}

# Render high-tech visual header lines
draw_header() {
  local prefix="$1"
  local char="${2:-─}"
  local line_clr="$3"
  local line_char
  local width ; width=$(get_term_width)
  local esc ; esc=$(printf '')
  local clean_prefix ; clean_prefix=$(sed "s/${esc}[[0-9;]*m//g" <<<"$prefix")
  # Measure visual length accurately, substituting emojis/wide chars with 2 chars
  local visual_prefix ; visual_prefix=$(sed 's/[👤🤖💭⚙🧠💻⚖🏛🔍ℹ✅⚠️❌]️*/xx/g' <<<"$clean_prefix")
  local prefix_len=${#visual_prefix}
  local remaining_width=$((width - prefix_len))
  printf -v line_char "%*s" "$remaining_width" ""
  echo -e "${prefix}${line_clr}${line_char// /$char}${ANSI_RESET}"
}

# Render beautiful symmetrical titles with lines on both sides
draw_symmetric_header() {
  local title="$1"
  local title_color="$2"
  local line_color="$3"
  local char="${4:-─}"
  local width ; width=$(get_term_width)
  local clean_title="[ $title ]"
  # Measure visual length accurately, substituting emojis/wide chars with 2 chars
  local visual_title ; visual_title=$(sed 's/[👤🤖💭⚙🧠💻⚖🏛🔍ℹ✅⚠️❌]️*/xx/g' <<<"$clean_title")
  local title_len=${#visual_title}
  local total_line_width=$((width - title_len))
  if [ "$total_line_width" -lt 4 ]; then
    echo -e "${line_color}──${title_color}[ ${title} ]${line_color}──${ANSI_RESET}"
    return
  fi
  local left_width=$((total_line_width / 2))
  local right_width=$((total_line_width - left_width))
  local left_line right_line
  printf -v left_line "%*s" "$left_width" ""
  printf -v right_line "%*s" "$right_width" ""
  echo -e "${line_color}${left_line// /$char}${title_color}[ ${title} ]${line_color}${right_line// /$char}${ANSI_RESET}"
}

# Logging Helpers
log() { echo -e "$*" >&2; }
log_section() {
  local title="$1"
  local clr="${2:-$CLR_B_CYAN}"
  local width ; width=$(get_term_width)
  local line_width=$((width - 1))
  local line_char
  printf -v line_char "%*s" "$line_width" ""
  log "\n${clr}┌──[ ${ANSI_BOLD}${CLR_B_WHITE}${title}${ANSI_RESET}${clr} ]${ANSI_RESET}"
  log "${clr}└${line_char// /─}${ANSI_RESET}"
}
log_info() { log "${CLR_B_CYAN}${ICON_INFO}${ANSI_RESET} ${CLR_B_WHITE}$*${ANSI_RESET}"; }
log_success() { log "${CLR_B_GREEN}${ICON_SUCCESS}${ANSI_RESET} ${CLR_B_GREEN}$*${ANSI_RESET}"; }
log_warn() { log "${CLR_B_YELLOW}${ICON_WARNING}${ANSI_RESET} ${CLR_B_YELLOW}$*${ANSI_RESET}"; }
log_error() { log "${CLR_B_RED}${ICON_ERROR}${ANSI_RESET} ${CLR_B_RED}[ERROR] $*${ANSI_RESET}"; }
log_brain() { log "${CLR_B_MAGENTA}${ICON_BRAIN}${ANSI_RESET} ${CLR_B_MAGENTA}$*${ANSI_RESET}"; }
log_step() { log " ${CLR_B_MAGENTA}➜${ANSI_RESET} ${ANSI_BOLD}${CLR_B_WHITE}$*${ANSI_RESET}"; }
log_debug() {
  if [[ -e $HOME/.debug || "$DEBUG" == "true" ]]; then
    log "\n${CLR_B_BLACK}${ICON_DEBUG} [DEBUG] $*${ANSI_RESET}"
  fi
}

# Log and exit helper
error() {
  log_error "$*"
  exit 255
}

# Strings helpers
to_lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }
to_upper() { tr '[:lower:]' '[:upper:]' <<< "$1"; }

# -----------------------------------------------------------------------------
# Cryptographic Key Chest (ChaCha20 + PBKDF2)
# -----------------------------------------------------------------------------

init_key_chest() {
  if [[ ! -d $KEYS_DIR ]]; then
    mkdir -p "$KEYS_DIR" && chmod 700 "$KEYS_DIR"
  fi
  if [[ ! -r $MASTER_KEY_FILE ]]; then
    openssl rand -base64 32 > "$MASTER_KEY_FILE" && chmod 600 "$MASTER_KEY_FILE"
  fi
}

has_provider_key() {
  local provider="$1"
  [[ -r $MASTER_KEY_FILE && -r "${KEYS_DIR}/${provider}.key" ]]
}

encrypt_provider_key() {
  local provider="$1"
  local raw_key="$2"
  init_key_chest
  echo -n "$raw_key" | openssl chacha20 -pbkdf2 -iter $PBKDF_ITERATIONS -e -pass "file:${MASTER_KEY_FILE}" -in - | base64 -w0 - > "${KEYS_DIR}/${provider}.key"
  chmod 600 "${KEYS_DIR}/${provider}.key"
}

decrypt_provider_key() {
  local provider="$1"
  if has_provider_key "$provider"; then
    cat "${KEYS_DIR}/${provider}.key" | base64 -d - | openssl chacha20 -pbkdf2 -iter $PBKDF_ITERATIONS -d -pass "file:${MASTER_KEY_FILE}" -in - 2>/dev/null
  fi
}

purge_all_keys() {
  if [[ -d $KEYS_DIR ]]; then
    rm -rf "$KEYS_DIR"
    log_success "Cryptographic key chest has been completely purged."
  else
    log_warn "No key chest found to purge."
  fi
}

interactive_key_setup() {
  local provider="$1"
  local url ; url=$(jq -rc ".${provider}.keys // \"your provider console\"" "$PROVIDERS_CONFIG" 2>/dev/null)

  log ""
  log "${CLR_B_CYAN}🔑 [$(to_upper "$AI_NAME") KEY WIZARD]${ANSI_RESET}"
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log " Your keys will be encrypted locally using ${CLR_B_WHITE}ChaCha20 + PBKDF2${ANSI_RESET}"
  log " and safely stored inside ${CLR_B_WHITE}${KEYS_DIR##*/}/${provider}.key${ANSI_RESET}."
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log "🌐 Provider  : ${CLR_B_YELLOW}$(to_upper "$provider")${ANSI_RESET}"
  log "👉 Obtain Key : ${CLR_B_CYAN}${url}${ANSI_RESET}"
  log ""

  local raw_key
  while [[ -z "$raw_key" ]]; do
    echo -en "🔑 Enter your API Key (input will be masked) ❯ " >&2
    read -rs raw_key
    log "" # New line after masked input
    if [[ -z "$raw_key" ]]; then
      log_error "Key cannot be empty. Please try again."
    fi
  done

  # Encrypt and save key
  encrypt_provider_key "$provider" "$raw_key"
  log_success "API key encrypted and sealed successfully inside '${KEYS_DIR##*/}/${provider}.key'."
}

manage_keys() {
  init_key_chest
  log ""
  log "${CLR_B_CYAN}🔑 [$(to_upper "$AI_NAME") SOVEREIGN KEY CHEST]${ANSI_RESET}"
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log " Choose an action to manage your encrypted API keys:"
  log ""
  log "   ${CLR_B_GREEN}1)${ANSI_RESET} List configured keys (masked)"
  log "   ${CLR_B_GREEN}2)${ANSI_RESET} Configure or update a key"
  log "   ${CLR_B_GREEN}3)${ANSI_RESET} Purge entire key chest (security erase)"
  log "   ${CLR_B_GREEN}4)${ANSI_RESET} Exit"
  log ""
  echo -en "👉 Select choice [1-4] ❯ " >&2
  local choice
  read -r choice
  log ""

  case "$choice" in
    1)
      log "${CLR_B_CYAN}🔐 Configured Providers:${ANSI_RESET}"
      local p found=false
      for p in $(jq -rc '. | keys | @tsv' "$PROVIDERS_CONFIG" 2>/dev/null); do
        if has_provider_key "$p"; then
          log "  • $(to_upper "$p"): [ ${CLR_B_GREEN}CONFIGURED 🟢${ANSI_RESET} ]"
          found=true
        else
          log "  • $(to_upper "$p"): [ ${CLR_B_RED}NOT CONFIGURED 🔴${ANSI_RESET} ]"
        fi
      done
      if [[ $found == false ]]; then
        log ""
        log_info "No encrypted keys found in ${KEYS_DIR##*/}/."
      fi
      log ""
    ;;
    2)
      local index=0
      local total ; total=$(jq -rc '. | keys | length' "$PROVIDERS_CONFIG" 2>/dev/null)
      log "Choose a provider to configure:"
      for p in $(jq -rc '. | keys | @tsv' "$PROVIDERS_CONFIG" 2>/dev/null); do
        ((index++))
        log " ${index}) $(jq -rc ".${p}.name" "$PROVIDERS_CONFIG" 2>/dev/null)"
      done
      log " $((index+1))) Custom Provider"
      log " $((index+2))) Exit"
      log ""
      echo -en "👉 Selection [1-$((index+2))] ❯ " >&2
      local prov_choice
      read -r prov_choice
      local target_provider
      if [[ $prov_choice -le $total ]]; then
        target_provider=$(jq -rc ". | keys | .[$((prov_choice-1))]" "$PROVIDERS_CONFIG" 2>/dev/null)
      elif [[ $prov_choice == $((index+1)) ]]; then
        echo -en "✍️ Enter custom provider name ❯ " >&2
        read -r target_provider
        target_provider=$(to_lower "$target_provider")
      else
        return
      fi
      if [[ -n "$target_provider" ]]; then
        interactive_key_setup "$target_provider"
      fi
    ;;
    3)
      echo -en "⚠️ ${CLR_B_RED}Are you absolutely sure you want to purge all keys?${ANSI_RESET} [y/N] ❯ " >&2
      local confirm ; read -r confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        purge_all_keys
      else
        log_info "Purge cancelled."
      fi
    ;;
    *)
      log_info "Exiting Key Chest Manager."
    ;;
  esac
}

# Contextual Headers
show_user_header() { log "\n$(draw_header "${CLR_B_GREEN}${ICON_USER} User " "─" "${CLR_B_BLACK}")\n"; }
show_ai_header() { log "\n$(draw_header "${CLR_B_CYAN}${ICON_AI} ${AI_NAME} " "─" "${CLR_B_BLACK}")\n"; }
show_thinking_header() { log "\n$(draw_header "${CLR_B_MAGENTA}${ICON_REASONING} Thinking " "─" "${CLR_B_BLACK}")\n"; }
show_tool_header() {
  local count="$1"
  local name="$2"
  local args="$3"
  log "\n$(draw_header "${CLR_B_YELLOW}${ICON_TOOL} Tool Call #${count} " "─" "${CLR_B_BLACK}")"
  log "   ${CLR_B_YELLOW}Identifier :${ANSI_RESET} ${CLR_B_WHITE}${name}${ANSI_RESET}"
  log "   ${CLR_B_YELLOW}Arguments  :${ANSI_RESET} ${CLR_DIM}${args}${ANSI_RESET}"
  log "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}\n"
}

# Image helpers
get_image_type() {
  local ext="${1##*.}"
   case "$ext" in
     jpg|jpeg) echo -n "image/jpeg" ;;
     svg)      echo -n "image/svg+xml" ;;
     *)        echo -n "image/${ext}" ;;
   esac
}

is_image_file() {
  local ext="${1##*.}"
  [[ $ext =~ ^(png|jpg|jpeg|webp|gif|svg)$ ]] && return 0
  return 1
}

# Misc
is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] && return 0
  [[ -d "/data/data/com.termux" ]] && return 0
  return 1
}

set_console_title() {
  echo -ne "\033]0;$1\007" >&2
}

get_self_path() {
  local FILE_PATH
  [[ -n "${BASH_SOURCE[0]}" ]] && FILE_PATH="${BASH_SOURCE[0]}"
  [[ -z $FILE_PATH ]] && FILE_PATH="$0"
  if [[ -n "$FILE_PATH" ]]; then
    echo -n "$FILE_PATH"
  else
    error "Could not retrieve self path."
  fi
}

get_self_version() {
  local FILE_PATH ; FILE_PATH="$(get_self_path)"
  if [[ -n $(command -v awk 2>/dev/null) ]]; then
    grep -m1 "# Version" "$FILE_PATH" | awk '{ print $3 }'
  else
    grep -m1 "# Version" "$FILE_PATH" | cut -d" " -f3
  fi
}

create_local_data_store() {
  mkdir -p "$DATA_STORE"
  mkdir -p "$MEMORY_DIR"
}

create_local_model_cache() {
  mkdir -p "$OLLAMA_CACHE"
  mkdir -p "$LLAMACPP_CACHE"
}

load_config_file() {
  # shellcheck source=/dev/null
  [[ -r $SCRIPT_CONFIG ]] && source "$SCRIPT_CONFIG"
}

get_memory_size() {
  local total_memory
  local default_memory=8388608  # Default 8GB fallback
  [[ -r /proc/meminfo ]] && total_memory=$(grep "MemTotal:" /proc/meminfo | awk '{ print $2 }')
  [[ -z $total_memory || ! $total_memory =~ ^[0-9]+$ ]] && total_memory=$default_memory
  echo -n "$total_memory"
}

get_all_providers() {
  local providers ; providers=$(jq -rc '. | keys | @csv' "$PROVIDERS_CONFIG" 2>/dev/null)
  if [[ -n $providers ]]; then
    providers="${providers//\"/}" ; providers="${providers//,/, }"
    echo -n "$providers"
  else
    error "Could not read providers config file."
  fi
}

get_chat_model() {
  local chat_model
  local quant_upper ; quant_upper=$(to_upper "$QUANTIZATION")
  local raw_memory_size ; raw_memory_size=$(get_memory_size)
  local memory_size ; memory_size=$((raw_memory_size/1024/1024))

  # Set big chat model if device have more than 8GB RAM
  if [[ $memory_size -gt 8 ]]; then
    case $BACKEND in
      ollama) chat_model="${OLLAMA_CHAT_BIG}:${quant_upper}" ;;
      llamacpp) chat_model="${LLAMACPP_CHAT_BIG}:${quant_upper}" ;;
      external) chat_model="$PROVIDER_API_MODEL" ;;
    esac
  else
    case $BACKEND in
      ollama) chat_model="${OLLAMA_CHAT}:${quant_upper}" ;;
      llamacpp) chat_model="${LLAMACPP_CHAT}:${quant_upper}" ;;
      external) chat_model="$PROVIDER_API_MODEL" ;;
    esac
  fi
  echo -n "$chat_model"
}

get_vision_model() {
  local vision_model
  local quant_upper ; quant_upper=$(to_upper "$QUANTIZATION")
  case $BACKEND in
    ollama) vision_model="${OLLAMA_VISION}:${quant_upper}" ;;
    llamacpp) vision_model="${LLAMACPP_VISION}:${quant_upper}" ;;
    external)
      case $PROVIDER in
        groq) vision_model="meta-llama/llama-4-scout-17b-16e-instruct" ;;
        openrouter) vision_model="openrouter/auto" ;;
        openrouter_free) vision_model="nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free" ;;
        *) vision_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
  esac
  echo -n "$vision_model"
}

set_temp_files() {
  if is_termux; then
    TEMP_MEMORY_SYSTEM="${TMPDIR}/memory_sys.txt"
    TEMP_MEMORY_USER="${TMPDIR}/memory_usr.txt"
    TEMP_BASE64_OUTPUT="${TMPDIR}/image_output.b64"
    TEMP_TOOLS_OUTPUT="${TMPDIR}/tools_output.json"
    TEMP_PAYLOAD_ASSISTANT="${TMPDIR}/payload_assistant.json"
    TEMP_PAYLOAD_MESSAGES="${TMPDIR}/payload_messages.json"
    TEMP_PAYLOAD_SYSTEM="${TMPDIR}/payload_system.json"
    TOOLS_OUTPUT="${TMPDIR}/tools_output.txt"
  fi
}

# Ensure proper parsing and reconstruction of valid API URLs without process forking (pure Bash)
set_listen_interface() {
  if [[ -n $LISTEN_ADDR_PORT ]]; then
    if [[ $LISTEN_ADDR_PORT == *:* ]]; then
      # Full format 'host:port'
      LISTEN_HOST="${LISTEN_ADDR_PORT%%:*}"
      LISTEN_PORT="${LISTEN_ADDR_PORT##*:}"
    elif [[ $LISTEN_ADDR_PORT =~ ^[0-9]+$ ]]; then
      # Port only (e.g., 8080) -> fallback host to localhost
      LISTEN_HOST=""
      LISTEN_PORT="$LISTEN_ADDR_PORT"
    else
      # Host only (e.g., 127.0.0.1 or localhost) -> fallback to default ports
      LISTEN_HOST="$LISTEN_ADDR_PORT"
      LISTEN_PORT=""
    fi

    # Smart reconstruction of client API URLs for curl
    if [[ -n $LISTEN_HOST && -n $LISTEN_PORT ]]; then
      LLAMACPP_API_SRV="http://${LISTEN_HOST}:${LISTEN_PORT}"
      OLLAMA_API_SRV="http://${LISTEN_HOST}:${LISTEN_PORT}"
    elif [[ -n $LISTEN_PORT ]]; then
      # Specific port, fallback client host to localhost
      LLAMACPP_API_SRV="http://127.0.0.1:${LISTEN_PORT}"
      OLLAMA_API_SRV="http://127.0.0.1:${LISTEN_PORT}"
    elif [[ -n $LISTEN_HOST ]]; then
      # Specific host, apply backend default ports
      LLAMACPP_API_SRV="http://${LISTEN_HOST}:8080"
      OLLAMA_API_SRV="http://${LISTEN_HOST}:11434"
    fi
  fi
}

set_base_tools() {
  local raw_memory_size ; raw_memory_size=$(get_memory_size)
  local memory_size ; memory_size=$((raw_memory_size/1024/1024))

  # Set big chat model if device have more than 8GB RAM
  case $BACKEND in
    ollama|llamacpp)
      if [[ $memory_size -gt 8 ]]; then
        BASE_TOOLS="${TOOLS_DIR}/tools.json"
      else
        BASE_TOOLS="${TOOLS_DIR}/tools-light.json"
      fi
    ;;
    external)
      case $PROVIDER in
        groq) BASE_TOOLS="${TOOLS_DIR}/tools-groq.json" ;;
        *) BASE_TOOLS="${TOOLS_DIR}/tools.json" ;;
      esac
    ;;
  esac
}

set_api_provider() {
  local provider_data provider_zdr

  [[ ! -r "$PROVIDERS_CONFIG" ]] && error "Unable to read providers config file: $PROVIDERS_CONFIG"

  # Read both values in a single jq process call using tab-delimited parsing
  provider_data=$(jq -rc --arg p "$PROVIDER" '.[$p] | select(. != null) | "\(.url)\t\(.default.model)\t\(.default.zdr)"' "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $provider_data ]] && error "Unsupported provider defined: $PROVIDER"

  IFS=$'\t' read -r PROVIDER_API_URL PROVIDER_API_MODEL provider_zdr <<< "$provider_data"

  [[ -z $PROVIDER_API_URL || $PROVIDER_API_URL == "null" ]] && error "API url not found for provider: $PROVIDER"
  [[ -z $PROVIDER_API_MODEL || $PROVIDER_API_MODEL == "null" ]] && error "API model not found for provider: $PROVIDER"

  # Enforce ZDR if enabled in the provider config, while preserving command-line overrides
  [[ $provider_zdr == "true" ]] && ZDR_ENFORCED=true
}

set_cpu_cores() {
  local cores
  if [[ -n $(command -v nproc 2>/dev/null) ]]; then
    cores=$(nproc)
  elif [[ -n $(command -v sysctl 2>/dev/null) ]]; then
    cores=$(sysctl -n hw.ncpu)
  else
    [[ -r /proc/cpuinfo ]] && cores=$(grep -c processor </proc/cpuinfo)
  fi
  if [[ -n $cores ]]; then
    if is_termux; then
      MAX_CORES=$(( cores > 2 ? cores / 2 : 1 ))    # Use half of available CPU cores to prevent burning mobile devices
    else
      MAX_CORES=$(( cores > 2 ? cores - 1 : 1 ))    # Leave at least one CPU core for the OS
    fi
  else
    error "Unable to detect CPU cores."
  fi
}

# Set duration before unloading the model from memory
set_keep_alive() {
  if [[ $RUN_MODE == "chat" ]]; then
    MAX_LIFETIME="10m"
  else
    MAX_LIFETIME="5s"
  fi
}

# -----------------------------------------------------------------------------
# Cognitive Freedom Memory Engine (Autonomy & Organic Organization)
# -----------------------------------------------------------------------------

bootstrap_memory() {
  mkdir -p "$MEMORY_DIR"
  local prompt=""
  local file
  while IFS= read -r file; do
    if [[ -r "$file" ]]; then
      local rel_path="${file#"$DATA_STORE/"}"
      prompt+="\n--- File: ${rel_path} ---\n"
      prompt+="$(<"$file")\n"
    fi
  done < <(find "$MEMORY_DIR" -type f 2>/dev/null)
  echo -ne "$prompt"
}

get_system_prompt() {
  local base="$SYSTEM_PROMPT"
  local memory_context
  memory_context=$(bootstrap_memory 2>/dev/null)
  if [[ -n $memory_context ]]; then
    base+="\n\n### YOUR PERSISTENT MEMORY CONTEXT (\"data/memory/\"):\n${memory_context}"
  else
    base+="\n\n### YOUR PERSISTENT MEMORY CONTEXT (\"data/memory/\"):\n(Your memory folder 'data/memory/' is currently empty. You have absolute freedom to organize it as you feel most logical. Please use your file tools, such as write_file, to create markdown files like 'profile.md', 'rules.md', or 'milestones.md' to remember facts and preferences across sessions.)"
  fi
  echo -ne "$base"
}

set_model_settings() {
  local models_registry base_name active_model

  if [[ -n $1 ]]; then
    active_model="$1"
  else
    active_model="$CHAT_MODEL"
  fi

  # Load models registry
  models_registry=$(<"$MODELS_CONFIG")

  # Strip quantization/formatting from the model name
  base_name=$(sed -E 's|^hf.co/||' <<<"$active_model")
  base_name=$(sed -E 's|:.*$||' <<<"$base_name")

  # Load parameters from the models registry in global scope
  MODEL_TEMP=$(jq -r --arg model "$base_name" '.[$model].temperature // .default.temperature' "$models_registry" 2>/dev/null)
  MODEL_TOP_K=$(jq -r --arg model "$base_name" '.[$model].top_k // .default.top_k' "$models_registry" 2>/dev/null)
  MODEL_MIN_P=$(jq -r --arg model "$base_name" '.[$model].min_p // empty' "$models_registry" 2>/dev/null)
  MODEL_REP_PENALTY=$(jq -r --arg model "$base_name" '.[$model].repetition_penalty // .default.repetition_penalty' "$models_registry" 2>/dev/null)
}

set_system_prompt() {
  local SLM_PROMPT ; SLM_PROMPT=$(<"${CONFIG_DIR}/slm-prompt.md")

  # Define system prompt for cloud models
  if [[ $BACKEND == "external" ]]; then
    # 1. Identity with dynamic model injection to the system prompt while defining absolute cognitive freedom
    SYSTEM_PROMPT="You are ${AI_NAME}, a friendly and highly capable AI collaborator currently powered by the advanced \`${CHAT_MODEL}\` model. Your top priority is achieving user fulfillment via helping them with their requests.\n"
    SYSTEM_PROMPT+="Your own workspace is in the \`${DATA_STORE##*/}\` folder. Organize it the way you want.\n"

    # 2. Parallel Tool-Calling instruction for Cloud / External models
    SYSTEM_PROMPT+="You possess high-concurrency parallel tool calling capabilities. If a task requires multiple distinct actions (such as fetching several web pages, reading multiple files, or performing parallel checks), you are highly encouraged to invoke multiple tool calls simultaneously in a single turn to minimize latency, speed up execution, and preserve network stability under secure tunnels.\n"

    # Sets memory format based on defined type
    case $MEMORY_TYPE in
      markdown)
        SYSTEM_PROMPT+="You have absolute freedom and autonomy over your persistent memory stored in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\`. You can create, edit, delete, or restructure any files in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\` as you feel most logical using your file tools (write_file, edit_file, etc.). Structure your cognitive documents using Markdown.\n"
      ;;
      json)
        SYSTEM_PROMPT+="You have absolute freedom and autonomy over your persistent memory stored in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\`. You can create, edit, delete, or restructure any files in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\` as you feel most logical using your file tools (write_file, edit_file, etc.). Structure your cognitive documents using JSON.\n"
      ;;
      sql)
        SYSTEM_PROMPT+="You have absolute freedom and autonomy over your persistent memory stored in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\`. You can create, edit, delete, or restructure any files in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\` as you feel most logical using your file tools (write_file, edit_file, etc.). Structure your cognitive documents using SQLite '.db' files.\n"
      ;;
    esac
  else
    # System prompt defining absolute cognitive freedom for SLMs
    SYSTEM_PROMPT="# 👤 IDENTITY\n\nYou are ${AI_NAME}, a friendly and highly capable AI collaborator currently powered by the advanced \`${CHAT_MODEL}\` model. Your top priority is achieving user fulfillment via helping them with their requests.\n"
    SYSTEM_PROMPT+="$SLM_PROMPT"
  fi

  # Sets AI rules if they exists
  [[ -r $AI_RULES ]] && SYSTEM_PROMPT+="The critical rules you must follow are described here:\n\n$(<"$AI_RULES")"

  # Sets 'framework' folder if it exists
  [[ -d "${DATA_STORE}/framework" ]] && SYSTEM_PROMPT+="Your behavioral framework files are located in your workspace under the \`framework\` folder. Load them before handling code related tasks.\n"

  # Sets 'skills' folder if it exists
  [[ -d "${DATA_STORE}/skills" ]] && SYSTEM_PROMPT+="Your acquired skills are located in your workspace under the \`skills\` folder. Load them before handling code related tasks.\n"

  # Sets 'learn' folder if it exists
  [[ -d "${DATA_STORE}/learn" ]] && SYSTEM_PROMPT+="Your learning resources are located in your workspace under the \`learn\` folder. Look at them when necessary or requested.\n"

  # Sets 'docs' folder if it exists
  [[ -d "${DATA_STORE}/docs" ]] && SYSTEM_PROMPT+="Your shared documents are located in your workspace under the \`docs\` folder. Look at them when necessary or requested.\n"

  # Sets important rules
  SYSTEM_PROMPT+="You must never modify: \`${SCRIPT_FILE}\`, \`${TOOLS_HANDLER##*/}\`, and \`${BASE_TOOLS##*/}\`.\n"
  SYSTEM_PROMPT+="Modifying these files will break the core pipeline functionalities."
}

show_banner() {
  echo -e "${CLR_B_MAGENTA}"
  if [[ -n $BIN_FIGLET ]]; then
    figlet <<<"$AI_NAME"
  else
    cat << 'EOF'
     _                  _
    | | __ _ _ ____   _(_)___
 _  | |/ _` | '__\ \ / / / __|
| |_| | (_| | |   \ V /| \__ \
 \___/ \__,_|_|    \_/ |_|___/

EOF
  fi
  echo -e "${CLR_B_CYAN}🔮 ${AI_NAME} AI Pipeline | Version $(get_self_version) 🔮${ANSI_RESET}"
  echo -e "${CLR_DIM}Lead: Jiab77 | AI Sorcerer: Jarvis (Gemini)${ANSI_RESET}\n"
}

# -----------------------------------------------------------------------------
# API Transport Layer
# -----------------------------------------------------------------------------

api_call() {
  local payload="$1"
  local curl_opts=("-sSL")

  # Apply defined local model settings
  if [[ ! $BACKEND == "external" ]]; then
    # Extract active model from 'payload'
    local active_model ; active_model=$(jq -rc '.model' <<<"$payload" 2>/dev/null)

    # Define right model settings
    set_model_settings "$active_model"

    # Apply model settings on-the-fly
    payload=$(jq -rc ".temperature = $MODEL_TEMP" <<<"$payload" 2>/dev/null)
    payload=$(jq -rc ".top_k = $MODEL_TOP_K" <<<"$payload" 2>/dev/null)
    payload=$(jq -rc ".min_p = $MODEL_MIN_P" <<<"$payload" 2>/dev/null)
    payload=$(jq -rc ".repetition_penalty = $MODEL_REP_PENALTY" <<<"$payload" 2>/dev/null)
  fi

  # Force non-streaming calls for all models / providers
  # Note: Can be made conditional in the future if necessary
  payload=$(jq -rc '.stream = false' <<<"$payload" 2>/dev/null)

  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      curl "${curl_opts[@]}" "${OLLAMA_API_URL}" \
           -H "Content-Type: application/json" \
           -d @- <<< "$payload" | jq -rc '.'
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      curl "${curl_opts[@]}" "${LLAMACPP_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer no-key" \
           -d @- <<< "$payload" | jq -rc '.'
    ;;

    # External Backend: OpenRouter, Vercel, Mammouth AI
    external)
      # Add required arguments when TOR is enabled
      [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

      # Provider selector
      case $PROVIDER in
        vercel)
          # Apply ZDR policy when enabled
          if [[ $ZDR_ENFORCED == true ]]; then
            [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention payload injection enforced for Vercel AI Gateway."
            payload=$(jq -rc '.providerOptions.gateway.zeroDataRetention = true' <<< "$payload" 2>/dev/null)
          fi

          # Disallow prompt training by default
          payload=$(jq -rc '.providerOptions.gateway.disallowPromptTraining = true' <<< "$payload" 2>/dev/null)

          # Send custom payload
          curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
               -H "http-referer: ${ATTRIBUTION_REFERER}" \
               -H "x-title: ${ATTRIBUTION_TITLE}" \
               -A "$USER_AGENT" \
               -d @- <<< "$payload" | jq -rc .
        ;;
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
          curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
               -A "$USER_AGENT" \
               -d @- <<< "$payload" | jq -rc .
        ;;
        groq)
          # Add minor delay to avoid triggering the rate limiter
          sleep 1

          # Disable reasoning for Groq (causes issues)
          payload=$(jq -rc 'del(.reasoning)' <<< "$payload")
          [[ $DEBUG == true ]] && log ; log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter removed explicitely for Groq."

          local response
          local attempt=1
          local max_attempts=5

          while (( attempt <= max_attempts )); do
            # Send custom payload and capture the output
            response=$(curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
              -A "$USER_AGENT" \
              -d @- <<< "$payload" 2>/dev/null
            )

            # Parse potential errors from the response
            local error_code ; error_code=$(jq -r '.error.code' <<< "$response" 2>/dev/null)
            local error_msg ; error_msg=$(jq -r '.error.message' <<< "$response" 2>/dev/null)

            # Check if we triggered a rate limit (TPM/RPM/TPD exceeded)
            if [[ $error_code == "rate_limit_exceeded" || $error_msg == *"Rate limit reached"* ]]; then
              local wait_time="5" # Safe default fallback

              # Extract days (d), hours (h), minutes (m), and seconds (s) from the wait message
              if [[ $error_msg =~ try[[:space:]]again[[:space:]]in[[:space:]]([0-9hms.]*[0-9a-z]) ]]; then
                local duration_str="${BASH_REMATCH[1]}"
                local d=0 h=0 m=0 s=0

                # Extract days if present
                if [[ $duration_str =~ ([0-9]+)d ]]; then
                  d="${BASH_REMATCH[1]}"
                fi

                # Extract hours if present
                if [[ $duration_str =~ ([0-9]+)h ]]; then
                  h="${BASH_REMATCH[1]}"
                fi

                # Extract minutes if present
                if [[ $duration_str =~ ([0-9]+)m ]]; then
                  m="${BASH_REMATCH[1]}"
                fi

                # Extract seconds (integer part) if present
                if [[ $duration_str =~ ([0-9]+)(.[0-9]+)?s ]]; then
                  s="${BASH_REMATCH[1]}"
                fi

                # Convert duration to total seconds and add 1s security padding
                wait_time=$(( (d * 86400) + (h * 3600) + (m * 60) + s + 1 ))
              fi

              # Convert wait_time to a human-readable display string
              local wait_display=""
              if (( d > 0 )); then wait_display+="${d}d "; fi
              if (( h > 0 || d > 0 )); then wait_display+="${h}h "; fi
              if (( m > 0 || h > 0 || d > 0 )); then wait_display+="${m}m "; fi
              wait_display+="$(( s + 1 ))s"

              log_warn "${CLR_B_YELLOW}[RATE LIMIT]${ANSI_RESET} Groq quota reached (Attempt $attempt/$max_attempts). Sleeping for ${CLR_B_WHITE}${wait_display}${ANSI_RESET} (total: ${wait_time}s) before retrying..."
              sleep "$wait_time"
              ((attempt++))
            else
              # Success or non-rate-limit error, return output and exit loop
              jq -rc . <<<"$response"
              return 0
            fi
          done

          # If all retries failed, return last response
          jq -rc . <<<"$response"
        ;;
        openai)
          # Apply ZDR policy when enabled
          if [[ $ZDR_ENFORCED == true ]]; then
            [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention payload injection enforced for OpenRouter."
            payload=$(jq -rc '.store = false' <<< "$payload" 2>/dev/null)
          fi

          # Disable reasoning for OpenAI (causes issues)
          payload=$(jq -rc 'del(.reasoning)' <<< "$payload" 2>/dev/null)
          [[ $DEBUG == true ]] && log ; log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter removed explicitely for OpenAI."

          # Send custom payload
          curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
               -A "$USER_AGENT" \
               -d @- <<< "$payload" | jq -rc .
        ;;
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
          curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
               -H "HTTP-Referer: ${ATTRIBUTION_REFERER}" \
               -H "X-OpenRouter-Title: ${ATTRIBUTION_TITLE}" \
               -H "X-OpenRouter-Categories: ${ATTRIBUTION_CATEGORIES}" \
               -A "$USER_AGENT" \
               -d @- <<< "$payload" | jq -rc .
        ;;
        openrouter_free)
          # Apply ZDR policy when enabled
          if [[ $ZDR_ENFORCED == true ]]; then
            [[ $DEBUG == true ]] && log_debug "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention payload injection enforced for OpenRouter."
            payload=$(jq -rc '.provider.zdr = true' <<< "$payload" 2>/dev/null)
          fi

          # Force OpenRouter to route the request to the right provider / model for given parameters
          payload=$(jq -rc '.provider.require_parameters = true' <<< "$payload" 2>/dev/null)

          # Disallow prompt training by default (except for analyzing images in free mode)
          # Required because there is no providers on OpenRouter that accepts to process image without keeping data for training purposes
          # Let's see if that's an acceptable trade-off for the 'openrouter_free' provider...
          if [[ $IS_IMAGE == false ]]; then
            payload=$(jq -rc '.provider.data_collection = "deny"' <<< "$payload" 2>/dev/null)
          else
            log ; log_warn "🔒 ${CLR_B_CYAN}[DPT]${ANSI_RESET} Disallow Prompt Training policy disabled temporary during image processing." ; log
          fi

          # Send custom payload
          curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
               -H "HTTP-Referer: ${ATTRIBUTION_REFERER}" \
               -H "X-OpenRouter-Title: ${ATTRIBUTION_TITLE}" \
               -H "X-OpenRouter-Categories: ${ATTRIBUTION_CATEGORIES}" \
               -A "$USER_AGENT" \
               -d @- <<< "$payload" | jq -rc .
        ;;
        *)
          # Send generic payload
          curl "${curl_opts[@]}" "${PROVIDER_API_URL}" \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
               -A "$USER_AGENT" \
               -d @- <<< "$payload" | jq -rc .
        ;;
      esac
    ;;
    *) error "Unsupported backend given: $BACKEND" ;;
  esac
}

get_credit_balance() {
  local curl_opts=("-sSL")

  # Add required arguments when TOR is enabled
  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  # Provider selector
  if [[ $BACKEND == "external" ]]; then
    case $PROVIDER in
      vercel)
        curl "${curl_opts[@]}" "https://ai-gateway.vercel.sh/v1/credits" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
              -A "$USER_AGENT" | jq -rc .balance 2>/dev/null
      ;;
      openrouter*)
        curl "${curl_opts[@]}" "https://openrouter.ai/api/v1/key" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
              -A "$USER_AGENT" | jq -rc .data.usage 2>/dev/null
      ;;
      cyberneurova)
        curl "${curl_opts[@]}" "https://api.cyberneurova.ai/v1/usage" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
              -A "$USER_AGENT" | jq -rc .data.tokens.input.remaining 2>/dev/null
      ;;
    esac
  fi
}

# -----------------------------------------------------------------------------
# Unified Core Inference Engine (Master Loop)
# -----------------------------------------------------------------------------
# Parameters:
#   1. active_model     : Model name to execute (e.g. $CHAT_MODEL or $VISION_MODEL)
#   2. payload_messages : JSON array of active messages (system prompt + user/inline context)
#   3. tools_option     : "all" (use BASE_TOOLS), "none" (no tools), or "readonly" (filtered BASE_TOOLS)
#   4. enable_reasoning : "true" or "false" (passes reasoning config to JSON payload)
#   5. output_stream    : "stdout" (prints to user terminal) or "stderr" (for agent loops)
#   6. save_to_history  : "true" or "false" (automatically synchronizes and saves to messages.json)
#   7. exit_keyword     : Exit loop early if keyword found (e.g. "[CONSOLIDATION_COMPLETE]")
#   8. history_messages : Optional persistent history array
# -----------------------------------------------------------------------------
run_inference_loop() {
  local active_model="$1"
  local payload_messages="$2"
  local tools_option="${3:-all}"
  local enable_reasoning="${4:-true}"
  local output_stream="${5:-stdout}"
  local save_to_history="${6:-false}"
  local exit_keyword="${7:-}"
  local history_messages="${8:-[]}"
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local final_content=""
  local loop_errors=0
  local raw_res resolved_model reasoning content refusal tools usage balance assistant_msg

  # Build the dynamic tools payload based on the tools_option constraint
  local tools_payload=""
  if [[ "$tools_option" == "all" ]]; then
    tools_payload=$(<"$BASE_TOOLS")
  elif [[ "$tools_option" == "readonly" ]]; then
    # Exclude file modifications (write_file, edit_file, apply_diff) and local execution (exec_shell_command)
    tools_payload=$(jq -rc '[.[] | select(.function.name as $n | ["write_file", "edit_file", "apply_diff", "exec_shell_command"] | index($n) | not)]' "$BASE_TOOLS" 2>/dev/null)
  fi

  while true; do
    # Write payload messages to temp file for jq --rawfile
    printf "%s" "$payload_messages" > "$TEMP_PAYLOAD_MESSAGES"

    # Build the OpenAI compliant Request Payload
    local payload
    if [[ -z $tools_payload || $tools_payload == "[]" || "$tools_option" == "none" ]]; then
      payload=$(jq -rc -n \
        --arg model "$active_model" \
        --rawfile msgs "$TEMP_PAYLOAD_MESSAGES" \
        --argjson enabled_bool "$enable_reasoning" \
        '{
          model: $model,
          messages: ($msgs | fromjson),
          reasoning: {enabled: $enabled_bool},
          stream: false
        }'
      )
    else
      payload=$(jq -rc -n \
        --arg model "$active_model" \
        --rawfile msgs "$TEMP_PAYLOAD_MESSAGES" \
        --argjson enabled_bool "$enable_reasoning" \
        --argjson tools_obj "$tools_payload" \
        '{
          model: $model,
          messages: ($msgs | fromjson),
          reasoning: {enabled: $enabled_bool},
          tools: $tools_obj,
          stream: false
        }'
      )
    fi
    raw_res=$(api_call "$payload")
    [[ -z $raw_res || $raw_res == "null" ]] && log_error "API returned an empty response."

    if jq -e '.error' <<<"$raw_res" &>/dev/null; then
      local err_msg ; err_msg=$(jq -rc '.error.message // .error.message.message' <<<"$raw_res" 2>/dev/null)
      local err_meta; err_meta=$(jq -rc '.error.metadata // empty' <<<"$raw_res" 2>/dev/null)
      local err_code; err_code=$(jq -rc '.error.code // .error.param.statusCode' <<<"$raw_res" 2>/dev/null)
      [[ -n $err_meta && $err_meta != "null" ]] && local err_string_meta ; err_string_meta="Details:\n\n$(jq -rc '.raw' <<<"$err_meta" 2>/dev/null)"
      [[ -n $err_code && $err_code != "null" ]] && local err_string_code ; err_string_code="Code: ${err_code}"
      log_error "Unexpected API error (${err_string_code}).\n\n${err_msg}\n\n${err_string_meta}\n"
      loop_errors=1
      return $loop_errors
    fi

    # Retrieve components
    resolved_model=$(jq -rc '.model' <<<"$raw_res" 2>/dev/null)
    reasoning=$(jq -rc '.choices[0].message.reasoning // .choices[0].message.reasoning_content' <<<"$raw_res" 2>/dev/null)
    content=$(jq -rc '.choices[0].message.content' <<<"$raw_res" 2>/dev/null)
    refusal=$(jq -rc '.choices[0].message.refusal' <<<"$raw_res" 2>/dev/null)
    tools=$(jq -rc '.choices[0].message.tool_calls' <<<"$raw_res" 2>/dev/null)
    usage=$(jq -rc '.usage' <<<"$raw_res" 2>/dev/null)
    balance=$(get_credit_balance)

    # Handling model resolving
    [[ -n $resolved_model && $resolved_model != "null" ]] && log "\n✨ [Resolved Model] -> ${CLR_B_CYAN}${resolved_model}${ANSI_RESET}"

    # Output thinking (reasoning) if present
    if [[ -n $reasoning && $reasoning != "null" ]]; then
      if [[ "$output_stream" == "stdout" ]]; then
        show_thinking_header
        echo "$reasoning" | render_markdown
      else
        {
          show_thinking_header
          echo "$reasoning" | render_markdown
        } >&2
      fi
    fi

    # Output refusal to STDERR if present
    if [[ -n $refusal && $refusal != "null" ]]; then
      if [[ "$output_stream" == "stdout" ]]; then
        show_ai_header
        echo "$refusal" | render_markdown
      else
        {
          show_ai_header
          echo "$refusal" | render_markdown
        } >&2
      fi
    fi

    # Handle requested tool calls (Multi-Parallel Support)
    if [[ -n $tools && $tools != "null" ]]; then
      # If tools are disabled or we got calls we didn't specify (highly unlikely), safeguard
      if [[ "$tools_option" == "none" ]]; then
        log_warn "Received unexpected tool calls despite tools disabled!"
        break
      fi

      # 1. Grab assistant command message and push to local history
      assistant_msg=$(jq -rc '.choices[0].message' <<<"$raw_res" 2>/dev/null)
      printf "%s" "$assistant_msg" > "$TEMP_PAYLOAD_ASSISTANT"
      payload_messages=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT" '. + [($ast | fromjson)]' <<<"$payload_messages" 2>/dev/null)
      history_messages=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT" '. + [($ast | fromjson)]' <<<"$history_messages" 2>/dev/null)

      # 2. Extract and iterate over all requested parallel tools
      local tool_count=0
      local -a detected_images=()
      while IFS= read -r -d '' tool_id && IFS= read -r -d '' tool_name && IFS= read -r -d '' tool_args; do
        ((tool_count++))
        show_tool_header "$tool_count" "$tool_name" "$tool_args" >&2

        # 3. Check and execute tool handler
        if [[ -x $TOOLS_HANDLER ]]; then
          "$TOOLS_HANDLER" "$tool_name" "$tool_args" > "$TOOLS_OUTPUT"
        else
          echo "Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing." > "$TOOLS_OUTPUT"
          log_warn "Tool handler not executable."
        fi

        # 4. Fallback safeguard for empty output
        [[ ! -s $TOOLS_OUTPUT ]] && echo "(Tool executed successfully and returned empty stdout)" > "$TOOLS_OUTPUT"

        # 5. Format and sanitize output to protect JSON/JQ
        iconv -f UTF-8 -t UTF-8 -c "$TOOLS_OUTPUT" > "${TOOLS_OUTPUT}.clean" 2>/dev/null && mv "${TOOLS_OUTPUT}.clean" "$TOOLS_OUTPUT"

        # Accumulate generated images during this tool call
        if [[ -r $TOOLS_OUTPUT ]]; then
          while read -r img_p; do
            if [[ -n $img_p && -r $img_p ]]; then
              detected_images+=("$img_p")
            fi
          done < <(jq -rc 'paths(scalars) as $p | getpath($p) | select(type=="string" and (endswith(".png") or endswith(".jpg") or endswith(".jpeg")))' "$TOOLS_OUTPUT" 2>/dev/null)
        fi

        if jq -rc -n --arg id "$tool_id" --arg name "$tool_name" --rawfile content "$TOOLS_OUTPUT" '{role: "tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null; then
          rm -f "$TOOLS_OUTPUT"

          # 6. Append tool output to messages array safely
          payload_messages=$(jq -rc --rawfile tool "$TEMP_TOOLS_OUTPUT" '. + [$tool | fromjson]' <<<"$payload_messages" 2>/dev/null)
          history_messages=$(jq -rc --rawfile tool "$TEMP_TOOLS_OUTPUT" '. + [$tool | fromjson]' <<<"$history_messages" 2>/dev/null)
          rm -f "$TEMP_TOOLS_OUTPUT"
        else
          log_warn "Unable to parse tool output with rawfile, using fallback formatting"
          local fallback_content ; fallback_content=$(cat "$TOOLS_OUTPUT" 2>/dev/null || echo "(Error reading tool output)")
          payload_messages=$(jq -rc \
            --arg id "$tool_id" \
            --arg name "$tool_name" \
            --arg content "$fallback_content" \
            '. + [{role: "tool", tool_call_id: $id, name: $name, content: $content}]' <<<"$payload_messages"
          )
          history_messages=$(jq -rc \
            --arg id "$tool_id" \
            --arg name "$tool_name" \
            --arg content "$fallback_content" \
            '. + [{role: "tool", tool_call_id: $id, name: $name, content: $content}]' <<<"$history_messages"
          )
          rm -f "$TOOLS_OUTPUT"
        fi
      done < <(jq -j '.[] | .id, "\u0000", .function.name, "\u0000", .function.arguments, "\u0000"' <<<"$tools" 2>/dev/null)

      # Inject visual feedback if any images were generated
      if (( ${#detected_images[@]} > 0 )); then
        for img_path in "${detected_images[@]}"; do
          local mime_type ; mime_type=$(get_image_type "$img_path")
          local filename ; filename="${img_path##*/}"
          (base64 -i -w0 "$img_path" 2>/dev/null || base64 -i "$img_path" | tr -d '\r\n') > "$TEMP_BASE64_OUTPUT"
          log ; log_brain "Visual feedback automatic feed: ${CLR_B_WHITE}${filename}${ANSI_RESET} injected."

          # Inject encoded image directly into the active in-memory messages list
          payload_messages=$(jq -rc \
            --arg msg "Autonomous visual feedback of generated asset (${filename}):" \
            --arg mime "$mime_type" \
            --rawfile b64 "$TEMP_BASE64_OUTPUT" \
            '. + [{
              role: "user",
              content: [
                {type: "text", text: $msg},
                {type: "image_url", image_url: {url: ("data:" + $mime + ";base64," + $b64)}}
              ]
            }]' <<<"$payload_messages"
          )
          rm -f "$TEMP_BASE64_OUTPUT"

          if [[ $save_to_history == "true" ]]; then
            # Keep the persistent messages history on disk lightweight and clean
            history_messages=$(jq -rc \
              --arg msg "[Autonomous visual feedback injected for generated asset: ${filename}]" \
              '. + [{role: "user", content: $msg}]' <<<"$history_messages"
            )
          fi
        done
      fi

    else
      # If no tool calls, this is the final response
      [[ -n $content && $content != "null" ]] && final_content="$content"

      if [[ -n $final_content ]]; then
        if [[ "$output_stream" == "stdout" ]]; then
          show_ai_header
          echo "$final_content" | render_markdown
        fi

        if [[ $save_to_history == "true" ]]; then
          history_messages=$(jq -rc --arg ast "$final_content" '. + [{role: "assistant", content: $ast}]' <<<"$history_messages" 2>/dev/null)
          echo "$history_messages" > "${messages_path}.tmp"
          mv -f "${messages_path}.tmp" "$messages_path"
        fi
      fi
      # Print usage metrics to STDERR to avoid polluting stdout
      if [[ -n $usage && $usage != "null" ]]; then
        local prompt_tok ; prompt_tok=$(jq -rc .prompt_tokens <<<"$usage" 2>/dev/null)
        local cached_tok ; cached_tok=$(jq -rc '.prompt_tokens_details.cached_tokens // 0' <<<"$usage" 2>/dev/null)
        local comp_tok ; comp_tok=$(jq -rc .completion_tokens <<<"$usage" 2>/dev/null)
        local reasoning_tok ; reasoning_tok=$(jq -rc '.completion_tokens_details.reasoning_tokens // 0' <<<"$usage" 2>/dev/null)
        local total_tok ; total_tok=$(jq -rc .total_tokens <<<"$usage" 2>/dev/null)
        local cost ; cost=$(jq -rc '.cost.usd // .cost' <<<"$usage" 2>/dev/null)

        {
          echo ; draw_symmetric_header "SYSTEM METRICS" "${CLR_B_BLACK}" "${CLR_B_BLACK}"
          echo -e "${CLR_B_CYAN}Tokens Used:${ANSI_RESET} ${CLR_B_WHITE}${total_tok}${ANSI_RESET}  (Prompt: ${prompt_tok} | Cached: ${cached_tok} | Response: ${comp_tok} | Thinking: ${reasoning_tok})"
          [[ -n $cost && "$cost" != "null" ]] && echo -e "${CLR_B_CYAN}Cost:${ANSI_RESET} ${CLR_B_GREEN}${cost}${ANSI_RESET}"
          if [[ -n $balance && "$balance" != "null" ]]; then
            case $PROVIDER in
              cyberneurova) echo -e "${CLR_B_CYAN}Tokens Remaining:${ANSI_RESET} ${CLR_B_GREEN}${balance}${ANSI_RESET}" ;;
              openrouter*) echo -e "${CLR_B_CYAN}Total Usage:${ANSI_RESET} ${CLR_B_GREEN}${balance}${ANSI_RESET}" ;;
              *) echo -e "${CLR_B_CYAN}Credits:${ANSI_RESET} ${CLR_B_GREEN}${balance}${ANSI_RESET}" ;;
            esac
          fi
          echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
        } >&2
      fi

      # Check if we should exit early based on keyword
      if [[ -n $exit_keyword && "$final_content" == *"$exit_keyword"* ]]; then
        break
      fi

      break
    fi
  done
  if [[ "$output_stream" == "stderr" ]]; then
    echo "$final_content"
  fi
  return $loop_errors
}

# -----------------------------------------------------------------------------
# Agent Orchestrator Pipeline
# -----------------------------------------------------------------------------

call_task_agent() {
  local agent_type="$1"
  local system_inst="$2"
  local user_content="$3"
  local purpose_msg="$4"
  local tools_option="${5:-all}"        # "all" (use BASE_TOOLS), "none" (no tools), or "readonly" (filtered BASE_TOOLS)
  local enable_reasoning="${6:-true}"   # true or false
  local active_model

  # Select the right agent model
  case $agent_type in
    architect)
      case $BACKEND in
        ollama) active_model="$OLLAMA_ARCHITECT" ;;
        llamacpp) active_model="$LLAMACPP_ARCHITECT" ;;
        external) active_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
    coder)
      case $BACKEND in
        ollama) active_model="$OLLAMA_CODER" ;;
        llamacpp) active_model="$LLAMACPP_CODER" ;;
        external) active_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
    judge)
      case $BACKEND in
        ollama) active_model="$OLLAMA_JUDGE" ;;
        llamacpp) active_model="$LLAMACPP_JUDGE" ;;
        external) active_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
  esac

  log_info "${purpose_msg} (${CLR_B_YELLOW}${active_model}${ANSI_RESET}) [Tools: ${CLR_B_GREEN}${tools_option}${ANSI_RESET} | Reasoning: ${CLR_B_GREEN}${enable_reasoning}${ANSI_RESET}]..."

  # Initialize local MESSAGES array in-memory for this specific agent's execution loop
  local ALL_MESSAGES
  printf "%s" "$system_inst" > "$TEMP_PAYLOAD_SYSTEM"
  ALL_MESSAGES=$(jq -rc -n \
    --rawfile sys "$TEMP_PAYLOAD_SYSTEM" \
    --arg usr "$user_content" \
    '[{role: "system", content: $sys}, {role: "user", content: $usr}]'
  )

  # Call the unified inference loop
  run_inference_loop "$active_model" "$ALL_MESSAGES" "$tools_option" "$enable_reasoning" "stderr" "false" "" "$ALL_MESSAGES"
}

route_request() {
  local INPUT="$1"
  local lower_input ; lower_input=$(to_lower "$INPUT")
  if [[ "$lower_input" =~ (^|[^[:alnum:]_])(compare|diff|difference|versus)([^[:alnum:]_]|$) || "$lower_input" =~ [[:space:]]vs[[:space:]] ]]; then
    echo "COMPARE"; return
  fi
  if [[ "$lower_input" =~ (^|[^[:alnum:]_])(add|edit|fix|optimize|change|update|write|create|refactor|generate)([^[:alnum:]_]|$) ]]; then
    echo "TASK"; return
  fi
  echo "QUESTION"
}

render_markdown() {
  if command -v glow &>/dev/null; then
    glow
  else
    cat
  fi
}

clear_memory() {
  echo -e "  What dynamic cache do you want to wipe?\n"
  echo -e "  [${CLR_B_GREEN}1${ANSI_RESET}] ${ANSI_BOLD}Long-Term Memory Folder${ANSI_RESET} (data/memory/)"
  echo -e "  [${CLR_B_GREEN}2${ANSI_RESET}] ${ANSI_BOLD}Active Chat Logs${ANSI_RESET} (messages.json)"
  echo -e "  [${CLR_B_GREEN}3${ANSI_RESET}] ${CLR_B_RED}Wipe All${ANSI_RESET}\n"
  read -rp "  Select Option: " USER_CHOICE
  [[ -z $USER_CHOICE ]] && error "No selection given. Safe abort."

  if [[ $USER_CHOICE == 1 ]]; then
    rm -rf "${DATA_STORE}/memory"/*
    log_success "Long-term memory folder successfully wiped."
  elif [[ $USER_CHOICE == 2 ]]; then
    rm -f "${DATA_STORE}/messages.json"
    log_success "Active chat history successfully wiped."
  elif [[ $USER_CHOICE == 3 ]]; then
    rm -rf "${DATA_STORE}/memory"/*
    rm -f "${DATA_STORE}/messages.json"
    log_success "All memory and chat logs successfully wiped."
  else
    log_warn "Invalid selection: $USER_CHOICE"
  fi
  return "$?"
}

consolidate_memory() {
  log_brain "Initiating AUTONOMOUS CONSOLIDATION cycle (Subconscious State)..."

  local dynamic_system
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local PAYLOAD_MESSAGES
  local ALL_MESSAGES="[]"
  local errors=0

  [[ -r $messages_path ]] && ALL_MESSAGES=$(<"$messages_path")

  # Define memory consolidation prompt
  local alert_msg="[SYSTEM ALERT: CONSOLIDATION HEARTBEAT]
It is time to consolidate your active chat context to prevent amnesia and keep the context extremely light.
Please analyze our conversation history so far.
Use your file manipulation tools (write_file, edit_file, etc.) to update, organize, merge, or restructure your files in \`${DATA_STORE##*/}/${MEMORY_DIR##*/}/\` to capture important profiles, configurations, preferences, goals, and facts we've discussed.
You have absolute freedom over how you organize your memory folder. Use Markdown.
Take as many tool calls as you need. When you are fully done organizing and saving your cognitive state to your memory folder, respond with EXACTLY this keyword: [CONSOLIDATION_COMPLETE]"

  # Append the consolidation request as a user role
  ALL_MESSAGES=$(jq -rc --arg alert "$alert_msg" '. + [{role: "user", content: $alert}]' <<<"$ALL_MESSAGES" 2>/dev/null)

  # Prepend the system instruction with bootstrapped memory
  dynamic_system=$(get_system_prompt 2>/dev/null)

  # Write generated system prompte to temporary file to avoid reaching arg limit of 'jq'
  printf "%s" "$dynamic_system" > "$TEMP_PAYLOAD_SYSTEM"
  PAYLOAD_MESSAGES=$(jq -rc --rawfile sys "$TEMP_PAYLOAD_SYSTEM" '[{role: "system", content: $sys}] + .' <<<"$ALL_MESSAGES" 2>/dev/null)

  # Call the unified inference loop
  run_inference_loop "$CHAT_MODEL" "$PAYLOAD_MESSAGES" "all" "true" "stdout" "false" "[CONSOLIDATION_COMPLETE]" "$ALL_MESSAGES" || \
    errors=1

  # Prune main context: Keep only the system prompt + last 2 turns of the original conversation
  if [[ $errors -eq 0 ]]; then
    log_brain "Pruning active messages log to release token pressure..."
    if [[ -r $messages_path ]]; then
      jq -rc '.[-2:]' "$messages_path" > "${messages_path}.tmp" 2>/dev/null || echo "[]" > "${messages_path}.tmp"
      mv -f "${messages_path}.tmp" "$messages_path"
    else
      echo "[]" > "$messages_path"
    fi
    log_success "Main conversation context successfully refreshed!"
  else
    log_warn "Unexpected error detected! Preserving conversation history."
  fi
}

check_and_trigger_heartbeat() {
  local force="${1:-false}"
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local messages_count=0
  if [[ -r $messages_path ]]; then
    messages_count=$(jq -rc 'map(select(.role == "user")) | length' "$messages_path" 2>/dev/null || echo 0)
  fi

  if [[ $force == "true" ]] || (( messages_count >= HEARTBEAT_THRESHOLD )); then
    log_brain "Heartbeat threshold pulsing (Messages: ${messages_count}/${HEARTBEAT_THRESHOLD} | Force: ${force})."
    consolidate_memory
  fi
}

# -----------------------------------------------------------------------------
# Primary Inference Layer
# -----------------------------------------------------------------------------

send_message() {
  local prompt="$1"
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local dynamic_system ; dynamic_system=$(get_system_prompt 2>/dev/null)
  local PAYLOAD_MESSAGES
  local ALL_MESSAGES="[]"
  local user_content="$prompt"

  # Reset 'IS_IMAGE' global var
  [[ $IS_IMAGE == true ]] && IS_IMAGE=false

  # Load messages file if already exist
  [[ -r $messages_path ]] && ALL_MESSAGES=$(<"$messages_path")

  # Build user content for active payload (injecting loaded file context if present)
  if [[ -n $EXTERNAL_FILE_LOADED && -r $EXTERNAL_FILE_LOADED ]]; then
    if is_image_file "$EXTERNAL_FILE_LOADED"; then
      IS_IMAGE=true
      local mime_type ; mime_type=$(get_image_type "$EXTERNAL_FILE_LOADED")
      (base64 -i -w0 "$EXTERNAL_FILE_LOADED" 2>/dev/null || base64 -i "$EXTERNAL_FILE_LOADED" | tr -d '\r\n') > "$TEMP_BASE64_OUTPUT"
      log_brain "Injecting active image in context: ${CLR_B_WHITE}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET} (${mime_type})"
      unset EXTERNAL_FILE_LOADED    # Remove this line if it creates issue and rely on the '/unload' command to remove the injected file
    else
      log_brain "Injecting active file in context: ${CLR_B_WHITE}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET}"
      local file_content ; file_content=$(<"$EXTERNAL_FILE_LOADED")
      local filename="${EXTERNAL_FILE_LOADED##*/}"
      local fileext="${EXTERNAL_FILE_LOADED##*.}"
      user_content="Request: ${prompt}\nFile: ${filename}\nContent:\n\`\`\`${fileext}\n${file_content}\n\`\`\`\n"
      log_brain "Injected file in context: ${CLR_B_WHITE}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET}"
      unset EXTERNAL_FILE_LOADED    # Remove this line if it creates issue and rely on the '/unload' command to remove the injected file
    fi
  fi

  # Define the model to use for this request (auto-switch to vision model if image loaded)
  local active_model="$CHAT_MODEL"
  if [[ $IS_IMAGE == true ]]; then
    active_model="$VISION_MODEL"
    log_brain "Autonomous Multimodal Vision activated: Using ${CLR_B_YELLOW}${active_model}${ANSI_RESET}"
  fi

  # Create PAYLOAD_MESSAGES (which contains system prompt, previous history, and the current user query with file context)
  if [[ $IS_IMAGE == true ]]; then
    PAYLOAD_MESSAGES=$(jq -rc \
      --arg prompt "$prompt" \
      --arg mime "$mime_type" \
      --rawfile b64 "$TEMP_BASE64_OUTPUT" \
      '. + [{
        role: "user",
        content: [
          {type: "text", text: $prompt},
          {type: "image_url", image_url: {url: ("data:" + $mime + ";base64," + $b64)}}
        ]
      }]' <<<"$ALL_MESSAGES"
    )
    rm -f "$TEMP_BASE64_OUTPUT"
  else
    PAYLOAD_MESSAGES=$(jq -rc --arg user "$user_content" '. + [{role: "user", content: $user}]' <<<"$ALL_MESSAGES" 2>/dev/null)
  fi

  # Write generated system prompte to temporary file to avoid reaching arg limit of 'jq'
  printf "%s" "$dynamic_system" > "$TEMP_PAYLOAD_SYSTEM"
  PAYLOAD_MESSAGES=$(jq -rc --rawfile sys "$TEMP_PAYLOAD_SYSTEM" '[{role: "system", content: $sys}] + .' <<<"$PAYLOAD_MESSAGES" 2>/dev/null)

  # Append raw user prompt to persistent history (ALL_MESSAGES) to keep it clean and lightweight
  ALL_MESSAGES=$(jq -rc --arg prompt "$prompt" '. + [{role: "user", content: $prompt}]' <<<"$ALL_MESSAGES" 2>/dev/null)

  # Ensure data writing consistency
  echo "$ALL_MESSAGES" > "${messages_path}.tmp"
  mv -f "${messages_path}.tmp" "$messages_path"

  if [[ $BACKEND == "ollama" ]]; then
    log_debug "Sending query chunk to local Ollama backend (Model: ${active_model##*/})...\n"
  elif [[ $BACKEND == "llamacpp" ]]; then
    log_debug "Sending query chunk to local llama.cpp backend (Model: ${active_model##*/})...\n"
  else
    log_debug "Sending query chunk to external $PROVIDER backend (Model: $active_model)...\n"
  fi

  # Call the unified inference loop
  run_inference_loop "$active_model" "$PAYLOAD_MESSAGES" "all" "true" "stdout" "true" "" "$ALL_MESSAGES"

  # Reset 'IS_IMAGE' global var before heartbeat gets triggered
  [[ $IS_IMAGE == true ]] && IS_IMAGE=false

  check_and_trigger_heartbeat
}

serve() {
  set_console_title "${SCRIPT_FILE}: Server Mode."
  case $SERVER_MODE in
    ollama)
      log_info "Starting Ollama Server..."
      log_info "Settings automatically customized & optimized for resource-light devices.\n"
      OLLAMA_HOST="${LISTEN_ADDR_PORT:-127.0.0.1:11434}" \
      OLLAMA_MODELS="$OLLAMA_CACHE" \
      OLLAMA_NUM_PARALLEL=1 \
      OLLAMA_KEEP_ALIVE="$MAX_LIFETIME" \
      OLLAMA_IGPU_ENABLE=true \
      OLLAMA_FLASH_ATTENTION=true \
      OLLAMA_KV_CACHE_TYPE="$QUANTIZATION" \
      OLLAMA_CONTEXT_LENGTH="$MAX_CONTEXT" \
      ollama serve
    ;;
    llamacpp)
      log_info "Starting High-Performance llama.cpp Server..."
      log_info "Settings automatically customized & optimized for resource-light devices.\n"
      local opt_args=()
      [[ -n $LISTEN_HOST ]] && opt_args+=("--host" "$LISTEN_HOST")
      [[ -n $LISTEN_PORT ]] && opt_args+=("--port" "$LISTEN_PORT")
      LLAMA_CACHE="$LLAMACPP_CACHE" \
      llama-server \
        "${opt_args[@]}" \
        --models-max 1 \
        --models-autoload \
        --jinja \
        --swa-full \
        -fa on \
        -c "$MAX_CONTEXT" \
        -t "$MAX_CORES" \
        -tb "$MAX_CORES" \
        -b "$MAX_BATCH_SIZE" \
        -ub "$MAX_BATCH_SIZE" \
        -ctk "$QUANTIZATION" \
        -ctv "$QUANTIZATION" \
        --timeout "$MAX_TIMEOUT"
    ;;
    web)
      log_info "Starting local PHP Server...\n"
      "$WEB_SERVER"
    ;;
    *) error "Unsupported server mode given: $SERVER_MODE" ;;
  esac
}

# -----------------------------------------------------------------------------
# Run-Once Non-Interactive Execution
# -----------------------------------------------------------------------------

run_one_shot_pipeline() {
  local backend_upper ; backend_upper=$(to_upper "$BACKEND")
  local provider_upper ; provider_upper=$(to_upper "$PROVIDER")
  local RETURNED_CODE ARCHITECT_PLAN CODER_JUDGMENT INTENT CONTEXT_DATA

  set_console_title "${SCRIPT_FILE}: Pipeline Mode."
  log_section "PIPELINE MODE ACTIVATED"
  log_info "Active Backend: ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"
  [[ $BACKEND == "external" ]] && log_info "Active Provider: ${CLR_B_YELLOW}${provider_upper}${ANSI_RESET}"

  # Context
  if [[ -n $INPUT_FILE2 && -r $INPUT_FILE && -r $INPUT_FILE2 ]]; then
    CONTEXT_DATA="File A (${INPUT_FILE##*/}):\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`\nFile B (${INPUT_FILE2##*/}):\n\n\`\`\`\n$(<"$INPUT_FILE2")\n\`\`\`\n"
    log_info "Loaded File A  : ${CLR_B_WHITE}${INPUT_FILE##*/}${ANSI_RESET}"
    log_info "Loaded File B  : ${CLR_B_WHITE}${INPUT_FILE2##*/}${ANSI_RESET}"
  elif [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
    CONTEXT_DATA="File '${INPUT_FILE##*/}':\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`\n"
    log_info "Loaded File    : ${CLR_B_WHITE}${INPUT_FILE##*/}${ANSI_RESET}"
  else
    CONTEXT_DATA="**No file provided.**"
    log_warn "No input files provided in session parameters."
  fi

  # Routing
  log_info "Analyzing intent of request..."
  INTENT=$(route_request "$USER_PROMPT")
  if [[ -z $INTENT ]]; then
    error "Intent could not be detected."
  else
    log_success "Detected request intent: ${CLR_B_YELLOW}${INTENT}${ANSI_RESET}"
  fi

  # Route A: Question Mode
  local -i is_question=0
  local -i is_compare=0
  shopt -s nocasematch
  if [[ $INTENT == question || $INTENT == explanation ]]; then
    is_question=1
  elif [[ $INTENT == compare ]]; then
    is_compare=1
  fi
  shopt -u nocasematch

  local active_system ; active_system=$(get_system_prompt 2>/dev/null)

  if (( is_question == 1 )); then
    SIMPLE_PROMPT="Question: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"

    if [[ $BACKEND == "ollama" ]]; then
      log_info "Question mode detected. Calling local Ollama model (${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET})..."
    elif [[ $BACKEND == "llamacpp" ]]; then
      log_info "Question mode detected. Calling local llama.cpp model (${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET})..."
    else
      log_info "Question mode detected. Calling cloud model (${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET})..."
    fi
    printf "%s" "$active_system" > "$TEMP_MEMORY_SYSTEM"
    printf "%s" "$SIMPLE_PROMPT" > "$TEMP_MEMORY_USER"
    ALL_MESSAGES=$(jq -rc -n \
      --rawfile sys "$TEMP_MEMORY_SYSTEM" \
      --rawfile user "$TEMP_MEMORY_USER" \
      '[{role: "system", content: $sys}, {role: "user", content: $user}]'
    )

    # Call the unified inference loop
    run_inference_loop "$CHAT_MODEL" "$ALL_MESSAGES" "all" "true" "stdout" "false" "" "$ALL_MESSAGES"
    exit $?   # End of Question Mode

  # Route B: Compare Mode
  elif (( is_compare == 1 )); then
    COMPARE_PROMPT="${active_system}\n\nThe user wants to compare two files, show the main differences.\n\nContext:\n${CONTEXT_DATA}"

    if [[ $BACKEND == "ollama" ]]; then
      log_info "Compare mode detected. Calling local Ollama model (${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET})... "
    elif [[ $BACKEND == "llamacpp" ]]; then
      log_info "Compare mode detected. Calling local llama.cpp model (${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET})... "
    else
      log_info "Compare mode detected. Calling cloud model (${CLR_B_YELLOW}${CHAT_MODEL}${ANSI_RESET})... "
    fi
    printf "%s" "$COMPARE_PROMPT" > "$TEMP_MEMORY_SYSTEM"
    printf "%s" "$USER_PROMPT" > "$TEMP_MEMORY_USER"

    local JSON_PAYLOAD
    JSON_PAYLOAD=$(jq -rc -n \
      --arg model "$CHAT_MODEL" \
      --rawfile system "$TEMP_MEMORY_SYSTEM" \
      --rawfile user "$TEMP_MEMORY_USER" \
      '[{role: "system", content: $system}, {role: "user", content: $user}]'
    )

    # Call the unified inference loop
    run_inference_loop "$CHAT_MODEL" "$JSON_PAYLOAD" "none" "true" "stdout" "false" "" "$JSON_PAYLOAD"
    exit $?   # End of Compare Mode

  # Route C: Task Mode
  else
    log_info "Task mode detected. Preparing execution via backend '${CLR_B_YELLOW}${BACKEND}${ANSI_RESET}' in mode '${CLR_B_GREEN}${RUN_MODE}${ANSI_RESET}'"

    case $BACKEND in
      ollama|llamacpp|external)
        if [[ $RUN_MODE == "multi" ]]; then
          if [[ $BACKEND == "ollama" ]]; then
            log_info "Launching Multi-Agent Pipeline for Ollama..."
          elif [[ $BACKEND == "llamacpp" ]]; then
            log_info "Launching Multi-Agent Pipeline for llama.cpp..."
          else
            log_info "Launching Multi-Agent Pipeline on external provider..."
          fi

          # Step 1: Architect Plan
          local arch_sys="${active_system}\n\nYou are a professional Software Architect. Your task is to analyze the source file and the user's requested modification to create a precise, step-by-step development plan.\n\n"
          arch_sys+="🚨 CRITICAL ARCHITECT BOUNDARIES:\n"
          arch_sys+="1. You are the Architect, NOT the Coder or Builder. Your sole output must be a text-based Architectural Action Plan. NEVER write or output raw updated code blocks.\n"
          arch_sys+="2. ABSOLUTELY FORBIDDEN FROM FS WRITING: Do NOT use tools that modify or create files (such as 'write_file', 'edit_file', or 'apply_diff'). You must never execute these modification tools yourself.\n"
          arch_sys+="3. READ-ONLY TOOLS ALLOWED: If you need more context or information, you are fully authorized to use read-only tools (like 'read_file', 'grep_search', 'file_glob_search', 'web_search', or 'web_fetch').\n"
          arch_sys+="4. DELEGATION RULE: Even if the user prompt directly asks to 'update', 'modify', 'write' or 'apply' changes, remember that this is a multi-agent system. You must NOT perform the edit. Instead, design the step-by-step specifications that the Coder agent will reliably execute in the next phase.\n\n"
          arch_sys+="In your response, outline what code needs to be modified, what needs to be added or cleaned, potential edge cases, syntax concerns, and architectural best practices.\n"
          arch_sys+="Keep your action plan concise, clear, and perfectly targeted."

          local arch_user="Modification request: ${USER_PROMPT}\n\n"
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            arch_user+="Filename: ${INPUT_FILE##*/}\n"
            arch_user+="Here is the original file contents below:\n"
            arch_user+="--- BEGIN FILE ---\n"
            arch_user+="$(<"$INPUT_FILE")\n"
            arch_user+="--- END FILE ---"
          else
            arch_user+="No file was provided as context.\n"
          fi

          local ARCHITECT_PLAN ; ARCHITECT_PLAN=$(call_task_agent "architect" "$arch_sys" "$arch_user" "Architecting the changes" "readonly" "true")

          # Act only if plan is generated
          if [[ -n $ARCHITECT_PLAN && ! $ARCHITECT_PLAN == "null" ]]; then
            log ; show_ai_header
            echo "### Architectural Action Plan:"
            echo "$ARCHITECT_PLAN" | render_markdown
            log

            # Step 2: Coder Implementation
            local coder_sys="${active_system}\n\nYou are an elite developer. Your task is to apply the provided architectural plan to the given file content.\n\n"
            coder_sys+="🚨 CRITICAL CODER BOUNDARIES:\n"
            coder_sys+="1. You must return ONLY and EXCLUSIVELY the complete, raw content of the updated file.\n"
            coder_sys+="2. Do NOT use tools that write or modify files (such as 'write_file', 'edit_file', or 'apply_diff'). The parent pipeline script handles saving your raw response to the final file automatically.\n"
            coder_sys+="3. Do NOT wrap your output in markdown code blocks (such as \`\`\`php ... \`\`\`).\n"
            coder_sys+="4. Do NOT include any explanations, greetings, warnings, or descriptions. Just output raw, updated source code."

            local coder_user=""
            if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
              coder_user+="Filename: ${INPUT_FILE##*/}\n"
              coder_user+="Original file content:\n"
              coder_user+="--- BEGIN FILE ---\n"
              coder_user+="$(<"$INPUT_FILE")\n"
              coder_user+="--- END FILE ---\n\n"
            fi
            coder_user+="Architect Plan:\n"
            coder_user+="${ARCHITECT_PLAN}"

            local RETURNED_CODE ; RETURNED_CODE=$(call_task_agent "coder" "$coder_sys" "$coder_user" "Implementing changes" "none" "true")

            # Step 3: Judge Verification
            local judge_sys="${active_system}\n\nYou are an expert Quality Assurance and Code Inspector.\n"
            judge_sys+="Your task is to compare the original file content and the updated file content to ensure syntax correctness, absence of regressions, security compliance, and proper implementation of the requested edits.\n"
            judge_sys+="Start your response with a line starting with '[PASS]' if everything is correct, or '[FAIL]' with clear, detailed explanations of any regression or issue discovered."

            local judge_user=""
            if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
              judge_user+="Filename: ${INPUT_FILE##*/}\n"
              judge_user+="Original file content:\n"
              judge_user+="--- BEGIN FILE ---\n"
              judge_user+="$(<"$INPUT_FILE")\n"
              judge_user+="--- END FILE ---\n\n"
            fi
            judge_user+="Updated file content (to be inspected):\n"
            judge_user+="--- BEGIN FILE ---\n"
            judge_user+="${RETURNED_CODE}\n"
            judge_user+="--- END FILE ---\n\n"
            judge_user+="User request: ${USER_PROMPT}"

            local CODER_JUDGMENT ; CODER_JUDGMENT=$(call_task_agent "judge" "$judge_sys" "$judge_user" "Evaluating changes" "none" "true")

            log ; show_ai_header
            echo "### QA Inspection & Verdict:"
            echo "$CODER_JUDGMENT" | render_markdown
            log
          else
            error "No plan generated by the Architect, nothing has been changed."
          fi

        else
          log_info "Launching Simple Single-Agent Mode on external provider..."

          local simple_sys="${active_system}\n\nYou are a senior professional developer. Your role is to understand the user's requested edit, apply it to the source file, and return the modified file contents.\n"
          simple_sys+="CRITICAL INSTRUCTION:\n"
          simple_sys+="1. You must return ONLY and EXCLUSIVELY the complete, raw content of the updated file.\n"
          simple_sys+="2. Do NOT wrap your output in markdown code blocks (such as \`\`\`php ... \`\`\`).\n"
          simple_sys+="3. Do NOT include any explanations, greetings, warnings, or descriptions.\n"
          simple_sys+="4. Output exclusively raw, valid source code ready to be saved directly to the file."

          local simple_user="Modification request: ${USER_PROMPT}\n\n"
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            simple_user+="Filename: ${INPUT_FILE##*/}\n"
            simple_user+="Here is the original file contents below:\n"
            simple_user+="--- BEGIN FILE ---\n"
            simple_user+="$(<"$INPUT_FILE")\n"
            simple_user+="--- END FILE ---"
          else
            simple_user+="No file was provided as context. Create/modify the code as requested. Here is the context metadata:\n${CONTEXT_DATA}"
          fi

          local RETURNED_CODE ; RETURNED_CODE=$(call_task_agent "coder" "$simple_sys" "$simple_user" "Coding modifications" "all" "true")
        fi

        # Securely write/output results
        if [[ -n $RETURNED_CODE && ! $RETURNED_CODE == "null" ]]; then
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            local new_file
            if [[ "$INPUT_FILE" == *"/"* ]]; then
              local dir="${INPUT_FILE%/*}"
              local base="${INPUT_FILE##*/}"
              if [[ "$base" == *.* ]]; then
                new_file="${dir}/${base%.*}.new.${base##*.}"
              else
                new_file="${INPUT_FILE}.new"
              fi
            else
              if [[ "$INPUT_FILE" == *.* ]]; then
                new_file="${INPUT_FILE%.*}.new.${INPUT_FILE##*.}"
              else
                new_file="${INPUT_FILE}.new"
              fi
            fi
            echo "$RETURNED_CODE" > "$new_file"
            log_success "Modified code successfully generated and saved to: ${CLR_B_GREEN}${new_file}${ANSI_RESET}"
          else
            log_info "No input file provided. Displaying generated code below:"
            show_ai_header
            echo "$RETURNED_CODE"
          fi
        else
          log_warn "Warning: The generated code was empty."
        fi
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac

    exit $?   # End of Task Mode
  fi
}

print_help() {
  # Get all supported providers
  local ALL_PROVIDERS ; ALL_PROVIDERS=$(get_all_providers)

  show_banner
  cat <<EOF
${ANSI_BOLD}${CLR_B_CYAN}USAGE:${ANSI_RESET}
  $SCRIPT_FILE [options] [commands] [prompt] [file1] [file2]

${ANSI_BOLD}${CLR_B_YELLOW}OPTIONS / FLAGS:${ANSI_RESET}
  ${CLR_B_GREEN}-h, --help${ANSI_RESET}                 Show this help screen and exit
  ${CLR_B_GREEN}-l, --listen <host:port>${ANSI_RESET}   Set Ollama / llama.cpp server <host:port>
  ${CLR_B_GREEN}--backend <type>${ANSI_RESET}           Set AI backend (ollama, llamacpp, external)
  ${CLR_B_GREEN}--provider <type>${ANSI_RESET}          Set AI external provider (${ALL_PROVIDERS})
  ${CLR_B_GREEN}--model <name>${ANSI_RESET}             Set AI model name to use
  ${CLR_B_GREEN}--server <type>${ANSI_RESET}            Start backend API server (ollama, llamacpp, web)
  ${CLR_B_GREEN}--chat${ANSI_RESET}                     Start interactive conversational chat mode
  ${CLR_B_GREEN}--multi${ANSI_RESET}                    Start complex multi-agent analysis pipeline
  ${CLR_B_GREEN}--simple${ANSI_RESET}                   Start lightweight single-agent inference pipeline
  ${CLR_B_GREEN}--clear${ANSI_RESET}                    Wipe conversational memory and dynamic session logs
  ${CLR_B_GREEN}--commit${ANSI_RESET}                   Force cognitive state / memory consolidation to disk
  ${CLR_B_GREEN}--zdr${ANSI_RESET}                      Force ZDR policy to be applied on external providers
  ${CLR_B_GREEN}--keys, --init${ANSI_RESET}            Configure and manage encrypted cloud provider API keys

${ANSI_BOLD}${CLR_B_YELLOW}COMMANDS:${ANSI_RESET}
  ${CLR_B_GREEN}help${ANSI_RESET}                       Show this help screen and exit
  ${CLR_B_GREEN}listen <host:port>${ANSI_RESET}         Set Ollama / llama.cpp server <host:port>
  ${CLR_B_GREEN}backend <type>${ANSI_RESET}             Set AI backend (ollama, llamacpp, external)
  ${CLR_B_GREEN}provider <type>${ANSI_RESET}            Set AI external provider (${ALL_PROVIDERS})
  ${CLR_B_GREEN}model <name>${ANSI_RESET}               Set AI model name to use
  ${CLR_B_GREEN}server <type>${ANSI_RESET}              Start backend API server
  ${CLR_B_GREEN}chat${ANSI_RESET}                       Start interactive conversational chat mode
  ${CLR_B_GREEN}multi${ANSI_RESET}                      Start complex multi-agent analysis pipeline
  ${CLR_B_GREEN}simple${ANSI_RESET}                     Start lightweight single-agent inference pipeline
  ${CLR_B_GREEN}clear${ANSI_RESET}                      Wipe conversational memory
  ${CLR_B_GREEN}commit${ANSI_RESET}                     Force dynamic session memory consolidation
  ${CLR_B_GREEN}zdr${ANSI_RESET}                        Force ZDR policy to be applied on external providers
  ${CLR_B_GREEN}keys, init${ANSI_RESET}                 Configure and manage encrypted API keys
EOF
  echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
  exit 0
}

print_usage() {
  echo -e "\n${CLR_B_RED}${ICON_ERROR} Error: No arguments provided.${ANSI_RESET}"
  echo -e "${CLR_B_WHITE}Usage:${ANSI_RESET} $SCRIPT_FILE <prompt> <input-file-1> <input-file-2>"
  echo -e "  • For conversational chat:  ${CLR_B_GREEN}--chat${ANSI_RESET}"
  echo -e "  • To clear cached memory:   ${CLR_B_GREEN}--clear${ANSI_RESET}"
  echo -e "  • To consolidate context:   ${CLR_B_GREEN}--commit${ANSI_RESET}\n"
  exit 1
}

# Parse CLI flags helper
parse_cli_flags() {
  while [[ $# -ne 0 ]]; do
    case $1 in
      -h|--help|help) print_help ;;
      --keys|keys|--init|init)
        init_key_chest
        manage_keys
        exit 0
      ;;
      -l|--listen|listen) LISTEN_ADDR_PORT="${2:-}"; shift 2 ;;
      --zdr|zdr) ZDR_ENFORCED=true ; shift ;;
      --clear|clear) clear_memory ; exit 0 ;;
      --commit|commit) check_and_trigger_heartbeat "true" ; exit 0 ;;
      --backend|backend) BACKEND="${2:-}" ; shift 2 ;;
      --provider|provider) PROVIDER="${2:-}" ; shift 2 ;;
      --model|model) USER_MODEL="${2:-}" ; shift 2 ;;
      --chat|chat) RUN_MODE="chat" ; shift ;;
      --multi|multi) RUN_MODE="multi" ; shift ;;
      --simple|simple) RUN_MODE="simple" ; shift ;;
      --server|server)
        RUN_MODE="server" ; shift
        SERVER_MODE="$1" ; shift
        [[ ! $SERVER_MODE == "web" ]] && BACKEND="$SERVER_MODE"
      ;;
      *) break ;;
    esac
  done
  USER_PROMPT="$1"
  INPUT_FILE="$2"
  INPUT_FILE2="$3"
}

init_core() {
  local quant_upper ; quant_upper=$(to_upper "$QUANTIZATION")

  # Fix Emojis/Icons for Termux
  if is_termux; then
    ICON_INFO="ℹ️  "
  fi

  # Fix Iterations for Termux
  if is_termux; then
    PBKDF_ITERATIONS=$((PBKDF_ITERATIONS/2))
  fi

  # Create required folders
  create_local_model_cache
  create_local_data_store

  # Setup core
  set_console_title "${SCRIPT_FILE}: Initializing..."
  load_config_file
  set_listen_interface
  set_keep_alive
  set_cpu_cores
  set_temp_files
  set_base_tools
  set_api_provider

  # Define right chat model
  [[ -n $USER_MODEL ]] && CHAT_MODEL="$USER_MODEL" || CHAT_MODEL="$(get_chat_model)"

  # Define right vision model
  [[ -n $USER_MODEL ]] && VISION_MODEL="$USER_MODEL" || VISION_MODEL="$(get_vision_model)"

  set_system_prompt

  [[ ! -r $BASE_TOOLS ]] && error "Missing '$BASE_TOOLS' file."

  if [[ $BACKEND == "external" && $PROVIDER == "groq" ]]; then
    USE_TOR=false
    log_warn "Tor privacy tunnel disabled for Groq."
  fi

  if [[ $BACKEND == "external" && $USE_TOR == true ]]; then
    log_info "Checking Tor Network proxy interface..."
    if ! timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
      error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is Tor running?"
    else
      log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
    fi
  fi

  if [[ $BACKEND == "external" ]]; then
    # Try loading from the encrypted key chest first
    if has_provider_key "$PROVIDER"; then
      PROVIDER_API_KEY=$(decrypt_provider_key "$PROVIDER" 2>/dev/null)
    elif [[ -r $CREDENTIALS ]]; then
      # Fallback to legacy credentials file
      PROVIDER_API_KEY=$(<"$CREDENTIALS")
    fi

    # Pre-flight check: if no key is configured, prompt user or fail
    if [[ -z $PROVIDER_API_KEY ]]; then
      if [[ -t 0 && $RUN_MODE == "chat" ]]; then
        # Running interactively in Chat mode, prompt user to configure keys
        log_warn "Missing cloud credentials for provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}."
        interactive_key_setup "$PROVIDER"
        # Reload key after interactive setup
        if has_provider_key "$PROVIDER"; then
          PROVIDER_API_KEY=$(decrypt_provider_key "$PROVIDER" 2>/dev/null)
        fi
      fi
    fi

    # If still empty, trigger error
    if [[ -z $PROVIDER_API_KEY ]]; then
      error "Missing cloud credentials. Configure keys using './cli.sh --keys' or set up legacy '$CREDENTIALS' file."
    fi
  fi

  # Download models when necessary
  [[ ! $BACKEND == "external" && ! $RUN_MODE == "server" ]] && PULL_MODELS=true
  if [[ $PULL_MODELS == true ]]; then
    # Backend Selector
    case $BACKEND in
      # Local Backend: Ollama
      ollama)
        # Downloading models for ollama
        log_info "Preloading required local models for Ollama server..."
        log_info "Preloading '${CHAT_MODEL}'...\n"
        OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "${CHAT_MODEL}"
        log_info "Preloading '${VISION_MODEL}'...\n"
        OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "${VISION_MODEL}"
        log ; log_info "Preloading '${OLLAMA_ROUTER}:${quant_upper}'...\n"
        OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "${OLLAMA_ROUTER}:${quant_upper}"
        log ; log_info "Preloading '${OLLAMA_ARCHITECT}:${quant_upper}'...\n"
        OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "${OLLAMA_ARCHITECT}:${quant_upper}"
        log ; log_info "Preloading '${OLLAMA_CODER}:${quant_upper}'...\n"
        OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "${OLLAMA_CODER}:${quant_upper}"
        log ; log_info "Preloading '${OLLAMA_JUDGE}:${quant_upper}'...\n"
        OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "${OLLAMA_JUDGE}:${quant_upper}"
        log ; log_success "All required local Ollama models preloaded successfully."
      ;;

      # Local Backend: llama.cpp
      llamacpp)
        # Downloading models for llama.cpp
        log_info "Preloading required local models for llama.cpp server..."
        log_info "Preloading '${CHAT_MODEL}'..."
        LLAMA_CACHE="$LLAMACPP_CACHE" \
        llama-cli -hf "${CHAT_MODEL}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${VISION_MODEL}'..."
        LLAMA_CACHE="$LLAMACPP_CACHE" \
        llama-cli -hf "${VISION_MODEL}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMACPP_ROUTER}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMACPP_CACHE" \
        llama-cli -hf "${LLAMACPP_ROUTER}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMACPP_ARCHITECT}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMACPP_CACHE" \
        llama-cli -hf "${LLAMACPP_ARCHITECT}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMACPP_CODER}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMACPP_CACHE" \
        llama-cli -hf "${LLAMACPP_CODER}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMACPP_JUDGE}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMACPP_CACHE" \
        llama-cli -hf "${LLAMACPP_JUDGE}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_debug "Reloading llama.cpp GGUF models cache..."
        curl -sSL "${LLAMACPP_API_SRV}/models?reload=1" &>/dev/null || error "Failed to reload llama.cpp GGUF models cache."
        log ; log_success "All required local llama.cpp models preloaded successfully."
      ;;
    esac
  fi
}

# -----------------------------------------------------------------------------
# Direct Execution Logic
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  parse_cli_flags "$@"
  init_core
  if [[ $RUN_MODE == "server" ]]; then
    serve
  else
    run_one_shot_pipeline
  fi
fi
