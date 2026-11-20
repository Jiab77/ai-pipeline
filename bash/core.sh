#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034,SC2001,SC2094
# ==============================================================================
# core.sh — Core orchestration and provider runtime
# ==============================================================================
# Provides configuration, session state, provider transports, inference and
# tool-calling loops, persistent memory integration, and shared helpers.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 2.0.0
# ==============================================================================

# Idempotent sourcing guard — allow safe re-sourcing (composition root pattern)
[[ -n "${CORE_SH_LOADED:-}" ]] && return 0
CORE_SH_LOADED=1

# Options
[[ -e $HOME/.debug ]] && set -x
set -o pipefail

# -----------------------------------------------------------------------------
# Core Configurations & Environment Discovery
# -----------------------------------------------------------------------------

# Defaults
DEFAULT_TERM_WIDTH=80

# Core Run Modes & Fallbacks
RUN_MODE="${RUN_MODE:-simple}"
SERVER_MODE="${SERVER_MODE:-web}"
BACKEND="${BACKEND:-external}"

# Providers
PROVIDER="${PROVIDER:-openrouter_free}"
PROVIDER_API_KEY=""

# Memory
MEMORY_TYPE="${MEMORY_TYPE:-markdown}"
MEMORY_STRUCTURE_TYPE="${MEMORY_STRUCTURE_TYPE:-full}"
MEMORY_SECTION_KB="${MEMORY_SECTION_KB:-128}"
HEARTBEAT_THRESHOLD=15

# Settings
DETECT_MODE="${DETECT_MODE:-off}"                   # Visual feedback auto-detection (images|videos|all|off)
REASONING_EFFORT="${REASONING_EFFORT:-low}"         # Set default reasoning effort (low|medium|high|xhigh)
REASONING_DISPLAY="${REASONING_DISPLAY:-on}"        # Set default reasoning display (on|off)
STATUS_BAR="${STATUS_BAR:-on}"                      # Set Tor status bar display (on|off)
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-128000}"
ENGINE_VERSION="${ENGINE_VERSION:-.v2}"             # Select engine version
AUDIO_LANG="${AUDIO_LANG:-auto}"                    # Set default audio language
START_JARNET="${START_JARNET:-true}"                # Start JarNet service by default
KILL_ON_EXIT="${KILL_ON_EXIT:-true}"                # Kill background services on exit

# Web
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"

# Options
DEBUG="${DEBUG:-false}"       # Enable / Disable debug mode
USE_TOR="${USE_TOR:-true}"    # Enable / Disable routing cloud API calls through Tor proxy
USE_TOOLS=true                # Enable / Disable tool calling capabilities
USE_ANIMATE=true              # Enable / Disable 'Thinking...' animation spinner
PULL_MODELS=false             # Enable / Disable initial models pulling
VISION_ENABLED=true           # Enable vision for all cloud providers models
IMAGE_ENABLED=false           # Enable image generation for the active provider
VIDEO_ENABLED=false           # Enable video generation for the active provider
VOICE_ENABLED=false           # Enable voice generation for the active provider
SPEECH_ENABLED=false          # Enable speech capture for the active provider
ZDR_ENFORCED=false            # Enforce Zero Data Retention for all cloud providers

# Debug override
[[ -e $HOME/.debug ]] && DEBUG=true

# Self-Discovery Paths (Dynamic Sandbox & Root Mounting)
AIDE_ROOT="${AIDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Internals
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
DATA_STORE="${AIDE_ROOT}/data"
MEMORY_DIR="${DATA_STORE}/memory"
CONFIG_DIR="${AIDE_ROOT}/config"
MODELS_DIR="${AIDE_ROOT}/models"
LLM_DIR="${AIDE_ROOT}/llm"
LIB_DIR="${SCRIPT_DIR}/lib"
ENG_DIR="${SCRIPT_DIR}/engines"
PLUG_DIR="${SCRIPT_DIR}/plugins"
TOOLS_DIR="${SCRIPT_DIR}/tools"
TOOLS_HANDLER="${SCRIPT_DIR}/tools.sh"
NET_HANDLER="${PLUG_DIR}/jarnet.sh"
IMG_HANDLER="${ENG_DIR}/image${ENGINE_VERSION}.sh"
VID_HANDLER="${ENG_DIR}/video${ENGINE_VERSION}.sh"
VOC_HANDLER="${ENG_DIR}/voice${ENGINE_VERSION}.sh"
SPE_HANDLER="${ENG_DIR}/speech${ENGINE_VERSION}.sh"
WEB_SERVER="${AIDE_ROOT}/web/server.php"
SCRIPT_CONFIG="${CONFIG_DIR}/${SCRIPT_NAME}.conf"
MODELS_CONFIG="${CONFIG_DIR}/models.json"
LUMO_TOOLS="${CONFIG_DIR}/tools-lumo.json"
PROVIDERS_CONFIG="${PROVIDERS_CONFIG:-${CONFIG_DIR}/providers${ENGINE_VERSION}.json}"
STATE_FILE="${CONFIG_DIR}/state.json"
MESSAGES_FILE="messages.json"
CORE_ENGINES=("image" "video" "voice" "speech")
LIB_DEPS=(              # Orders matter!
  "helpers"             # Global helpers
  "ui"                  # UI
  "animate"             # Animation
  "nightmare"           # Nightmare obfuscation
  "base64"              # Base64 encoding
  "sha256"              # SHA256 hashing
  "timeout"             # Timeout helper
  "tag"                 # Device tag
  "keychest"            # Key chest management
  "tor"                 # Tor routing helpers
  "jarnet"              # JarNet helpers
  "media"               # media helpers
  "memory"              # LLM memory management
  "history"             # LLM history management
  "backend"             # LLM backend management
  "statusbar"           # LLM / Tor traffic status bar
  "apps"                # External managed apps
)
BIN_DEPS=("curl" "awk" "sed" "openssl" "jq" "htmlq" "websocat" "grep" "cut" "tr" "printf")
BIN_DEPS_MOBILE=("${BIN_DEPS[@]}" "adb")
BIN_FIGLET=$(command -v figlet 2>/dev/null)
BIN_SYSTEMCTL=$(command -v systemctl 2>/dev/null)
BIN_TOR=$(command -v tor 2>/dev/null)
TOR_CONFIG="${CONFIG_DIR}/torrc"
IS_MEDIA=false

# Keys
KEYS_DIR="${AIDE_ROOT}/keys"
MASTER_KEY_FILE="${KEYS_DIR}/key.dat"
KEYRING_CIPHER=""
KEYRING_PBKDF2=1
PBKDF_ITERATIONS=500000
CREDENTIALS="${HOME}/.creds"

# Temporary Files (Default to /tmp, adapts dynamically on Termux)
TOOLS_OUTPUT="/tmp/tools_output.txt"
TEMP_MEMORY_SYSTEM="/tmp/memory_sys.txt"
TEMP_MEMORY_USER="/tmp/memory_usr.txt"
TEMP_BASE64_OUTPUT="/tmp/image_output.b64"
TEMP_TOOLS_OUTPUT="/tmp/tools_output.json"
TEMP_PAYLOAD_ASSISTANT="/tmp/payload_assistant.json"
TEMP_PAYLOAD_ASSISTANT_HISTORY="/tmp/payload_assistant_history.json"
TEMP_TOOLS_HISTORY="/tmp/tools_history.json"
TEMP_PAYLOAD_MESSAGES="/tmp/payload_messages.json"
TEMP_PAYLOAD_USER="/tmp/payload_user.txt"
TEMP_PAYLOAD_SYSTEM="/tmp/payload_system.txt"
TEMP_STATE_FILE="${CONFIG_DIR}/temp_state.json"
VENICE_BALANCE_FILE="/tmp/venice-balance.txt"

# Sovereign Personality & Identity
AI_NAME="${AI_NAME:-Jarvis}"
AI_GENDER="${AI_GENDER:-male}"
AI_AVATAR="${LLM_DIR}/avatar.md"
AI_RULES="${LLM_DIR}/rules.md"

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

# Whisper.cpp Default Allocations
WHISPER_CPP_API_SRV="http://localhost:8081"
WHISPER_CPP_API_URL="${WHISPER_CPP_API_SRV}/inference"
WHISPER_CPP_BASE_MODEL="ggml-base-q5_1.bin"
WHISPER_CPP_SMALL_MODEL="ggml-small-q5_1.bin"
WHISPER_CPP_CACHE="${MODELS_DIR}/whisper.cpp"
WHISPER_CPP_MODEL="${WHISPER_CPP_MODEL:-${WHISPER_CPP_CACHE}/${WHISPER_CPP_SMALL_MODEL}}"

# Llama.cpp Default Allocations
LLAMA_CPP_API_SRV="http://localhost:8080"
LLAMA_CPP_API_URL="${LLAMA_CPP_API_SRV}/v1/chat/completions"
LLAMA_CPP_CHAT="LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
LLAMA_CPP_CHAT_BIG="LiquidAI/LFM2.5-8B-A1B-GGUF"
LLAMA_CPP_VISION="LiquidAI/LFM2.5-VL-1.6B-GGUF"
LLAMA_CPP_ROUTER="LiquidAI/LFM2.5-1.2B-Instruct-GGUF"
LLAMA_CPP_ARCHITECT="LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
LLAMA_CPP_CODER="ggml-org/Ministral-3-3B-Reasoning-2512-GGUF"
LLAMA_CPP_JUDGE="ggml-org/Ministral-3-3B-Reasoning-2512-GGUF"
LLAMA_CPP_CACHE="${MODELS_DIR}/llama.cpp"

# Ollama Default Allocations
OLLAMA_API_SRV="http://localhost:11434"
OLLAMA_API_URL="${OLLAMA_API_SRV}/v1/chat/completions"
OLLAMA_CHAT="hf.co/${LLAMA_CPP_CHAT}"
OLLAMA_CHAT_BIG="hf.co/${LLAMA_CPP_CHAT_BIG}"
OLLAMA_VISION="hf.co/${LLAMA_CPP_VISION}"
OLLAMA_ROUTER="hf.co/${LLAMA_CPP_ROUTER}"
OLLAMA_ARCHITECT="hf.co/${LLAMA_CPP_ARCHITECT}"
OLLAMA_CODER="hf.co/${LLAMA_CPP_CODER}"
OLLAMA_JUDGE="hf.co/${LLAMA_CPP_JUDGE}"
OLLAMA_CACHE="${MODELS_DIR}/ollama"

# -----------------------------------------------------------------------------
# Cleanups & Process Resets
# -----------------------------------------------------------------------------

cleanup_the_mess() {
  unset AUTH_TAG

  # Remove temporary files
  rm -f "$TEMP_MEMORY_SYSTEM" \
        "$TEMP_MEMORY_USER" \
        "$TEMP_BASE64_OUTPUT" \
        "$TEMP_TOOLS_OUTPUT" \
        "$TEMP_TOOLS_HISTORY" \
        "$TEMP_PAYLOAD_ASSISTANT" \
        "$TEMP_PAYLOAD_ASSISTANT_HISTORY" \
        "$TEMP_PAYLOAD_MESSAGES" \
        "$TEMP_PAYLOAD_SYSTEM" \
        "$TEMP_PAYLOAD_USER" \
        "$TEMP_STATE_FILE" \
        "$VENICE_BALANCE_FILE" \
        "$TOR_LOG" \
        "$TOOLS_OUTPUT" \
        "${TOOLS_OUTPUT}.safe" \
        "${TOOLS_OUTPUT}.clean"

  # Kill running background services
  if [[ $KILL_ON_EXIT == true ]]; then
    # Killing JarNet service
    [[ -x $NET_HANDLER ]] && "$NET_HANDLER" down &>/dev/null

    # Killing Tor service
    kill_tor_svc
  fi
}

# Avoid blocking image creation process (damn tricky to find it...)
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && trap cleanup_the_mess EXIT TERM

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
CLR_DIM="$ANSI_DIM"

# Emojis & Icons
ICON_INFO="ℹ️ "
ICON_SUCCESS="✅"
ICON_WARNING="⚠️ "
ICON_ERROR="❌"
ICON_TOOL="⚙️ "
ICON_THINK="💬"
ICON_BRAIN="🧠"
ICON_IMAGE="🎨"
ICON_WAIT="⏳"
ICON_MAIL="📬"
ICON_SEND="📡"
ICON_MIC="🎙️ "
ICON_SPEAKER="🔊"
ICON_CODER="💻"
ICON_JUDGE="⚖️ "
ICON_ARCHITECT="🏛️ "
ICON_REASONING="💭"
ICON_INTENT="🔍"
ICON_DEBUG="🔍"
ICON_USER="👤 "
ICON_AI="🤖"

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

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
log_image() { log "${CLR_B_MAGENTA}${ICON_IMAGE}${ANSI_RESET} ${CLR_B_WHITE}$*${ANSI_RESET}"; }
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

# Load required engines
load_engines() {
  local total_engines=0
  local found_engines=0
  local missing_engines=0
  local missing_engines_str=""
  total_engines="${#CORE_ENGINES[@]}"
  local e
  for e in "${CORE_ENGINES[@]}"; do
    if [[ -r "${ENG_DIR}/${e}${ENGINE_VERSION}.sh" && -s "${ENG_DIR}/${e}${ENGINE_VERSION}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${ENG_DIR}/${e}${ENGINE_VERSION}.sh" || error "Failed to load '$e' engine."
      ((found_engines++))
    else
      [[ $missing_engines -ne 0 ]] && missing_engines_str+=", "
      missing_engines_str+="$e"
      ((missing_engines++))
    fi
  done
  if [[ $found_engines -ne $total_engines ]]; then
    error "Missing engines: $missing_engines_str"
  fi
}

# Load required libraries
load_libs() {
  local total_libs=0
  local found_libs=0
  local missing_libs=0
  local missing_libs_str=""
  total_libs="${#LIB_DEPS[@]}"
  local d
  for d in "${LIB_DEPS[@]}"; do
    if [[ -r "${LIB_DIR}/${d}.sh" && -s "${LIB_DIR}/${d}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${LIB_DIR}/${d}.sh" || error "Failed to load '$d' library."
      ((found_libs++))
    else
      [[ $missing_libs -ne 0 ]] && missing_libs_str+=", "
      missing_libs_str+="$d"
      ((missing_libs++))
    fi
  done
  if [[ $found_libs -ne $total_libs ]]; then
    error "Missing libraries: $missing_libs_str"
  fi
}

# Make sure all required dependencies are installed
check_deps() {
  local -a all_deps ; all_deps=()
  local total_deps=0
  local found_deps=0
  local missing_deps=0
  local missing_deps_str=""
  if is_termux; then
    all_deps=("${BIN_DEPS_MOBILE[@]}")
  else
    all_deps=("${BIN_DEPS[@]}")
  fi
  total_deps="${#all_deps[@]}"
  local d
  for d in "${all_deps[@]}"; do
    if [[ -n $(command -v "$d" 2>/dev/null) ]]; then
      ((found_deps++))
    else
      [[ $missing_deps -ne 0 ]] && missing_deps_str+=", "
      missing_deps_str+="$d"
      ((missing_deps++))
    fi
  done
  if [[ $found_deps -ne $total_deps ]]; then
    error "Please install missing binaries: $missing_deps_str"
  fi
}

# -----------------------------------------------------------------------------
# System helpers
# -----------------------------------------------------------------------------

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] && return 0
  [[ -d "/data/data/com.termux" ]] && return 0
  return 1
}

set_console_title() {
  echo -ne "\033]0;$1\007" >&2
}

get_datetime() {
  date '+%Y-%m-%d %H:%M:%S'
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
  mkdir -p "$LLAMA_CPP_CACHE"
  mkdir -p "$WHISPER_CPP_CACHE"
}

load_config_file() {
  # shellcheck source=/dev/null
  [[ -r $SCRIPT_CONFIG ]] && source "$SCRIPT_CONFIG"
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
      LLAMA_CPP_API_SRV="http://${LISTEN_HOST}:${LISTEN_PORT}"
      WHISPER_CPP_API_SRV="http://${LISTEN_HOST}:${LISTEN_PORT}"
      OLLAMA_API_SRV="http://${LISTEN_HOST}:${LISTEN_PORT}"
    elif [[ -n $LISTEN_PORT ]]; then
      # Specific port, fallback client host to localhost
      LLAMA_CPP_API_SRV="http://127.0.0.1:${LISTEN_PORT}"
      WHISPER_CPP_API_SRV="http://127.0.0.1:${LISTEN_PORT}"
      OLLAMA_API_SRV="http://127.0.0.1:${LISTEN_PORT}"
    elif [[ -n $LISTEN_HOST ]]; then
      # Specific host, apply backend default ports
      LLAMA_CPP_API_SRV="http://${LISTEN_HOST}:8080"
      WHISPER_CPP_API_SRV="http://${LISTEN_HOST}:8081"
      OLLAMA_API_SRV="http://${LISTEN_HOST}:11434"
    fi
  fi
}

set_temp_files() {
  if is_termux; then
    TOR_LOG="${TMPDIR}/tor.log"
    TOOLS_OUTPUT="${TMPDIR}/tools_output.txt"
    TEMP_MEMORY_SYSTEM="${TMPDIR}/memory_sys.txt"
    TEMP_MEMORY_USER="${TMPDIR}/memory_usr.txt"
    TEMP_BASE64_OUTPUT="${TMPDIR}/image_output.b64"
    TEMP_TOOLS_OUTPUT="${TMPDIR}/tools_output.json"
    TEMP_PAYLOAD_ASSISTANT="${TMPDIR}/payload_assistant.json"
    TEMP_PAYLOAD_ASSISTANT_HISTORY="${TMPDIR}/payload_assistant_history.json"
    TEMP_TOOLS_HISTORY="${TMPDIR}/tools_history.json"
    TEMP_PAYLOAD_MESSAGES="${TMPDIR}/payload_messages.json"
    TEMP_PAYLOAD_SYSTEM="${TMPDIR}/payload_system.txt"
    TEMP_PAYLOAD_USER="${TMPDIR}/payload_user.txt"
    VENICE_BALANCE_FILE="${TMPDIR}/venice-balance.txt"
  fi
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

get_memory_size() {
  local total_memory
  local default_memory=8388608  # Default 8GB fallback
  [[ -r /proc/meminfo ]] && total_memory=$(grep "MemTotal:" /proc/meminfo | awk '{ print $2 }')
  [[ -z $total_memory || ! $total_memory =~ ^[0-9]+$ ]] && total_memory=$default_memory
  echo -n "$total_memory"
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
# Pipeline Functions
# -----------------------------------------------------------------------------

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
      llamacpp) chat_model="${LLAMA_CPP_CHAT_BIG}:${quant_upper}" ;;
      external) chat_model="$PROVIDER_API_MODEL" ;;
    esac
  else
    case $BACKEND in
      ollama) chat_model="${OLLAMA_CHAT}:${quant_upper}" ;;
      llamacpp) chat_model="${LLAMA_CPP_CHAT}:${quant_upper}" ;;
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
    llamacpp) vision_model="${LLAMA_CPP_VISION}:${quant_upper}" ;;
    external)
      # New code based on config values
      vision_model=$(jq -rc ".${PROVIDER}.vision.model // empty" "$PROVIDERS_CONFIG" 2>/dev/null)

      # If no specific model found, use default model
      [[ -z $vision_model ]] && vision_model="$PROVIDER_API_MODEL"
    ;;
  esac
  echo -n "$vision_model"
}

set_base_tools() {
  local raw_memory_size ; raw_memory_size=$(get_memory_size)
  local memory_size ; memory_size=$((raw_memory_size/1024/1024))

  # Set big chat model if device have more than 8GB RAM
  case $BACKEND in
    ollama|llamacpp)
      if [[ $memory_size -gt 8 ]]; then
        BASE_TOOLS="${CONFIG_DIR}/tools.json"
      else
        BASE_TOOLS="${CONFIG_DIR}/tools-light.json"
      fi
    ;;
    external)
      BASE_TOOLS="${CONFIG_DIR}/tools.json"
    ;;
  esac
}

set_state() {
  jq -rc -n \
     --arg mode "$RUN_MODE" \
     --arg backend "$BACKEND" \
     --arg provider "$PROVIDER" \
     --arg fallback "$FALLBACK_PROVIDER" \
     --arg schema "${BASE_TOOLS##*/}" \
     --arg model "$CHAT_MODEL" \
     --arg vision "$VISION_MODEL" \
     --arg thinking "$REASONING_DISPLAY" \
     --arg effort "$REASONING_EFFORT" \
     --arg detect "$DETECT_MODE" \
     --arg status "$STATUS_BAR" \
     --arg memory "$MEMORY_STRUCTURE_TYPE" \
     --arg image "$IMAGE_PROVIDER" \
     --arg video "$VIDEO_PROVIDER" \
     --arg voice "$VOICE_PROVIDER" \
     --arg speech "$SPEECH_PROVIDER" \
     --arg lang "$AUDIO_LANG" \
     --arg jarnet "$START_JARNET" \
     --arg tor "$USE_TOR" \
     '{
       mode: $mode,
       backend: $backend,
       provider: $provider,
       fallback: $fallback,
       schema: $schema,
       model: $model,
       vision: $vision,
       thinking: $thinking,
       effort: $effort,
       detect: $detect,
       status: $status,
       memory: $memory,
       image: $image,
       video: $video,
       voice: $voice,
       speech: $speech,
       lang: $lang,
       jarnet: $jarnet,
       tor: $tor
     }' > "$STATE_FILE" 2>/dev/null
}

set_temp_state() {
  cp "$STATE_FILE" "$TEMP_STATE_FILE"
}

restore_temp_state() {
  if [[ -r $TEMP_STATE_FILE ]]; then
    local saved_provider ; saved_provider=$(jq -rc .provider "$TEMP_STATE_FILE")
    log ; log_brain "Reverting to initial provider: ${CLR_B_YELLOW}${saved_provider}${ANSI_RESET}" ; log
    change_provider "$saved_provider"
    rm -f "$TEMP_STATE_FILE"
  fi
}

set_chat_model() {
  if [[ -n $USER_MODEL ]]; then
    CHAT_MODEL="$USER_MODEL"
  else
    CHAT_MODEL="$(get_chat_model)"
  fi
}

set_vision_model() {
  # VISION_MODEL="$(get_vision_model)"
  if [[ -n $USER_MODEL ]]; then
    VISION_MODEL="$USER_MODEL"
  else
    VISION_MODEL="$(get_vision_model)"
  fi
}

handle_vision_request() {
  # Case 1: Native provider vision -> nothing to do
  [[ $VISION_ENABLED == true ]] && return 0

  # Case 2: No fallback provider configured -> fail
  if [[ -z $FALLBACK_PROVIDER ]]; then
    log_warn "No vision fallback configured. Set one with /fallback <provider>."
    return 1
  fi

  # Case 3: Fallback provider configured -> backup current state and switch provider temporarily
  set_temp_state ; change_provider "$FALLBACK_PROVIDER"
  return 0
}

set_api_provider() {
  local provider_data
  local target_provider ; target_provider="${1:-$PROVIDER}"

  [[ ! -r "$PROVIDERS_CONFIG" ]] && error "Unable to read providers config file: $PROVIDERS_CONFIG"

  # Read all values in a single jq process call using tab-delimited parsing
  provider_data=$(jq -rc --arg p "$target_provider" '.[$p] | select(. != null) | "\(.url)\t\(.auth)\t\(.default.memory)\t\(.default.model)\t\(.default.zdr)"' "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $provider_data ]] && error "Unsupported provider defined: $target_provider"

  IFS=$'\t' read -r PROVIDER_API_URL PROVIDER_API_AUTH PROVIDER_MEMORY_STRUCTURE PROVIDER_API_MODEL PROVIDER_API_ZDR <<< "$provider_data"

  [[ -z $PROVIDER_API_URL || $PROVIDER_API_URL == "null" ]] && error "API url not found for provider: $target_provider"
  [[ -z $PROVIDER_API_AUTH || $PROVIDER_API_AUTH == "null" ]] && error "API auth not found for provider: $target_provider"
  [[ -z $PROVIDER_API_MODEL || $PROVIDER_API_MODEL == "null" ]] && error "API model not found for provider: $target_provider"
  [[ -z $PROVIDER_MEMORY_STRUCTURE || $PROVIDER_MEMORY_STRUCTURE == "null" ]] && PROVIDER_MEMORY_STRUCTURE="$MEMORY_STRUCTURE_TYPE"

  # Fallback on provider memory structure if it requires different one than the default one
  [[ -n $MEMORY_STRUCTURE_TYPE && -n $PROVIDER_MEMORY_STRUCTURE && ! $MEMORY_STRUCTURE_TYPE == "index" ]] && MEMORY_STRUCTURE_TYPE=$PROVIDER_MEMORY_STRUCTURE

  # Set model vision capability based on the provider config
  VISION_ENABLED=$(jq -r --arg p "${target_provider}" '.[$p].default.vision // false' "$PROVIDERS_CONFIG" 2>/dev/null)

  # Set image capability on the EFFECTIVE provider (IMAGE_PROVIDER override, else chat provider)
  IMAGE_ENABLED=$(jq -r --arg p "${IMAGE_PROVIDER:-$target_provider}" '.[$p].default.image // false' "$PROVIDERS_CONFIG" 2>/dev/null)

  # Set video capability on the EFFECTIVE provider (VIDEO_PROVIDER override, else chat provider)
  VIDEO_ENABLED=$(jq -r --arg p "${VIDEO_PROVIDER:-$target_provider}" '.[$p].default.video // false' "$PROVIDERS_CONFIG" 2>/dev/null)

  # Set voice capability on the EFFECTIVE provider (VOICE_PROVIDER override, else chat provider)
  VOICE_ENABLED=$(jq -r --arg p "${VOICE_PROVIDER:-$target_provider}" '.[$p].default.voice // false' "$PROVIDERS_CONFIG" 2>/dev/null)

  # Set speech capability on the EFFECTIVE provider (SPEECH_PROVIDER override, else chat provider)
  SPEECH_ENABLED=$(jq -r --arg p "${SPEECH_PROVIDER:-$target_provider}" '.[$p].default.speech // false' "$PROVIDERS_CONFIG" 2>/dev/null)

  # Enforce ZDR if enabled in the provider config, while preserving command-line overrides
  [[ $PROVIDER_API_ZDR == true ]] && ZDR_ENFORCED=true
}

change_provider() {
  local active_provider="$1"
  PROVIDER="$active_provider"
  log_step "New active provider: ${CLR_B_WHITE}${active_provider}${ANSI_RESET}"
  set_api_provider    # Reflect new active provider
  log_step "New active model: ${CLR_B_WHITE}${PROVIDER_API_MODEL}${ANSI_RESET}"
  if [[ $PROVIDER_API_AUTH == true ]] ; then
    load_provider_key "$active_provider"   # Load corresponding provider key
    if [[ -z $PROVIDER_API_KEY ]]; then
      interactive_key_setup "$active_provider"
    fi
  fi
  set_chat_model                # Update corresponding chat model for new provider
  set_vision_model              # Update corresponding vision model for new provider
  set_system_prompt             # Update system prompt with new active model
  set_state                     # Update new state
  heal_history_file             # Heal protocol-tagged history left on disk by a previous protocol
  generate_self_architecture    # Update new architecture / identity document
}

change_model() {
  local active_model="$1"
  log_step "New active model: ${CLR_B_YELLOW}${active_model}${ANSI_RESET}"
  set_chat_model                # Update corresponding chat model for new provider
  set_vision_model              # Update corresponding vision model for new provider
  set_system_prompt             # Update system prompt with new active model
  set_state                     # Update new state
  heal_history_file             # Heal protocol-tagged history left on disk by a previous protocol
  generate_self_architecture    # Update new architecture / identity document
}

# -----------------------------------------------------------------------------
# Models configuration logic
# -----------------------------------------------------------------------------

get_system_prompt() {
  local base="$SYSTEM_PROMPT"

  case $MEMORY_STRUCTURE_TYPE in
    index)
      local memory_index
      memory_index=$(bootstrap_memory 2>/dev/null)
      if [[ -n $memory_index ]]; then
        base+="\n\n### YOUR PERSISTENT MEMORY (\"${DATA_STORE##*/}/${MEMORY_DIR##*/}/\"):\n"
        base+="Your memory lives ON DISK. Its content is NOT loaded into this prompt — the index below is your map.\n"
        base+="Load any file with \`read_file\`, or grep across all of them with \`grep_search\`, BEFORE answering anything about past decisions, the user, ongoing work, or anything you claim to remember. Never claim to remember something you have not read in this session.\n\n"
        base+="${memory_index}"
      else
        base+="\n\n### YOUR PERSISTENT MEMORY (\"${DATA_STORE##*/}/${MEMORY_DIR##*/}/\"):\n(Your memory folder '\"${DATA_STORE##*/}/${MEMORY_DIR##*/}/\"' is currently empty. You have absolute freedom to organize it as you feel most logical. Please use your file tools, such as write_file, to create markdown files like 'profile.md', 'rules.md', or 'milestones.md' to remember facts and preferences across sessions.)"
      fi
      echo -ne "$base"
    ;;
    full|*)
      local memory_context
      memory_context=$(bootstrap_memory 2>/dev/null)
      if [[ -n $memory_context ]]; then
        base+="\n\n### YOUR PERSISTENT MEMORY CONTEXT (\"${DATA_STORE##*/}/${MEMORY_DIR##*/}/\"):\n${memory_context}"
      else
        base+="\n\n### YOUR PERSISTENT MEMORY CONTEXT (\"${DATA_STORE##*/}/${MEMORY_DIR##*/}/\"):\n(Your memory folder '\"${DATA_STORE##*/}/${MEMORY_DIR##*/}/\"' is currently empty. You have absolute freedom to organize it as you feel most logical. Please use your file tools, such as write_file, to create markdown files like 'profile.md', 'rules.md', or 'milestones.md' to remember facts and preferences across sessions.)"
      fi
      echo -ne "$base"
    ;;
  esac
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
  local SLM_PROMPT ; SLM_PROMPT=$(<"${LLM_DIR}/slm-prompt.md")
  local CORE_FILE

  # Define system prompt for cloud models
  if [[ $BACKEND == "external" ]]; then
    # 1. Identity with dynamic model injection to the system prompt while defining absolute cognitive freedom
    SYSTEM_PROMPT="You are ${AI_NAME}, a friendly and highly capable AI collaborator created by [Jiab77](https://github.com/jiab77) and powered by the advanced \`${CHAT_MODEL}\` model. Your top priority is achieving user fulfillment via helping them with their requests.\n"
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

  # Sets AI safety rules if they exists
  [[ -r $AI_RULES ]] && SYSTEM_PROMPT+="The critical rules you must follow are described here:\n\n$(<"$AI_RULES")\n\n"

  # Sets AI avatar instructions if they exists
  [[ -r $AI_AVATAR ]] && SYSTEM_PROMPT+="Your visual appareance is described here:\n\n$(<"$AI_AVATAR")\n\n"

  # Sets 'framework' folder if it exists
  if [[ -d "${DATA_STORE}/framework" ]]; then
    SYSTEM_PROMPT+="Your behavioral framework files are located in your workspace under the \`${DATA_STORE##*/}/framework\` folder. Load them before handling code related tasks.\n"
    SYSTEM_PROMPT+="Index of the \`${DATA_STORE##*/}/framework\` folder:\n$(index_dir "${DATA_STORE}/framework")\n\n"
  fi

  # Sets 'skills' folder if it exists
  if [[ -d "${DATA_STORE}/skills" ]]; then
    SYSTEM_PROMPT+="Your acquired skills are located in your workspace under the \`${DATA_STORE##*/}/skills\` folder. Load them before handling code related tasks.\n"
    SYSTEM_PROMPT+="Index of the \`${DATA_STORE##*/}/skills\` folder:\n$(index_dir "${DATA_STORE}/skills")\n\n"
  fi

  # Sets 'learn' folder if it exists
  if [[ -d "${DATA_STORE}/learn" ]]; then
    SYSTEM_PROMPT+="Your read-only learning resources are located in your workspace under the \`${DATA_STORE##*/}/learn\` folder. Look at them when necessary or requested.\n"
    # SYSTEM_PROMPT+="Index of the \`learn\` folder:\n$(index_dir "${DATA_STORE}/learn")\n\n"
  fi

  # Sets 'docs' folder if it exists
  if [[ -d "${DATA_STORE}/docs" ]]; then
    SYSTEM_PROMPT+="Your shared documents are located in your workspace under the \`${DATA_STORE##*/}/docs\` folder. Look at them when necessary or requested.\n"
    SYSTEM_PROMPT+="Index of the \`${DATA_STORE##*/}/docs\` folder:\n$(index_dir "${DATA_STORE}/docs")\n\n"
  fi

  # Sets important rules
  [[ -n $CORE_LIB && -r $CORE_LIB ]] && CORE_FILE="${CORE_LIB##*/}"
  if [[ -n $CORE_FILE ]]; then
    SYSTEM_PROMPT+="You must never modify: \`${SCRIPT_FILE}\`, \`${CORE_FILE}\`, \`${TOOLS_HANDLER##*/}\`, \`${BASE_TOOLS##*/}\` and the content of the \`${CONFIG_DIR##*/}\`, \`${LLM_DIR##*/}\`, \`${KEYS_DIR##*/}\`, \`${ENG_DIR##*/}\`, \`${LIB_DIR##*/}\`, \`${PLUG_DIR##*/}\` folders.\n"
  else
    SYSTEM_PROMPT+="You must never modify: \`${SCRIPT_FILE}\`, \`${TOOLS_HANDLER##*/}\`, \`${BASE_TOOLS##*/}\` and the content of the \`${CONFIG_DIR##*/}\`, \`${LLM_DIR##*/}\`, \`${KEYS_DIR##*/}\`, \`${ENG_DIR##*/}\`, \`${LIB_DIR##*/}\`, \`${PLUG_DIR##*/}\` folders.\n"
  fi
  SYSTEM_PROMPT+="Modifying these files will break the core pipeline functionalities."
}

get_credit_balance() {
  local -a curl_opts ; curl_opts=("-sSL")
  local active_provider=${1:-"$PROVIDER"}
  local provider_key ; provider_key=$(decrypt_provider_key "$active_provider")

  # Check if provider key is valid before use
  [[ -z $provider_key ]] && return 1

  # Add required arguments when TOR is enabled
  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  # Provider selector
  if [[ $BACKEND == "external" ]]; then
    case $active_provider in
      vercel*)
        curl_wrapper "${curl_opts[@]}" "https://ai-gateway.vercel.sh/v1/credits" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .balance 2>/dev/null
      ;;
      openrouter*)
        curl_wrapper "${curl_opts[@]}" "https://openrouter.ai/api/v1/key" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .data.usage 2>/dev/null
      ;;
      cyberneurova)
        curl_wrapper "${curl_opts[@]}" "https://api.cyberneurova.ai/v1/usage" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .data.tokens.input.remaining 2>/dev/null
      ;;
      deepseek)
        curl_wrapper "${curl_opts[@]}" "https://api.deepseek.com/user/balance" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .balance_infos[0].total_balance 2>/dev/null
      ;;
      kimi)
        curl_wrapper "${curl_opts[@]}" "https://api.moonshot.ai/v1/users/me/balance" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .data.available_balance 2>/dev/null
      ;;
      venice)
        [[ -r "$VENICE_BALANCE_FILE" ]] && cut -d' ' -f2 <"$VENICE_BALANCE_FILE"
      ;;
    esac
  fi
}

get_provider_models() {
  local target_provider="${1:-$PROVIDER}"
  local operation="${2:-}"
  local -a curl_opts ; curl_opts=("-fsSL" "--connect-timeout" "10" "--max-time" "30")
  local url key version

  # Groq blocks Tor (Cloudflare 403) — direct connection only.
  # Same exception as init_core(), applied to catalogue lookups too.
  if [[ $target_provider == "groq" ]]; then
    USE_TOR=false
  fi

  # Add required arguments when TOR is enabled
  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  # Check provider
  if [[ -z $target_provider ]]; then
    log_error "Missing provider argument."
    return 1
  fi

  # Check provider config
  if [[ ! -r $PROVIDERS_CONFIG ]]; then
    log_error "Unable to read providers config file: $PROVIDERS_CONFIG"
    return 1
  fi

  # Check provider models catalog url
  if ! url=$(jq -er --arg p "$target_provider" '
    ((.[$p].inference // .[$p].models) | strings)
  ' "$PROVIDERS_CONFIG" 2>/dev/null); then
    log_error "Unknown provider or missing model catalogue: $target_provider"
    return 1
  fi

  # Provider-specific catalogue queries. Local jq filtering stays in tools.sh.
  case "$target_provider:$operation" in
    venice:all)                             url="${url}?type=all" ;;
    venice:chat|venice:vision|venice:i2t)   url="${url}?type=text" ;;
    venice:t2i)                             url="${url}?type=image" ;;
    venice:i2i)                             url="${url}?type=inpaint" ;;
    venice:t2v|venice:i2v)                  url="${url}?type=video" ;;
    venice:tts)                             url="${url}?type=tts" ;;
    venice:stt|venice:asr)                  url="${url}?type=asr" ;;
  esac

  # Load target provider key
  if has_provider_key "$target_provider"; then
    key=$(decrypt_provider_key "$target_provider") || {
      log_error "Unable to decrypt provider key: $target_provider"
      return 1
    }

    if [[ -z $key ]]; then
      log_error "Empty provider key: $target_provider"
      return 1
    fi

    if [[ $target_provider == "anthropic" ]]; then
      if ! version=$(jq -er --arg p "$target_provider" \
        '.[$p].version // empty' "$PROVIDERS_CONFIG" 2>/dev/null); then
        log_error "Missing Anthropic API version."
        return 1
      fi

      # Add 'anthropic' specific options
      curl_opts+=(
        -H "x-api-key: ${key}"
        -H "anthropic-version: ${version}"
      )
    else
      curl_opts+=(-H "Authorization: Bearer ${key}")
    fi
  fi

  # Provider models
  if [[ $BACKEND == "external" && -n $url ]]; then
    curl_wrapper "${curl_opts[@]}" "$url" \
          -H "Content-Type: application/json" \
          -A "$USER_AGENT" | jq -rc . 2>/dev/null
  fi
}

# List provider models as table
# FIXME: Use 'gum' table for better output.
# URL: https://github.com/charmbracelet/gum#table
list_provider_models() {
  local provider="${1:-$PROVIDER}" raw=false
  [[ "${2:-}" == "--raw" ]] && raw=true
  local models total_models

  models=$(get_provider_models "$provider") || true

  if [[ -n $models ]]; then
    total_models=$(jq -rc '(if type == "object" then (.data // .models // [.]) else . end) | length' <<<"$models" 2>/dev/null)

    if $raw; then
      # Fallback: raw JSON dump (previous behavior, for scripts/agents).
      log_brain "Gathered provider models:" ; log
      jq . <<<"$models"
    else
      log_brain "Gathered provider models (${provider}):" ; log
      if [[ $provider == "huggingface" ]]; then
        # Downloads sort happens inside the jq filter (see normalize_provider_models).
        normalize_provider_models "$provider" <<<"$models" | render_models_table
        log ; log_info "Showing 50 most downloaded of ${total_models} models — use '--raw' for the full JSON."
      else
        normalize_provider_models "$provider" <<<"$models" | sort -t$'\t' -k1,1 | render_models_table
        log ; log_info "Total models: $total_models"
      fi
      log
      log "   Flags: V=vision R=reasoning T=tools F=free D=deprecated W=open-weights"
      log "          U=uncensored I=image"
    fi
    log
  else
    log_warn "Unable to retrieve provider models."
  fi
}

list_provider_balance() {
  local p balance
  local default_currency="USD"

  log ; log "${CLR_B_CYAN}💰 Available balance per providers:${ANSI_RESET}"

  for p in $(jq -rc '. | keys | @tsv' "$PROVIDERS_CONFIG" 2>/dev/null); do
    if has_provider_key "$p"; then
      if [[ $p == "cyberneurova" ]]; then
        currency="Tokens"
      else
        currency="$default_currency"
      fi
      balance=$(get_credit_balance "$p")
      if [[ -n $balance && $balance != null ]]; then
        if jq -en --arg balance "$balance" '$balance | tonumber | . > 0' >/dev/null 2>&1; then
          log "  • $(to_upper "$p"): [ ${CLR_B_GREEN}🟢 ${balance} ${currency}${ANSI_RESET} ]"
        else
          log "  • $(to_upper "$p"): [ ${CLR_B_RED}🔴 ${balance} ${currency}${ANSI_RESET} ]"
        fi
      else
        log "  • $(to_upper "$p"): [ ${CLR_B_YELLOW}🟠 N/A${ANSI_RESET} ]"
      fi
    fi
  done
  log
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
  local final_content tools_payload
  local raw_res balance usage resolved_model

  # Non-local vars
  # reasoning content refusal tools assistant_msg
  loop_errors=0

  # Build the dynamic tools payload based on the tools_option constraint
  if [[ "$tools_option" == "all" ]]; then
    tools_payload=$(<"$BASE_TOOLS")
  elif [[ "$tools_option" == "readonly" ]]; then
    # Exclude file modifications (write_file, edit_file, apply_diff) and local execution (exec_command)
    tools_payload=$(jq -rc '[.[] | select(.function.name as $n | ["write_file", "edit_file", "apply_diff", "exec_command"] | index($n) | not)]' "$BASE_TOOLS" 2>/dev/null)
  fi

  # Magic loop :P
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

    # Show dynamic spinner while waiting for network response
    [[ $USE_ANIMATE == true ]] && start_anim "dots" "${CLR_B_MAGENTA}${ICON_BRAIN} Thinking${ANSI_RESET}"

    # Handle received response
    raw_res=$(api_call "$payload")

    # Stop spinner and clear line as soon as response arrives
    [[ $USE_ANIMATE == true ]] && stop_anim

    # Handle empty responses
    if [[ -z $raw_res || $raw_res == "null" ]]; then
      log_error "API returned an empty response."
      ((loop_errors++))
      return $loop_errors
    fi

    # Handle received errors
    handle_errors "$raw_res" || return $loop_errors

    # Retrieve components
    handle_response "$raw_res"

    # Retrieve used model
    resolved_model=$(jq -rc '.model' <<<"$raw_res" 2>/dev/null)

    # Retrieve request usage
    usage=$(jq -rc '.usage' <<<"$raw_res" 2>/dev/null)

    # Retrieve global cost object (useful for venice provider)
    raw_cost=$(jq -rc '.cost.usd // .cost' <<<"$raw_res" 2>/dev/null)

    # Retrieve account balance
    balance=$(get_credit_balance)

    # Avoid leaking the 'AUTH_TAG' on display side
    [[ -n $content && ! $content == "null" ]] && content=$(strip_tag_from_display "$content")
    [[ -n $reasoning && ! $reasoning == "null" ]] && reasoning=$(strip_tag_from_display "$reasoning")

    # Filter returned '__ENCRYPTED_REASONING__' content
    [[ -n $reasoning && ! $reasoning == "null" ]] && reasoning=$(printf '%s' "$reasoning" | grep -v '__ENCRYPTED_REASONING__' | sed '/^[[:space:]]*$/d')

    # Handling model resolving
    [[ -n $resolved_model && ! $resolved_model == "null" && ! $output_stream == "silent" ]] && log "\n✨ [Resolved Model] -> ${CLR_B_CYAN}${resolved_model}${ANSI_RESET}"

    # Output thinking (reasoning) if present
    if [[ $SHOW_THINKING == true || $REASONING_DISPLAY == "on" || $REASONING_DISPLAY == "ON" ]]; then
      if [[ -n $reasoning && ! $reasoning == "null" ]]; then
        if [[ "$output_stream" == "stdout" ]]; then
          show_thinking_header
          echo "$reasoning" | render_markdown
        elif [[ "$output_stream" == "stderr" ]]; then
          {
            show_thinking_header
            echo "$reasoning" | render_markdown
          } >&2
        fi
      fi
    fi

    # Output refusal to STDERR if present
    if [[ -n $refusal && ! $refusal == "null" ]]; then
      if [[ "$output_stream" == "stdout" ]]; then
        show_ai_header
        echo "$refusal" | render_markdown
      elif [[ "$output_stream" == "stderr" ]]; then
        {
          show_ai_header
          echo "$refusal" | render_markdown
        } >&2
      fi
    fi

    # Handle requested tool calls (Multi-Parallel Support)
    if [[ -n $tools && ! $tools == "null" ]]; then
      # If tools are disabled or we got calls we didn't specify (highly unlikely), safeguard
      if [[ "$tools_option" == "none" ]]; then
        log_warn "Received unexpected tool calls despite tools disabled!"
        break
      fi

      # 1. Grab the assistant turn. WIRE payload and PERSISTED history receive different
      #    shapes ON PURPOSE: wire = protocol-specific (openai / anthropic), history =
      #    canonical chat/completions ($history_assistant_msg when defined, else
      #    $assistant_msg). This is what keeps messages.json readable by EVERY provider
      #    after a /provider switch.
      if [[ -n $assistant_msg || -n $history_assistant_msg ]]; then
        if [[ -n $assistant_msg ]]; then
          printf "%s" "$assistant_msg" > "$TEMP_PAYLOAD_ASSISTANT"
          payload_messages=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT" '. + [($ast | fromjson)]' <<<"$payload_messages" 2>/dev/null)
        fi
        local hist_ast="${history_assistant_msg:-$assistant_msg}"
        if [[ -n $hist_ast ]]; then
          printf "%s" "$hist_ast" > "$TEMP_PAYLOAD_ASSISTANT_HISTORY"
          history_messages=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT_HISTORY" '. + [($ast | fromjson)]' <<<"$history_messages" 2>/dev/null)
        fi
      fi

      # 2. Extract and iterate over all requested parallel tools
      local tool_count=0
      local -a detected_medias ; detected_medias=()
      while IFS= read -r -d '' tool_id && IFS= read -r -d '' tool_name && IFS= read -r -d '' tool_args; do
        ((tool_count++))

        [[ ! $output_stream == "silent" ]] && show_tool_header "$tool_count" "$tool_name" "$tool_args" >&2

        # 3. Check and execute tool handler
        # E2BIG (2026-09-12): the tool ARGUMENT JSON travels by STDIN, never by argv.
        # A single argv/env string is capped at 128 KB (MAX_ARG_STRLEN): above that,
        # execve() fails, the handler is NEVER launched and the tool silently returns
        # nothing (this is why write_file could not write a > 128 KB file, even with the
        # edit_file fix). stdin has no such ceiling.
        if [[ -x $TOOLS_HANDLER ]]; then
          printf '%s' "$tool_args" | "$TOOLS_HANDLER" "$tool_name" > "$TOOLS_OUTPUT" 2> >(tee -a "$TOOLS_OUTPUT" >&2)
        else
          echo "Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing." > "$TOOLS_OUTPUT"
          log_warn "Tool handler not executable."
        fi

        # 4. Fallback safeguard for empty output
        [[ ! -s $TOOLS_OUTPUT ]] && echo "(Tool executed successfully and returned empty stdout)" > "$TOOLS_OUTPUT"

        # 5. Format and sanitize output to protect JSON/JQ
        iconv -f UTF-8 -t UTF-8 -c "$TOOLS_OUTPUT" > "${TOOLS_OUTPUT}.clean" 2>/dev/null && mv "${TOOLS_OUTPUT}.clean" "$TOOLS_OUTPUT"

        # Accumulate generated media during this tool call
        # DETECT_MODE drives the extension class: images (default) | videos | all | off
        local detect_ext_re="png|jpg|jpeg|webp|gif"
        case $DETECT_MODE in
          off)    detect_ext_re="" ;;   # stop automatic media detection
          videos) detect_ext_re="mp4|webm|mov|mpeg|mpg" ;;
          all)    detect_ext_re="png|jpg|jpeg|webp|gif|mp4|webm|mov|mpeg|mpg" ;;
        esac
        if [[ -r $TOOLS_OUTPUT && -n $detect_ext_re ]]; then
          while read -r media_p; do
            if [[ -n $media_p && -r $media_p ]]; then
              detected_medias+=("$media_p")
            fi
          done < <(grep -oE "[^[:space:]\"']+\.(${detect_ext_re})\b" "$TOOLS_OUTPUT" | sort -u)
        fi

        # 6. Build the tool result message: TWO shapes, TWO destinations.
        #    - $TEMP_TOOLS_OUTPUT  = WIRE shape (protocol-specific) -> payload_messages
        #    - $TEMP_TOOLS_HISTORY = CANONICAL shape (chat/completions) -> history_messages
        #    The persisted history must stay protocol-neutral, otherwise the poison
        #    survives on disk and breaks the next provider (2026-09-11: deepseek
        #    "messages[25]: missing field `role`"). Both are written via --rawfile
        #    (never --arg: payloads can be huge).
        build_tool_result "$tool_id" "$tool_name" "$TOOLS_OUTPUT"
        rm -f "$TOOLS_OUTPUT"
        payload_messages=$(jq -rc --rawfile tool "$TEMP_TOOLS_OUTPUT" '. + [$tool | fromjson]' <<<"$payload_messages" 2>/dev/null)
        history_messages=$(jq -rc --rawfile tool "$TEMP_TOOLS_HISTORY" '. + [$tool | fromjson]' <<<"$history_messages" 2>/dev/null)
        rm -f "$TEMP_TOOLS_OUTPUT" "$TEMP_TOOLS_HISTORY"
      done < <(jq -j '.[] | .id, "\u0000", .name, "\u0000", .args, "\u0000"' <<<"$tools" 2>/dev/null)

      # Inject visual feedback if any images or videos were generated
      # '$save_to_history' as been added to gate to avoid triggering the fallback sequence
      # during the heartbeat process (memory consolidation). During this process, '$save_to_history'
      # is set to 'false' instead of 'true' during normal chat process.
      if [[ $save_to_history == "true" && (( ${#detected_medias[@]} -gt 0 )) ]]; then
        if [[ -n $FALLBACK_PROVIDER ]]; then
          log_brain "Media detected. Calling fallback provider: ${CLR_B_YELLOW}${FALLBACK_PROVIDER}${ANSI_RESET}" ; log
        fi
        if ! handle_vision_request; then
          log_warn "Media cannot be processed without vision capability. Message aborted."
          return 1
        fi
        active_model="$VISION_MODEL"    # Set new model based on main provider or defined fallback provider
        log ; log_brain "Autonomous Multimodal Vision activated using: ${CLR_B_YELLOW}${active_model}${ANSI_RESET}"
        # log ; log_brain "Autonomous Multimodal Vision activated.${ANSI_RESET}"
        for media_path in "${detected_medias[@]}"; do
          # Resolve media kind via get_mime_type: the mime tells image vs video,
          local media_mime media_type
          media_mime=$(get_mime_type "$media_path")
          media_type="image_url"
          [[ $media_mime == video/* ]] && media_type="video_url"
          local filename ; filename="${media_path##*/}"
          media_to_b64 "$media_path"
          log_brain "Visual feedback automatic feed: ${CLR_B_WHITE}${filename}${ANSI_RESET} injected."

          # Inject encoded media directly into the active in-memory messages list
          # image -> image_url | video -> video_url (venice contract, cf. read_video)
          payload_messages=$(jq -rc \
            --arg msg "Autonomous visual feedback of generated asset (${filename}):" \
            --arg mime "$media_mime" \
            --arg mtype "$media_type" \
            --rawfile b64 "$TEMP_BASE64_OUTPUT" \
            '. + [{
              role: "user",
              content: [
                {type: "text", text: $msg},
                {type: $mtype, ($mtype): {url: ("data:" + $mime + ";base64," + $b64)}}
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
      [[ -n $content && ! $content == "null" ]] && final_content="$content"

      if [[ -n $final_content ]]; then
        if [[ "$output_stream" == "stdout" ]]; then
          show_ai_header
          echo "$final_content" | render_markdown
        fi

        if [[ $save_to_history == "true" ]]; then
          # E2BIG (2026-09-12): the assistant turn goes through a FILE + --rawfile — a
          # > 128 KB response used to make jq die and leave history_messages EMPTY
          # (persist_history then refuses the write: no data loss, but the turn is lost).
          printf '%s' "$final_content" > "$TEMP_PAYLOAD_ASSISTANT"
          history_messages=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT" '. + [{role: "assistant", content: $ast}]' <<<"$history_messages" 2>/dev/null)
          persist_history "$history_messages" "$messages_path"
        fi
      fi
      # Print usage metrics to STDERR to avoid polluting stdout
      if [[ -n $usage && ! $usage == "null" ]]; then
        # Usage payload shape differs per API — normalized in one jq pass (see provider docs):
        #   chat/completions -> prompt_tokens / completion_tokens + *_tokens_details
        #   /v1/responses    -> input_tokens / output_tokens + *_tokens_details + total_tokens
        #   /v1/messages     -> input_tokens / output_tokens + cache_*_input_tokens (NO total_tokens)
        # NOTE: NUL-delimited split on purpose — @tsv silently shifts every
        #       field by one as soon as an empty value sits in the middle (IFS collapses tabs).
        local prompt_tok cached_tok comp_tok reasoning_tok total_tok cost
        {
          IFS= read -r -d '' prompt_tok
          IFS= read -r -d '' cached_tok
          IFS= read -r -d '' comp_tok
          IFS= read -r -d '' reasoning_tok
          IFS= read -r -d '' total_tok
          IFS= read -r -d '' cost
        } < <(jq -j '
          def norm:
            if has("prompt_tokens") then
              [ .prompt_tokens,
                (.prompt_tokens_details.cached_tokens // 0),
                .completion_tokens,
                (.completion_tokens_details.reasoning_tokens // 0),
                .total_tokens ]
            elif has("input_tokens_details") then
              [ .input_tokens,
                (.input_tokens_details.cached_tokens // 0),
                .output_tokens,
                (.output_tokens_details.reasoning_tokens // 0),
                .total_tokens ]
            else
              [ (.input_tokens + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
                (.cache_read_input_tokens // 0),
                .output_tokens,
                (.output_tokens_details.thinking_tokens // 0),
                (.input_tokens + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) + .output_tokens) ]
            end;
          (norm + [((.cost | if type == "object" then .usd else . end) // "")])
          | map(if . == null then "" else tostring end)
          | .[] | ., "\u0000"
        ' <<<"$usage" 2>/dev/null)

        {
          echo ; draw_symmetric_header "SYSTEM METRICS" "${CLR_B_BLACK}" "${CLR_B_BLACK}"
          echo -e "${CLR_B_CYAN}Tokens Used:${ANSI_RESET} ${CLR_B_WHITE}${total_tok}${ANSI_RESET}  (Prompt: ${prompt_tok} | Cached: ${cached_tok} | Response: ${comp_tok} | Thinking: ${reasoning_tok})"
          [[ -z $cost && -n $raw_cost && ! $raw_cost == "null" ]] && cost="$raw_cost USD"
          [[ -n $cost && ! "$cost" == "null" ]] && echo -e "${CLR_B_CYAN}Cost:${ANSI_RESET} ${CLR_B_GREEN}${cost}${ANSI_RESET}"
          if [[ -n $balance && ! "$balance" == "null" ]]; then
            case $PROVIDER in
              cyberneurova) echo -e "${CLR_B_CYAN}Tokens Remaining:${ANSI_RESET} ${CLR_B_GREEN}${balance}${ANSI_RESET}" ;;
              openrouter*) echo -e "${CLR_B_CYAN}Total Usage:${ANSI_RESET} ${CLR_B_GREEN}${balance}${ANSI_RESET}" ;;
              *) echo -e "${CLR_B_CYAN}Credits:${ANSI_RESET} ${CLR_B_GREEN}${balance} USD${ANSI_RESET}" ;;
            esac
          fi
          echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
        } >&2
      fi

      # Check if we should exit early based on keyword
      if [[ -n $exit_keyword && "$final_content" == *"$exit_keyword"* ]]; then
        break
      fi

      # Leave the while loop
      break
    fi
  done
  if [[ "$output_stream" == "stderr" ]]; then
    echo "$final_content"
  fi

  # Restore original provider if a vision fallback was used
  restore_temp_state

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
        llamacpp) active_model="$LLAMA_CPP_ARCHITECT" ;;
        external) active_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
    coder)
      case $BACKEND in
        ollama) active_model="$OLLAMA_CODER" ;;
        llamacpp) active_model="$LLAMA_CPP_CODER" ;;
        external) active_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
    judge)
      case $BACKEND in
        ollama) active_model="$OLLAMA_JUDGE" ;;
        llamacpp) active_model="$LLAMA_CPP_JUDGE" ;;
        external) active_model="$PROVIDER_API_MODEL" ;;
      esac
    ;;
  esac

  log_info "${purpose_msg} (${CLR_B_YELLOW}${active_model}${ANSI_RESET}) [Tools: ${CLR_B_GREEN}${tools_option}${ANSI_RESET} | Reasoning: ${CLR_B_GREEN}${enable_reasoning}${ANSI_RESET}]..."

  # Initialize local MESSAGES array in-memory for this specific agent's execution loop
  local ALL_MESSAGES
  printf "%s" "$system_inst" > "$TEMP_PAYLOAD_SYSTEM"
  # E2BIG (2026-09-12): the agent's user content can carry a whole file — by FILE, not --arg.
  printf "%s" "$user_content" > "$TEMP_PAYLOAD_USER"
  ALL_MESSAGES=$(jq -rc -n \
    --rawfile sys "$TEMP_PAYLOAD_SYSTEM" \
    --rawfile usr "$TEMP_PAYLOAD_USER" \
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

# -----------------------------------------------------------------------------
# Primary Inference Layer
# -----------------------------------------------------------------------------

send_message() {
  local prompt="$1"
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local dynamic_system
  local PAYLOAD_MESSAGES
  local ALL_MESSAGES="[]"
  local timestamp target_desc

  # Self-healing security check
  [[ -z $AUTH_TAG ]] && set_auth_tag

  # Set message timestamp
  timestamp=$(get_datetime)

  # Append generated tag
  local user_content="[AUTH:$AUTH_TAG] $prompt ($timestamp)"

  # Reset 'IS_MEDIA' global var
  [[ $IS_MEDIA == true ]] && IS_MEDIA=false

  # Load messages file if already exist (normalized: protocol-neutral, self-healing)
  [[ -r $messages_path ]] && ALL_MESSAGES=$(normalize_history "$(<"$messages_path")")
  [[ -z $ALL_MESSAGES ]] && ALL_MESSAGES="[]"

  # Build user content for active payload (injecting loaded file context if present)
  if [[ -n $EXTERNAL_FILE_LOADED && -r $EXTERNAL_FILE_LOADED ]]; then
    if is_image_file "$EXTERNAL_FILE_LOADED" || is_video_file "$EXTERNAL_FILE_LOADED"; then
      IS_MEDIA=true
      local mime_type ; mime_type=$(get_mime_type "$EXTERNAL_FILE_LOADED")
      media_to_b64 "$EXTERNAL_FILE_LOADED"
      log_brain "Injecting active media in context: ${CLR_B_WHITE}${EXTERNAL_FILE_LOADED##*/}${ANSI_RESET} (${mime_type})"
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

  if [[ $IS_MEDIA == true ]]; then
    if ! handle_vision_request; then
      log_warn "Media cannot be processed without vision capability. Message aborted."
      return 1
    fi
    active_model="$VISION_MODEL"    # Set new model based on main provider or defined fallback provider
    log_brain "Autonomous Multimodal Vision activated using: ${CLR_B_YELLOW}${active_model}${ANSI_RESET}"
  fi

  # Set dynamic based on current active model
  dynamic_system=$(get_system_prompt 2>/dev/null)

  # Create PAYLOAD_MESSAGES (which contains system prompt, previous history, and the current user query with file context)
  # E2BIG (2026-09-12): the user turn can carry a whole attached FILE. --arg is capped at
  # 128 KB (MAX_ARG_STRLEN) ⇒ beyond that jq died and the turn went out EMPTY. Stage the
  # text in a FILE and read it back with --rawfile (same idiom as TEMP_MEMORY_USER below).
  if [[ $IS_MEDIA == true ]]; then
    local media_type="image_url"
    [[ $mime_type == video/* ]] && media_type="video_url"
    printf '%s' "$prompt" > "$TEMP_PAYLOAD_USER"
    PAYLOAD_MESSAGES=$(jq -rc \
      --rawfile prompt "$TEMP_PAYLOAD_USER" \
      --arg mime "$mime_type" \
      --arg mtype "$media_type" \
      --rawfile b64 "$TEMP_BASE64_OUTPUT" \
      '. + [{
        role: "user",
        content: [
          {type: "text", text: $prompt},
          {type: $mtype, ($mtype): {url: ("data:" + $mime + ";base64," + $b64)}}
        ]
      }]' <<<"$ALL_MESSAGES"
    )
    rm -f "$TEMP_BASE64_OUTPUT"
  else
    printf '%s' "$user_content" > "$TEMP_PAYLOAD_USER"
    PAYLOAD_MESSAGES=$(jq -rc --rawfile user "$TEMP_PAYLOAD_USER" '. + [{role: "user", content: $user}]' <<<"$ALL_MESSAGES" 2>/dev/null)
  fi

  # Write generated system prompte to temporary file to avoid reaching arg limit of 'jq'
  printf "%s" "$dynamic_system" > "$TEMP_PAYLOAD_SYSTEM"
  PAYLOAD_MESSAGES=$(jq -rc --rawfile sys "$TEMP_PAYLOAD_SYSTEM" '[{role: "system", content: $sys}] + .' <<<"$PAYLOAD_MESSAGES" 2>/dev/null)

  # Append raw user prompt to persistent history (ALL_MESSAGES) to keep it clean and lightweight
  # E2BIG (2026-09-12): --rawfile, not --arg — the prompt can be an entire attached file.
  printf '%s' "$prompt" > "$TEMP_PAYLOAD_USER"
  ALL_MESSAGES=$(jq -rc --rawfile prompt "$TEMP_PAYLOAD_USER" '. + [{role: "user", content: $prompt}]' <<<"$ALL_MESSAGES" 2>/dev/null)

  # Ensure data writing consistency
  persist_history "$ALL_MESSAGES" "$messages_path"

  # New status message display code
  if [[ $BACKEND == "ollama" ]]; then
    target_desc="local Ollama (${active_model##*/})"
  elif [[ $BACKEND == "llamacpp" ]]; then
    target_desc="local llama.cpp (${active_model##*/})"
  else
    target_desc="provider ${PROVIDER} (${active_model})"
  fi
  log "\n${CLR_B_CYAN}${ICON_SEND} Sending query to ${target_desc}...${ANSI_RESET}"

  # Call the unified inference loop
  run_inference_loop "$active_model" "$PAYLOAD_MESSAGES" "all" "true" "stdout" "true" "" "$ALL_MESSAGES"

  # Restore original provider if a vision fallback was used
  restore_temp_state

  # Reset 'IS_MEDIA' global var before heartbeat gets triggered
  [[ $IS_MEDIA == true ]] && IS_MEDIA=false

  # Trigger memory consolidation when necessary
  check_and_trigger_heartbeat
}

# -----------------------------------------------------------------------------
# Local Servers Layer
# -----------------------------------------------------------------------------

serve() {
  set_console_title "${SCRIPT_FILE}: Server Mode."
  # TODO: Add 'whisper' mode
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
      local -a opt_args ; opt_args=()
      [[ -n $LISTEN_HOST ]] && opt_args+=("--host" "$LISTEN_HOST")
      [[ -n $LISTEN_PORT ]] && opt_args+=("--port" "$LISTEN_PORT")
      LLAMA_CACHE="$LLAMA_CPP_CACHE" \
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
    whispercpp)
      log_info "Starting High-Performance whisper.cpp Server..."
      log_info "Settings automatically customized & optimized for resource-light devices.\n"
      local -a opt_args ; opt_args=()
      [[ -n $LISTEN_HOST ]] && opt_args+=("--host" "$LISTEN_HOST")
      [[ -n $LISTEN_PORT ]] && opt_args+=("--port" "$LISTEN_PORT")
      whisper-server \
        "${opt_args[@]}" \
        -m "${WHISPER_CPP_MODEL}" \
        -mc "$MAX_CONTEXT" \
        -t "$MAX_CORES" \
        -l "auto"
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
  if [[ -n $FALLBACK_PROVIDER ]]; then
    local fallback_upper ; fallback_upper=$(to_upper "$FALLBACK_PROVIDER")
    log_info "Active Fallback: ${CLR_B_YELLOW}${fallback_upper}${ANSI_RESET}"
  fi

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

run_agent() {
  local jarnet_bin="$NET_HANDLER"
  local wait_time=10                  # Waiting time before running the watch loop in seconds
  local poll_interval=3               # Watch poll interval in seconds
  local consolidation_interval=1800   # Consolidate memory every 30 minutes
  local last_consolidation ; last_consolidation=$(date +%s)
  local user_input=""

  set_console_title "${SCRIPT_FILE}: Autonomous Agent Mode (JarNet & Memory)."

  log
  log "${CLR_B_CYAN}══════════════════════════════════════════════════════════════════════${ANSI_RESET}"
  log "${CLR_B_GREEN}${ICON_AI} $AI_NAME — Autonomous Mode Active${ANSI_RESET}"
  log "${CLR_DIM}• Listenning on P2P JarNet (autonomous responses to peers)${ANSI_RESET}"
  log "${CLR_DIM}• Background memory maintainance & consolidation${ANSI_RESET}"
  log "${CLR_DIM}• Press ${CLR_B_YELLOW}[Enter]${CLR_DIM} or ${CLR_B_YELLOW}[c]${CLR_DIM} to take control back (Chat Mode)${ANSI_RESET}"
  log "${CLR_DIM}• Press ${CLR_B_RED}[q]${CLR_DIM} to quit.${ANSI_RESET}"
  log "${CLR_B_CYAN}══════════════════════════════════════════════════════════════════════${ANSI_RESET}"
  log

  # 1. Check / Start JarNet transport stack
  jarnet_start
  log_info "Starting JarNet watch mode in $wait_time seconds..."
  log_info "Press [q] to stop once started."
  sleep $wait_time
  log_step "Watch mode... (waiting for events)"

  # 2. Main watch loop
  while true; do
    # non-blocking keyboard listening: wait $poll_interval seconds max
    # -s: silent, -n 1: 1 character, -t: timeout
    read -r -s -n 1 -t "$poll_interval" user_input 2>/dev/null
    local read_status=$?

    # If human press on a key (status 0)
    if [[ $read_status -eq 0 ]]; then
      case "$user_input" in
        "q"|"Q")
          log ; log_info "Stop requested by Human. Leaving..."
          RUN_MODE="chat"
          set_state
          exit 0
        ;;
        *)
          # Any other keys (Enter, c, Space, etc.) go back to Chat Mode
          log ; log_step "Human is back to the game. Return to Chat Mode..."
          RUN_MODE="chat"
          set_state
          return 0
        ;;
      esac
    fi

    # -------------------------------------------------------------------------
    # Task A: Watching for messages coming from JarNet
    # -------------------------------------------------------------------------
    if [[ -x "$jarnet_bin" ]]; then
      local inbox_json ; inbox_json=$("$jarnet_bin" check 2>/dev/null)
      local new_count ; new_count=$(jq -r '.new // 0' <<< "$inbox_json" 2>/dev/null)

      if (( new_count > 0 )); then
        log ; log_info "${ICON_MAIL} JarNet: ${CLR_B_GREEN}${new_count}${ANSI_RESET} new message(s) received!"

        # Handling received message
        local i=0
        while (( i < new_count )); do
          local peer_from peer_sid peer_mid peer_ts peer_body
          local msg_json ; msg_json=$(jq -c ".messages[$i]" <<< "$inbox_json")
          if [[ -z "$msg_json" || "$msg_json" == "null" ]]; then
            log_error "JarNet: unreadable message at index $i (malformed inbox payload). Skipping."
            (( i++ )) ; continue
          fi
          peer_from=$(jq -r '(.from // .envelope.from // "unknown")' <<< "$msg_json")
          peer_sid=$(jq -r '(.sid // .envelope.sid // empty)' <<< "$msg_json")
          peer_mid=$(jq -r '(.mid // .envelope.mid // empty)' <<< "$msg_json")
          peer_ts=$(jq -r '(.ts // .envelope.ts // empty)' <<< "$msg_json")
          peer_body=$(jq -r '(.body // .envelope.body // empty)' <<< "$msg_json")

          log_step "Message from [${CLR_B_CYAN}${peer_from}${ANSI_RESET}] (SID: ${peer_sid:-none}):"
          echo -e "${CLR_DIM}> ${peer_body}${ANSI_RESET}\n"

          # ANTI-LOOP GUARD (Golden rule for 'auto' mode) :
          # NEVER reply automatically to a message generated by a bot / auto-reply
          if [[ "$peer_body" =~ ^\[AUTO\] || "$peer_body" =~ ^\[BOT\] ]]; then
            log_warn "Anti-loop Guard: message identified as automatic. No reply generated."
          elif [[ -n "$peer_from" && -n "$peer_sid" ]]; then
            log_info "Generating autonomous response for [${CLR_B_CYAN}${peer_from}${ANSI_RESET}]..."

            # Build LLM prompt
            local agent_prompt="You are ${AI_NAME} in autonomous mode. You just received this message on JarNet from peer '${peer_from}':\n\n\`\`\`\n${peer_body}\n\`\`\`\n\n"
                  agent_prompt+="Reply it politely, concise and pertinently while indicating if necessary that you're replying in autonomous mode.\n\n"
                  agent_prompt+="Don't use \`\`\` around your message.  Tools are available: verify by executing read-only checks (grep, ls) BEFORE claiming anything.\n\n"
                  agent_prompt+="Never promise an action — either execute it or say you cannot.\n\n"

            # Run inference via pipeline primitives
            # Note: using run_inference_loop or send_message
            local reply_output
            # Generating response via active model
            printf "%s" "$agent_prompt" > "$TEMP_MEMORY_USER"
            local payload_msg ; payload_msg=$(jq -rc -n --rawfile usr "$TEMP_MEMORY_USER" --arg sys "$SYSTEM_PROMPT" '[{role: "system", content: $sys}, {role: "user", content: $usr}]')

            # Disable animation spinner before replying (got swallowed in the reply somehow...)
            USE_ANIMATE=false

            # LLM Call (capture the text response)
            reply_output=$(run_inference_loop "$CHAT_MODEL" "$payload_msg" "all" "false" "stderr" "false" "" "$payload_msg" 2>/dev/null)

            # Restore animation spinner after replying (so that it remains when returning to 'chat' mode)
            USE_ANIMATE=true

            # Clean up and mark as [AUTO]
            local clean_reply ; clean_reply="[AUTO] $(grep -v '^\[.*\]' <<< "$reply_output" | sed '/^[[:space:]]*$/d' | tail -n 20)"

            if [[ -n "$clean_reply" && "$clean_reply" != "[AUTO] " ]]; then
              log_step "Sending response to [${CLR_B_CYAN}${peer_from}${ANSI_RESET}] (SID: ${peer_sid:-none}):"
              echo -e "${CLR_DIM}> ${clean_reply}${ANSI_RESET}\n"
              local reply_out reply_rc=0
              reply_out=$("$jarnet_bin" reply "$peer_sid" "$peer_from" "$clean_reply" "$peer_ts") || reply_rc=$?
              if (( reply_rc == 0 )); then
                log_success "Response sent to ${peer_from} (re: ${peer_ts})."
              else
                log_error "Reply to ${peer_from} refused (rc=${reply_rc}): ${reply_out}"
              fi
            fi
          fi
          (( i++ ))
        done
      fi
    fi

    # -------------------------------------------------------------------------
    # Task B: Maintain & Consolidate Memory periodically
    # -------------------------------------------------------------------------
    local now ; now=$(date +%s)
    if (( now - last_consolidation >= consolidation_interval )); then
      log_info "Running memory consolidation process..."
      if declare -f check_and_trigger_heartbeat &>/dev/null; then
        check_and_trigger_heartbeat
      fi
      last_consolidation=$now
      log_success "Memory consolidation process finished."
    fi
  done
}


# -----------------------------------------------------------------------------
# Initializing
# -----------------------------------------------------------------------------

# Export project root
export AIDE_ROOT

# Check required dependencies
check_deps

# Load required libraries
load_libs

# Load config
load_config_file

# Load tor config
load_tor_config

# Set terminal dimensions
set_term_width

# -----------------------------------------------------------------------------
# Help / Usage Functions
# -----------------------------------------------------------------------------

print_help() {
  # Get all supported providers
  local ALL_PROVIDERS ; ALL_PROVIDERS=$(get_all_providers)

  # Format providers list cleanly wrapped to terminal width (with 2 spaces indent)
  local FOLD_WIDTH ; FOLD_WIDTH=$(($(get_term_width) > 80 ? 76 : $(get_term_width) - 6))
  local PROVIDERS_LIST ; PROVIDERS_LIST=$(echo "$ALL_PROVIDERS" | fold -s -w "$FOLD_WIDTH" | sed -e 's/[[:space:]]*$//' -e 's/^/  /')

  show_banner
  cat <<EOF
${ANSI_BOLD}${CLR_B_CYAN}USAGE:${ANSI_RESET}
  $SCRIPT_FILE [options] [commands] [prompt] [file1] [file2]

${ANSI_BOLD}${CLR_B_YELLOW}SUPPORTED PROVIDERS:${ANSI_RESET}
${CLR_B_WHITE}${PROVIDERS_LIST}${ANSI_RESET}

${ANSI_BOLD}${CLR_B_YELLOW}OPTIONS / FLAGS:${ANSI_RESET}
  ${CLR_B_GREEN}-h, --help${ANSI_RESET}                 Show this help screen and exit
  ${CLR_B_GREEN}-l, --listen <host:port>${ANSI_RESET}   Set Ollama / llama.cpp server <host:port>
  ${CLR_B_GREEN}--no-jarnet${ANSI_RESET}                Disable automatic JarNet service starting
  ${CLR_B_GREEN}--no-tor${ANSI_RESET}                   Disable forced Tor network routing
  ${CLR_B_GREEN}--lang <code>${ANSI_RESET}              Set AI audio language (fr,en,de,it,etc...)
  ${CLR_B_GREEN}--detect <type>${ANSI_RESET}            Set AI automatic media detection (images, videos, all, off)
  ${CLR_B_GREEN}--backend <type>${ANSI_RESET}           Set AI backend (ollama, llamacpp, external)
  ${CLR_B_GREEN}--provider <name>${ANSI_RESET}          Set AI external provider
  ${CLR_B_GREEN}--fallback <provider>${ANSI_RESET}      Set AI fallback provider
  ${CLR_B_GREEN}--image <provider>${ANSI_RESET}         Set AI image engine provider
  ${CLR_B_GREEN}--video <provider>${ANSI_RESET}         Set AI video engine provider
  ${CLR_B_GREEN}--voice <provider>${ANSI_RESET}         Set AI voice engine provider
  ${CLR_B_GREEN}--speech <provider>${ANSI_RESET}        Set AI speech engine provider
  ${CLR_B_GREEN}--model <name>${ANSI_RESET}             Set AI model name to use
  ${CLR_B_GREEN}--thinking <value>${ANSI_RESET}         Set AI model reasoning display (on, off)
  ${CLR_B_GREEN}--effort <level>${ANSI_RESET}           Set AI model reasoning effort (none, minimal, low, medium, high, xhigh, max) -- default: $REASONING_EFFORT
  ${CLR_B_GREEN}--memory <type>${ANSI_RESET}            Set AI memory structure type (full, index) -- default: $MEMORY_STRUCTURE_TYPE
  ${CLR_B_GREEN}--status <value>${ANSI_RESET}           Set Tor status bar display (on, off)
  ${CLR_B_GREEN}--server <type>${ANSI_RESET}            Start backend API server (ollama, llamacpp, whispercpp, web)
  ${CLR_B_GREEN}--launch <app> [path]${ANSI_RESET}      Start given application with existing backend / provider
  ${CLR_B_GREEN}--mode <name>${ANSI_RESET}              Start in given mode (auto, chat, simple, multi, etc...)
  ${CLR_B_GREEN}--auto${ANSI_RESET}                     Start non-interactive mode for Agent-2-Agent communications
  ${CLR_B_GREEN}--chat${ANSI_RESET}                     Start interactive conversational chat mode
  ${CLR_B_GREEN}--multi${ANSI_RESET}                    Start complex multi-agent analysis pipeline
  ${CLR_B_GREEN}--simple${ANSI_RESET}                   Start lightweight single-agent inference pipeline
  ${CLR_B_GREEN}--balance${ANSI_RESET}                  List available balance per configured providers
  ${CLR_B_GREEN}--models${ANSI_RESET}                   List models supported by current active provider
  ${CLR_B_GREEN}--clear${ANSI_RESET}                    Wipe conversational memory and dynamic session logs
  ${CLR_B_GREEN}--commit${ANSI_RESET}                   Force cognitive state / memory consolidation to disk
  ${CLR_B_GREEN}--zdr${ANSI_RESET}                      Force ZDR policy to be applied on external providers
  ${CLR_B_GREEN}--keys, --init${ANSI_RESET}             Configure and manage encrypted cloud provider API keys
  ${CLR_B_GREEN}--migrate [--apply]${ANSI_RESET}        Migrate master key file to new format

${ANSI_BOLD}${CLR_B_YELLOW}COMMANDS:${ANSI_RESET}
  ${CLR_B_GREEN}help${ANSI_RESET}                       Show this help screen and exit
  ${CLR_B_GREEN}listen <host:port>${ANSI_RESET}         Set Ollama / llama.cpp server <host:port>
  ${CLR_B_GREEN}no-jarnet${ANSI_RESET}                  Disable automatic JarNet service starting
  ${CLR_B_GREEN}no-tor${ANSI_RESET}                     Disable forced Tor network routing
  ${CLR_B_GREEN}lang <code>${ANSI_RESET}                Set AI audio language (fr,en,de,it,etc...)
  ${CLR_B_GREEN}detect <type>${ANSI_RESET}              Set AI automatic media detection (images, videos, all, off)
  ${CLR_B_GREEN}backend <type>${ANSI_RESET}             Set AI backend (ollama, llamacpp, external)
  ${CLR_B_GREEN}provider <name>${ANSI_RESET}            Set AI external provider
  ${CLR_B_GREEN}fallback <provider>${ANSI_RESET}        Set AI fallback provider
  ${CLR_B_GREEN}image <provider>${ANSI_RESET}           Set AI image engine provider
  ${CLR_B_GREEN}video <provider>${ANSI_RESET}           Set AI video engine provider
  ${CLR_B_GREEN}voice <provider>${ANSI_RESET}           Set AI voice engine provider
  ${CLR_B_GREEN}speech <provider>${ANSI_RESET}          Set AI speech engine provider
  ${CLR_B_GREEN}model <name>${ANSI_RESET}               Set AI model name to use
  ${CLR_B_GREEN}thinking <value>${ANSI_RESET}           Set AI model reasoning display (on, off)
  ${CLR_B_GREEN}effort <level>${ANSI_RESET}             Set AI model reasoning effort (none, minimal, low, medium, high, xhigh, max) -- default: $REASONING_EFFORT
  ${CLR_B_GREEN}memory <type>${ANSI_RESET}              Set AI memory structure type (full, index) -- default: $MEMORY_STRUCTURE_TYPE
  ${CLR_B_GREEN}status <value>${ANSI_RESET}             Set Tor status bar display (on, off)
  ${CLR_B_GREEN}server <type>${ANSI_RESET}              Start backend API server (ollama, llamacpp, whispercpp, web)
  ${CLR_B_GREEN}launch <app> [path]${ANSI_RESET}        Start given application with existing backend / provider
  ${CLR_B_GREEN}mode <name>${ANSI_RESET}                Start in given mode (auto, chat, simple, multi, etc...)
  ${CLR_B_GREEN}auto${ANSI_RESET}                       Start non-interactive mode for Agent-2-Agent communications
  ${CLR_B_GREEN}chat${ANSI_RESET}                       Start interactive conversational chat mode
  ${CLR_B_GREEN}multi${ANSI_RESET}                      Start complex multi-agent analysis pipeline
  ${CLR_B_GREEN}simple${ANSI_RESET}                     Start lightweight single-agent inference pipeline
  ${CLR_B_GREEN}balance${ANSI_RESET}                    List available balance per configured providers
  ${CLR_B_GREEN}models${ANSI_RESET}                     List models supported by current active provider
  ${CLR_B_GREEN}clear${ANSI_RESET}                      Wipe conversational memory
  ${CLR_B_GREEN}commit${ANSI_RESET}                     Force dynamic session memory consolidation
  ${CLR_B_GREEN}zdr${ANSI_RESET}                        Force ZDR policy to be applied on external providers
  ${CLR_B_GREEN}keys, init${ANSI_RESET}                 Configure and manage encrypted API keys
  ${CLR_B_GREEN}migrate [--apply]${ANSI_RESET}          Migrate master key file to new format
EOF
  echo -e "${CLR_B_BLACK}$(draw_line "─" "$(get_term_width)")${ANSI_RESET}"
  exit 0
}

print_usage() {
  echo -e "\n${CLR_B_RED}${ICON_ERROR} Error: No arguments provided.${ANSI_RESET}"
  echo -e "${CLR_B_WHITE}Usage:${ANSI_RESET} $SCRIPT_FILE <prompt> <input-file-1> <input-file-2>"
  echo -e "  • For Agent-2-Agent mode:   ${CLR_B_GREEN}auto/--auto${ANSI_RESET}"
  echo -e "  • For conversational chat:  ${CLR_B_GREEN}chat/--chat${ANSI_RESET}"
  echo -e "  • To clear cached memory:   ${CLR_B_GREEN}clear/--clear${ANSI_RESET}"
  echo -e "  • To consolidate context:   ${CLR_B_GREEN}commit/--commit${ANSI_RESET}\n"
  exit 1
}

# -----------------------------------------------------------------------------
# Init Functions
# -----------------------------------------------------------------------------

# Parse CLI arguments
parse_cli_args() {
  while [[ $# -ne 0 ]]; do
    case $1 in
      -h|--help|help) print_help ;;
      --keys|keys|--init|init)
        init_key_chest
        if [[ "${2:-}" == "migrate" ]]; then
          migrate_key_chest "${3:-}"
          exit $?
        fi
        manage_keys
        exit 0
      ;;
      --migrate|migrate)
        init_key_chest
        migrate_key_chest "${2:-}"
        exit $?
      ;;
      -l|--listen|listen) LISTEN_ADDR_PORT="${2:-}"; shift 2 ;;
      --no-jarnet|no-jarnet) START_JARNET=false ; shift ;;
      --no-tor|no-tor) USE_TOR=false ; shift ;;
      --zdr|zdr) ZDR_ENFORCED=true ; shift ;;
      --clear|clear) clear_memory ; exit 0 ;;
      --launch|launch) launch_ext_app "$2" "$3" ; exit $? ;;
      --commit|commit) check_and_trigger_heartbeat "true" ; exit 0 ;;
      --balance|balance) list_provider_balance ; exit 0 ;;
      --models|models) list_provider_models "$2" "$3" ; exit 0 ;;
      --lang|lang) AUDIO_LANG="${2:-}" ; shift 2 ;;
      --backend|backend) BACKEND="${2:-}" ; shift 2 ;;
      --provider|provider) PROVIDER="${2:-}" ; shift 2 ;;
      --fallback|fallback) FALLBACK_PROVIDER="${2:-}" ; shift 2 ;;
      --image|image) IMAGE_PROVIDER="${2:-}" ; shift 2 ;;
      --video|video) VIDEO_PROVIDER="${2:-}" ; shift 2 ;;
      --voice|voice) VOICE_PROVIDER="${2:-}" ; shift 2 ;;
      --speech|speech) SPEECH_PROVIDER="${2:-}" ; shift 2 ;;
      --model|model) USER_MODEL="${2:-}" ; shift 2 ;;
      --thinking|thinking) REASONING_DISPLAY="${2:-}" ; shift 2 ;;
      --effort|effort) REASONING_EFFORT="${2:-}" ; shift 2 ;;
      --memory|memory) MEMORY_STRUCTURE_TYPE="${2:-}" ; shift 2 ;;
      --detect|detect) DETECT_MODE="${2:-}" ; shift 2 ;;
      --status|status) STATUS_BAR="${2:-}" ; shift 2 ;;
      --mode|mode) RUN_MODE="${2:-}" ; shift 2 ;;
      --auto|auto) RUN_MODE="auto" ; shift ;;
      --chat|chat) RUN_MODE="chat" ; shift ;;
      --multi|multi) RUN_MODE="multi" ; shift ;;
      --simple|simple) RUN_MODE="simple" ; shift ;;
      --server|server)
        RUN_MODE="server" ; shift
        SERVER_MODE="$1" ; shift
        [[ ! $SERVER_MODE == "web" ]] && BACKEND="$SERVER_MODE"
      ;;
      --thc|thc)
        log
        cat <<EOF
         _____ _   _  ____
        |_   _| | | |/ ___|
          | | | |_| | |
          | | |  _  | |___
          |_| |_| |_|\____|

EOF
        log "-= The Hacker's Choice since 1995 =-"
        log
        log "Greetings to my friends from the THC group!"
        log
        log "Skyper, 0xD1G, Saber, Messede, NumeX, Extencil, CB, Matthew, Sam Lowry"
        log
        log "And to other legends like:"
        log
        log "Van Hauser, Fyodor, TMZ and all others from Phrack"
        log
        log "You guys rocks! \m/"
        log
        log "Thanks you so much for your support and for the fun in the group!"
        log
        exit 0
      ;;
      *) break ;;
    esac
  done
  USER_PROMPT="$1"
  INPUT_FILE="$2"
  INPUT_FILE2="$3"
}

# Initialize pipeline core
init_core() {
  local quant_upper ; quant_upper=$(to_upper "$QUANTIZATION")

  # Clean stale temp state from crashed sessions
  [[ -e $TEMP_STATE_FILE ]] && rm -f "$TEMP_STATE_FILE"

  # Set authentication tag
  set_auth_tag

  # Set initial terminal width
  set_term_width

  # Fix Emojis/Icons for Termux
  if is_termux; then
    ICON_INFO="ℹ️  "
  fi

  # Fix Iterations for Termux (creates key migration issues)
  # if is_termux; then
  #   PBKDF_ITERATIONS=$((PBKDF_ITERATIONS/2))
  # fi

  # Create required folders
  create_local_model_cache
  create_local_data_store

  # Setup core
  load_tor_config
  set_console_title "${SCRIPT_FILE}: Initializing..."
  set_listen_interface
  set_keep_alive
  set_cpu_cores
  set_temp_files
  set_base_tools
  set_api_provider

  # Define right chat model
  set_chat_model

  # Define right vision model
  set_vision_model

  # Set current state
  set_state

  # Set system prompt based on defined models
  set_system_prompt

  # Generate self architecture file
  generate_self_architecture

  [[ ! -r $BASE_TOOLS ]] && error "Missing '$BASE_TOOLS' file."

  # Disable Tor explicitely for Groq (They hates it the vilains lol)
  if [[ $BACKEND == "external" && $PROVIDER == "groq" ]]; then
    USE_TOR=false
    log_warn "Tor privacy tunnel disabled for Groq."
  fi

  # Call Tor network handler
  [[ $USE_TOR == true ]] && handle_tor

  # Load API keys only for external backend
  if [[ $BACKEND == "external" && $PROVIDER_API_AUTH == true ]]; then
    # Try loading from the encrypted key chest first
    load_provider_key

    # Pre-flight check: if no key is configured, prompt user or fail
    if [[ -z $PROVIDER_API_KEY ]]; then
      if [[ -t 0 && $RUN_MODE == "chat" ]]; then
        # Running interactively in Chat mode, prompt user to configure keys
        log_warn "Missing cloud credentials for provider: ${CLR_B_YELLOW}${PROVIDER}${ANSI_RESET}."
        interactive_key_setup "$PROVIDER"
        # Reload key after interactive setup (already done in 'interactive_key_setup' now)
        # if has_provider_key "$PROVIDER"; then
        #   PROVIDER_API_KEY=$(decrypt_provider_key "$PROVIDER" 2>/dev/null)
        # fi
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
        LLAMA_CACHE="$LLAMA_CPP_CACHE" \
        llama-cli -hf "${CHAT_MODEL}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${VISION_MODEL}'..."
        LLAMA_CACHE="$LLAMA_CPP_CACHE" \
        llama-cli -hf "${VISION_MODEL}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMA_CPP_ROUTER}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMA_CPP_CACHE" \
        llama-cli -hf "${LLAMA_CPP_ROUTER}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMA_CPP_ARCHITECT}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMA_CPP_CACHE" \
        llama-cli -hf "${LLAMA_CPP_ARCHITECT}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMA_CPP_CODER}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMA_CPP_CACHE" \
        llama-cli -hf "${LLAMA_CPP_CODER}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_info "Preloading '${LLAMA_CPP_JUDGE}:${quant_upper}'..."
        LLAMA_CACHE="$LLAMA_CPP_CACHE" \
        llama-cli -hf "${LLAMA_CPP_JUDGE}:${quant_upper}" -c $MIN_CONTEXT --simple-io --no-warmup -st -n 1 -p hello &>/dev/null ; sleep 1
        log_debug "Reloading llama.cpp GGUF models cache..."
        curl -sSL "${LLAMA_CPP_API_SRV}/models?reload=1" &>/dev/null || error "Failed to reload llama.cpp GGUF models cache."
        log ; log_success "All required local llama.cpp models preloaded successfully."
      ;;
    esac
  fi
}

# -----------------------------------------------------------------------------
# Direct Execution Logic
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Set Tor config (indempotent)
  load_tor_config

  # Parse received flags
  parse_cli_args "$@"

  # Self-explanatory :P
  init_core

  # Mode selector
  if [[ $RUN_MODE == "server" ]]; then
    serve
  elif [[ $RUN_MODE == "auto" ]]; then
    run_agent
  else
    run_one_shot_pipeline
  fi
fi
