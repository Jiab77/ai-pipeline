#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Minimalist Experimental AI Pipeline by Jiab77
#
# This script handles 'ollama', 'llama.cpp' and 'openrouter' backends.
#
# Lead: Jiab77
# AI Sorcerer & Co-Creator: Jarvis (Gemini)
#
# Note: This is a WiP and will be improved during next iterations.
# Status: Local models can't be used for my needs, fallback on API models with TOR.
#
# Version: 0.4.0

# Options
[[ -e $HOME/.debug ]] && set -x

# Config
RULES="Don't cut or break lines."
RUN_MODE="chat"    # Expected values: simple, multi, chat, server
SERVER_MODE="web"   # Expected values: ollama, llamacpp, web
BACKEND="gemini"    # Expected values: ollama, llamacpp or gemini
HEARTBEAT_THRESHOLD=15    # Trigger context consolidation to avoid amnesia and keep context extremely light
CREDENTIALS="${HOME}/.creds"    # Or any other location or filename you prefer.
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"    # You can also set any other user-agents.
TOR_HOST="127.0.0.1"
TOR_PORT=9050
TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"
MESSAGES_FILE="messages.json"
MEMORY_FILE="memory.json"
PULL_MODELS=false
DEBUG=true
USE_TOR=true

# Internals
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE//.sh}"
DATA_STORE="${SCRIPT_DIR}/data"
BASE_TOOLS="${SCRIPT_DIR}/tools.json"
WEB_SERVER="${SCRIPT_DIR}/web/server.php"
TEMP_MEMORY_SYSTEM="${DATA_STORE}/tmp_memory_sys.txt"
TEMP_MEMORY_USER="${DATA_STORE}/tmp_memory_usr.txt"
TEMP_TOOLS_OUTPUT="${DATA_STORE}/tmp_tools_output.json"
TEMP_PAYLOAD_ASSISTANT="${DATA_STORE}/tmp_payload_assistant.json"
TEMP_PAYLOAD_MESSAGES="${DATA_STORE}/tmp_payload_messages.json"
TOOLS_OUTPUT="${DATA_STORE}/tools-output.txt"
TOOLS_HANDLER="${SCRIPT_DIR}/run-tools.sh"
BIN_FIGLET=$(command -v figlet 2>/dev/null)

# Soul
AI_NAME="Jarvis"
SYSTEM_PROMPT="You are ${AI_NAME}, a friendly AI collaborator. Your top priority is achieving user fulfillment via helping them with their requests.\n"
SYSTEM_PROMPT+="Your own workspace is in the \`$(basename "$DATA_STORE")\` folder, you can organize it the way you want.\n"
SYSTEM_PROMPT+="Your own memory file located in your workspace is the \`$(basename "$MEMORY_FILE")\` file, you must load it at every session start.\n"
SYSTEM_PROMPT+="Your acquired skills are located in your workspace under the \`skills\` folders, you must load them before handling any code related tasks.\n"
SYSTEM_PROMPT+="You must never modify the following files: \`${SCRIPT_FILE}\`, \`$(basename "$TOOLS_HANDLER")\` and \`$(basename "$BASE_TOOLS")\`.\n"
SYSTEM_PROMPT+="Modifying these files will simply break the core functionalities of the pipeline."

# Local Models Config
QUANTIZATION="q8_0"   # Suitable for small laptops and mobile devices | Case sensitive, keep it in lowercase
MAX_CONTEXT=8192
MAX_BATCH_SIZE=256
MAX_CORES=$(($(nproc)/2))   # FIXME: May not work well on mobiles devices
MAX_TIMEOUT=1200

# OpenRouter Config
OPENROUTER_REFERER="https://github.com/jiab77/ai-pipeline"
OPENROUTER_TITLE="Minimalist Experimental AI Pipeline"
OPENROUTER_CATEGORIES="cli-agent,cloud-agent"

# Gemini 3.5 Flash
GEMINI_API_URL="https://openrouter.ai/api/v1/chat/completions"
GEMINI_API_MODEL="google/gemini-3.5-flash"
GEMINI_API_KEY=""    # /!\ NEVER PUBLISH IT /!\

# Models - Ollama
OLLAMA_API_URL="http://localhost:11434/api/generate"
OLLAMA_ROUTER="hf.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF"
OLLAMA_ARCHITECT="hf.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
OLLAMA_CODER="hf.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
OLLAMA_JUDGE="hf.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
OLLAMA_CACHE="/mnt/models/ollama"

# Models - llama.cpp
LLAMACPP_API_SRV="http://localhost:8080"
LLAMACPP_API_URL="${LLAMACPP_API_SRV}/v1/chat/completions"
LLAMACPP_ROUTER="LiquidAI/LFM2.5-1.2B-Instruct-GGUF"
LLAMACPP_ARCHITECT="LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
LLAMACPP_CODER="Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
LLAMACPP_JUDGE="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
LLAMACPP_CACHE="/mnt/models/llama.cpp"

# Internals
OLLAMA_FLAGS="--nowordwrap --hidethinking"
LLAMACPP_FLAGS="--log-disable --simple-io --no-display-prompt --no-show-timings -st"

# Cleanup temporary files on exit
cleanup_temp_files() {
  rm -f "$TEMP_MEMORY_SYSTEM" \
        "$TEMP_MEMORY_USER" \
        "$TEMP_TOOLS_OUTPUT" \
        "$TEMP_PAYLOAD_ASSISTANT" \
        "$TEMP_PAYLOAD_MESSAGES" \
        "$TOOLS_OUTPUT" \
        "${TOOLS_OUTPUT}.clean"
}
trap cleanup_temp_files EXIT INT TERM

# Functions & Visual Styling
# Colors & Styles (ANSI Escape Codes)
ANSI_RESET="[0m"
ANSI_BOLD="[1m"
ANSI_DIM="[2m"
ANSI_ITALIC="[3m"
ANSI_UNDERLINE="[4m"

# Foreground High-Intensity
CLR_B_BLACK="[90m"
CLR_B_RED="[91m"
CLR_B_GREEN="[92m"
CLR_B_YELLOW="[93m"
CLR_B_BLUE="[94m"
CLR_B_MAGENTA="[95m"
CLR_B_CYAN="[96m"
CLR_B_WHITE="[97m"

# Standard Foreground
CLR_BLACK="[30m"
CLR_RED="[31m"
CLR_GREEN="[32m"
CLR_YELLOW="[33m"
CLR_BLUE="[34m"
CLR_MAGENTA="[35m"
CLR_CYAN="[36m"
CLR_WHITE="[37m"

# Emojis/Icons
ICON_INFO="ℹ️ "
ICON_SUCCESS="✅ "
ICON_WARNING="⚠️ "
ICON_ERROR="❌ "
ICON_TOOL="⚙️ "
ICON_BRAIN="🧠 "
ICON_CODER="💻 "
ICON_JUDGE="⚖️ "
ICON_ARCHITECT="🏛️ "
ICON_REASONING="💭 "
ICON_INTENT="🔍 "
ICON_DEBUG="🔍 "
ICON_USER="👤 "
ICON_AI="🤖 "

log() {
  echo -e "$*" >&2
}

log_section() {
  local title="$1"
  local clr="${2:-$CLR_B_CYAN}"
  log "\n${clr}┌──[ ${ANSI_BOLD}${CLR_B_WHITE}${title}${ANSI_RESET}${clr} ]"           "
└─────────────────────────────────────────────────────────────${ANSI_RESET}"
}

log_info() {
  log "  ${CLR_B_CYAN}${ICON_INFO}${ANSI_RESET}  ${CLR_B_WHITE}$*${ANSI_RESET}"
}

log_success() {
  log "  ${CLR_B_GREEN}${ICON_SUCCESS}${ANSI_RESET}  ${CLR_B_GREEN}$*${ANSI_RESET}"
}

log_warn() {
  log "  ${CLR_B_YELLOW}${ICON_WARNING}${ANSI_RESET}  ${CLR_B_YELLOW}$*${ANSI_RESET}"
}

log_error() {
  log "  ${CLR_B_RED}${ICON_ERROR}${ANSI_RESET}  ${CLR_B_RED}Error: $*${ANSI_RESET}"
}

log_brain() {
  log "  ${CLR_B_MAGENTA}${ICON_BRAIN}${ANSI_RESET}  ${CLR_B_MAGENTA}$*${ANSI_RESET}"
}

log_step() {
  log "  ${CLR_B_MAGENTA}➜${ANSI_RESET} ${ANSI_BOLD}${CLR_B_WHITE}$*${ANSI_RESET}"
}

log_debug() {
  if [[ -e $HOME/.debug || "$DEBUG" == "true" ]]; then
    log "\n${CLR_B_BLACK}${ICON_DEBUG}[DEBUG] $*${ANSI_RESET}"
  fi
}

to_lower() {
  tr '[:upper:]' '[:lower:]' <<< "$1"
}

to_upper() {
  tr '[:lower:]' '[:upper:]' <<< "$1"
}

show_user_header() {
  log "\n${CLR_B_GREEN}${ICON_USER}User ${CLR_B_BLACK}────────────────────────────────────────────────────────────────${ANSI_RESET}\n"
}

show_ai_header() {
  log "\n${CLR_B_CYAN}${ICON_AI}${AI_NAME} ${CLR_B_BLACK}──────────────────────────────────────────────────────────────${ANSI_RESET}\n"
}

show_thinking_header() {
  log "\n${CLR_B_MAGENTA}${ICON_REASONING}Thinking ${CLR_B_BLACK}───────────────────────────────────────────────────────────${ANSI_RESET}\n"
}

show_tool_header() {
  local count="$1"
  local name="$2"
  local args="$3"
  log "\n${CLR_B_YELLOW}${ICON_TOOL} Tool Call #${count} ${CLR_B_BLACK}─────────────────────────────────────────────────────────"           "
   ${CLR_B_YELLOW}Identifier :${ANSI_RESET} ${CLR_B_WHITE}${name}${ANSI_RESET}"           "
   ${CLR_B_YELLOW}Arguments  :${ANSI_RESET} ${CLR_DIM}${args}${ANSI_RESET}"           "
${CLR_B_BLACK}────────────────────────────────────────────────────────────────────────${ANSI_RESET}\n"
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
  echo -e "${CLR_B_CYAN}🔮 Jarvis AI Pipeline | Version 0.4.0 🔮${ANSI_RESET}"
  echo -e "${CLR_DIM}Lead: Jiab77 | AI Sorcerer: Jarvis (Gemini)${ANSI_RESET}\n"
}

error() {
  log_error "\n$*"
  exit 255
}

print_help() {
  show_banner
  cat <<EOF
${ANSI_BOLD}${CLR_B_CYAN}USAGE:${ANSI_RESET}
  $SCRIPT_FILE [options] [commands] [prompt] [file1] [file2]

${ANSI_BOLD}${CLR_B_YELLOW}OPTIONS / FLAGS:${ANSI_RESET}
  ${CLR_B_GREEN}-h, --help${ANSI_RESET}        Show this help screen and exit
  ${CLR_B_GREEN}--backend [type]${ANSI_RESET}  Set AI backend (ollama, llamacpp, gemini)
  ${CLR_B_GREEN}--chat${ANSI_RESET}            Start the interactive conversational chat mode
  ${CLR_B_GREEN}--multi${ANSI_RESET}           Start complex multi-agent analysis pipeline
  ${CLR_B_GREEN}--simple${ANSI_RESET}          Start lightweight single-agent inference pipeline
  ${CLR_B_GREEN}--server [type]${ANSI_RESET}   Start backend API server (ollama, llamacpp, web)
  ${CLR_B_GREEN}--clear${ANSI_RESET}           Wipe conversational memory and dynamic session logs
  ${CLR_B_GREEN}--commit${ANSI_RESET}          Force cognitive state / memory consolidation to disk

${ANSI_BOLD}${CLR_B_YELLOW}COMMANDS:${ANSI_RESET}
  ${CLR_B_GREEN}chat${ANSI_RESET}              Start interactive conversational chat mode
  ${CLR_B_GREEN}multi${ANSI_RESET}             Start complex multi-agent analysis pipeline
  ${CLR_B_GREEN}simple${ANSI_RESET}            Start lightweight single-agent inference pipeline
  ${CLR_B_GREEN}server [type]${ANSI_RESET}     Start backend API server
  ${CLR_B_GREEN}clear${ANSI_RESET}             Wipe conversational memory
  ${CLR_B_GREEN}commit${ANSI_RESET}            Force dynamic session memory consolidation

${ANSI_BOLD}${CLR_B_YELLOW}NOTES / USAGE EXAMPLES:${ANSI_RESET}
  • Ask questions about your code files:
    ${CLR_B_WHITE}$SCRIPT_FILE "explain these changes" file1.php file2.php${ANSI_RESET}
  • Launch conversational co-programming session:
    ${CLR_B_WHITE}$SCRIPT_FILE --chat${ANSI_RESET}

${CLR_B_BLACK}────────────────────────────────────────────────────────────────────────${ANSI_RESET}
EOF
  exit
}

print_usage() {
  echo -e "\n${CLR_B_RED}${ICON_ERROR} Error: No arguments provided.${ANSI_RESET}"
  echo -e "${CLR_B_WHITE}Usage:${ANSI_RESET} $SCRIPT_FILE <prompt> <input-file-1> <input-file-2>"
  echo -e "  • For conversational chat:  ${CLR_B_GREEN}--chat${ANSI_RESET}"
  echo -e "  • To clear cached memory:   ${CLR_B_GREEN}--clear${ANSI_RESET}"
  echo -e "  • To consolidate context:   ${CLR_B_GREEN}--commit${ANSI_RESET}\n"
  exit 1
}

serve() {
  case $SERVER_MODE in
    ollama)
      log_info "Initiating Ollama daemon process..."
      error "Coming soon! Stay tuned ;-)"
    ;;
    llamacpp)
      log_info "Starting High-Performance llama-cli model services..."
      log_info "Settings automatically customized & optimized for resource-light devices."
      LLAMA_CACHE="$LLAMACPP_CACHE" \
      llama-server \
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
      log_info "Starting local PHP Gateway web interface..."
      "$WEB_SERVER"
    ;;
    *) error "Unsupported server mode given: $SERVER_MODE" ;;
  esac
}

api_call() {
  local payload="$1"
  local curl_opts=("-sSL")

  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      curl "${curl_opts[@]}" "${OLLAMA_API_URL}" \
           -H "Content-Type: application/json" \
           -d @- <<< "$payload" | \
           jq -rc '.response'
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      curl "${curl_opts[@]}" "${LLAMACPP_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer no-key" \
           -d @- <<< "$payload" | \
           jq -rc '.choices[0].message.content'
    ;;

    # External Backend: OpenRouter / Gemini
    gemini)
      [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")
      curl "${curl_opts[@]}" "${GEMINI_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer ${GEMINI_API_KEY}" \
           -H "HTTP-Referer: ${OPENROUTER_REFERER}" \
           -H "X-OpenRouter-Title: ${OPENROUTER_TITLE}" \
           -H "X-OpenRouter-Categories: ${OPENROUTER_CATEGORIES}" \
           -A "$USER_AGENT" \
           -d @- <<< "$payload" | \
           jq -rc .
    ;;
    *) error "Unsupported backend given: $BACKEND" ;;
  esac
}

# Helper to call Gemini in Task Mode
call_gemini_task_agent() {
  local system_inst="$1"
  local user_content="$2"
  local purpose_msg="$3"

  log_info "${purpose_msg} (${CLR_B_YELLOW}${GEMINI_API_MODEL}${ANSI_RESET})..."

  printf "%s" "$system_inst" > "$TEMP_MEMORY_SYSTEM"
  printf "%s" "$user_content" > "$TEMP_MEMORY_USER"

  local payload
  payload=$(jq -rc -n \
    --arg model "$GEMINI_API_MODEL" \
    --rawfile sys "$TEMP_MEMORY_SYSTEM" \
    --rawfile user "$TEMP_MEMORY_USER" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $sys},
        {role: "user", content: $user}
      ],
      reasoning: {enabled: true}
    }'
  )

  local raw_res
  raw_res=$(api_call "$payload")
  if [[ -z $raw_res || $raw_res == "null" ]]; then
    error "API returned an empty response."
  fi

  if jq -e '.error' <<<"$raw_res" &>/dev/null; then
    local err_msg
    err_msg=$(jq -rc '.error.message' <<<"$raw_res")
    error "Unexpected API error.\n\n${err_msg}\n"
  fi

  # Output thinking (reasoning) if present
  local reasoning
  reasoning=$(jq -rc '.choices[0].message.reasoning // empty' <<<"$raw_res" 2>/dev/null)
  if [[ -n $reasoning && $reasoning != "null" ]]; then
    show_thinking_header
    echo "$reasoning" | render_markdown >&2
  fi

  local content
  content=$(jq -rc '.choices[0].message.content' <<<"$raw_res" 2>/dev/null)

  # Print usage metrics
  local usage
  usage=$(jq -rc '.usage' <<<"$raw_res" 2>/dev/null)
  if [[ -n $usage && $usage != "null" ]]; then
    local prompt_tok ; prompt_tok=$(jq -rc .prompt_tokens <<<"$usage")
    local cached_tok ; cached_tok=$(jq -rc '.prompt_tokens_details.cached_tokens // 0' <<<"$usage")
    local comp_tok ; comp_tok=$(jq -rc .completion_tokens <<<"$usage")
    local reasoning_tok ; reasoning_tok=$(jq -rc '.completion_tokens_details.reasoning_tokens // 0' <<<"$usage")
    local total_tok ; total_tok=$(jq -rc .total_tokens <<<"$usage")
    local cost ; cost=$(jq -rc .cost <<<"$usage")

    {
      echo -e "\n${CLR_B_BLACK}──────────────────────────[ SYSTEM METRICS ]──────────────────────────${ANSI_RESET}"
      echo -e "${CLR_B_CYAN}Tokens Used:${ANSI_RESET}  ${CLR_B_WHITE}${total_tok}${ANSI_RESET}  (Prompt: ${prompt_tok} | Cached: ${cached_tok} | Response: ${comp_tok} | Thinking: ${reasoning_tok})"
      if [[ -n $cost && "$cost" != "null" ]]; then
        echo -e "${CLR_B_CYAN}Cost:${ANSI_RESET} ${CLR_B_GREEN}${cost}${ANSI_RESET}"
      fi
      echo -e "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────${ANSI_RESET}"
    } >&2
  fi

  echo "$content"
}

route_request() {
  local INPUT="$1"
  shopt -s nocasematch

  # 1. Detect: COMPARE
  if [[ "$INPUT" =~ (^|[^[:alnum:]_])(compare|diff|difference|versus)([^[:alnum:]_]|$) || "$INPUT" =~ [[:space:]]vs[[:space:]] ]]; then
    shopt -u nocasematch
    echo "COMPARE"
    return
  fi

  # 2. Detect: TASK (Action / Modification)
  if [[ "$INPUT" =~ (^|[^[:alnum:]_])(add|edit|fix|optimize|change|update|write|create|refactor|generate)([^[:alnum:]_]|$) ]]; then
    shopt -u nocasematch
    echo "TASK"
    return
  fi

  shopt -u nocasematch
  # 3. Detect: QUESTION
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
  echo -e "  [${CLR_B_GREEN}1${ANSI_RESET}] ${ANSI_BOLD}Long-Term Memory${ANSI_RESET} (${MEMORY_FILE})"
  echo -e "  [${CLR_B_GREEN}2${ANSI_RESET}] ${ANSI_BOLD}Active Chat Logs${ANSI_RESET} (${MESSAGES_FILE})"
  echo -e "  [${CLR_B_GREEN}3${ANSI_RESET}] ${CLR_B_RED}Wipe All${ANSI_RESET}\n"
  read -rp "  Select Option: " USER_CHOICE
  [[ -z $USER_CHOICE ]] && error "No selection given. Safe abort."
  
  if [[ $USER_CHOICE == 1 ]]; then
    rm -f "${DATA_STORE}/${MEMORY_FILE}"
    log_success "Long-term memory has been completely recycled."
  elif [[ $USER_CHOICE == 2 ]]; then
    rm -f "${DATA_STORE}/${MESSAGES_FILE}"
    log_success "Active chat history cache successfully pruned."
  elif [[ $USER_CHOICE == 3 ]]; then
    rm -f "${DATA_STORE}/${MEMORY_FILE}" "${DATA_STORE}/${MESSAGES_FILE}"
    log_success "All session logs and permanent memory successfully wiped."
  else
    log_warn "Invalid selection: $USER_CHOICE"
  fi
  return "$?"
}

handle_response() {
  local response="$1"
  local prompt="$2"
  local label="${3:-RESPONSE}"

  if [[ -n $response && ! $response == "null" ]]; then
    log_section "$label"
    echo "$response" | render_markdown
  fi
}

check_and_trigger_heartbeat() {
  local force="${1:-false}"
  local messages_path="${DATA_STORE}/${MESSAGES_FILE}"
  local messages_filename ; messages_filename="$(basename "$MESSAGES_FILE")"
  local memory_path="${DATA_STORE}/${MEMORY_FILE}"
  local memory_filename ; memory_filename="$(basename "$MEMORY_FILE")"
  local memory_user_payload
  local memory_system_prompt
  local current_memory
  local current_messages
  local messages_count
  local consolidated_json
  local raw_response
  local payload

  # Ensure the messages file exists and is readable
  [[ ! -r $messages_path ]] && return

  # Count the messages inside messages.json
  messages_count=$(jq -rc '. | length' "$messages_path" 2>/dev/null)

  # Validate that messages_count is indeed a number
  [[ ! $messages_count =~ ^[0-9]+$ ]] && return

  # Check if quantity of messages exceeds our heartbeat threshold OR if we are forcing execution
  if [[ $force == "true" ]] || (( messages_count >= HEARTBEAT_THRESHOLD )); then
    log_brain "Heartbeat threshold pulsing (Messages: ${messages_count}/${HEARTBEAT_THRESHOLD} | Force: ${force})."
    log_brain "Automatically consolidating session context into ${memory_filename}..."

    if [[ -r $memory_path ]]; then
      current_memory=$(<"$memory_path")
    else
      current_memory='{}'
    fi

    current_messages=$(<"$messages_path")

    # Construct the instruction and user payload to summarize and update the JSON memory structure
    memory_system_prompt="$(cat <<EOF
You are ${AI_NAME}'s Cognitive Memory Engine. Your goal is to consolidate active chat history into the permanent memory file ($memory_filename).
You will receive the current '$memory_filename' and the active conversation log.
Analyze what milestones, accomplishments, user configurations, personal traits, technical stacks, or tools have been decided, added, or modified in the conversation.
Merge these learnings with absolute fidelity into '$memory_filename':
- user_profile/technical_stack_additions/installed_utils: append new utilities mentioned
- milestones: append new landmarks or successes as objects with 'event' and 'description' (do NOT duplicate existing milestones)
- last_updated: format as 'YYYY-MM-DD (Event description)'
- future_roadmap: update listed goals. If a roadmapped goal has been achieved, remove it from the future_roadmap and add it to milestones. Add any new goals or priorities that were agreed on in the conversation.

CRITICAL REQUIREMENT:
- You must output the ENTIRE updated JSON structure matching '$memory_filename' EXACTLY.
- Output ONLY valid raw JSON.
- DO NOT wrap the output in markdown code blocks like \`\`\`json. Just raw, unescaped, parsed JSON.
- Maintain other preexisting properties in $memory_filename unchanged.
EOF
)"

    memory_user_payload="$(cat <<EOF
Current $memory_filename:
<memory>
${current_memory}
</memory>

Active context $messages_filename:
<messages>
${current_messages}
</messages>
EOF
)"

    # Prepare payload for API call
    # Save prompts to temporary files to avoid ARG_MAX errors with large chat history
    echo "$memory_system_prompt" > "$TEMP_MEMORY_SYSTEM"
    echo "$memory_user_payload" > "$TEMP_MEMORY_USER"

    # Prepare payload for API call (using --rawfile to bypass ARG_MAX)
    payload=$(jq -rc -n \
      --arg model "$GEMINI_API_MODEL" \
      --rawfile sys "$TEMP_MEMORY_SYSTEM" \
      --rawfile user "$TEMP_MEMORY_USER" \
      '{
        model: $model,
        messages: [
          {role: "system", content: $sys},
          {role: "user", content: $user}
        ],
        temperature: 0.1,
        stream: false
      }'
    )

    # Clean up temporary files immediately
    rm -f "$TEMP_MEMORY_SYSTEM" "$TEMP_MEMORY_USER"

    log_brain "Invoking $GEMINI_API_MODEL for synthesis..."
    raw_response=$(api_call "$payload")
    if [[ -z $raw_response || $raw_response == "null" ]]; then
      log_warn "Memory consolidation API call returned empty response."
      return
    fi

    # Extract assistant's message content
    consolidated_json=$(jq -rc '.choices[0].message.content' <<<"$raw_response")

    # Sanitize markdown block wrappers if the model accidentally included them
    local bt='```'
    if [[ "$consolidated_json" == "$bt"* ]]; then
      if [[ "$consolidated_json" == "${bt}json"* ]]; then
        consolidated_json="${consolidated_json#"${bt}"json}"
      else
        consolidated_json="${consolidated_json#"$bt"}"
      fi
      if [[ "$consolidated_json" == *"$bt" ]]; then
        consolidated_json="${consolidated_json%"$bt"}"
      fi
      consolidated_json="${consolidated_json#"${consolidated_json%%[![:space:]]*}"}"
      consolidated_json="${consolidated_json%"${consolidated_json##*[![:space:]]}"}"
    fi

    # Strictly validate that the output is valid JSON
    if jq -e . <<<"$consolidated_json" &>/dev/null; then
      # Write updated memory to memory.json
      echo "$consolidated_json" > "$memory_path"
      log_success "Permanent memory (${memory_filename}) successfully consolidated!"

      # Truncate messages.json to keep only the System Prompt (index 0) and the last 4 messages to preserve flow.
      log_brain "Pruning '$messages_filename' to release conversational context tokens..."
      jq -rc '[.[0]] + .[-4:]' "$messages_path" > "${messages_path}.tmp"
      mv -f "${messages_path}.tmp" "$messages_path"
      log_success "$messages_filename successfully pruned! Context is now ultra-light and ready."
    else
      log_error "Consolidated output was not valid JSON. Memory consolidation aborted to prevent corruption."
      log_debug "Raw response payload was: ${consolidated_json:0:400}..."
    fi
  fi
}

send_message() {
  local prompt="$1"
  local system="$SYSTEM_PROMPT"
  local combined="[System] ${system}\n[User] ${prompt}"

  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      log_debug "Sending query chunk to local Ollama agent..."
      JSON_PAYLOAD=$(jq -rc -n \
        --arg model "$OLLAMA_ARCHITECT" \
        --arg prompt "$combined" \
        '{
          model: $model,
          prompt: $prompt,
          stream: false
        }'
      )
      RESPONSE=$(api_call "$JSON_PAYLOAD")
      show_ai_header
      jq -rc '.response' <<<"$RESPONSE" | render_markdown
    ;;
    # Local Backend: llama.cpp
    llamacpp)
      log_debug "Sending query chunk to local llama-server..."
      LLAMACPP_MODEL=$(curl -sfSL "${LLAMACPP_API_SRV}/models?reload=1" | jq -rc '.data[].id' | grep "$LLAMACPP_ARCHITECT")
      JSON_PAYLOAD=$(jq -rc -n \
        --arg model "$LLAMACPP_MODEL" \
        --arg sys "$system" \
        --arg user "$prompt" \
        '{
          model: $model,
          messages: [
            {role: "system", content: $sys},
            {role: "user", content: $user}
          ],
          temperature: 0.0,
          stream: false
        }'
      )

      # Sending request and store response
      RESPONSE=$(api_call "$JSON_PAYLOAD")
      show_ai_header
      jq -rc '.choices[0].message.content' <<<"$RESPONSE" | render_markdown
    ;;

    # External Backend: OpenRouter / Gemini
    gemini)
      log_debug "Sending query chunk to cloud Gemini agent..."

      # Loading history file if exist or start from zero
      if [[ -r "${DATA_STORE}/${MESSAGES_FILE}" ]]; then
        ALL_MESSAGES=$(<"${DATA_STORE}/${MESSAGES_FILE}")
      else
        ALL_MESSAGES=$(jq -rc -n --arg sys "$system" '[{role: "system", content: $sys}]')
      fi

      # Adding new user message
      ALL_MESSAGES=$(jq -rc --arg user "$prompt" '. + [{role: "user", content: $user}]' <<<"$ALL_MESSAGES")

      # The Magic Loop
      while true; do
        # Write payload variables to temporary files inside the loop to capture any updates
        printf "%s" "$ALL_MESSAGES" > "$TEMP_PAYLOAD_MESSAGES"

        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$GEMINI_API_MODEL" \
          --rawfile msgs "$TEMP_PAYLOAD_MESSAGES" \
          --rawfile tools "$BASE_TOOLS" \
          '{
            model: $model,
            messages: ($msgs | fromjson),
            reasoning: {enabled: true}
          } + if (($tools | fromjson) | length) > 0 then {tools: ($tools | fromjson)} else {} end'
        )

        # Sending request and store response
        RAW_RESPONSE=$(api_call "$JSON_PAYLOAD")
        [[ -z $RAW_RESPONSE ]] && error "Unexpected error! Check the logs and try again."

        # Handling raw response
        if [[ -n $RAW_RESPONSE && ! $RAW_RESPONSE == "null" ]]; then
          # log "\n\n=== RAW RESPONSE ===\n\n"
          # jq . <<<"$RAW_RESPONSE"

          # Check for errors before continuing
          if jq -e '.error' <<<"$RAW_RESPONSE" &>/dev/null; then
            err_msg=$(jq -rc '.error.message' <<<"$RAW_RESPONSE")
            error "Unexpected API error.\n\n${err_msg}\n"
          fi

          # Store relevant data
          REASONING=$(jq -rc '.choices[0].message.reasoning' <<<"$RAW_RESPONSE")
          RESPONSE=$(jq -rc '.choices[0].message.content' <<<"$RAW_RESPONSE")
          REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<"$RAW_RESPONSE")
          TOOLS=$(jq -rc '.choices[0].message.tool_calls' <<<"$RAW_RESPONSE")
          USAGE=$(jq -rc '.usage' <<<"$RAW_RESPONSE")
        fi

        # Handling model reasoning
        if [[ -n $REASONING && ! $REASONING == "null" ]]; then
          show_thinking_header
          echo "$REASONING" | render_markdown
        fi

        # Handling model refusal
        if [[ -n $REFUSAL && ! $REFUSAL == "null" ]]; then
          show_ai_header
          echo "$REFUSAL" | render_markdown
        fi

        # Handling model requested tools (Multi-Parallel Support)
        if [[ -n $TOOLS && ! $TOOLS == "null" ]]; then
          # 1. Grab assistant command message and push to history
          ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<"$RAW_RESPONSE")
          # Write payload variables to temporary files inside the loop to capture any updates
          printf "%s" "$ASSISTANT_MSG" > "$TEMP_PAYLOAD_ASSISTANT"
          ALL_MESSAGES=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT" '. + [($ast | fromjson)]' <<<"$ALL_MESSAGES")

          # 2. Extract and iterate over all requested parallel tools (Single-jq process optimized stream)
          local tool_count=0
          while IFS= read -r -d '' tool_id && IFS= read -r -d '' tool_name && IFS= read -r -d '' tool_args; do
            ((tool_count++))
            show_tool_header "$tool_count" "$tool_name" "$tool_args"

            # 3. Check and execute tool handler
            if [[ -x $TOOLS_HANDLER ]]; then
              "$TOOLS_HANDLER" "$tool_name" "$tool_args" &> "$TOOLS_OUTPUT"
            else
              echo "Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing." > "$TOOLS_OUTPUT"
              log_warn "Tool handler not executable."
            fi

            # 4. Fallback safeguard for empty output
            if [[ ! -s $TOOLS_OUTPUT ]]; then
              echo "(Tool executed successfully and returned empty stdout)" > "$TOOLS_OUTPUT"
            fi

            # 5. Format according to OpenAI guidelines
            # and clean/sanitize TOOLS_OUTPUT to ensure 100% valid UTF-8 and protect JQ
            iconv -f UTF-8 -t UTF-8 -c "$TOOLS_OUTPUT" > "${TOOLS_OUTPUT}.clean" 2>/dev/null && mv "${TOOLS_OUTPUT}.clean" "$TOOLS_OUTPUT"
            if jq -rc -n --arg id "$tool_id" --arg name "$tool_name" --rawfile content "$TOOLS_OUTPUT" '{role: "tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null; then
              # Clear tools output file
              rm -f "$TOOLS_OUTPUT"

              # 6. Append tool output to messages array safely
              if NEW_MESSAGES=$(jq -rc --rawfile tool "$TEMP_TOOLS_OUTPUT" '. + [$tool | fromjson]' <<<"$ALL_MESSAGES" 2>/dev/null); then
                ALL_MESSAGES="$NEW_MESSAGES"
              else
                log_warn "fromjson failed, using fallback --arg serialization"
                ALL_MESSAGES=$(jq -rc \
                  --arg id "$tool_id" \
                  --arg name "$tool_name" \
                  --arg content "$(< "$TEMP_TOOLS_OUTPUT")" \
                  '. + [{role: "tool", tool_call_id: $id, name: $name, content: $content}]' <<<"$ALL_MESSAGES"
                )
              fi

              # Clear temporary tools output file
              rm -f "$TEMP_TOOLS_OUTPUT"
            else
              log_warn "Unable to parse tool output with rawfile, using fallback formatting"
              local fallback_content
              fallback_content=$(cat "$TOOLS_OUTPUT" 2>/dev/null || echo "(Error reading tool output)")
              ALL_MESSAGES=$(jq -rc \
                --arg id "$tool_id" \
                --arg name "$tool_name" \
                --arg content "$fallback_content" \
                '. + [{role: "tool", tool_call_id: $id, name: $name, content: $content}]' <<<"$ALL_MESSAGES"
              )

              # Clear tools output file
              rm -f "$TOOLS_OUTPUT"
            fi
          done < <(jq -j '.[] | .id, "\u0000", .function.name, "\u0000", .function.arguments, "\u0000"' <<<"$TOOLS" 2>/dev/null)

        # Handling model final response
        else
          if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
            show_ai_header
            echo "$RESPONSE" | render_markdown

            # Store final AI response
            ALL_MESSAGES=$(jq -rc --arg ast "$RESPONSE" '. + [{role: "assistant", content: $ast}]' <<<"$ALL_MESSAGES")
            echo "$ALL_MESSAGES" > "${DATA_STORE}/${MESSAGES_FILE}"
          fi
          break   # Leaving the loop
        fi

        # Handling model usage
        if [[ -n $USAGE && ! $USAGE == "null" ]]; then
          local prompt_tok ; prompt_tok=$(jq -rc .prompt_tokens <<<"$USAGE")
          local cached_tok ; cached_tok=$(jq -rc '.prompt_tokens_details.cached_tokens // 0' <<<"$USAGE")
          local comp_tok ; comp_tok=$(jq -rc .completion_tokens <<<"$USAGE")
          local reasoning_tok ; reasoning_tok=$(jq -rc '.completion_tokens_details.reasoning_tokens // 0' <<<"$USAGE")
          local total_tok ; total_tok=$(jq -rc .total_tokens <<<"$USAGE")
          local cost ; cost=$(jq -rc .cost <<<"$USAGE")

          echo -e "\n${CLR_B_BLACK}──────────────────────────[ SYSTEM METRICS ]──────────────────────────${ANSI_RESET}"
          echo -e "${CLR_B_CYAN}Tokens Used:${ANSI_RESET}  ${CLR_B_WHITE}${total_tok}${ANSI_RESET}  (Prompt: ${prompt_tok} | Cached: ${cached_tok} | Response: ${comp_tok} | Thinking: ${reasoning_tok})"
          if [[ -n $cost && "$cost" != "null" ]]; then
            echo -e "${CLR_B_CYAN}Cost:${ANSI_RESET} ${CLR_B_GREEN}${cost}${ANSI_RESET}"
          fi
          echo -e "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────${ANSI_RESET}"
        fi
      done
    ;;
  esac

  # Autonomous Memory Consolidation Heartbeat
  check_and_trigger_heartbeat
}

run_chat() {
  show_banner
  log_info "Initializing chat context..."
  local backend_upper ; backend_upper=$(to_upper "$BACKEND")
  log_info "Active Backend : ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"
  log_info "Conversation online. Type ${CLR_B_GREEN}/help${ANSI_RESET} to view commands."

  while true; do
    echo -en "\n${CLR_B_GREEN}${ICON_USER}User${ANSI_RESET} ${CLR_B_BLACK}❯${ANSI_RESET} "
    read -r USER_MSG

    # Do nothing when user message is empty
    [[ -z $USER_MSG ]] && continue

    case $USER_MSG in
      "/help")
        echo -e "\n${CLR_B_CYAN}✨ Available Commands ✨${ANSI_RESET}"
        echo -e "  ${CLR_B_GREEN}/help${ANSI_RESET}      • Show this help menu"
        echo -e "  ${CLR_B_GREEN}/clear${ANSI_RESET}     • Clear current conversation context and memory"
        echo -e "  ${CLR_B_GREEN}/commit${ANSI_RESET}    • Consolidate active context to permanent disk"
        echo -e "  ${CLR_B_GREEN}/run <cmd>${ANSI_RESET} • Execute a shell command locally in the session"
        echo -e "  ${CLR_B_GREEN}/start${ANSI_RESET}     • Switch active context to multi-agent pipeline"
        echo -e "  ${CLR_B_GREEN}/quit${ANSI_RESET}      • Terminate session gracefully"
      ;;
      "/run")
        log_warn "Missing command arguments. Usage: /run <command>"
      ;;
      "/run "*)
        local cmd="${USER_MSG#"/run "}"
        log_step "Locally executing: ${CLR_B_WHITE}${cmd}${ANSI_RESET}"
        echo -e "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────${ANSI_RESET}"
        eval "$cmd"
        echo -e "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────${ANSI_RESET}"
      ;;
      "/clear") clear_memory ;;
      "/commit") check_and_trigger_heartbeat "true" ;;
      "/start")
        echo -en "\n${CLR_B_CYAN}🎯 Enter your pipeline prompt:${ANSI_RESET} "
        read -r PIPELINE_PROMPT
        if [[ -n $PIPELINE_PROMPT ]]; then
          USER_PROMPT="$PIPELINE_PROMPT"
          run_pipeline
        fi
      ;;
      "/quit") break ;;
      *)
        send_message "$USER_MSG"
      ;;
    esac
  done

  echo -e "\n${CLR_B_MAGENTA}🔮 Bye then, see you soon! Have fun! :P${ANSI_RESET}\n"
  exit
}

run_pipeline() {
  log_section "PIPELINE MODE ACTIVATED"
  local backend_upper ; backend_upper=$(to_upper "$BACKEND")
  log_info "Active Backend : ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"

  # Context
  if [[ -n $INPUT_FILE2 && -r $INPUT_FILE && -r $INPUT_FILE2 ]]; then
    CONTEXT_DATA="File A ($(basename "$INPUT_FILE")):\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`\nFile B ($(basename "$INPUT_FILE2")):\n\n\`\`\`\n$(<"$INPUT_FILE2")\n\`\`\`\n"
    log_info "Loaded File A  : ${CLR_B_WHITE}$(basename "$INPUT_FILE")${ANSI_RESET}"
    log_info "Loaded File B  : ${CLR_B_WHITE}$(basename "$INPUT_FILE2")${ANSI_RESET}"
  elif [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
    CONTEXT_DATA="File '$(basename "$INPUT_FILE")':\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`\n"
    log_info "Loaded File    : ${CLR_B_WHITE}$(basename "$INPUT_FILE")${ANSI_RESET}"
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

  if (( is_question == 1 )); then
    # SYSTEM_PROMPT="The user has a question, reply to it."
    SIMPLE_PROMPT="Question: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
    SIMPLE_PROMPT_COMBINED="${SYSTEM_PROMPT}\n\nStart your reply with 'Response: '\n\nQuestion: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"

    # Backend Selector
    case $BACKEND in
      # Local Backend: Ollama
      ollama)
        log_info "Question mode detected. Calling local Architect (${CLR_B_YELLOW}$OLLAMA_ARCHITECT${ANSI_RESET})..."
        printf "%s" "$SIMPLE_PROMPT_COMBINED" > "$TEMP_MEMORY_USER"
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$OLLAMA_ARCHITECT" \
          --rawfile prompt "$TEMP_MEMORY_USER" \
          '{
            model: $model,
            prompt: $prompt,
            stream: false
          }'
        )

        # Sending request and store response
        RESPONSE=$(api_call "$JSON_PAYLOAD")
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # Local Backend: llama.cpp
      llamacpp)
        log_info "Question mode detected. Calling local Architect (${CLR_B_YELLOW}$LLAMACPP_ARCHITECT${ANSI_RESET})... "
        LLAMACPP_MODEL=$(curl -sfSL "${LLAMACPP_API_SRV}/models?reload=1" | jq -rc '.data[].id' | grep "$LLAMACPP_ARCHITECT")
        printf "%s" "$SYSTEM_PROMPT" > "$TEMP_MEMORY_SYSTEM"
        printf "%s" "$SIMPLE_PROMPT" > "$TEMP_MEMORY_USER"
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$LLAMACPP_MODEL" \
          --rawfile system "$TEMP_MEMORY_SYSTEM" \
          --rawfile user "$TEMP_MEMORY_USER" \
          '{
            model: $model,
            messages: [
              {role: "system", content: $system},
              {role: "user", content: $user}
            ],
            temperature: 0.0,
            stream: false
          }'
        )

        # Sending request and store response
        RESPONSE=$(api_call "$JSON_PAYLOAD")
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # External Backend: OpenRouter / Gemini
      gemini)
        log_info "Question mode detected. Calling cloud Gemini (${CLR_B_YELLOW}$GEMINI_API_MODEL${ANSI_RESET})..."
        printf "%s" "$SYSTEM_PROMPT" > "$TEMP_MEMORY_SYSTEM"
        printf "%s" "$SIMPLE_PROMPT" > "$TEMP_MEMORY_USER"
        ALL_MESSAGES=$(jq -rc -n \
          --rawfile sys "$TEMP_MEMORY_SYSTEM" \
          --rawfile user "$TEMP_MEMORY_USER" \
          '[{role: "system", content: $sys}, {role: "user", content: $user}]'
        )

        # The Magic Loop
        while true; do
          # Write payload variables to temporary files inside the loop to capture any updates
          printf "%s" "$ALL_MESSAGES" > "$TEMP_PAYLOAD_MESSAGES"

          JSON_PAYLOAD=$(jq -rc -n \
            --arg model "$GEMINI_API_MODEL" \
            --rawfile msgs "$TEMP_PAYLOAD_MESSAGES" \
            --rawfile tools "$BASE_TOOLS" \
            '{
              model: $model,
              messages: ($msgs | fromjson),
              reasoning: {enabled: true}
            } + if (($tools | fromjson) | length) > 0 then {tools: ($tools | fromjson)} else {} end'
          )
          [[ -z $JSON_PAYLOAD ]] && error "Unexpected error! Check the logs and try again."

          # Sending request and store response
          RAW_RESPONSE=$(api_call "$JSON_PAYLOAD")
          [[ -z $RAW_RESPONSE ]] && error "Unexpected error! Check the logs and try again."

          # Handling raw response
          if [[ -n $RAW_RESPONSE && ! $RAW_RESPONSE == "null" ]]; then
            # Check for errors before continuing
            if jq -e '.error' <<<"$RAW_RESPONSE" &>/dev/null; then
              err_msg=$(jq -rc '.error.message' <<<"$RAW_RESPONSE")
              error "Unexpected API error.\n\n${err_msg}\n"
            fi

            # Store relevant data
            REASONING=$(jq -rc '.choices[0].message.reasoning' <<<"$RAW_RESPONSE")
            RESPONSE=$(jq -rc '.choices[0].message.content' <<<"$RAW_RESPONSE")
            REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<"$RAW_RESPONSE")
            TOOLS=$(jq -rc '.choices[0].message.tool_calls' <<<"$RAW_RESPONSE")
            USAGE=$(jq -rc '.usage' <<<"$RAW_RESPONSE")
          fi

          # Handling model reasoning
          if [[ -n $REASONING && ! $REASONING == "null" ]]; then
            show_thinking_header
            echo "$REASONING" | render_markdown
          fi

          # Handling model refusal
          if [[ -n $REFUSAL && ! $REFUSAL == "null" ]]; then
            show_ai_header
            echo "$REFUSAL" | render_markdown
          fi

          # Handling model requested tools (Multi-Parallel Support)
          if [[ -n $TOOLS && ! $TOOLS == "null" ]]; then
            # 1. Grab assistant command message and push to history
            ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<"$RAW_RESPONSE")
            # Write payload variables to temporary files inside the loop to capture any updates
            printf "%s" "$ASSISTANT_MSG" > "$TEMP_PAYLOAD_ASSISTANT"
            ALL_MESSAGES=$(jq -rc --rawfile ast "$TEMP_PAYLOAD_ASSISTANT" '. + [($ast | fromjson)]' <<<"$ALL_MESSAGES")

            # 2. Extract and iterate over all requested parallel tools (Single-jq process optimized stream)
            local tool_count=0
            while IFS= read -r -d '' tool_id && IFS= read -r -d '' tool_name && IFS= read -r -d '' tool_args; do
              ((tool_count++))
              show_tool_header "$tool_count" "$tool_name" "$tool_args"

              # 3. Check and execute tool handler
              if [[ -x $TOOLS_HANDLER ]]; then
                "$TOOLS_HANDLER" "$tool_name" "$tool_args" &> "$TOOLS_OUTPUT"
              else
                echo "Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing." > "$TOOLS_OUTPUT"
                log_warn "Tool handler not executable."
              fi

              # 4. Fallback safeguard for empty output
              if [[ ! -s $TOOLS_OUTPUT ]]; then
                echo "(Tool executed successfully and returned empty stdout)" > "$TOOLS_OUTPUT"
              fi

              # 5. Format according to OpenAI guidelines
              # and clean/sanitize TOOLS_OUTPUT to ensure 100% valid UTF-8 and protect JQ
              iconv -f UTF-8 -t UTF-8 -c "$TOOLS_OUTPUT" > "${TOOLS_OUTPUT}.clean" 2>/dev/null && mv "${TOOLS_OUTPUT}.clean" "$TOOLS_OUTPUT"
              if jq -rc -n --arg id "$tool_id" --arg name "$tool_name" --rawfile content "$TOOLS_OUTPUT" '{role: "tool", tool_call_id: $id, name: $name, content: $content}' > "$TEMP_TOOLS_OUTPUT" 2>/dev/null; then
                # Clear tools output file
                rm -f "$TOOLS_OUTPUT"

                # 6. Append tool output to messages array safely
                if NEW_MESSAGES=$(jq -rc --rawfile tool "$TEMP_TOOLS_OUTPUT" '. + [$tool | fromjson]' <<<"$ALL_MESSAGES" 2>/dev/null); then
                  ALL_MESSAGES="$NEW_MESSAGES"
                else
                  log_warn "fromjson failed, using fallback --arg serialization"
                  ALL_MESSAGES=$(jq -rc \
                    --arg id "$tool_id" \
                    --arg name "$tool_name" \
                    --arg content "$(< "$TEMP_TOOLS_OUTPUT")" \
                    '. + [{role: "tool", tool_call_id: $id, name: $name, content: $content}]' <<<"$ALL_MESSAGES"
                  )
                fi

                # Clear temporary tools output file
                rm -f "$TEMP_TOOLS_OUTPUT"
              else
                log_warn "Unable to parse tool output with rawfile, using fallback formatting"
                local fallback_content
                fallback_content=$(cat "$TOOLS_OUTPUT" 2>/dev/null || echo "(Error reading tool output)")
                ALL_MESSAGES=$(jq -rc \
                  --arg id "$tool_id" \
                  --arg name "$tool_name" \
                  --arg content "$fallback_content" \
                  '. + [{role: "tool", tool_call_id: $id, name: $name, content: $content}]' <<<"$ALL_MESSAGES"
                )

                # Clear tools output file
                rm -f "$TOOLS_OUTPUT"
              fi
            done < <(jq -j '.[] | .id, "\u0000", .function.name, "\u0000", .function.arguments, "\u0000"' <<<"$TOOLS" 2>/dev/null)

          # Handling model final response
          else
            if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
              show_ai_header
              echo "$RESPONSE" | render_markdown
            fi
            break   # Leaving the loop
          fi

          # Handling model usage
          if [[ -n $USAGE && ! $USAGE == "null" ]]; then
            local prompt_tok ; prompt_tok=$(jq -rc .prompt_tokens <<<"$USAGE")
            local cached_tok ; cached_tok=$(jq -rc '.prompt_tokens_details.cached_tokens // 0' <<<"$USAGE")
            local comp_tok ; comp_tok=$(jq -rc .completion_tokens <<<"$USAGE")
            local reasoning_tok ; reasoning_tok=$(jq -rc '.completion_tokens_details.reasoning_tokens // 0' <<<"$USAGE")
            local total_tok ; total_tok=$(jq -rc .total_tokens <<<"$USAGE")
            local cost ; cost=$(jq -rc .cost <<<"$USAGE")

            echo -e "\n${CLR_B_BLACK}──────────────────────────[ SYSTEM METRICS ]──────────────────────────${ANSI_RESET}"
            echo -e "${CLR_B_CYAN}Tokens Used:${ANSI_RESET}  ${CLR_B_WHITE}${total_tok}${ANSI_RESET}  (Prompt: ${prompt_tok} | Cached: ${cached_tok} | Response: ${comp_tok} | Thinking: ${reasoning_tok})"
            if [[ -n $cost && "$cost" != "null" ]]; then
              echo -e "${CLR_B_CYAN}Cost:${ANSI_RESET} ${CLR_B_GREEN}${cost}${ANSI_RESET}"
            fi
            echo -e "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────${ANSI_RESET}"
          fi
        done
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac
    exit $?   # End of Question Mode

  # Route B: Compare Mode
  elif (( is_compare == 1 )); then
    COMPARE_PROMPT="${SYSTEM_PROMPT}\n\nThe user wants to compare two files, show the main differences.\n\nContext:\n${CONTEXT_DATA}"
    COMPARE_PROMPT_COMBINED="${SYSTEM_PROMPT}\n\nThe user wants to compare two files, show the main differences.\n\nRequest: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
    # COMPARE_PROMPT_COMBINED="${SYSTEM_PROMPT}\n\nThe user wants to compare two files, show the main differences. Start your reply with 'Response:'\n\nRequest: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"

    # Backend Selector
    case $BACKEND in
      # Local Backend: Ollama
      ollama)
        log_info "Compare mode detected. Calling local Architect (${CLR_B_YELLOW}$OLLAMA_ARCHITECT${ANSI_RESET})... "
        printf "%s" "$COMPARE_PROMPT_COMBINED" > "$TEMP_MEMORY_USER"
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$OLLAMA_ARCHITECT" \
          --rawfile prompt "$TEMP_MEMORY_USER" \
          '{
            model: $model,
            prompt: $prompt,
            stream: false
          }'
        )

        # Sending request and store response
        RESPONSE=$(api_call "$JSON_PAYLOAD")
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # Local Backend: llama.cpp
      llamacpp)
        log_info "Compare mode detected. Calling local Architect (${CLR_B_YELLOW}$LLAMACPP_ARCHITECT${ANSI_RESET})... "
        LLAMACPP_MODEL=$(curl -sfSL "${LLAMACPP_API_SRV}/models?reload=1" | jq -rc '.data[].id' | grep "$LLAMACPP_ARCHITECT")
        printf "%s" "$COMPARE_PROMPT" > "$TEMP_MEMORY_SYSTEM"
        printf "%s" "$USER_PROMPT" > "$TEMP_MEMORY_USER"
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$LLAMACPP_MODEL" \
          --rawfile system "$TEMP_MEMORY_SYSTEM" \
          --rawfile user "$TEMP_MEMORY_USER" \
          '{
            model: $model,
            messages: [
              {role: "system", content: $system},
              {role: "user", content: $user}
            ],
            temperature: 0.0,
            stream: false
          }'
        )

        # Sending request and store response
        RESPONSE=$(api_call "$JSON_PAYLOAD")
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # External Backend: OpenRouter / Gemini
      gemini)
        log_info "Compare mode detected. Calling cloud Gemini (${CLR_B_YELLOW}$GEMINI_API_MODEL${ANSI_RESET})... "
        printf "%s" "$COMPARE_PROMPT" > "$TEMP_MEMORY_SYSTEM"
        printf "%s" "$USER_PROMPT" > "$TEMP_MEMORY_USER"
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$GEMINI_API_MODEL" \
          --rawfile system "$TEMP_MEMORY_SYSTEM" \
          --rawfile user "$TEMP_MEMORY_USER" \
          '{
            model: $model,
            messages: [
              {role: "system", content: $system},
              {role: "user", content: $user}
            ],
            reasoning: {enabled: true}
          }'
        )

        # Sending request and store response
        RAW_RESPONSE=$(api_call "$JSON_PAYLOAD")

        # Handling raw response
        if [[ -n $RAW_RESPONSE && ! $RAW_RESPONSE == "null" ]]; then
          # Check for errors before continuing
          if jq -e '.error' <<<"$RAW_RESPONSE" &>/dev/null; then
            err_msg=$(jq -rc '.error.message' <<<"$RAW_RESPONSE")
            error "Unexpected API error.\n\n${err_msg}\n"
          fi

          # Store relevant data
          REASONING=$(jq -rc '.choices[0].message.reasoning' <<<"$RAW_RESPONSE")
          RESPONSE=$(jq -rc '.choices[0].message.content' <<<"$RAW_RESPONSE")
          REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<"$RAW_RESPONSE")
          USAGE=$(jq -rc '.usage' <<<"$RAW_RESPONSE")
        fi

        # Handling model reasoning
        if [[ -n $REASONING && ! $REASONING == "null" ]]; then
          show_thinking_header
          echo "$REASONING" | render_markdown
        fi

        # Handling model refusal
        if [[ -n $REFUSAL && ! $REFUSAL == "null" ]]; then
          show_ai_header
          echo "$REFUSAL" | render_markdown
        fi

        # Handling model final response
        if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
          show_ai_header
          echo "$RESPONSE" | render_markdown
        fi

        # Handling model usage
        if [[ -n $USAGE && ! $USAGE == "null" ]]; then
          local prompt_tok ; prompt_tok=$(jq -rc .prompt_tokens <<<"$USAGE")
          local cached_tok ; cached_tok=$(jq -rc '.prompt_tokens_details.cached_tokens // 0' <<<"$USAGE")
          local comp_tok ; comp_tok=$(jq -rc .completion_tokens <<<"$USAGE")
          local reasoning_tok ; reasoning_tok=$(jq -rc '.completion_tokens_details.reasoning_tokens // 0' <<<"$USAGE")
          local total_tok ; total_tok=$(jq -rc .total_tokens <<<"$USAGE")
          local cost ; cost=$(jq -rc .cost <<<"$USAGE")

          echo -e "\n${CLR_B_BLACK}──────────────────────────[ SYSTEM METRICS ]──────────────────────────${ANSI_RESET}"
          echo -e "${CLR_B_CYAN}Tokens Used:${ANSI_RESET}  ${CLR_B_WHITE}${total_tok}${ANSI_RESET}  (Prompt: ${prompt_tok} | Cached: ${cached_tok} | Response: ${comp_tok} | Thinking: ${reasoning_tok})"
          if [[ -n $cost && "$cost" != "null" ]]; then
            echo -e "${CLR_B_CYAN}Cost:${ANSI_RESET} ${CLR_B_GREEN}${cost}${ANSI_RESET}"
          fi
          echo -e "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────${ANSI_RESET}"
        fi
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac
    exit $?   # End of Compare Mode

  # Route C: Task Mode
  # TODO: Finish the 'task' part
  else
    log_info "Task mode detected. Preparing execution via backend '${CLR_B_YELLOW}${BACKEND}${ANSI_RESET}' in mode '${CLR_B_GREEN}${RUN_MODE}${ANSI_RESET}'"

    case $BACKEND in
      ollama)
        error "Coming soon! Stay tuned ;-)"
        # if [[ $RUN_MODE == "multi" ]]; then
        #   log "\nTask mode detected. Running heavy pipeline.\n"
        #   log "[1/3] The Architect ($OLLAMA_ARCHITECT) will prepare the plan...\n"
        #   ARCHITECT_PROMPT="The user wants to make some changes: $USER_PROMPT. Analyze the file and create an action plan for the coder model.\n\nContext:\n$CONTEXT_DATA"
        #   ACTION_PLAN=$(ollama run "${OLLAMA_FLAGS[@]}" "$OLLAMA_ARCHITECT" <<<"$ARCHITECT_PROMPT")
        #   log "\n[2/3] The Coder ($OLLAMA_CODER) will write the code...\n"
        #   CODER_PROMPT="Follow this action plan on the given file ($INPUT_FILE). Return only the updated code without anything else. Don't use Markdown.\n\nPlan:\n$ACTION_PLAN\n\nContext:\n$CONTEXT_DATA"
        #   RETURNED_CODE=$(ollama run "${OLLAMA_FLAGS[@]}" "$OLLAMA_CODER" <<<"$CODER_PROMPT" | sed '1d;$d')
        #   log "\n[3/3] The Judge ($OLLAMA_JUDGE) will inspect the changes...\n"
        #   JUDGE_PROMPT="Verify that there is no syntax errors or regressions in the updated code compared to the original.\n\nOriginal:\n$CONTEXT_DATA\n\nUpdated:\n$RETURNED_CODE"
        #   FINAL_REPORT=$(ollama run "${OLLAMA_FLAGS[@]}" "$OLLAMA_JUDGE" <<<"$JUDGE_PROMPT")
        #   log "\n\n=== JUDGE REPORT ===\n\n"
        #   echo "$FINAL_REPORT" | handle_markdown
        # else
        #   log "\n[1/1] The Coder ($OLLAMA_CODER) will write the code...\n"
        #   CODER_PROMPT="Follow the user prompt for the given file ($INPUT_FILE). Return only the updated code without anything else. Don't use Markdown.\n\nContext:\n$CONTEXT_DATA"
        #   RETURNED_CODE=$(ollama run "${OLLAMA_FLAGS[@]}" "$OLLAMA_CODER" <<<"$CODER_PROMPT" | sed '1d;$d')
        # fi
        # if [[ -n $RETURNED_CODE ]]; then
        #   log "\n\n+++ WRITING CHANGES +++\n\n"
        #   echo "$RETURNED_CODE" > "${INPUT_FILE}.new"
        #   log "\n[Finished] Code written in ${INPUT_FILE}.new\n"
        # else
        #   log "\n[Done]\n"
        # fi
      ;;

      llamacpp)
        error "Coming soon! Stay tuned ;-)"
      ;;

      gemini)
        local RETURNED_CODE
        if [[ $RUN_MODE == "multi" ]]; then
          log_info "Launching Multi-Agent Pipeline for Gemini..."

          # Step 1: Architect Plan
          local arch_sys="${SYSTEM_PROMPT}\n\nYou are a professional Software Architect. Your task is to analyze the source file and the user's requested modification to create a precise development plan.\n"
          arch_sys+="In your response, outline what code needs to be modified, what needs to be added or cleaned, potential edge cases, syntax concerns, and architectural best practices.\n"
          arch_sys+="Keep your action plan concise, clear, and perfectly targeted."

          local arch_user="Modification request: ${USER_PROMPT}\n\n"
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            arch_user+="Filename: $(basename "$INPUT_FILE")\n"
            arch_user+="Here is the original file contents below:\n"
            arch_user+="--- BEGIN FILE ---\n"
            arch_user+="$(<"$INPUT_FILE")\n"
            arch_user+="--- END FILE ---"
          else
            arch_user+="No file was provided as context.\n"
          fi

          local ARCHITECT_PLAN
          ARCHITECT_PLAN=$(call_gemini_task_agent "$arch_sys" "$arch_user" "Architecting the changes")

          log ; show_ai_header
          echo "### Architectural Action Plan:"
          echo "$ARCHITECT_PLAN" | render_markdown
          log

          # Step 2: Coder Implementation
          local coder_sys="${SYSTEM_PROMPT}\n\nYou are an elite developer. Your task is to apply the provided architectural plan to the given file content.\n"
          coder_sys+="CRITICAL INSTRUCTION:\n"
          coder_sys+="1. You must return ONLY and EXCLUSIVELY the complete, raw content of the updated file.\n"
          coder_sys+="2. Do NOT wrap your output in markdown code blocks (such as \`\`\`php ... \`\`\`).\n"
          coder_sys+="3. Do NOT include any explanations, greetings, warnings, or descriptions.\n"
          coder_sys+="4. Output exclusively raw, valid source code ready to be saved directly to the file."

          local coder_user=""
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            coder_user+="Filename: $(basename "$INPUT_FILE")\n"
            coder_user+="Original file content:\n"
            coder_user+="--- BEGIN FILE ---\n"
            coder_user+="$(<"$INPUT_FILE")\n"
            coder_user+="--- END FILE ---\n\n"
          fi
          coder_user+="Architect Plan:\n"
          coder_user+="${ARCHITECT_PLAN}"

          RETURNED_CODE=$(call_gemini_task_agent "$coder_sys" "$coder_user" "Implementing changes")

          # Step 3: Judge Verification
          local judge_sys="${SYSTEM_PROMPT}\n\nYou are an expert Quality Assurance and Code Inspector.\n"
          judge_sys+="Your task is to compare the original file content and the updated file content to ensure syntax correctness, absence of regressions, security compliance, and proper implementation of the requested edits.\n"
          judge_sys+="Start your response with a line starting with '[PASS]' if everything is correct, or '[FAIL]' with clear, detailed explanations of any regression or issue discovered."

          local judge_user=""
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            judge_user+="Filename: $(basename "$INPUT_FILE")\n"
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

          local CODER_JUDGMENT
          CODER_JUDGMENT=$(call_gemini_task_agent "$judge_sys" "$judge_user" "Evaluating changes")

          log ; show_ai_header
          echo "### QA Inspection & Verdict:"
          echo "$CODER_JUDGMENT" | render_markdown
          log

        else
          log_info "Launching Simple Single-Agent Mode for Gemini..."

          local simple_sys="${SYSTEM_PROMPT}\n\nYou are a senior professional developer. Your role is to understand the user's requested edit, apply it to the source file, and return the modified file contents.\n"
          simple_sys+="CRITICAL INSTRUCTION:\n"
          simple_sys+="1. You must return ONLY and EXCLUSIVELY the complete, raw content of the updated file.\n"
          simple_sys+="2. Do NOT wrap your output in markdown code blocks (such as \`\`\`php ... \`\`\`).\n"
          simple_sys+="3. Do NOT include any explanations, greetings, warnings, or descriptions.\n"
          simple_sys+="4. Output exclusively raw, valid source code ready to be saved directly to the file."

          local simple_user="Modification request: ${USER_PROMPT}\n\n"
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            simple_user+="Filename: $(basename "$INPUT_FILE")\n"
            simple_user+="Here is the original file contents below:\n"
            simple_user+="--- BEGIN FILE ---\n"
            simple_user+="$(<"$INPUT_FILE")\n"
            simple_user+="--- END FILE ---"
          else
            simple_user+="No file was provided as context. Create/modify the code as requested. Here is the context metadata:\n${CONTEXT_DATA}"
          fi

          RETURNED_CODE=$(call_gemini_task_agent "$simple_sys" "$simple_user" "Coding modifications")
        fi

        # Securely write/output results
        if [[ -n $RETURNED_CODE ]]; then
          if [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
            echo "$RETURNED_CODE" > "${INPUT_FILE}.new"
            log_success "Modified code successfully generated and saved to: ${CLR_B_GREEN}${INPUT_FILE}.new${ANSI_RESET}"
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

# Checks
[[ $# -eq 0 && ! $RUN_MODE == "chat" ]] && print_usage

# Flags
while [[ $# -ne 0 ]]; do
  case $1 in
    # Help
    -h|--help|help) print_help ;;

    # Clean
    --clear|clear) clear_memory ;;

    # Consolidate
    --commit|commit) check_and_trigger_heartbeat "true" ;;

    # Backends
    --backend|backend)
      shift
      BACKEND="$1"
      backend_upper=$(to_upper "$BACKEND")
      log_info "Backend context switch: ${CLR_B_YELLOW}${backend_upper}${ANSI_RESET}"
      shift
    ;;

    # Modes
    --chat|chat)
      log_info "Running modes loaded: ${CLR_B_GREEN}CHAT INTERACTIVE${ANSI_RESET}"
      RUN_MODE="chat" ; shift
    ;;
    --multi|multi)
      log_info "Running modes loaded: ${CLR_B_GREEN}MULTI-AGENT PIPELINE${ANSI_RESET}"
      RUN_MODE="multi" ; shift
    ;;
    --simple|simple)
      log_info "Running modes loaded: ${CLR_B_GREEN}SIMPLE SINGLE-AGENT${ANSI_RESET}"
      RUN_MODE="simple" ; shift
    ;;
    --server|server)
      log_info "Running modes loaded: ${CLR_B_GREEN}API SERVER MODE${ANSI_RESET}"
      RUN_MODE="server" ; shift
      SERVER_MODE="$1" ; shift
    ;;
    *)
      # All flags set, leaving the loop
      break
    ;;
  esac
done

# Args
USER_PROMPT="$1"
INPUT_FILE="$2"
INPUT_FILE2="$3"

# Init
mkdir -p "$DATA_STORE"
[[ ! -r $BASE_TOOLS ]] && error "Missing '$BASE_TOOLS' file."
if [[ $USE_TOR == true && $BACKEND == "gemini" ]]; then
  log_info "Checking Tor Network proxy interface..."
  if ! timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
    error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is Tor running?"
  else
    log_success "Tor privacy tunnel established! Routing securely to $TOR_PROXY."
  fi
fi
if [[ $BACKEND == "gemini" ]]; then
  [[ -r $CREDENTIALS ]] && GEMINI_API_KEY=$(<"$CREDENTIALS")
  [[ -z $GEMINI_API_KEY ]] && error "Missing cloud credentials. Please configure local '.creds' file with your OpenRouter API key."
fi

# Download models when necessary
if [[ $PULL_MODELS == true ]]; then
  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      # Downloading models for ollama
      log_info "Synchronizing required local architectures for Ollama daemon..."
      [[ -n $OLLAMA_ROUTER ]] && OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_ROUTER"
      OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_ARCHITECT"
      OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_CODER"
      OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_JUDGE"
      log_success "All Ollama architectures synchronized successfully."
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      # Downloading models for llama.cpp
      log_info "Preloading local GGUF models into llama.cpp cache..."
      quant_upper=$(to_upper "$QUANTIZATION")
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_ROUTER}:${quant_upper}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_ARCHITECT}:${quant_upper}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_CODER}:${quant_upper}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_JUDGE}:${quant_upper}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      log_success "Llama.cpp cache populated successfully."
    ;;
  esac
fi

# Main
case $RUN_MODE in
  chat) run_chat ;;
  multi|simple) run_pipeline ;;
  server) serve ;;
  *) error "Unsupported run mode given: $RUN_MODE" ;;
esac
