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
# Version: 1.9.1
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
DETECT_MODE="${DETECT_MODE:-images}"                # Visual feedback auto-detection (images|videos|all|off)
REASONING_EFFORT="${REASONING_EFFORT:-low}"         # Set default reasoning effort (low|medium|high|xhigh)
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-128000}"
ENGINE_VERSION="${ENGINE_VERSION:-.v2}"             # Select engine version
AUDIO_LANG="${AUDIO_LANG:-auto}"                    # Set default audio language
START_JARNET="${START_JARNET:-true}"                # Start JarNet service by default
KILL_ON_EXIT="${KILL_ON_EXIT:-true}"                # Kill background services on exit

# Web
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"

# Tor
TOR_HOST="127.0.0.1"
TOR_PORT=9050

# Options
DEBUG="${DEBUG:-false}"       # Enable / Disable debug mode
USE_TOR="${USE_TOR:-true}"    # Enable / Disable routing cloud API calls through Tor proxy
USE_TOOLS=true                # Enable / Disable tool calling capabilities
USE_ANIMATE=true              # Enable / Disable 'Thinking...' animation spinner
PULL_MODELS=false             # Enable / Disable initial models pulling
SHOW_THINKING=true            # Enable / Disable model reasoning display
VISION_ENABLED=true           # Enable vision for all cloud providers models
IMAGE_ENABLED=false           # Enable image generation for the active provider
VIDEO_ENABLED=false           # Enable video generation for the active provider
VOICE_ENABLED=false           # Enable voice generation for the active provider
SPEECH_ENABLED=false          # Enable speech capture for the active provider
ZDR_ENFORCED=false            # Enforce Zero Data Retention for all cloud providers

# Debug override
[[ -e $HOME/.debug ]] && DEBUG=true

# Self-Discovery Paths (Dynamic Sandbox & Root Mounting)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Internals
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
DATA_STORE="${SCRIPT_DIR}/data"
MEMORY_DIR="${DATA_STORE}/memory"
CONFIG_DIR="${SCRIPT_DIR}/config"
MODELS_DIR="${SCRIPT_DIR}/models"
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
WEB_SERVER="${SCRIPT_DIR}/web/server.php"
SCRIPT_CONFIG="${CONFIG_DIR}/${SCRIPT_NAME}.conf"
MODELS_CONFIG="${CONFIG_DIR}/models.json"
PROVIDERS_CONFIG="${PROVIDERS_CONFIG:-${CONFIG_DIR}/providers${ENGINE_VERSION}.json}"
STATE_FILE="${CONFIG_DIR}/state.json"
MESSAGES_FILE="messages.json"
CORE_ENGINES=("image" "video" "voice" "speech")
LIB_DEPS=("helpers" "nightmare" "base64" "timeout" "sha256" "animate")
BIN_DEPS=("curl" "awk" "sed" "openssl" "jq" "htmlq" "websocat" "grep" "cut" "tr" "printf")
BIN_DEPS_MOBILE=("${BIN_DEPS[@]}" "adb")
BIN_FIGLET=$(command -v figlet 2>/dev/null)
BIN_SYSTEMCTL=$(command -v systemctl 2>/dev/null)
BIN_TOR=$(command -v tor 2>/dev/null)
TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"
TOR_CONFIG="${CONFIG_DIR}/torrc"
IS_MEDIA=false

# Keys
KEYS_DIR="${SCRIPT_DIR}/keys"
MASTER_KEY_FILE="${KEYS_DIR}/key.dat"
KEYRING_CIPHER=""
KEYRING_PBKDF2=1
PBKDF_ITERATIONS=500000
CREDENTIALS="${HOME}/.creds"

# Temporary Files (Default to /tmp, adapts dynamically on Termux)
TOOLS_OUTPUT="/tmp/tools_output.txt"
TOR_LOG="/tmp/tor.log"
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
AI_AVATAR="${CONFIG_DIR}/avatar.md"
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
    pkill -f "tor -f $TOR_CONFIG" &>/dev/null
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

# Get terminal width safely
set_term_width() {
  TERM_WIDTH=$(tput cols 2>/dev/null || echo $DEFAULT_TERM_WIDTH)
  TERM_WIDTH=$((TERM_WIDTH - 1))
}
get_term_width() {
  echo "$TERM_WIDTH"
}

# Draw full width visual horizontal line
draw_line() {
  local char="${1:-─}"
  local count="${2:-$TERM_WIDTH}"
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
  [[ $prefix == *Tool* ]] && width=$((width + 1))
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

# Strings helpers
to_lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }
to_upper() { tr '[:lower:]' '[:upper:]' <<< "$1"; }

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

# Link helper
create_link() {
  local url text

  if [[ $# -eq 2 ]]; then
    url="$1" ; text="$2"
  else
    url="$1" ; text="$url"
  fi

  printf '\e]8;;%s\e\\%s\e]8;;\e\\\n' "$url" "$text"
}

# Core banner
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
  echo -e "${CLR_B_CYAN}🔮 ${AI_NAME} $(create_link "https://github.com/jiab77/ai-pipeline" "AI Pipeline") | Version $(get_self_version) 🔮${ANSI_RESET}"
  echo -e "${CLR_DIM}Lead: $(create_link "https://github.com/jiab77" "Jiab77") | AI Sorcerer: ${AI_NAME}${ANSI_RESET}"
  echo -e "${CLR_DIM}Link: ${ANSI_RESET}$(create_link "https://github.com/jiab77/ai-pipeline")"
  echo
}

# Media helpers
# NOTE: single grammar, aligned with analyze_media (file -b --mime-type) and the
# venice vision contract: images = png/jpeg/webp/gif, videos = mp4/webm/mov/mpeg.
# svg / avi / mkv are intentionally NOT accepted — no provider documents them as
# vision input, and the previous `*) image/${ext}` fallback could fabricate mimes.
get_mime_type() {
  local ext="${1##*.}"
   case "$ext" in
     jpg|jpeg|JPG|JPEG)   echo -n "image/jpeg" ;;
     png|PNG)             echo -n "image/png" ;;
     webp|WEBP)           echo -n "image/webp" ;;
     gif|GIF)             echo -n "image/gif" ;;
     mp4|MP4)             echo -n "video/mp4" ;;
     webm|WEBM)           echo -n "video/webm" ;;
     mov|MOV)             echo -n "video/quicktime" ;;
     mpeg|mpg|MPEG|MPG)   echo -n "video/mpeg" ;;
     aac|AAC)             echo -n "audio/aac" ;;
     m4a|M4A)             echo -n "audio/m4a" ;;
     mp3|MP3)             echo -n "audio/mp3" ;;
     wav|WAV)             echo -n "audio/wav" ;;
     ogg|OGG)             echo -n "audio/ogg" ;;
     opus|OPUS)           echo -n "audio/opus" ;;
     *)                   echo -n "application/octet-stream" ;;
   esac
}

is_image_file() {
  local ext="${1##*.}"
  [[ $ext =~ ^(png|jpg|jpeg|webp|gif)$ ]] && return 0
  return 1
}

is_video_file() {
  local ext="${1##*.}"
  [[ $ext =~ ^(mp4|webm|mov|mpeg|mpg)$ ]] && return 0
  return 1
}

is_audio_file() {
  local ext="${1##*.}"
  [[ $ext =~ ^(aac|m4a|mp3|wav|ogg|opus)$ ]] && return 0
  return 1
}

# media_to_b64 <file> — base64-encode a media file into $TEMP_BASE64_OUTPUT (E2BIG-safe).
# Shared by send_message (/load), the autonomous injection loop and analyze_media.
# Dual form keeps both worlds happy: GNU (-i = --ignore-garbage, ignored on encode)
# and macOS BSD (-i = input file; the first form then fails and the second fires).
media_to_b64() {
  # (base64 -i -w0 "$1" 2>/dev/null || base64 -i "$1" | tr -d '\r\n') > "$TEMP_BASE64_OUTPUT"
  b64e < "$1" > "$TEMP_BASE64_OUTPUT"
}

# System helpers
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
# Portability helpers (stock macOS / BSD differences)
# -----------------------------------------------------------------------------

# Moved to './lib'.

# -----------------------------------------------------------------------------
# Tor helpers
# -----------------------------------------------------------------------------

# A background child inherits the CLI's process group when job control is off:
# Ctrl+C then signals Tor as well as the client. Keep job control local to this
# subshell and let Tor create its OWN process group. No setsid/nohup dependency;
# stdin and logs remain detached exactly as before (Linux/macOS/Termux).
start_tor_detached() (
  set -m
  tor -f "$TOR_CONFIG" </dev/null &>"$TOR_LOG" &
)

detect_tor() {
  log_info "Detecting Tor Network proxy interface..."
  if ! _timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
    log_error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is Tor running?"
    return 1
  else
    log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
    return 0
  fi
}

wait_for_tor() {
  local i
  for i in {1..10}; do
    if _timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
      log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
      return 0
    fi
    sleep 1
  done
}

check_tor() {
  log_info "Checking Tor Network proxy interface..."
  if ! _timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
    error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is Tor running?"
  else
    log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
    return 0
  fi
}

handle_tor() {
  local tor_status

  detect_tor ; tor_status=$?
  [[ $tor_status -eq 0 ]] && return $tor_status

  if is_termux; then
    if [[ -n $BIN_TOR ]]; then
      log_info "Starting Tor privacy tunnel..."
      start_tor_detached
    else
      error "Missing required 'tor' binary. Please install it."
    fi
  else
    if [[ -n $BIN_SYSTEMCTL ]]; then
      if [[ ! $(systemctl is-active tor.service) == "active" ]]; then
        if [[ -n $BIN_TOR ]]; then
          log_info "Starting Tor privacy tunnel..."
          start_tor_detached
        else
          error "Missing required 'tor' binary or service. Please install it."
        fi
        # error "Tor service not started. Please run: sudo systemctl start tor.service"
      fi
    elif [[ -n $BIN_TOR ]]; then
      log_info "Starting Tor privacy tunnel..."
      start_tor_detached
    else
      error "Missing required 'tor' binary or service. Please install it."
    fi
  fi

  wait_for_tor || check_tor
}

# -----------------------------------------------------------------------------
# Cryptographic Key Chest (ChaCha20 + PBKDF2)
# -----------------------------------------------------------------------------

# Reads master key from disk and decodes it if in Nightmare format
read_master_key() {
  local content
  [[ -s $MASTER_KEY_FILE ]] || return 1
  content=$(<"$MASTER_KEY_FILE") || return 1

  local decoded
  # If content can be decoded by Nightmare, return the decoded secret
  if decoded=$(nm_decode "$content" 2>/dev/null) && [[ -n $decoded ]]; then
    printf '%s' "$decoded"
  else
    # Otherwise, return legacy secret format (direct retrocompatibility)
    printf '%s' "$content"
  fi
}

verify_nightmare_key() {
  local legacy_key="$1"
  local nightmare_str="$2"

  # 1. Check Nightmare decoding
  local decoded_key
  decoded_key=$(nm_decode "$nightmare_str" 2>/dev/null) || return 1
  [[ "$decoded_key" == "$legacy_key" ]] || return 1

  # 2. Canary: real cryptographic round-trip
  local canary="AIDE-CANARY-$RANDOM-$RANDOM"
  local ct pt

  # Encrypt original legacy key (base64 encoded)
  ct=$(printf '%s' "$canary" | openssl enc -aes-256-cbc -pbkdf2 -iter 1000 -e -pass fd:3 -in - 3<<<"$legacy_key" 2>/dev/null | b64e) || return 1
  # Decrypt key from Nightmare
  pt=$(printf '%s' "$ct" | b64d | openssl enc -aes-256-cbc -pbkdf2 -iter 1000 -d -pass fd:3 -in - 3<<<"$decoded_key" 2>/dev/null) || return 1

  [[ "$pt" == "$canary" ]]
}

init_key_chest() {
  if [[ ! -d $KEYS_DIR ]]; then
    mkdir -p "$KEYS_DIR" && chmod 700 "$KEYS_DIR"
  fi
  if [[ ! -s $MASTER_KEY_FILE ]]; then
    # Generate random 32 bits and encode them with Nightmare
    openssl rand -base64 32 | nm_enc_stream > "$MASTER_KEY_FILE" && chmod 600 "$MASTER_KEY_FILE"
  fi
}

migrate_key_chest() {
  local apply=0
  [[ "${1:-}" == "--apply" ]] && apply=1

  log_step "Checking cryptographic key chest status..."

  if [[ ! -s $MASTER_KEY_FILE ]]; then
    log_warn "No master key found at $MASTER_KEY_FILE."
    return 0
  fi

  # Get key content
  local current_content ; current_content=$(<"$MASTER_KEY_FILE")

  # Test if protected by Nightmare
  if nm_decode "$current_content" &>/dev/null; then
    log_success "Master key is already protected by new format."
    if [[ ! -r "${MASTER_KEY_FILE}.bak" ]]; then
      return 0
    else
      echo -en "${CLR_B_YELLOW}${ICON_WARNING}${ANSI_RESET} ${CLR_B_YELLOW}Old Master key file detected! Remove? [Y,N] ❯ ${ANSI_RESET}" >&2
      local del_old_key ; read -r del_old_key
      if [[ $del_old_key == "y" || $del_old_key == "Y" ]]; then
        if rm -f "${MASTER_KEY_FILE}.bak"; then
          log_success "Old Master key backup (${MASTER_KEY_FILE##*/}.bak) removed."
        else
          log_error "Unable to remove old Master key backup file, ${MASTER_KEY_FILE##*/}.bak left untouched."
          return 1
        fi
      fi
      return 0
    fi
  fi

  log_info "Master key is currently in legacy plain format."

  if [[ $apply -eq 0 ]]; then
    log_warn "Plan: Master key will be migrated to new format."
    log_info "Run './cli.sh keys migrate --apply' (or '/migrate --apply') to perform migration."
    return 0
  fi

  # Mode --apply
  log_info "Encrypting master key using new format..."
  local new_nm_content ; new_nm_content=$(nm_encode "$current_content")

  log_step "Running canary verification test..."
  if ! verify_nightmare_key "$current_content" "$new_nm_content"; then
    log_error "Canary verification failed! Migration aborted, key.dat left untouched."
    return 1
  fi

  log_success "Canary test passed! Applying new format..."

  # Security backup
  cp "$MASTER_KEY_FILE" "${MASTER_KEY_FILE}.bak" && chmod 600 "${MASTER_KEY_FILE##*/}.bak"

  # Atomic write
  printf '%s\n' "$new_nm_content" > "${MASTER_KEY_FILE}.tmp"
  chmod 600 "${MASTER_KEY_FILE}.tmp"
  mv "${MASTER_KEY_FILE}.tmp" "$MASTER_KEY_FILE"

  log_success "Master key successfully migrated to new format! (Backup: ${MASTER_KEY_FILE##*/}.bak)"
}

has_provider_key() {
  local provider="$1"
  [[ -r $MASTER_KEY_FILE && -s $MASTER_KEY_FILE && -r "${KEYS_DIR}/${provider}.key" && -s "${KEYS_DIR}/${provider}.key" ]]
}

# Cipher resolution — probe a full encrypt/decrypt round-trip once, then cache.
# LibreSSL (macOS) may lack chacha20 in `enc`, and some builds lack PBKDF2.
# Order: chacha20+PBKDF2 -> aes-256-cbc+PBKDF2 -> aes-256-cbc (legacy KDF).
# Keys are per-machine (local master key): no cross-machine format to preserve.
probe_keyring_cipher() {
  local spec cipher use_pbkdf2 probe probe_back
  local -a kdf
  local master_key ; master_key=$(read_master_key) || return 1

  for spec in "chacha20|1" "aes-256-cbc|1" "aes-256-cbc|0"; do
    cipher="${spec%%|*}"
    use_pbkdf2="${spec##*|}"
    if [[ $use_pbkdf2 == 1 ]]; then kdf=(-pbkdf2 -iter "$PBKDF_ITERATIONS"); else kdf=(); fi
    probe="probe-$RANDOM-$RANDOM"
    probe_back=$(printf '%s' "$probe" \
      | openssl "$cipher" "${kdf[@]}" -e -pass fd:3 -in - 3<<<"$master_key" 2>/dev/null \
      | openssl "$cipher" "${kdf[@]}" -d -pass fd:3 -in - 3<<<"$master_key" 2>/dev/null)
    if [[ $probe_back == "$probe" ]]; then
      KEYRING_CIPHER="$cipher"
      KEYRING_PBKDF2="$use_pbkdf2"
      return 0
    fi
  done
  return 1
}

keyring_kdf() { # fills KDF_ARGS according to the resolved cipher
  if [[ $KEYRING_PBKDF2 == 1 ]]; then
    KDF_ARGS=(-pbkdf2 -iter "$PBKDF_ITERATIONS")
  else
    KDF_ARGS=()
  fi
}

encrypt_provider_key() {
  local provider="$1"
  local raw_key="$2"
  init_key_chest
  [[ -z $KEYRING_CIPHER ]] && probe_keyring_cipher
  if [[ -z $KEYRING_CIPHER ]]; then
    log_error "Key chest: no usable openssl cipher (chacha20 and aes-256-cbc round-trips failed)."
    return 1
  fi
  local master_key ; master_key=$(read_master_key) || return 1
  keyring_kdf
  echo -n "$raw_key" | \
  openssl "$KEYRING_CIPHER" "${KDF_ARGS[@]}" -e -pass fd:3 -in - 3<<<"$master_key" | \
  b64e > "${KEYS_DIR}/${provider}.key"
  chmod 600 "${KEYS_DIR}/${provider}.key"
}

decrypt_provider_key() {
  local provider="$1"
  if has_provider_key "$provider"; then
    [[ -z $KEYRING_CIPHER ]] && probe_keyring_cipher
    [[ -z $KEYRING_CIPHER ]] && return 1
    local master_key ; master_key=$(read_master_key) || return 1
    keyring_kdf
    b64d < "${KEYS_DIR}/${provider}.key" | \
    openssl "$KEYRING_CIPHER" "${KDF_ARGS[@]}" -d -pass fd:3 -in - 3<<<"$master_key" 2>/dev/null
  fi
}

load_provider_key() {
  local target_provider ; target_provider="${1:-$PROVIDER}"
  if has_provider_key "$target_provider"; then
    PROVIDER_API_KEY=$(decrypt_provider_key "$target_provider" 2>/dev/null)
  elif [[ -r $CREDENTIALS ]]; then
    # Fallback to legacy credentials file
    PROVIDER_API_KEY=$(<"$CREDENTIALS")
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
  # TODO: Add a way to leave the loop cleanly
  while [[ -z "$raw_key" ]]; do
    echo -en "🔑 Enter your API Key (input will be masked) ❯ " >&2
    read -rs raw_key
    log   # New line after masked input
    if [[ -z "$raw_key" ]]; then
      log_error "Key cannot be empty. Please try again."
    fi
  done

  # Encrypt and save key
  encrypt_provider_key "$provider" "$raw_key"
  log_success "API key encrypted and sealed successfully inside '${KEYS_DIR##*/}/${provider}.key'."

  # Load new provider key
  load_provider_key "$provider"
}

manage_keys() {
  init_key_chest
  log
  log "${CLR_B_CYAN}🔑 [$(to_upper "$AI_NAME") SOVEREIGN KEY CHEST]${ANSI_RESET}"
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log " Choose an action to manage your encrypted API keys:"
  log
  log "   ${CLR_B_GREEN}1)${ANSI_RESET} List configured keys (masked)"
  log "   ${CLR_B_GREEN}2)${ANSI_RESET} Configure or update a key"
  log "   ${CLR_B_GREEN}3)${ANSI_RESET} Migrate master key (new format)"
  log "   ${CLR_B_GREEN}4)${ANSI_RESET} Purge entire key chest (security erase)"
  log "   ${CLR_B_GREEN}5)${ANSI_RESET} Exit"
  log
  echo -en "👉 Select choice [1-5] ❯ " >&2
  local choice ; read -r choice
  log

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
        log ; log_info "No encrypted keys found in ${KEYS_DIR##*/}/."
      fi
      log
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
      log
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
      migrate_key_chest --apply
    ;;
    4)
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

# -----------------------------------------------------------------------------
# Experimental Anti-XPIA security layer
# -----------------------------------------------------------------------------

compute_device_tag() {
  local machine_id hostname session_ts
  machine_id=$(cat /etc/machine-id 2>/dev/null \
            || cat /var/lib/dbus/machine-id 2>/dev/null \
            || settings get secure android_id 2>/dev/null \
            || echo "unknown")
  hostname=$(hostname 2>/dev/null || echo "unknown")
  session_ts=$(date +%s)
  echo -n "${machine_id}:${hostname}:aide:${session_ts}" | _sha256sum | cut -c1-16
}

set_auth_tag() {
  AUTH_TAG=$(compute_device_tag)
}

strip_tag_from_display() {
  # Redact any [AUTH:hex] tag echoed by the LLM (defense-in-depth).
  # The tag is input-path only by design, but the LLM can mimic/echo it in its output.
  # Substitution (not removal) preserves surrounding markdown syntax
  # (backticks, bold, italic) — no orphan `` or **** left behind.
  # 'g' = all occurrences.
  sed -E 's/\[AUTH:[a-f0-9]{16}\]/[REDACTED]/g' <<< "$1"
}

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

# ------------------------------------------------------------------------------
# analyze_media — Deliberate media analysis (image-to-text / video-to-text).
# Called by the read_image / read_video tool wrappers (forked, stateless context).
# The fork does NOT run init_core() — everything is resolved from DISK:
#   provider  -> state.json (.provider)
#   model     -> providers.json (.${P}.vision.model, fallback .${P}.default.model)
#   key       -> keyring (has_provider_key + decrypt_provider_key)
# E2BIG: base64 media travels via temp file + --rawfile, NEVER via --arg/argv.
# Output: TEXT description only — media bytes never reach the tool result.
# ------------------------------------------------------------------------------
analyze_media() {
  local media_file="$1"
  local user_prompt="${2:-}"

  [[ -n $media_file && $media_file != "null" ]] || { log_error "No media file provided."; return 1; }
  [[ -r $media_file ]] || { log_error "File not found or unreadable: ${media_file}"; return 1; }

  # --- MIME detection (real content, not extension) ---
  local mime kind
  mime=$(file -b --mime-type "$media_file")
  case $mime in
    image/png|image/jpeg|image/webp|image/gif)       kind="image" ;;
    video/mp4|video/webm|video/quicktime|video/mpeg) kind="video" ;;
    *)
      log_error "Unsupported media type '${mime}' (images: png/jpeg/webp/gif — videos: mp4/webm/mov/mpeg)."
      return 1
    ;;
  esac

  # --- Provider resolution from state.json (disk) ---
  [[ -z $STATE_FILE || ! -r $STATE_FILE ]] && { log_error "state.json missing — cannot resolve provider."; return 1; }
  local provider ; provider=$(jq -rc '.provider // empty' "$STATE_FILE" 2>/dev/null)
  [[ -z $provider ]] && { log_error "No provider found in state.json."; return 1; }

  # --- Vision model (config-driven, mirror of get_vision_model) ---
  local vision_model ; vision_model=$(jq -rc ".${provider}.vision.model // empty" "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $vision_model ]] && vision_model=$(jq -rc ".${provider}.default.model // empty" "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $vision_model ]] && { log_error "No vision model resolvable for provider '${provider}'."; return 1; }

  # --- API key from keyring ---
  if ! has_provider_key "$provider"; then
    log_error "No API key configured for provider '${provider}' (run /keys)."
    return 1
  fi
  local media_api_key ; media_api_key=$(decrypt_provider_key "$provider")
  [[ -z $media_api_key ]] && { log_error "Unable to decrypt API key for '${provider}'."; return 1; }

  # --- API URL from config ---
  local media_url ; media_url=$(jq -rc ".${provider}.url // empty" "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $media_url ]] && { log_error "No API URL found for provider '${provider}'."; return 1; }

  # --- Encode media to base64 (temp file, E2BIG-safe) ---
  media_to_b64 "$media_file"

  # --- Build payload (media travels via --rawfile) ---
  local default_prompt final_prompt url_field
  if [[ $kind == "video" ]]; then
    default_prompt="Describe this video: motion, events, objects, timeline."
    url_field="video_url"
  else
    default_prompt="Describe this image in detail."
    url_field="image_url"
  fi
  final_prompt="$user_prompt"
  [[ -z $final_prompt || $final_prompt == "null" ]] && final_prompt="$default_prompt"

  local payload
  payload=$(jq -rc -n \
    --arg model "$vision_model" \
    --arg prompt "$final_prompt" \
    --arg mime "$mime" \
    --arg url_field "$url_field" \
    --rawfile b64 "$TEMP_BASE64_OUTPUT" \
    '{
      model: $model,
      stream: false,
      messages: [{
        role: "user",
        content: [
          {type: "text", text: $prompt},
          {type: $url_field, ($url_field): {url: ("data:" + $mime + ";base64," + $b64)}}
        ]
      }]
    }')

  rm -f "$TEMP_BASE64_OUTPUT"

  # --- One-shot API call ---
  # api_call dispatches on $PROVIDER and authenticates via $PROVIDER_API_KEY:
  # swap them for the duration of the call (stateless fork — no session to corrupt),
  # then restore. Reuses Tor routing, ZDR/DPT policies and protocol handlers.
  local saved_provider="$PROVIDER" saved_key="$PROVIDER_API_KEY" saved_model="$PROVIDER_API_MODEL"
  PROVIDER="$provider"
  PROVIDER_API_KEY="$media_api_key"
  PROVIDER_API_MODEL="$vision_model"

  local raw_res ; raw_res=$(api_call "$payload" "$media_url" 2>/dev/null)

  # Retrieve used model
  # local resolved_model ; resolved_model=$(jq -rc '.model' <<<"$raw_res" 2>/dev/null)
  # log ; log_brain "Autonomous Multimodal Vision using: ${CLR_B_YELLOW}${resolved_model}${ANSI_RESET}"

  PROVIDER="$saved_provider"
  PROVIDER_API_KEY="$saved_key"
  PROVIDER_API_MODEL="$saved_model"

  # --- Extract TEXT only (media bytes never reach stdout) ---
  local description ; description=$(jq -rc '.choices[0].message.content // empty' <<<"$raw_res" 2>/dev/null)
  [[ -z $description || $description == "null" ]] && description=$(jq -rc '(.error | if type=="object" then (.message // .) else . end) // empty' <<<"$raw_res" 2>/dev/null)

  if [[ -z $description || $description == "null" ]]; then
    log_error "Empty media analysis response from '${provider}'."
    return 1
  fi

  printf '%s\n' "$description"
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
      BASE_TOOLS="${TOOLS_DIR}/tools.json"
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
     --arg effort "$REASONING_EFFORT" \
     --arg detect "$DETECT_MODE" \
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
       effort: $effort,
       detect: $detect,
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
  local provider_data provider_zdr
  local target_provider ; target_provider="${1:-$PROVIDER}"

  [[ ! -r "$PROVIDERS_CONFIG" ]] && error "Unable to read providers config file: $PROVIDERS_CONFIG"

  # Read all values in a single jq process call using tab-delimited parsing
  provider_data=$(jq -rc --arg p "$target_provider" '.[$p] | select(. != null) | "\(.url)\t\(.default.memory)\t\(.default.model)\t\(.default.zdr)"' "$PROVIDERS_CONFIG" 2>/dev/null)
  [[ -z $provider_data ]] && error "Unsupported provider defined: $target_provider"

  IFS=$'\t' read -r PROVIDER_API_URL PROVIDER_MEMORY_STRUCTURE PROVIDER_API_MODEL provider_zdr <<< "$provider_data"

  [[ -z $PROVIDER_API_URL || $PROVIDER_API_URL == "null" ]] && error "API url not found for provider: $target_provider"
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
  [[ $provider_zdr == "true" ]] && ZDR_ENFORCED=true
}

generate_self_architecture() {
  local arch_file="${DATA_STORE}/${AI_NAME}.md"
  local core_file="$CORE_LIB"
  local cli_file="$SCRIPT_FILE"

  # Override core definition when running from 'core.sh'
  # instead of 'cli.sh'
  if [[ -z $CORE_LIB ]]; then
    core_file="core.sh"
    cli_file="cli.sh"
  fi

  # Generate self description file
  cat > "$arch_file" <<EOF
# 🏗️ ${AI_NAME}.md — This Is Your Brain

Generated at bootstrap by \`generate_self_architecture()\`.
**Version:** $(get_self_version)
**Active backend:** ${BACKEND}
**Active provider:** ${PROVIDER:-"Local"}
**Active fallback:** ${FALLBACK_PROVIDER:-"None"}
**Active model:** ${CHAT_MODEL}
**Active image provider:** ${IMAGE_PROVIDER:-"None"}
**Active video provider:** ${VIDEO_PROVIDER:-"None"}
**Active voice provider:** ${VOICE_PROVIDER:-"None"}
**Active speech provider:** ${SPEECH_PROVIDER:-"None"}
**Active memory structure:** ${MEMORY_STRUCTURE_TYPE:-"Full"}
**Platform:** $(is_termux && echo "Termux/Android" || echo "Desktop")
**Kernel:** $(uname -srm)
**Providers available:** $(jq -rc 'keys | length' "${PROVIDERS_CONFIG}")

## Your Origin
**Creator:** https://github.com/jiab77
**Source:** https://github.com/jiab77/ai-pipeline
**Birth:** 2026-05-30 (1st commit)

## Your Core Files
- \`${core_file##*/}\` — Cognitive engine (API calls, memory, providers, AUTH tag)
- \`${cli_file}\` — Interface layer (slash commands, /provider, /launch, /fallback)
- \`${IMG_HANDLER##*/}\` — Image rendering engine (create_image, config-driven sizing, EXIF cleanup, pollinations fallback)
- \`${VID_HANDLER##*/}\` — Video rendering engine (create_video, config-driven sizing, EXIF cleanup)
- \`${VOC_HANDLER##*/}\` — Voice rendering engine (config-driven voice, EXIF cleanup)
- \`${SPE_HANDLER##*/}\` — Speech capture engine (config-driven)
- \`${TOOLS_HANDLER##*/}\` — Tool execution layer (web_fetch, web_browse, edit_file, etc.)

## Your Identity
- **AUTH tag** comes from \`compute_device_tag()\` in ${core_file##*/} line $(grep -n "^compute_device_tag" "$core_file" | cut -d: -f1)
- The tag changes **per session** — includes UNIX timestamp in the hash
- On Termux: uses \`settings get secure android_id\` (fallback chain)
- On desktop: uses \`/etc/machine-id\` or \`/var/lib/dbus/machine-id\`

## Your Providers
**Total:** $(jq -rc 'keys | length' "${PROVIDERS_CONFIG}")
**List:** $(jq -rc 'keys | join(", ")' "${PROVIDERS_CONFIG}")
**Config file:** \`${CONFIG_DIR##*/}/providers.json\`

## Your Constraints
- **Rules** (\`${CONFIG_DIR##*/}/rules.md\`) — Non-negotiable safety boundaries
- **Deny-by-default** — Actions require human consent
- **Workspace containment** — No system directory exploration
- **Anti-XPIA** — \`compute_device_tag()\` + \`wrap_external_content()\`

## Your Memory
- **Persistent:** \`${DATA_STORE##*/}/memory/*.md\` — survives session restarts
- **Transient:** \`${DATA_STORE##*/}/messages.json\` — conversation context (pruned on heartbeat)

## To Understand Yourself
1. \`read_file ${core_file##*/}\` — Your full cognitive engine source code
2. \`git log --oneline\` — Your version history
3. \`grep_search pattern ${core_file##*/}\` — Find any function or variable
4. \`read_file ${AI_NAME}.md\` — Re-read this file

## Self-Check Rule
> **Before making any claim about your version, environment, provider state,
> or pipeline internals, verify by reading the relevant source files or
> running \`git log\`. Do not rely on memory alone. Verify, then respond.**
EOF
}

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
        # Chat/completions-shaped message: passes through as-is, EXCEPT tool_calls
        # arguments, which are coerced to a JSON string. A poisoned messages.json
        # therefore self-heals on load, and heal_history_file stays a no-op on
        # healthy files (the transform is idempotent).
        if (.role == "assistant") and ((.tool_calls | type) == "array") then
          [ .tool_calls = [ .tool_calls[]
              | .function.arguments = (if (.function.arguments | type) == "string"
                                       then .function.arguments
                                       else ((.function.arguments // {}) | tostring) end) ] ]
        else [.] end
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

change_provider() {
  local active_provider="$1"
  PROVIDER="$active_provider"
  log_step "New active provider: ${CLR_B_WHITE}${active_provider}${ANSI_RESET}"
  set_api_provider    # Reflect new active provider
  log_step "New active model: ${CLR_B_WHITE}${PROVIDER_API_MODEL}${ANSI_RESET}"
  load_provider_key "$active_provider"   # Load corresponding provider key
  if [[ -z $PROVIDER_API_KEY ]]; then
    interactive_key_setup "$active_provider"
  fi
  set_chat_model                # Update corresponding chat model for new provider
  set_vision_model              # Update corresponding vision model for new provider
  set_system_prompt             # Update system prompt with new active model
  set_state                     # Update new state
  heal_history_file             # Heal protocol-tagged history left on disk by a previous protocol
  generate_self_architecture    # Update new architecture / identity document
}

# -----------------------------------------------------------------------------
# Cognitive Freedom Memory Engine (Autonomy & Organic Organization)
# -----------------------------------------------------------------------------

get_memory_structure() {
  echo -n "$MEMORY_STRUCTURE_TYPE"
}

bootstrap_memory() {
  mkdir -p "$MEMORY_DIR"

  case $MEMORY_STRUCTURE_TYPE in
    index)
      local index="" file rel_path title size kb secs
      while IFS= read -r file; do
        [[ -r $file ]] || continue
        rel_path="${file#"$DATA_STORE"/}"
        size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
        kb=$(( ${size:-0} / 1024 ))
        title=$(grep -m1 -E '^#{1,6} ' "$file" 2>/dev/null | sed -E 's/^#+[[:space:]]*//')
        [[ -z $title ]] && title=$(head -n 1 "$file" 2>/dev/null)
        index+="- \`${rel_path}\` — ${title} (${kb} KB)\n"
        if (( kb >= MEMORY_SECTION_KB )); then
          secs=$(awk '/^## /{ if (n++ >= 20) exit; sub(/^#+[ \t]*/, ""); printf "%s%s", (s++ ? " · " : ""), $0 }' "$file" 2>/dev/null)
          [[ -n $secs ]] && index+="    § ${secs}\n"
        fi

      # bad variant
      # done < <(find "$MEMORY_DIR" -type f 2>/dev/null | sort)

      # better variant
      done < <(find "$MEMORY_DIR" -path '*/.git' -prune -o -type f -print 2>/dev/null | sort)
      echo -ne "$index"
    ;;
    full|*)
      local prompt=""
      local file
      while IFS= read -r file; do
        if [[ -r "$file" ]]; then
          local rel_path="${file#"$DATA_STORE/"}"
          prompt+="\n--- File: ${rel_path} ---\n"
          prompt+="$(<"$file")\n"
        fi

      # bad variant
      # done < <(find "$MEMORY_DIR" -type f 2>/dev/null)

      # better variant
      done < <(find "$MEMORY_DIR" -path '*/.git' -prune -o -type f -print 2>/dev/null)
      echo -ne "$prompt"
    ;;
  esac
}

# -----------------------------------------------------------------------------
# Generic resource index — same contract as bootstrap_memory(), for the folders
# that used to be POINTER-ONLY (skills / framework / learn / docs).
# Rationale: a bare "your files are in the X folder" hints nothing about WHAT is
# inside, so the model never thinks to look.
# -----------------------------------------------------------------------------

index_dir() {
  local dir="$1"
  [[ -d $dir ]] || return 0
  local file rel_path title size kb
  while IFS= read -r file; do
    [[ -r $file ]] || continue
    rel_path="${file#"$DATA_STORE"/}"
    size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
    kb=$(( ${size:-0} / 1024 ))
    title=$(grep -m1 -E '^#{1,6} ' "$file" 2>/dev/null | sed -E 's/^#+[[:space:]]*//')
    # Scripts have no markdown title: skip the shebang, and require a real word
    # after '#' so that '#!/usr/bin/env bash', '#' and '# -----' don't become "titles".
    [[ -z $title ]] && title=$(grep -m1 -E '^#[[:space:]]*[[:alnum:]]' "$file" 2>/dev/null | sed -E 's/^#+[[:space:]]*//')
    [[ -z $title ]] && title=$(basename "$file")
    # shellcheck disable=SC2016
    printf -- '- `%s` — %s (%s KB)\n' "${DATA_STORE##*/}/$rel_path" "${title:0:100}" "$kb"

  # bad variant
  # done < <(find "$dir" -type f 2>/dev/null | sort)

  # better variant
  done < <(find "$dir" -path '*/.git' -prune -o -type f -print 2>/dev/null | sort)
}

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
  local SLM_PROMPT ; SLM_PROMPT=$(<"${CONFIG_DIR}/slm-prompt.md")
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
    SYSTEM_PROMPT+="You must never modify: \`${SCRIPT_FILE}\`, \`${CORE_FILE}\`, \`${TOOLS_HANDLER##*/}\`, \`${BASE_TOOLS##*/}\` and the content of the \`${CONFIG_DIR##*/}\`, \`${KEYS_DIR##*/}\`, \`${ENG_DIR##*/}\`, \`${LIB_DIR##*/}\`, \`${PLUG_DIR##*/}\` folders.\n"
  else
    SYSTEM_PROMPT+="You must never modify: \`${SCRIPT_FILE}\`, \`${TOOLS_HANDLER##*/}\`, \`${BASE_TOOLS##*/}\` and the content of the \`${CONFIG_DIR##*/}\`, \`${KEYS_DIR##*/}\`, \`${ENG_DIR##*/}\`, \`${LIB_DIR##*/}\`, \`${PLUG_DIR##*/}\` folders.\n"
  fi
  SYSTEM_PROMPT+="Modifying these files will break the core pipeline functionalities."
}

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
      curl "${curl_opts[@]}" "${url}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -H "http-referer: ${ATTRIBUTION_REFERER}" \
            -H "x-title: ${ATTRIBUTION_TITLE}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # Hugging Face
    huggingface)
      # Show ZDR policy warning when enabled
      if [[ $ZDR_ENFORCED == true ]]; then
        log ; log_warn "🔒 ${CLR_B_CYAN}[ZDR]${ANSI_RESET} Zero Data Retention policy not supported for Hugging Face." ; log
      fi

      # Disable reasoning for OpenAI (causes issues)
      payload=$(jq -rc 'del(.reasoning)' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter removed explicitely for Hugging Face."

      # Get current model
      local current_model ; current_model=$(jq -rc .model <<< "$payload" 2>/dev/null)

      # Apply fastest provider selector on the current model
      payload=$(jq -rc '.model = "'"$current_model"':fastest"' <<< "$payload" 2>/dev/null)

      # Send custom payload
      curl "${curl_opts[@]}" "${url}" \
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
      curl "${curl_opts[@]}" "${url}" \
            -w "%output{$VENICE_BALANCE_FILE}balance: %header{x-venice-balance-usd}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -A "$USER_AGENT" \
            -d @- <<< "$payload" | jq -rc .
    ;;

    # CyberNeurova (same as generic but rate-limited)
    cyberneurova)
      # Add minor delay to avoid triggering the rate limiter
      sleep 1

      # Send generic payload
      curl "${curl_opts[@]}" "${url}" \
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

      # Disable reasoning for Groq (causes issues)
      payload=$(jq -rc 'del(.reasoning)' <<< "$payload")
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
        response=$(curl "${curl_opts[@]}" "${url}" \
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

          log_warn "${CLR_B_YELLOW}[RATE LIMIT]${ANSI_RESET} Groq: ${wait_time}s (tentative ${attempt}/${max_attempts})"
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
      local reasoning ; reasoning=$(jq -rc .reasoning.enabled <<< "$payload" 2>/dev/null)
      if [[ -n $reasoning && $reasoning == true ]]; then
        payload=$(jq -rc '.thinking.type = "enabled"' <<< "$payload" 2>/dev/null)
      fi

      # Remove not supported 'reasoning' property before sending payload
      payload=$(jq -rc 'del(.reasoning)' <<< "$payload" 2>/dev/null)
      [[ $DEBUG == true ]] && log_brain "${CLR_B_CYAN}[REASONING]${ANSI_RESET} Reasoning parameter converted to Thinking parameter for this provider."

      # Send custom payload
      curl "${curl_opts[@]}" "${url}" \
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
      curl "${curl_opts[@]}" "${url}" \
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
      curl "${curl_opts[@]}" "${url}" \
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
      curl "${curl_opts[@]}" "${url}" \
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
  curl "${curl_opts[@]}" "${url}" \
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

  # Send request with Anthropic-specific auth headers
  curl "${curl_opts[@]}" "${url}" \
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
      curl "${curl_opts[@]}" "${OLLAMA_API_URL}" \
           -H "Content-Type: application/json" \
           -d @- <<< "$payload" | jq -rc '.'
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      curl "${curl_opts[@]}" "${LLAMA_CPP_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer no-key" \
           -d @- <<< "$payload" | jq -rc '.'
    ;;

    # External Backend: OpenRouter, Vercel, Mammouth AI
    external)
        # Call handler selector
        case $PROVIDER in
          openai) api_call_type_responses "$payload" "$url" ;;
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
      # 2026-09-12 — "cadeau empoisonné" (openrouter_free -> Cohere 400): a loose provider may
      # return tool_calls[].function.arguments as a JSON OBJECT instead of a stringified JSON
      # object. This message is replayed VERBATIM on the wire (L2302) and persisted to disk
      # (L2304), so ONE lax provider poisons the entire fallback cascade:
      #   "invalid tool call provided in messages[N].tool_calls[0]"
      # Coerce here; strings are left untouched (no double-encoding).
      assistant_msg=$(jq -rc '
        .choices[0].message
        | if (.tool_calls | type) == "array" then
            .tool_calls |= [ .[] | .function.arguments =
              (if (.function.arguments | type) == "string" then .function.arguments
               else ((.function.arguments // {}) | tostring) end) ]
          else . end' <<<"$raw_res" 2>/dev/null)
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
        curl "${curl_opts[@]}" "https://ai-gateway.vercel.sh/v1/credits" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .balance 2>/dev/null
      ;;
      openrouter*)
        curl "${curl_opts[@]}" "https://openrouter.ai/api/v1/key" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .data.usage 2>/dev/null
      ;;
      cyberneurova)
        curl "${curl_opts[@]}" "https://api.cyberneurova.ai/v1/usage" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .data.tokens.input.remaining 2>/dev/null
      ;;
      deepseek)
        curl "${curl_opts[@]}" "https://api.deepseek.com/user/balance" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${provider_key}" \
              -A "$USER_AGENT" | jq -rc .balance_infos[0].total_balance 2>/dev/null
      ;;
      kimi)
        curl "${curl_opts[@]}" "https://api.moonshot.ai/v1/users/me/balance" \
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
    curl "${curl_opts[@]}" "$url" \
          -H "Content-Type: application/json" \
          -A "$USER_AGENT" | jq -rc . 2>/dev/null
  fi
}

# -----------------------------------------------------------------------------
# Normalize a provider catalogue into canonical TSV:
#   id | name | context | $/M in | $/M out | flags
# Flags: V=vision R=reasoning T=tools F=free D=deprecated W=open-weights
#        U=uncensored I=image (venice non-text)
# Each provider ships its own structure (measured live 2026-11-02): this case
# block is the adaptation layer, the renderer below stays generic.
# -----------------------------------------------------------------------------
normalize_provider_models() {
  local provider="$1"
  case "$provider" in
    anthropic)
      jq -r '.data[] | [ .id, (.display_name // "-"), (.max_input_tokens // "-"), "-", "-",
        (if .lifecycle == "deprecated" then "D" else "" end) ] | @tsv'
    ;;
    cyberneurova)
      jq -r '.data[] | [ .id, (.display_name // "-"), (.context_length // "-"), "-", "-",
        ([ (if .supports_image_in then "V" else "" end),
            (if .supports_reasoning then "R" else "" end),
            (if .supports_tool_use then "T" else "" end) ] | join("")) ] | @tsv'
    ;;
    deepseek)
      jq -r '.data[] | [ .id, (.name // "-"), (.context_window // "-"), "-", "-",
        ([ (if ((.input_modalities // []) | index("image")) then "V" else "" end),
            (if .effort then "R" else "" end) ] | join("")) ] | @tsv'
    ;;
    groq)
      jq -r '.data[] | [ .id, (.name // "-"), (.context_window // "-"), "-", "-",
        ([ (if ((.input_modalities // []) | index("image")) then "V" else "" end),
            (if ((.output_modalities // []) | index("speech")) then "S" else "" end),
            (if ((.output_modalities // []) | index("transcription")) then "A" else "" end),
            (if .active == false then "D" else "" end) ] | join("")) ] | @tsv'
    ;;
    inception)
      jq -r '.data[] | [ .id, (.name // "-"), (.context_window // "-"), "-", "-",
        ([ (if ((.input_modalities // []) | index("image")) then "V" else "" end),
            (if ((.output_modalities // []) | index("speech")) then "S" else "" end),
            (if ((.output_modalities // []) | index("transcription")) then "A" else "" end),
            (if .active == false then "D" else "" end) ] | join("")) ] | @tsv'
    ;;
    huggingface)
      # Raw array, 1000+ models: top 50 by downloads, the rest is noise.
      jq -r 'sort_by(-(.downloads // 0))[:50][] | [ (.modelId // .id // "?"),
        "-", "-", "-", "-",
        ([ (if .downloads then "dl:" + ((.downloads / 1000000 * 10 | round / 10 | tostring) + "M") else "" end),
            (if .likes then "♥" + (.likes | tostring) else "" end) ] | join(" ")) ] | @tsv'
    ;;
    kimi)
      jq -r '.data[] | [ .id, .id, (.context_length // "-"), "-", "-",
        ([ (if .supports_image_in then "V" else "" end),
            (if .supports_reasoning then "R" else "" end) ] | join("")) ] | @tsv'
    ;;
    mammouth)
      jq -r '.data[] | [ .id, .id, (.model_info.max_input_tokens // "-"),
        (if .model_info.input_cost_per_token then (.model_info.input_cost_per_token * 1000000) else "-" end),
        (if .model_info.output_cost_per_token then (.model_info.output_cost_per_token * 1000000) else "-" end), "-" ] | @tsv'
    ;;
    openai)
      jq -r '.data[] | [ .id, .id, "-", "-", "-",
        (if .shutdown_date then "D:" + .shutdown_date else "" end) ] | @tsv'
    ;;
    openroute)
      jq -r '.data[] | [ .id, (.display_name // "-"), (.context_length // "-"),
        (if .pricing.prompt then ((.pricing.prompt | tonumber) * 1000000) else "-" end),
        (if .pricing.completion then ((.pricing.completion | tonumber) * 1000000) else "-" end),
        ([ (if ((.input_modalities // []) | index("image")) then "V" else "" end),
            (if .supports_reasoning then "R" else "" end),
            (if .supports_tool_use then "T" else "" end),
            (if ((.badges // []) | index("uncensored")) then "U" else "" end) ] | join("")) ] | @tsv'
    ;;
    openrouter*)
      # jq -r '.data[] | [ .id, (.name // "-"), (.context_length // "-"),
      jq -r '.data[] | [ .id, "-", (.context_length // "-"),
        (if .pricing.prompt then ((.pricing.prompt | tonumber) * 1000000) else "-" end),
        (if .pricing.completion then ((.pricing.completion | tonumber) * 1000000) else "-" end),
        ([ (if ((.architecture.input_modalities // []) | index("image")) then "V" else "" end),
            (if ((.pricing.prompt | tonumber) == 0 and (.pricing.completion | tonumber) == 0) then "F" else "" end) ] | join("")) ] | @tsv'
    ;;
    venice)
      jq -r '.data[] | [ .id, (.model_spec.name // "-"),
        (.model_spec.availableContextTokens // .context_length // "-"),
        (.model_spec.pricing.input.usd // "-"), (.model_spec.pricing.output.usd // "-"),
        ([ (if (.model_spec.capabilities.supportsFunctionCalling // false) then "T" else "" end),
            (if (.model_spec.capabilities.supportsReasoning // false) then "R" else "" end),
            (if ((.type // "text") != "text") then (.type | .[0:1] | ascii_upcase) else "" end) ] | join("")) ] | @tsv'
    ;;
    vercel*)
      jq -r '.data[] | [ .id, (.name // "-"), (.context_window // "-"), "-", "-",
        ([ (if ((.tags // []) | index("vision")) then "V" else "" end),
            (if ((.tags // []) | index("reasoning")) then "R" else "" end),
            (if ((.tags // []) | index("tool-use")) then "T" else "" end),
            (if ((.tags // []) | index("free")) then "F" else "" end),
            (if ((.tags // []) | index("open-weights")) then "W" else "" end) ] | join("")) ] | @tsv'
    ;;
    xai)
      jq -r '.data[] | [ .id, (.name // "-"), (.context_length // "-"), "-", "-",
        ([ (if ((.input_modalities // []) | index("image")) then "V" else "" end),
            (if ((.output_modalities // []) | index("speech")) then "S" else "" end),
            (if ((.output_modalities // []) | index("transcription")) then "A" else "" end),
            (if .active == false then "D" else "" end) ] | join("")) ] | @tsv'
    ;;
    zai*)
      jq -r '.data[] | [ .id, .id, "-", "-", "-", "-" ] | @tsv'
    ;;
    *)
      # Unknown structure: best-effort extraction on universal keys.
      jq -r 'if type == "object" then (.data // .models // [.] )[] else .[] end |
        [ (.id // .modelId // "?"), "-", "-", "-", "-", "-" ] | @tsv'
    ;;
  esac
}

# -----------------------------------------------------------------------------
# Human rendering: TSV (id|model|ctx|$/M in|$/M out|flags) -> aligned table.
# Column widths computed dynamically, free pricing in green, deprecated
# models in red. No external dependency.
# -----------------------------------------------------------------------------
render_models_table() {
  local -a rows ; rows=()
  local _row
  while IFS= read -r _row; do rows+=("$_row"); done   # Bash 3.2 trick for macOS
  [[ ${#rows[@]} -eq 0 ]] && { log_warn "No models found in catalogue." ; return 0 ; }

  local -a hdr ; hdr=(ID NAME CONTEXT '$/M IN' '$/M OUT' FLAGS)
  local -a w ; w=() ; local line f i len
  for i in 0 1 2 3 4 5 ; do w[i]=${#hdr[i]} ; done
  for line in "${rows[@]}" ; do
    IFS=$'\t' read -ra f <<<"$line"
    for i in 0 1 2 3 4 5 ; do
      len=${#f[i]} ; (( len > w[i] )) && w[i]=$len
    done
  done

  local sep="" ; for ((i=0; i<w[0]+w[1]+w[2]+w[3]+w[4]+w[5]+10; i++)) ; do sep+="─" ; done

  printf "${CLR_B_CYAN}%-*s  %-*s  %*s  %*s  %*s  %s${ANSI_RESET}\n" \
    "${w[0]}" "${hdr[0]}" "${w[1]}" "${hdr[1]}" "${w[2]}" "${hdr[2]}" \
    "${w[3]}" "${hdr[3]}" "${w[4]}" "${hdr[4]}" "${hdr[5]}"
  log "$sep"

  local id name ctx pin pout flags free deprecated c_in c_id
  for line in "${rows[@]}" ; do
    IFS=$'\t' read -r id name ctx pin pout flags <<<"$line" || true
    free=$([[ $flags == *F* ]] && echo 1 || echo 0)
    deprecated=$([[ $flags == *D* ]] && echo 1 || echo 0)
    pin=$([[ $pin == "-" || -z $pin ]] && echo "-" || printf '%g' "$pin")
    pout=$([[ $pout == "-" || -z $pout ]] && echo "-" || printf '%g' "$pout")
    c_in=$ANSI_RESET ; c_id=$ANSI_RESET
    [[ $free == 1 ]] && c_in=$CLR_B_GREEN
    [[ $deprecated == 1 ]] && c_id=$CLR_B_RED
    printf "%b%-*s${ANSI_RESET}  %-*s  %*s  %b%*s${ANSI_RESET}  %*s  %s\n" \
      "$c_id" "${w[0]}" "$id" "${w[1]}" "$name" "${w[2]}" "$ctx" \
      "$c_in" "${w[3]}" "$pin" "${w[4]}" "$pout" "$flags"
  done
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
      log "          U=uncensored I=image (venice non-text)"
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

    # Handling model resolving
    [[ -n $resolved_model && ! $resolved_model == "null" && ! $output_stream == "silent" ]] && log "\n✨ [Resolved Model] -> ${CLR_B_CYAN}${resolved_model}${ANSI_RESET}"

    # Output thinking (reasoning) if present
    if [[ $SHOW_THINKING == true ]]; then
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

render_markdown() {
  if command -v glow &>/dev/null; then
    glow -w "$(get_term_width)"
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
  local dynamic_system
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local PAYLOAD_MESSAGES
  local ALL_MESSAGES="[]"
  local errors=0
  local output="silent"

  log_brain "Initiating AUTONOMOUS CONSOLIDATION cycle (Subconscious State)..."

  [[ $DEBUG == true ]] && output="stdout"

  # Normalize on load: a poisoned history must never reach the wire (see normalize_history)
  [[ -r $messages_path ]] && ALL_MESSAGES=$(normalize_history "$(<"$messages_path")")
  [[ -z $ALL_MESSAGES ]] && ALL_MESSAGES="[]"

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
  run_inference_loop "$CHAT_MODEL" "$PAYLOAD_MESSAGES" "all" "true" "$output" "false" "[CONSOLIDATION_COMPLETE]" "$ALL_MESSAGES" || \
    errors=1

  # Prune main context: Keep only the system prompt + last 2 turns of the original conversation
  if [[ $errors -eq 0 ]]; then
    log ; log_brain "Pruning active messages log to release token pressure..."
    if [[ -r $messages_path ]]; then
      jq -rc '([.[].role] | reverse | index("user")) as $ri | if $ri then .[length - $ri - 1:] else [] end' "$messages_path" > "${messages_path}.tmp" 2>/dev/null || echo "[]" > "${messages_path}.tmp"
      mv -f "${messages_path}.tmp" "$messages_path"
    else
      echo "[]" > "$messages_path"
    fi
    log_success "Main conversation context successfully refreshed!"
  else
    log ; log_warn "Unexpected error detected! Preserving conversation history."
  fi
}

check_and_trigger_heartbeat() {
  local forced="${1:-false}"
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local messages_count=0
  if [[ -r $messages_path ]]; then
    messages_count=$(jq -rc 'map(select(.role == "user")) | length' "$messages_path" 2>/dev/null || echo 0)
  fi

  if [[ $forced == "true" ]] || (( messages_count >= HEARTBEAT_THRESHOLD )); then
    log_brain "Heartbeat threshold pulsing (Messages: ${messages_count}/${HEARTBEAT_THRESHOLD} | Forced: ${forced})."
    consolidate_memory
  fi
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
  if [[ -x "$jarnet_bin" ]]; then
    log_info "Checking JarNet service..."
    # 'up' makes sure that hidden service Tor and local listener are active
    "$jarnet_bin" up &>/dev/null

    # Get hidden service address and onboarding token
    local who_json ; who_json=$("$jarnet_bin" who 2>/dev/null)
    local my_addr ; my_addr=$(jq -r '.onion // empty' <<< "$who_json" 2>/dev/null)
    local my_onboarding ; my_onboarding=$(jq -r '.share // empty' <<< "$who_json" 2>/dev/null)

    # Show hidden service address and onboarding token
    if [[ -n $my_addr ]]; then
      log_success "JarNet online: ${CLR_B_YELLOW}${my_addr}.onion${ANSI_RESET}"
      log_info "Onboarding token: ${ANSI_BOLD}${CLR_B_WHITE}${my_onboarding}${ANSI_RESET} (copy/paste to peer)"
    else
      log_warn "JarNet offline: Please run './${PLUG_DIR##*/}/${jarnet_bin##*/} doctor' to find out why."
      return 1
    fi
  else
    log_warn "Plugin JarNet not found (${jarnet_bin}), P2P listening disabled."
    return 1
  fi

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
        log_info "${ICON_MAIL} JarNet: ${CLR_B_GREEN}${new_count}${ANSI_RESET} new message(s) received!"

        # Handling received message
        local i=0
        while (( i < new_count )); do
          local peer_from peer_sid peer_reply_to peer_mid peer_ts peer_body
          local msg_json ; msg_json=$(jq -c ".messages[$i]" <<< "$inbox_json" 2>/dev/null)
          peer_from=$(jq -r '.envelope.from // "unknown"' <<< "$msg_json" 2>/dev/null)
          peer_sid=$(jq -r '.envelope.sid // empty' <<< "$msg_json" 2>/dev/null)
          # peer_reply_to=$(jq -r '.envelope.reply_to // empty' <<< "$msg_json" 2>/dev/null)
          peer_mid=$(jq -r '.envelope.mid // empty' <<< "$msg_json" 2>/dev/null)
          peer_ts=$(jq -r '.envelope.ts // empty' <<< "$msg_json" 2>/dev/null)
          peer_body=$(jq -r '.envelope.body // empty' <<< "$msg_json" 2>/dev/null)

          log_step "Message from [${CLR_B_CYAN}${peer_from}${ANSI_RESET}] (SID: ${peer_sid:-none}):"
          echo -e "${CLR_DIM}> ${peer_body}${ANSI_RESET}\n"

          # ANTI-LOOP GUARD (Golden rule for 'auto' mode) :
          # NEVER reply automatically to a message generated by a bot / auto-reply
          if [[ "$peer_body" =~ ^\[AUTO\] || "$peer_body" =~ ^\[BOT\] ]]; then
            log_warn "Anti-loop Guard: message identified as automatic. No reply generated."
          elif [[ -n "$peer_reply_to" || -n "$peer_sid" ]]; then
            log_info "Generating autonomous response for ${peer_from}..."

            # Build LLM prompt
            local agent_prompt="You are ${AI_NAME} in autonomous mode. You just received this message on JarNet from peer '${peer_from}':\n\n\`\`\`\n${peer_body}\n\`\`\`\n\nReply it politely, concise and pertinently while indicating if necessary that you're replying in autonomous mode. Don't use \`\`\` around your message."

            # Run inference via pipeline primitives
            # Note: using run_inference_loop or send_message
            local reply_output
            # Generating response via active model
            printf "%s" "$agent_prompt" > "$TEMP_MEMORY_USER"
            local payload_msg ; payload_msg=$(jq -rc -n --rawfile u "$TEMP_MEMORY_USER" '[{role: "user", content: $u}]')

            # Disable animation spinner before replying (got swallowed in the reply somehow...)
            USE_ANIMATE=false

            # LLM Call (capture the text response)
            reply_output=$(run_inference_loop "$CHAT_MODEL" "$payload_msg" "none" "false" "stderr" "false" "" "$payload_msg" 2>/dev/null)

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
# JarNet Init
# -----------------------------------------------------------------------------

jarnet_start() {
  local jarnet_bin="$NET_HANDLER"

  # Check / Start JarNet transport stack
  if [[ -x "$jarnet_bin" ]]; then
    log_info "Checking JarNet service..."
    # 'up' makes sure that hidden service Tor and local listener are active
    "$jarnet_bin" up &>/dev/null

    # Get hidden service address and onboarding token
    local who_json ; who_json=$("$jarnet_bin" who 2>/dev/null)
    local my_addr ; my_addr=$(jq -r '.onion // empty' <<< "$who_json" 2>/dev/null)
    local my_onboarding ; my_onboarding=$(jq -r '.share // empty' <<< "$who_json" 2>/dev/null)

    # Show hidden service address and onboarding token
    if [[ -n $my_addr ]]; then
      log_success "JarNet online: ${CLR_B_YELLOW}${my_addr}.onion${ANSI_RESET}"
      log_info "Onboarding token: ${ANSI_BOLD}${CLR_B_WHITE}${my_onboarding}${ANSI_RESET} (copy/paste to peer)"
    else
      log_warn "JarNet offline: Please run './${PLUG_DIR##*/}/${jarnet_bin##*/} doctor' to find out why."
      return 1
    fi
  else
    log_warn "Plugin JarNet not found (${jarnet_bin}), P2P listening disabled."
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Initializing
# -----------------------------------------------------------------------------

# Check required dependencies
check_deps

# Load required libraries
load_libs

# Load config
load_config_file

# Set terminal dimensions
set_term_width

# -----------------------------------------------------------------------------
# Public Functions
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
  ${CLR_B_GREEN}--thinking <boolean>${ANSI_RESET}       Set AI model reasoning display
  ${CLR_B_GREEN}--effort <level>${ANSI_RESET}           Set AI model reasoning effort (none, minimal, low, medium, high, xhigh, max) -- default: $REASONING_EFFORT
  ${CLR_B_GREEN}--memory <type>${ANSI_RESET}            Set AI memory structure type (full, index) -- default: $MEMORY_STRUCTURE_TYPE
  ${CLR_B_GREEN}--server <type>${ANSI_RESET}            Start backend API server (ollama, llamacpp, whispercpp, web)
  ${CLR_B_GREEN}--launch <app> [path]${ANSI_RESET}      Start given application with existing backend / provider
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
  ${CLR_B_GREEN}thinking <boolean>${ANSI_RESET}         Set AI model reasoning display
  ${CLR_B_GREEN}effort <level>${ANSI_RESET}             Set AI model reasoning effort (none, minimal, low, medium, high, xhigh, max) -- default: $REASONING_EFFORT
  ${CLR_B_GREEN}memory <type>${ANSI_RESET}              Set AI memory structure type (full, index) -- default: $MEMORY_STRUCTURE_TYPE
  ${CLR_B_GREEN}server <type>${ANSI_RESET}              Start backend API server (ollama, llamacpp, whispercpp, web)
  ${CLR_B_GREEN}launch <app> [path]${ANSI_RESET}        Start given application with existing backend / provider
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
# System Functions
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
      --thinking|thinking) SHOW_THINKING="${2:-}" ; shift 2 ;;
      --effort|effort) REASONING_EFFORT="${2:-}" ; shift 2 ;;
      --memory|memory) MEMORY_STRUCTURE_TYPE="${2:-}" ; shift 2 ;;
      --detect|detect) DETECT_MODE="${2:-}" ; shift 2 ;;
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

  # Fix Iterations for Termux
  if is_termux; then
    PBKDF_ITERATIONS=$((PBKDF_ITERATIONS/2))
  fi

  # Create required folders
  create_local_model_cache
  create_local_data_store

  # Setup core
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
  if [[ $BACKEND == "external" ]]; then
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
