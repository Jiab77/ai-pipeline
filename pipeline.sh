#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329
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
# Version: 0.2.1

# Options
[[ -e $HOME/.debug ]] && set -x

# Config
RULES="Don't cut or break lines."
RUN_MODE="chat"    # Expected values: simple, multi, chat
BACKEND="gemini"    # Expected values: ollama, llamacpp or gemini
HEARTBEAT_THRESHOLD=15    # Trigger context consolidation to avoid amnesia and keep context extremely light
CREDENTIALS="${HOME}/.creds"    # Or any other location or filename you prefer.
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
TOR_PROXY="socks5h://0:9050"
MESSAGES_FILE="messages.json"
MEMORY_FILE="memory.json"
PULL_MODELS=false
USE_TOR=true

# Internals
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE//.sh}"
DATA_STORE="${SCRIPT_DIR}/data"
BASE_TOOLS="${SCRIPT_DIR}/tools.json"
TEMP_MEMORY_SYSTEM="${DATA_STORE}/tmp_memory_sys.txt"
TEMP_MEMORY_USER="${DATA_STORE}/tmp_memory_usr.txt"
TEMP_TOOLS_OUTPUT="${DATA_STORE}/tmp_tools_output.json"
TEMP_PAYLOAD_MESSAGES="${DATA_STORE}/tmp_payload_messages.json"
TEMP_PAYLOAD_TOOLS="${DATA_STORE}/tmp_payload_tools.json"
TOOLS_OUTPUT="${DATA_STORE}/tools-output.txt"
TOOLS_HANDLER="${SCRIPT_DIR}/run-tools.sh"
TOOLS_CONTENT="[]"

# Soul
AI_NAME="Jarvis"
SYSTEM_PROMPT="You are ${AI_NAME}, a friendly AI collaborator. Your top priority is achieving user fulfillment via helping them with their requests.\n"
SYSTEM_PROMPT+="Your own workspace is in the \`$(basename "$DATA_STORE")\` folder, you can organize it the way you want.\n"
SYSTEM_PROMPT+="Your own memory file located in your workspace is the \`$(basename "$MEMORY_FILE")\` file, you must load it at every session start.\n"
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
        "$TEMP_PAYLOAD_MESSAGES" \
        "$TEMP_PAYLOAD_TOOLS" \
        "$TOOLS_OUTPUT" \
        "${TOOLS_OUTPUT}.clean"
}
trap cleanup_temp_files EXIT INT TERM

# Functions
log() {
  echo -e "$*" >&2
}
error() {
  echo -e "\n[!] Error: $*\n" >&2
  exit 255
}
print_help() {
  cat <<EOF

AI Pipeline by Jiab77

Usage: $SCRIPT_FILE <prompt> <input-file-1> <input-file-2>
Flags:

  -h | --help       Print this message and exit
  --clear           Clear pipeline memory
  --commit          Manually consolidate messages history with permanent memory
  --chat            Start in 'chat' mode
  --simple          Start in 'simple' mode
  --multi           Start in 'multi' mode

EOF
  exit
}
print_usage() {
  log "\nUsage: $SCRIPT_FILE <prompt> <input-file-1> <input-file-2>\n"
  log "To clear the memory: --clear"
  log "To consolidate the memory: --commit\n"
  exit 1
}
serve() {
  # Backend Selector
  case $BACKEND in
    ollama)
      error "Coming soon! Stay tuned ;-)"
    ;;
    llamacpp)
      log "\n[*] Starting llama-cpp server...\n"
      log "[!] Settings are optimized for small devices.\n"
      LLAMA_CACHE="$LLAMACPP_CACHE" \
      llama-server \
        --models-max 1 \
        --models-autoload \
        --jinja \
        -fa on \
        --swa-full \
        -c "$MAX_CONTEXT" \
        -t "$MAX_CORES" \
        -tb "$MAX_CORES" \
        -b "$MAX_BATCH_SIZE" \
        -ub "$MAX_BATCH_SIZE" \
        -ctk "$QUANTIZATION" \
        -ctv "$QUANTIZATION" \
        --timeout "$MAX_TIMEOUT"
    ;;
    *) error "Unsupported backend given: $BACKEND" ;;
  esac
}
api_call() {
  local payload="$1"
  local curl_opts=("-sfSL")

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
route_request() {
  # Format input query to lowercase
  # local INPUT=$(tr '[:upper:]' '[:lower:]' <<<$1)
  local INPUT="${1,,}"    # Converts $1 to lowercase natively

  # 1. Detect: COMPARE
  # if grep -qE "compare|diff|difference|versus| vs " <<<$INPUT; then
  # if [[ "$INPUT" =~ \b(compare|diff|difference|versus)\b || "$INPUT" =~ [[:space:]]vs[[:space:]] ]]; then
  if [[ "$INPUT" =~ (^|[^[:alnum:]_])(compare|diff|difference|versus)([^[:alnum:]_]|$) || "$INPUT" =~ [[:space:]]vs[[:space:]] ]]; then
    echo "COMPARE"
    return
  fi

  # 2. Detect: TASK (Action / Modification)
  # if grep -qE "add|edit|fix|optimize|change|update|write|create|refactor|generate" <<<$INPUT; then
  # if [[ "$INPUT" =~ \b(add|edit|fix|optimize|change|update|write|create|refactor|generate)\b ]]; then
  if [[ "$INPUT" =~ (^|[^[:alnum:]_])(add|edit|fix|optimize|change|update|write|create|refactor|generate)([^[:alnum:]_]|$) ]]; then
    echo "TASK"
    return
  fi

  # 3. Detect: QUESTION
  # If user asks for "explain", "analyze", "help", "how to", "why", etc.
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
  log "\n[*] Cleaning memory...\n"
  read -rp "What do you want to clear? [1. Memory, 2. Messages]: " USER_CHOICE
  [[ -z $USER_CHOICE ]] && error "No selection given. Nothing deleted."
  if [[ $USER_CHOICE == 1 ]]; then
    rm -f "${DATA_STORE}/${MEMORY_FILE}"
  elif [[ $USER_CHOICE == 2 ]]; then
    rm -f "${DATA_STORE}/${MESSAGES_FILE}"
  else
    error "Invalid selection given: $USER_CHOICE"
  fi
  # exit $?
  return
}
handle_response() {
  local response="$1"
  local prompt="$2"
  local label="${3:-RESPONSE}"

  if [[ -n $response && ! $response == "null" ]]; then
    log "\n\n=== $label ===\n\n"
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
    log "\n[🧠] Heartbeat threshold pulsing (Messages: ${messages_count}/${HEARTBEAT_THRESHOLD} | Force: ${force})."
    log "[🧠] Automatically consolidating session context into ${memory_filename}..."

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
      --rawfile usr "$TEMP_MEMORY_USER" \
      '{
        model: $model,
        messages: [
          {role: "system", content: $sys},
          {role: "user", content: $usr}
        ],
        temperature: 0.1,
        stream: false
      }'
    )

    # Clean up temporary files immediately
    rm -f "$TEMP_MEMORY_SYSTEM" "$TEMP_MEMORY_USER"

    log "[🧠] Invoking $GEMINI_API_MODEL for synthesis..."
    raw_response=$(api_call "$payload")
    if [[ -z $raw_response || $raw_response == "null" ]]; then
      log "[!] Warning: Memory consolidation API call returned empty response."
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
      log "[🧠] Permanent '$memory_filename' successfully consolidated & synchronized!"

      # Truncate messages.json to keep only the System Prompt (index 0) and the last 4 messages to preserve flow.
      log "[🧠] Pruning '$messages_filename' to free up conversational context tokens..."
      jq -rc '[.[0]] + .[-4:]' "$messages_path" > "${messages_path}.tmp"
      mv -f "${messages_path}.tmp" "$messages_path"
      log "[🧠] $messages_filename successfully pruned! Context is now ultra-light and ready to resume."
    else
      log "[!] Error: Consolidated output was not valid JSON. Memory consolidation aborted to prevent corruption."
      log "[Debug] Raw response payload was: ${consolidated_json:0:400}..."
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
      log "[Debug] Sending message to 'ollama'..."
      JSON_PAYLOAD=$(jq -rc -n \
        --arg model "$OLLAMA_ARCHITECT" \
        --arg prompt "$combined" \
        '{
          model: $model,
          prompt: $prompt,
          stream: false
        }'
      )

      # Sending request and store response
      RESPONSE=$(api_call "$JSON_PAYLOAD")
      # RESPONSE=$(curl -sfSL "${OLLAMA_API_URL}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" | jq -rc '.response')
      # RESPONSE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_ARCHITECT" <<<$SIMPLE_PROMPT | grep "Response:" | tail -n 1 | cut -d' ' -f2)
      echo "[AI] $(jq -rc '.response' <<<"$RESPONSE")" | render_markdown
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      log "[Debug] Sending message to 'llama.cpp'..."
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
      # RESPONSE=$(curl -sfSL "${LLAMACPP_API_URL}" -H "Content-Type: application/json" -H "Authorization: Bearer no-key" -d "$JSON_PAYLOAD" | jq -rc '.choices[0].message.content')
      # RESPONSE=$(LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_ARCHITECT" $LLAMACPP_FLAGS --temp 0.2 -rea off -p "$SIMPLE_PROMPT" 2>&1 | grep -v '>' | grep "Response:" | tail -n 1 | cut -d' ' -f2)
      echo "[AI] $(jq -rc '.choices[0].message.content' <<<"$RESPONSE")" | render_markdown
    ;;

    # External Backend: OpenRouter / Gemini
    gemini)
      log "\n[Debug] Sending message to 'gemini'..."

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
        printf "%s" "$TOOLS_CONTENT" > "$TEMP_PAYLOAD_TOOLS"

        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$GEMINI_API_MODEL" \
          --rawfile msgs "$TEMP_PAYLOAD_MESSAGES" \
          --rawfile tools "$TEMP_PAYLOAD_TOOLS" \
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
            error "API Error: $err_msg"
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
          echo "[Thinking] $REASONING" | render_markdown
        fi

        # Handling model refusal
        if [[ -n $REFUSAL && ! $REFUSAL == "null" ]]; then
          echo "[AI] $REFUSAL" | render_markdown
        fi

        # Handling model intermediary response
        # if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
        #   log "\n\n=== INTERMEDIARY RESPONSE ===\n\n"
        #   echo "$RESPONSE" | render_markdown
        # fi

        # Handling model requested tools (Multi-Parallel Support)
        if [[ -n $TOOLS && ! $TOOLS == "null" ]]; then
          # log "\n\n[SYS] Tools:\n\n"
          # jq . <<<"$TOOLS"

          # 1. Grab assistant command message and push to history
          ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<"$RAW_RESPONSE")
          ALL_MESSAGES=$(jq -rc --argjson ast "$ASSISTANT_MSG" '. + [$ast]' <<<"$ALL_MESSAGES")

          # 2. Extract and iterate over all requested parallel tools (Single-jq process optimized stream)
          local tool_count=0
          while IFS= read -r -d '' tool_id && IFS= read -r -d '' tool_name && IFS= read -r -d '' tool_args; do
            ((tool_count++))
            log "\n[+] Tool (${tool_count}) AI model wants to run: $tool_name\n[+] With the following arguments: $tool_args\n"

            # 3. Check and execute tool handler
            if [[ -x $TOOLS_HANDLER ]]; then
              "$TOOLS_HANDLER" "$tool_name" "$tool_args" &> "$TOOLS_OUTPUT"
            else
              echo "Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing." > "$TOOLS_OUTPUT"
              log "[!] Warning: Tool handler not executable."
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
                log "[!] Warning: fromjson failed, using fallback --arg serialization"
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
              log "[!] Warning: Unable to parse tool output with rawfile, using fallback formatting"
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
          # echo -e "\n\n**SENDING NEW MODEL DATA**\n\n" | render_markdown

        # Handling model final response
        else
          if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
            # log "\n\n=== FINAL RESPONSE ===\n\n"
            echo "[AI] $RESPONSE" | render_markdown

            # Store final AI response
            ALL_MESSAGES=$(jq -rc --arg ast "$RESPONSE" '. + [{role: "assistant", content: $ast}]' <<<"$ALL_MESSAGES")
            echo "$ALL_MESSAGES" > "${DATA_STORE}/${MESSAGES_FILE}"
          fi
          break   # Leaving the loop
        fi

        # Handling model usage
        if [[ -n $USAGE && ! $USAGE == "null" ]]; then
          log "[+] Usage:"
          log "  - Prompt Tokens: $(jq -rc .prompt_tokens <<<"$USAGE")"
          log "  - Cached Tokens: $(jq -rc .prompt_tokens_details.cached_tokens <<<"$USAGE")"
          log "  - Completion Tokens: $(jq -rc .completion_tokens <<<"$USAGE")"
          log "  - Reasoning Tokens: $(jq -rc '.completion_tokens_details.reasoning_tokens // 0' <<<"$USAGE")"
          log "  - Total Tokens: $(jq -rc .total_tokens <<<"$USAGE")"
          log "  - Cost: $(jq -rc .cost <<<"$USAGE")"
          # jq . <<<"$USAGE"
        fi
      done
    ;;
  esac

  # Autonomous Memory Consolidation Heartbeat
  check_and_trigger_heartbeat
}
run_chat() {
  log "\n[+] Starting 'chat' mode...\n"

  while true; do
    log ; read -rp "Enter your message or /help: " USER_MSG

    # Do nothing when user message is empty (at least for now)
    if [[ -n $USER_MSG ]]; then
      case $USER_MSG in
        "/help")
          cat <<EOF

Here is all supported commands:

  /help       Print this screen
  /clear      Clear pipeline memory
  /commit     Commit session history to long-term memory immediately
  /run <cmd>  Execute a shell command locally
  /start      Start pipeline and exit
  /quit       Exit

EOF
        ;;
        "/run")
          log "\n[!] Usage: /run <command>\n"
        ;;
        "/run "*)
          local cmd="${USER_MSG#"/run "}"
          log "\n[+] Executing: ${cmd}\n"
          eval "$cmd"
        ;;
        "/clear") clear_memory ;;
        "/commit") check_and_trigger_heartbeat "true" ;;
        "/start")
          read -rp "Enter your pipeline prompt: " PIPELINE_PROMPT
          if [[ -n $PIPELINE_PROMPT ]]; then
            USER_PROMPT="$PIPELINE_PROMPT"
            run_pipeline
          fi
        ;;
        "/quit") break ;;
        *)
          log "\n[User] $USER_MSG"
          send_message "$USER_MSG"
        ;;
      esac
    fi
  done

  log "\nOk! Bye then and have fun! :P\n" ; exit
}
run_pipeline() {
  log "\n[+] Starting 'pipeline' mode...\n"

  # Context
  if [[ -n $INPUT_FILE2 && -r $INPUT_FILE && -r $INPUT_FILE2 ]]; then
    CONTEXT_DATA="File A ($(basename "$INPUT_FILE")):\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`\nFile B ($(basename "$INPUT_FILE2")):\n\n\`\`\`\n$(<"$INPUT_FILE2")\n\`\`\`\n"
  elif [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
    CONTEXT_DATA="File '$(basename "$INPUT_FILE")':\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`"
  else
    CONTEXT_DATA="**No file provided.**"
  fi

  # Routing
  log "\n[*] Analyzing user request...\n"
  INTENT=$(route_request "$USER_PROMPT")
  if [[ -z $INTENT ]]; then
    error "Intent could not be detected."
  else
    log "[+] Detected intent: ${INTENT}\n"
  fi

  # Route A: Question Mode (including TASK-intent fallback)
  # TODO: Finish the 'task' part
  if [[ "${INTENT,,}" == "question" || "${INTENT,,}" == "explanation" || "${INTENT,,}" == "task" ]]; then
    # SYSTEM_PROMPT="The user has a question, reply to it."
    SIMPLE_PROMPT="Question: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
    SIMPLE_PROMPT_COMBINED="${SYSTEM_PROMPT}\n\nStart your reply with 'Response: '\n\nQuestion: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"

    # Backend Selector
    case $BACKEND in
      # Local Backend: Ollama
      ollama)
        log "\nQuestion mode detected. Calling the Architect ($OLLAMA_ARCHITECT)...\n"
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
        # RESPONSE=$(curl -sfSL "${OLLAMA_API_URL}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" | jq -rc '.response')
        # RESPONSE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_ARCHITECT" <<<$SIMPLE_PROMPT | grep "Response:" | tail -n 1 | cut -d' ' -f2)
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # Local Backend: llama.cpp
      llamacpp)
        log "\n[+] Question mode detected. Calling the Architect ($LLAMACPP_ARCHITECT)...\n"
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
        # RESPONSE=$(curl -sfSL "${LLAMACPP_API_URL}" -H "Content-Type: application/json" -H "Authorization: Bearer no-key" -d "$JSON_PAYLOAD" | jq -rc '.choices[0].message.content')
        # RESPONSE=$(LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_ARCHITECT" $LLAMACPP_FLAGS --temp 0.2 -rea off -p "$SIMPLE_PROMPT" 2>&1 | grep -v '>' | grep "Response:" | tail -n 1 | cut -d' ' -f2)
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # External Backend: OpenRouter / Gemini
      gemini)
        log "\n[+] Question mode detected. Calling Gemini ($GEMINI_API_MODEL)...\n"
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
          printf "%s" "$TOOLS_CONTENT" > "$TEMP_PAYLOAD_TOOLS"

          JSON_PAYLOAD=$(jq -rc -n \
            --arg model "$GEMINI_API_MODEL" \
            --rawfile msgs "$TEMP_PAYLOAD_MESSAGES" \
            --rawfile tools "$TEMP_PAYLOAD_TOOLS" \
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
            log "\n\n=== RAW RESPONSE ===\n\n"
            jq . <<<"$RAW_RESPONSE"

            # Check for errors before continuing
            if jq -e '.error' <<<"$RAW_RESPONSE" &>/dev/null; then
              err_msg=$(jq -rc '.error.message' <<<"$RAW_RESPONSE")
              error "API Error: $err_msg"
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
            log "\n\n=== REASONING ===\n\n"
            echo "$REASONING" | render_markdown
          fi

          # Handling model refusal
          if [[ -n $REFUSAL && ! $REFUSAL == "null" ]]; then
            log "\n\n=== REFUSAL ===\n\n"
            echo "$REFUSAL" | render_markdown
          fi

          # Handling model intermediary response
          if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
            log "\n\n=== INTERMEDIARY RESPONSE ===\n\n"
            echo "$RESPONSE" | render_markdown
          fi

          # Handling model requested tools (Multi-Parallel Support)
          if [[ -n $TOOLS && ! $TOOLS == "null" ]]; then
            log "\n\n=== TOOLS REQUEST ===\n\n"
            jq . <<<"$TOOLS"

            # 1. Grab assistant command message and push to history
            ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<"$RAW_RESPONSE")
            ALL_MESSAGES=$(jq -rc --argjson ast "$ASSISTANT_MSG" '. + [$ast]' <<<"$ALL_MESSAGES")

            # 2. Extract and iterate over all requested parallel tools (Single-jq process optimized stream)
            local tool_count=0
            while IFS= read -r -d '' tool_id && IFS= read -r -d '' tool_name && IFS= read -r -d '' tool_args; do
              ((tool_count++))
              log "\n[+] Tool (${tool_count}) AI model wants to run: $tool_name\n[+] With the following arguments: $tool_args\n"

              # 3. Check and execute tool handler
              if [[ -x $TOOLS_HANDLER ]]; then
                "$TOOLS_HANDLER" "$tool_name" "$tool_args" &> "$TOOLS_OUTPUT"
              else
                echo "Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing." > "$TOOLS_OUTPUT"
                log "[!] Warning: Tool handler not executable."
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
                  log "[!] Warning: fromjson failed, using fallback --arg serialization"
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
                log "[!] Warning: Unable to parse tool output with rawfile, using fallback formatting"
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
            echo -e "\n\n**SENDING NEW MODEL DATA**\n\n" | render_markdown

          # Handling model final response
          else
            if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
              log "\n\n=== FINAL RESPONSE ===\n\n"
              echo "$RESPONSE" | render_markdown
            fi
            break   # Leaving the loop
          fi

          # Handling model usage
          if [[ -n $USAGE && ! $USAGE == "null" ]]; then
            log "\n\n=== USAGE ===\n\n"
            jq . <<<"$USAGE"
          fi
        done
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac
    exit $?   # End of Question Mode

  # Route B: Compare Mode
  elif [[ "${INTENT,,}" == "compare" ]]; then
    COMPARE_PROMPT="${SYSTEM_PROMPT}\n\nThe user wants to compare two files, show the main differences.\n\nContext:\n${CONTEXT_DATA}"
    COMPARE_PROMPT_COMBINED="${SYSTEM_PROMPT}\n\nThe user wants to compare two files, show the main differences.\n\nRequest: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
    # COMPARE_PROMPT_COMBINED="${SYSTEM_PROMPT}\n\nThe user wants to compare two files, show the main differences. Start your reply with 'Response:'\n\nRequest: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"

    # Backend Selector
    case $BACKEND in
      # Local Backend: Ollama
      ollama)
        log "\nCompare mode detected. Calling the Architect ($OLLAMA_ARCHITECT)...\n"
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
        # RESPONSE=$(curl -sfSL "${OLLAMA_API_URL}" -H "Content-Type: application/json" -d "$JSON_PAYLOAD" | jq -rc '.response')
        # RESPONSE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_ARCHITECT" <<<$COMPARE_PROMPT | grep "Response:" | tail -n 1)
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # Local Backend: llama.cpp
      llamacpp)
        log "\nCompare mode detected. Calling the Architect ($LLAMACPP_ARCHITECT)...\n"
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
        # RESPONSE=$(curl -sfSL "${LLAMACPP_API_URL}" -H "Content-Type: application/json" -H "Authorization: Bearer no-key" -d "$JSON_PAYLOAD" | jq -rc '.choices[0].message.content')
        handle_response "$RESPONSE" "$USER_PROMPT"
      ;;

      # External Backend: OpenRouter / Gemini
      gemini)
        log "\nCompare mode detected. Calling Gemini ($GEMINI_API_MODEL)...\n"
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
          log "\n\n=== RAW RESPONSE ===\n\n"
          jq . <<<"$RAW_RESPONSE"

          # Check for errors before continuing
          if jq -e '.error' <<<"$RAW_RESPONSE" &>/dev/null; then
            err_msg=$(jq -rc '.error.message' <<<"$RAW_RESPONSE")
            error "API Error: $err_msg"
          fi

          # Store relevant data
          REASONING=$(jq -rc '.choices[0].message.reasoning' <<<"$RAW_RESPONSE")
          RESPONSE=$(jq -rc '.choices[0].message.content' <<<"$RAW_RESPONSE")
          REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<"$RAW_RESPONSE")
          USAGE=$(jq -rc '.usage' <<<"$RAW_RESPONSE")
        fi

        # Handling model reasoning
        if [[ -n $REASONING && ! $REASONING == "null" ]]; then
          log "\n\n=== REASONING ===\n\n"
          echo "$REASONING" | render_markdown
        fi

        # Handling model refusal
        if [[ -n $REFUSAL && ! $REFUSAL == "null" ]]; then
          log "\n\n=== REFUSAL ===\n\n"
          echo "$REFUSAL" | render_markdown
        fi

        # Handling model final response
        if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
          log "\n\n=== RESPONSE ===\n\n"
          echo "$RESPONSE" | render_markdown
        fi

        # Handling model usage
        if [[ -n $USAGE && ! $USAGE == "null" ]]; then
          log "\n\n=== USAGE ===\n\n"
          jq . <<<"$USAGE"
        fi
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac
    exit $?   # End of Compare Mode

  # Route C: Task Mode
  else
    exit 1

    ### /!\ MAKING SURE THE CODE BELOW DOES NOT RUN AS IT MUST BE REWRITEN /!\ ###

    if [[ $RUN_MODE == "multi" ]]; then
      log "\nTask mode detected. Running heavy pipeline.\n"
      if [[ $BACKEND == "ollama" ]]; then
        log "[1/3] The Architect ($OLLAMA_ARCHITECT) will prepare the plan...\n"
        ARCHITECT_PROMPT="The user wants to make some changes: $USER_PROMPT. Analyze the file and create an action plan for the coder model.\n\nContext:\n$CONTEXT_DATA"
        ACTION_PLAN=$(ollama run $OLLAMA_FLAGS "$OLLAMA_ARCHITECT" <<<"$ARCHITECT_PROMPT")
        log "\n[2/3] The Coder ($OLLAMA_CODER) will write the code...\n"
        CODER_PROMPT="Follow this action plan on the given file ($INPUT_FILE). Return only the updated code without anything else. Don't use Markdown.\n\nPlan:\n$ACTION_PLAN\n\nContext:\n$CONTEXT_DATA"
        RETURNED_CODE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_CODER" <<<"$CODER_PROMPT" | sed '1d;$d')
        log "\n[3/3] The Judge ($OLLAMA_JUDGE) will inspect the changes...\n"
        JUDGE_PROMPT="Verify that there is no syntax errors or regressions in the updated code compared to the original.\n\nOriginal:\n$CONTEXT_DATA\n\nUpdated:\n$RETURNED_CODE"
        FINAL_REPORT=$(ollama run $OLLAMA_FLAGS "$OLLAMA_JUDGE" <<<"$JUDGE_PROMPT")
      fi
      log "\n\n=== JUDGE REPORT ===\n\n"
      echo "$FINAL_REPORT" | handle_markdown
    else
      if [[ $BACKEND == "ollama" ]]; then
        log "\n[1/1] The Coder ($OLLAMA_CODER) will write the code...\n"
        CODER_PROMPT="Follow the user prompt for the given file ($INPUT_FILE). Return only the updated code without anything else. Don't use Markdown.\n\nContext:\n$CONTEXT_DATA"
        RETURNED_CODE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_CODER" <<<$CODER_PROMPT | sed '1d;$d')
      fi
    fi
    if [[ -n $RETURNED_CODE ]]; then
      log "\n\n+++ WRITING CHANGES +++\n\n"
      echo "$RETURNED_CODE" > "${INPUT_FILE}.new"
      log "\n[Finished] Code written in ${INPUT_FILE}.new\n"
    else
      log "\n[Done]\n"
    fi
    exit $?   # End of Task Mode
  fi
}

# Checks
[[ $# -eq 0 && ! $RUN_MODE == "chat" ]] && print_usage

# Flags
while [[ $# -ne 0 ]]; do
  case $1 in
    # Help
    -h|--help) print_help ;;

    # Clean
    --clear) clear_memory ;;

    # Consolidate
    --commit) check_and_trigger_heartbeat "true" ;;

    # Modes
    --chat)
      log "\n[+] Entering to 'chat' mode.\n"
      RUN_MODE="chat" ; shift
    ;;
    --multi)
      log "\n[+] Entering to 'multi' mode.\n"
      RUN_MODE="multi" ; shift
    ;;
    --simple)
      log "\n[+] Entering to 'simple' mode.\n"
      RUN_MODE="simple" ; shift
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
[[ -r $BASE_TOOLS ]] && TOOLS_CONTENT=$(<"$BASE_TOOLS")
if [[ $USE_TOR == true && $BACKEND == "gemini" ]]; then
  log "\n[*] Checking Tor service...\n"
  if ! timeout 2 bash -c '</dev/tcp/0/9050' &>/dev/null; then
    error "Tor proxy ($TOR_PROXY) is configured but unreachable. Is the Tor service running?"
  fi
fi
if [[ $BACKEND == "gemini" ]]; then
  [[ -r $CREDENTIALS ]] && GEMINI_API_KEY=$(<"$CREDENTIALS")
  [[ -z $GEMINI_API_KEY ]] && error "Missing API Key. Set 'GEMINI_API_KEY' or Create a '.creds' file with your API key inside and try again."
fi

# Download models when necessary
if [[ $PULL_MODELS == true ]]; then
  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      # Downloading models for ollama
      log "\n[*] Pulling required models for Ollama...\n"
      [[ -n $OLLAMA_ROUTER ]] && OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_ROUTER"
      OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_ARCHITECT"
      OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_CODER"
      OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_JUDGE"
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      # Downloading models for llama.cpp
      log "\n[*] Pulling required models for llama.cpp...\n"
      # TODO: Find a better way to preload models
      # Note: The current way is a bit intensive for small laptops and mobile devices
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_ROUTER}:${QUANTIZATION^^}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_ARCHITECT}:${QUANTIZATION^^}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_CODER}:${QUANTIZATION^^}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
      LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "${LLAMACPP_JUDGE}:${QUANTIZATION^^}" -c $MAX_CONTEXT --simple-io -st -p hello &>/dev/null ; sleep 5
    ;;
  esac
fi

# Main
if [[ $RUN_MODE == "chat" ]]; then
  run_chat
else
  run_pipeline
fi
