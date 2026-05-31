#!/usr/bin/env bash

# Minimalist Experimental AI Pipeline by Jiab77
#
# This script handles 'ollama', 'llama.cpp' and 'openrouter' backends.
#
# Lead: Jiab77
# Reviewer: Gemini
#
# Note: This is a WiP and will be improved during next iterations.
# Status: Local models can't be used for my needs, fallback on API models with TOR.
#
# Version: 0.1.0

# Options
[[ -e $HOME/.debug ]] && set -x

# Config
RULES="Don't cut or break lines."
RUN_MODE="chat"    # Expected values: simple, multi, chat
BACKEND="gemini"    # Expected values: ollama, llamacpp or gemini
CREDENTIALS="${HOME}/.creds"    # Or any other location or filename you prefer.
MESSAGES_FILE="messages.json"
ASSISTANT_FILE="assistant.json"
RESPONSE_FILE="response.json"
MEMORY_FILE="memory.json"
PULL_MODELS=false
USE_TOR=true

# Internals
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE//.sh}"
DATA_STORE="${SCRIPT_DIR}/data"
BASE_TOOLS="${SCRIPT_DIR}/tools.json"
TOOLS_HANDLER="${SCRIPT_DIR}/run-tools.sh"
TOOLS_CONTENT="[]"

# Soul
AI_NAME="Jarvis"
SYSTEM_PROMPT="You are ${AI_NAME}, a friendly AI collaborator. Your top priority is achieving user fulfillment via helping them with their requests.\n"
SYSTEM_PROMPT+="Your own memory space is in the '$(basename "$DATA_STORE")' folder, you can organize it the way you want.\n"
SYSTEM_PROMPT+="You must never modify the following files: \`${SCRIPT_FILE}\`, \`${TOOLS_HANDLER}\` and \`${BASE_TOOLS}\`.\n"
SYSTEM_PROMPT+="Modifying these files will simply break the core functionalities of the pipeline."

# Local Models Config
QUANTIZATION="q8_0"   # Suitable for small laptops and mobile devices | Case sensitive, keep it in lowercase
MAX_CONTEXT=8192
MAX_BATCH_SIZE=256
MAX_CORES=$(($(nproc)/2))   # FIXME: May not work well on mobiles devices
MAX_TIMEOUT=1200

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
  --chat            Start in 'chat' mode
  --simple          Start in 'simple' mode
  --multi           Start in 'multi' mode

EOF
  exit
}
print_usage() {
  log "\nUsage: $SCRIPT_FILE <prompt> <input-file-1> <input-file-2>\n"
  log "To clear the memory: --clear\n"
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
        -c $MAX_CONTEXT \
        -t $MAX_CORES \
        -tb $MAX_CORES \
        -b $MAX_BATCH_SIZE \
        -ub $MAX_BATCH_SIZE \
        -ctk $QUANTIZATION \
        -ctv $QUANTIZATION \
        --timeout $MAX_TIMEOUT
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
      	     -d "$payload" | \
      	     jq -rc '.response'
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      curl "${curl_opts[@]}" "${LLAMACPP_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer no-key" \
           -d "$payload" | \
           jq -rc '.choices[0].message.content'
    ;;

    # External Backend: OpenRouter / Gemini
    gemini)
      [[ $USE_TOR == true ]] && curl_opts+=("-x" "socks5h://127.0.0.1:9050")
      curl "${curl_opts[@]}" "${GEMINI_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer ${GEMINI_API_KEY}" \
           -d "$payload" | \
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
  rm -f "${DATA_STORE}/${MEMORY_FILE}"
  rm -f "${DATA_STORE}/${MESSAGES_FILE}"
  exit $?
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
send_message() {
  local prompt="$1"
  local system="$SYSTEM_PROMPT"
  local combined="[System] ${system}\n[User] ${prompt}"

  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      log "[DEBUG] Sending message to 'ollama'..."
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
	    echo "[AI] $(jq -rc '.response' <<<$RESPONSE)" | render_markdown
    ;;

    # Local Backend: llama.cpp
    llamacpp)
      log "[DEBUG] Sending message to 'llama.cpp'..."
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
	    echo "[AI] $(jq -rc '.choices[0].message.content' <<<$RESPONSE)" | render_markdown
    ;;

    # External Backend: OpenRouter / Gemini
    gemini)
      log "[DEBUG] Sending message to 'gemini'..."

      # Loading history file if exist or start from zero
      if [[ -r "${DATA_STORE}/${MESSAGES_FILE}" ]]; then
        ALL_MESSAGES=$(<"${DATA_STORE}/${MESSAGES_FILE}")
      else
        ALL_MESSAGES=$(jq -rc -n --arg sys "$system" '[{role: "system", content: $sys}]')
      fi

      # Adding new user message
      ALL_MESSAGES=$(jq -rc --arg user "$prompt" '. + [{role: "user", content: $user}]' <<<$ALL_MESSAGES)

      # The Magic Loop
      while true; do
	      JSON_PAYLOAD=$(printf '%s\n%s\n' "$ALL_MESSAGES" "$TOOLS_CONTENT" | jq -rc -s \
	        --arg model "$GEMINI_API_MODEL" \
	        '{
	          model: $model,
	          messages: .[0],
	          reasoning: {enabled: true}
	        } + if (.[1] | length) > 0 then {tools: .[1]} else {} end'
	      )
	      [[ -z $JSON_PAYLOAD ]] && error "Unexpected error! Check the logs and try again."

	      # Sending request and store response
	      RAW_RESPONSE=$(api_call "$JSON_PAYLOAD")
	      [[ -z $RAW_RESPONSE ]] && error "Unexpected error! Check the logs and try again."

	      # Handling raw response
	      if [[ -n $RAW_RESPONSE && ! $RAW_RESPONSE == "null" ]]; then
	        # log "\n\n=== RAW RESPONSE ===\n\n"
	        # echo "$RAW_RESPONSE" | jq .

	        # Check for errors before continuing
          if jq -e '.error' <<<$RAW_RESPONSE &>/dev/null; then
            err_msg=$(jq -rc '.error.message' <<<$RAW_RESPONSE)
            error "API Error: $err_msg"
          fi

	        # Store relevant data
	        REASONING=$(jq -rc '.choices[0].message.reasoning' <<<$RAW_RESPONSE)
	        RESPONSE=$(jq -rc '.choices[0].message.content' <<<$RAW_RESPONSE)
	        REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<$RAW_RESPONSE)
	        TOOLS=$(jq -rc '.choices[0].message.tool_calls' <<<$RAW_RESPONSE)
	        USAGE=$(jq -rc '.usage' <<<$RAW_RESPONSE)
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
			    log "\n\n[SYS] Tools:\n\n"
			    echo "$TOOLS" | jq .

          # 1. Grab assistant command message and push to history
          ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<$RAW_RESPONSE)
          ALL_MESSAGES=$(jq -rc --argjson ast "$ASSISTANT_MSG" '. + [$ast]' <<<$ALL_MESSAGES)

          # 2. Extract and iterate over all requested parallel tools
          NUM_TOOLS=$(jq -rc '. | length' <<<$TOOLS)
          log "\n[+] Executing $NUM_TOOLS parallel tool(s)...\n"

          # Looping throught all requested tools
          for ((i=0; i<NUM_TOOLS; i++)); do
			      # Store requested tool
			      TOOL_NAME=$(jq -rc ".[$i].function.name" <<<$TOOLS)
			      TOOL_ARGS=$(jq -rc ".[$i].function.arguments" <<<$TOOLS)
			      TOOL_ID=$(jq -rc ".[$i].id" <<<$TOOLS)
			      log "\n[+] Tool ($((i+1))/${NUM_TOOLS}) AI model wants to run: $TOOL_NAME\n[+] With the following arguments: $TOOL_ARGS\n"

			      # 3. Check and execute tool handler
			      if [[ -x $TOOLS_HANDLER ]]; then
			        TOOL_OUTPUT=$("$TOOLS_HANDLER" "$TOOL_NAME" "$TOOL_ARGS" 2>&1)
			      else
              TOOL_OUTPUT="Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing."
              log "[!] Warning: Tool handler not executable."
			      fi

            # 4. Fallback safeguard for empty output
            if [[ -z $TOOL_OUTPUT ]]; then
              TOOL_OUTPUT="(Tool executed successfully and returned empty stdout)"
            fi

            # 5. Format according to OpenAI guidelines
            TOOL_RESPONSE_MSG=$(jq -rc -n \
              --arg id "$TOOL_ID" \
              --arg name "$TOOL_NAME" \
              --arg content "$TOOL_OUTPUT" \
              '{role: "tool", tool_call_id: $id, name: $name, content: $content}'
            )

            # 6. Append tool output to messages array
            ALL_MESSAGES=$(jq -rc --argjson tool "$TOOL_RESPONSE_MSG" '. + [$tool]' <<<$ALL_MESSAGES)
			    done
			    # echo -e "\n\n**SENDING NEW MODEL DATA**\n\n" | render_markdown

		    # Handling model final response
		    else
			    if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
				    # log "\n\n=== FINAL RESPONSE ===\n\n"
				    echo "[AI] $RESPONSE" | render_markdown

				    # Store final AI response
				    ALL_MESSAGES=$(jq -rc --arg ast "$RESPONSE" '. + [{role: "assistant", content: $ast}]' <<<$ALL_MESSAGES)
            echo "$ALL_MESSAGES" > "${DATA_STORE}/${MESSAGES_FILE}"
			    fi
			    break		# Leaving the loop
		    fi

		    # Handling model usage
		    if [[ -n $USAGE && ! $USAGE == "null" ]]; then
			    log "\n\n[SYS] Usage:\n\n"
			    echo "$USAGE" | jq .
		    fi
	    done
    ;;
  esac
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
  /start      Start pipeline and exit
  /quit       Exit

EOF
        ;;
        "/clear") clear_memory ;;
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
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$OLLAMA_ARCHITECT" \
          --arg prompt "$SIMPLE_PROMPT_COMBINED" \
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
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$LLAMACPP_MODEL" \
          --arg system "$SYSTEM_PROMPT" \
          --arg user "$SIMPLE_PROMPT" \
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
	      ALL_MESSAGES=$(jq -rc -n \
	        --arg sys "$SYSTEM_PROMPT" \
	        --arg user "$SIMPLE_PROMPT" \
	        '[{role: "system", content: $sys}, {role: "user", content: $user}]'
	      )

	      # The Magic Loop
        while true; do
		      JSON_PAYLOAD=$(printf '%s\n%s\n' "$ALL_MESSAGES" "$TOOLS_CONTENT" | jq -rc -s \
		        --arg model "$GEMINI_API_MODEL" \
		        '{
		          model: $model,
		          messages: .[0],
		          reasoning: {enabled: true}
		        } + if (.[1] | length) > 0 then {tools: .[1]} else {} end'
		      )
	        [[ -z $JSON_PAYLOAD ]] && error "Unexpected error! Check the logs and try again."

		      # Sending request and store response
		      RAW_RESPONSE=$(api_call "$JSON_PAYLOAD")
	        [[ -z $RAW_RESPONSE ]] && error "Unexpected error! Check the logs and try again."

		      # Handling raw response
		      if [[ -n $RAW_RESPONSE && ! $RAW_RESPONSE == "null" ]]; then
		        log "\n\n=== RAW RESPONSE ===\n\n"
		        echo "$RAW_RESPONSE" | jq .

		        # Check for errors before continuing
            if jq -e '.error' <<<$RAW_RESPONSE &>/dev/null; then
              err_msg=$(jq -rc '.error.message' <<<$RAW_RESPONSE)
              error "API Error: $err_msg"
            fi

		        # Store relevant data
		        REASONING=$(jq -rc '.choices[0].message.reasoning' <<<$RAW_RESPONSE)
		        RESPONSE=$(jq -rc '.choices[0].message.content' <<<$RAW_RESPONSE)
		        REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<$RAW_RESPONSE)
		        TOOLS=$(jq -rc '.choices[0].message.tool_calls' <<<$RAW_RESPONSE)
		        USAGE=$(jq -rc '.usage' <<<$RAW_RESPONSE)
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
				    echo "$TOOLS" | jq .

            # 1. Grab assistant command message and push to history
            ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<$RAW_RESPONSE)
            ALL_MESSAGES=$(jq -rc --argjson ast "$ASSISTANT_MSG" '. + [$ast]' <<<$ALL_MESSAGES)

            # 2. Extract and iterate over all requested parallel tools
            NUM_TOOLS=$(jq -rc '. | length' <<<$TOOLS)
            log "\n[+] Executing $NUM_TOOLS parallel tool(s)...\n"

            # Looping throught all requested tools
            for ((i=0; i<NUM_TOOLS; i++)); do
				      # Store requested tool
				      TOOL_NAME=$(jq -rc ".[$i].function.name" <<<$TOOLS)
				      TOOL_ARGS=$(jq -rc ".[$i].function.arguments" <<<$TOOLS)
				      TOOL_ID=$(jq -rc ".[$i].id" <<<$TOOLS)
				      log "\n[+] Tool ($((i+1))/${NUM_TOOLS}) AI model wants to run: $TOOL_NAME\n[+] With the following arguments: $TOOL_ARGS\n"

				      # 3. Check and execute tool handler
				      if [[ -x $TOOLS_HANDLER ]]; then
				        TOOL_OUTPUT=$("$TOOLS_HANDLER" "$TOOL_NAME" "$TOOL_ARGS" 2>&1)
				      else
                TOOL_OUTPUT="Error: Tool handler file '$TOOLS_HANDLER' is not executable or missing."
                log "[!] Warning: Tool handler not executable."
				      fi

              # 4. Fallback safeguard for empty output
              if [[ -z $TOOL_OUTPUT ]]; then
                TOOL_OUTPUT="(Tool executed successfully and returned empty stdout)"
              fi

              # 5. Format according to OpenAI guidelines
              TOOL_RESPONSE_MSG=$(jq -rc -n \
                --arg id "$TOOL_ID" \
                --arg name "$TOOL_NAME" \
                --arg content "$TOOL_OUTPUT" \
                '{role: "tool", tool_call_id: $id, name: $name, content: $content}'
              )

              # 6. Append tool output to messages array
              ALL_MESSAGES=$(jq -rc --argjson tool "$TOOL_RESPONSE_MSG" '. + [$tool]' <<<$ALL_MESSAGES)
				    done
				    echo -e "\n\n**SENDING NEW MODEL DATA**\n\n" | render_markdown

			    # Handling model final response
			    else
				    if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
					    log "\n\n=== FINAL RESPONSE ===\n\n"
					    echo "$RESPONSE" | render_markdown
				    fi
				    break		# Leaving the loop
			    fi

			    # Handling model usage
			    if [[ -n $USAGE && ! $USAGE == "null" ]]; then
				    log "\n\n=== USAGE ===\n\n"
				    echo "$USAGE" | jq .
			    fi
		    done
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac
    exit $?		# End of Question Mode

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
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$OLLAMA_ARCHITECT" \
          --arg prompt "$COMPARE_PROMPT_COMBINED" \
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
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$LLAMACPP_MODEL" \
          --arg system "$COMPARE_PROMPT" \
          --arg user "$USER_PROMPT" \
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
        JSON_PAYLOAD=$(jq -rc -n \
          --arg model "$GEMINI_API_MODEL" \
          --arg system "$COMPARE_PROMPT" \
          --arg user "$USER_PROMPT" \
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
          echo "$RAW_RESPONSE" | jq .

	        # Check for errors before continuing
          if jq -e '.error' <<<$RAW_RESPONSE &>/dev/null; then
            err_msg=$(jq -rc '.error.message' <<<$RAW_RESPONSE)
            error "API Error: $err_msg"
          fi

	        # Store relevant data
          REASONING=$(jq -rc '.choices[0].message.reasoning' <<<$RAW_RESPONSE)
          RESPONSE=$(jq -rc '.choices[0].message.content' <<<$RAW_RESPONSE)
          REFUSAL=$(jq -rc '.choices[0].message.refusal' <<<$RAW_RESPONSE)
          USAGE=$(jq -rc '.usage' <<<$RAW_RESPONSE)
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
		      echo "$USAGE" | jq .
		    fi
      ;;
      *) error "Unsupported backend given: $BACKEND" ;;
    esac
    exit $?		# End of Compare Mode

  # Route C: Task Mode
  else
    exit 1

    ### /!\ MAKING SURE THE CODE BELOW DOES NOT RUN AS IT MUST BE REWRITEN /!\ ###

    if [[ $RUN_MODE == "multi" ]]; then
      log "\nTask mode detected. Running heavy pipeline.\n"
      if [[ $BACKEND == "ollama" ]]; then
        log "[1/3] The Architect ($OLLAMA_ARCHITECT) will prepare the plan...\n"
        ARCHITECT_PROMPT="The user wants to make some changes: $USER_PROMPT. Analyze the file and create an action plan for the coder model.\n\nContext:\n$CONTEXT_DATA"
        ACTION_PLAN=$(ollama run $OLLAMA_FLAGS "$OLLAMA_ARCHITECT" <<<$ARCHITECT_PROMPT)
        log "\n[2/3] The Coder ($OLLAMA_CODER) will write the code...\n"
        CODER_PROMPT="Follow this action plan on the given file ($INPUT_FILE). Return only the updated code without anything else. Don't use Markdown.\n\nPlan:\n$ACTION_PLAN\n\nContext:\n$CONTEXT_DATA"
        RETURNED_CODE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_CODER" <<<$CODER_PROMPT | sed '1d;$d')
        log "\n[3/3] The Judge ($OLLAMA_JUDGE) will inspect the changes...\n"
        JUDGE_PROMPT="Verify that there is no syntax errors or regressions in the updated code compared to the original.\n\nOriginal:\n$CONTEXT_DATA\n\nUpdated:\n$RETURNED_CODE"
        FINAL_REPORT=$(ollama run $OLLAMA_FLAGS "$OLLAMA_JUDGE" <<<$JUDGE_PROMPT)
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
    exit $?		# End of Task Mode
  fi
}

# Checks
[[ $# -eq 0 && ! $RUN_MODE == "chat" ]] && print_usage

# Flags
while [[ $# -ne 0 ]]; do
  case $1 in
    # Help
    # TODO: Make a better help screen
    -h|--help)
      log "\nUsage: $(basename "$0") <prompt> <input-file-1> <input-file-2>\n"
      log "To clear the memory: --clear\n"
      exit
    ;;

    # Clean
    --clear) clear_memory ;;

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
[[ -r $BASE_TOOLS ]] && TOOLS_CONTENT=$(<$BASE_TOOLS)
if [[ $USE_TOR == true && $BACKEND == "gemini" ]]; then
  log "\n[*] Checking Tor service...\n"
  if ! timeout 2 bash -c '</dev/tcp/127.0.0.1/9050' &>/dev/null; then
    error "Tor proxy (socks5h://127.0.0.1:9050) is configured but unreachable. Is the Tor service running?"
  fi
fi
if [[ $BACKEND == "gemini" ]]; then
  [[ -r $CREDENTIALS ]] && GEMINI_API_KEY=$(<$CREDENTIALS)
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
