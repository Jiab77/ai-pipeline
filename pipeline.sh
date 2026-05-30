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
# Version: 0.0.0

# Options
[[ -e $HOME/.debug ]] && set -x

# Config
RULES="Don't cut or break lines."
RUN_MODE="multi"
BACKEND="gemini"    # Expected values: ollama, llamacpp or gemini
MEMORY_FILE="PIPELINE_MEMORY.md"
ENABLE_MEMORY=false
PULL_MODELS=false
USE_TOR=true

# Internals
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE//.sh}"
CREDENTIALS="${HOME}/.creds"    # Or any other location or filename you prefer.
BASE_TOOLS="${SCRIPT_DIR}/tools.json"
TOOLS_HANDLER="${SCRIPT_DIR}/run-tools.sh"
TOOLS_CONTENT="[]"

# Gemini 3.5 Flash
GEMINI_API_URL="https://openrouter.ai/api/v1/chat/completions"
GEMINI_API_MODEL="google/gemini-3.5-flash"
GEMINI_API_KEY=""    # /!\ NEVER PUBLISH IT /!\

# Models - Ollama
OLLAMA_API_URL="http://localhost:11434/api/generate"
# OLLAMA_ROUTER="gemma3:1b"
OLLAMA_ARCHITECT="lfm2.5-thinking"
OLLAMA_CODER="qwen2.5-coder:1.5b"
OLLAMA_JUDGE="qwen2.5-coder:3b"
OLLAMA_CACHE="/mnt/models/ollama"

# Models - llama.cpp
LLAMACPP_API_SRV="http://localhost:8080"
LLAMACPP_API_URL="${LLAMACPP_API_SRV}/v1/chat/completions"
# LLAMACPP_ROUTER="ggml-org/gemma-3-1b-it-qat-GGUF"
LLAMACPP_ARCHITECT="LiquidAI/LFM2.5-1.2B-Thinking-GGUF"
LLAMACPP_CODER="Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
LLAMACPP_JUDGE="ibm-granite/granite-4.0-h-micro-GGUF"
LLAMACPP_CACHE="/mnt/models/llama.cpp"

# Internals
OLLAMA_FLAGS="--nowordwrap --hidethinking"
LLAMACPP_FLAGS="--log-disable --simple-io --no-display-prompt --no-show-timings -st"

# Args
USER_PROMPT="$1"
INPUT_FILE="$2"
INPUT_FILE2="$3"

# Functions
log() {
  echo -e "$*" >&2
}
error() {
  echo -e "\n[!] Error: $*\n" >&2
  exit 255
}
api_call() {
  local payload="$1"
  local curl_opts=("-sfSL")

  # Backend Selector
  case $BACKEND in
    ollama)
      curl "${curl_opts[@]}" "${OLLAMA_API_URL}" \
      	     -H "Content-Type: application/json" \
      	     -d "$payload" | \
      	     jq -rc '.response'
    ;;
    llamacpp)
      curl "${curl_opts[@]}" "${LLAMACPP_API_URL}" \
           -H "Content-Type: application/json" \
           -H "Authorization: Bearer no-key" \
           -d "$payload" | \
           jq -rc '.choices[0].message.content'
    ;;
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
  if [[ "$INPUT" =~ \b(compare|diff|difference|versus)\b || "$INPUT" =~ [[:space:]]vs[[:space:]] ]]; then
    echo "COMPARE"
    return
  fi

  # 2. Detect: TASK (Action / Modification)
  # if grep -qE "add|edit|fix|optimize|change|update|write|create|refactor|generate" <<<$INPUT; then
  if [[ "$INPUT" =~ \b(add|edit|fix|optimize|change|update|write|create|refactor|generate)\b ]]; then
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
handle_response() {
  local response="$1"
  local prompt="$2"
  local label="${3:-RESPONSE}"

  if [[ -n $response && ! $response == "null" ]]; then
    log "\n\n=== $label ===\n\n"
    echo "$response" | render_markdown
    if [[ $ENABLE_MEMORY == true ]]; then
      log "\n\n=== SAVING TO MEMORY ===\n\n"
      echo -e "\n---\n\n* Request: ${prompt}\n* Response: ${response}\n\n---\n" >> "$MEMORY_FILE"
    fi
  fi
}

# Clean
if [[ $1 == "--clear" ]]; then
  log "\n[*] Cleaning memory...\n"
  rm -f "$MEMORY_FILE" ; exit $?
fi

# Mode
if [[ $1 == "--simple" ]]; then
  log "\n[+] Entering to 'simple' mode.\n"
  RUN_MODE="simple" ; shift
fi

# Checks
if [[ $# -eq 0 ]]; then
  log "\nUsage: $(basename "$0") <prompt> <input-file-1> <input-file-2>\n"
  log "To clear the memory: --clear\n"
  exit 1
fi
if [[ $USE_TOR == true && $BACKEND == "gemini" ]]; then
  log "\n[*] Checking Tor service...\n"
  if ! timeout 2 bash -c '</dev/tcp/127.0.0.1/9050' &>/dev/null; then
    error "Tor proxy (socks5h://127.0.0.1:9050) is configured but unreachable. Is the Tor service running?"
  fi
fi

# Init
[[ -r $BASE_TOOLS ]] && TOOLS_CONTENT=$(<$BASE_TOOLS)
if [[ $BACKEND == "gemini" ]]; then
  [[ -r $CREDENTIALS ]] && GEMINI_API_KEY=$(<$CREDENTIALS)
  [[ -z $GEMINI_API_KEY ]] && error "Missing API Key. Set 'GEMINI_API_KEY' or Create a '.creds' file with your API key inside and try again."
fi

# Download models when necessary
if [[ $BACKEND == "ollama" && $PULL_MODELS == true ]]; then
  # Downloading models for ollama
  log "\n[*] Pulling required models for Ollama...\n"
  [[ -n $OLLAMA_ROUTER ]] && OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_ROUTER"
  OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_ARCHITECT"
  OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_CODER"
  OLLAMA_MODELS="$OLLAMA_CACHE" ollama pull "$OLLAMA_JUDGE"

# Downloading models for llama.cpp
# else
#   LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_ROUTER" --simple-io -st -p hello &>/dev/null ; sleep 5
#   LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_ARCHITECT" --simple-io -st -p hello &>/dev/null ; sleep 5
#   LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_CODER" --simple-io -st -p hello &>/dev/null ; sleep 5
#   LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_JUDGE" --simple-io -st -p hello &>/dev/null ; sleep 5
fi

# Context
if [[ -n $INPUT_FILE2 && -r $INPUT_FILE && -r $INPUT_FILE2 ]]; then
  CONTEXT_DATA="File A ($(basename "$INPUT_FILE")):\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`\nFile B ($(basename "$INPUT_FILE2")):\n\n\`\`\`\n$(<"$INPUT_FILE2")\n\`\`\`\n"
elif [[ -n $INPUT_FILE && -r $INPUT_FILE ]]; then
  CONTEXT_DATA="File '$(basename "$INPUT_FILE")':\n\n\`\`\`\n$(<"$INPUT_FILE")\n\`\`\`"
else
  CONTEXT_DATA="**No file provided.**"
fi

# Memory
[[ $ENABLE_MEMORY == true && -f $MEMORY_FILE ]] && MEMORY_DATA=$(<"$MEMORY_FILE")

# Step 0 - Routing
log "\n[*] Analyzing user request...\n"
INTENT=$(route_request "$USER_PROMPT")
if [[ -z $INTENT ]]; then
  error "Intent could not be detected."
else
  log "[+] Detected intent: ${INTENT}\n"
fi

# Route A: Question Mode
if [[ "${INTENT,,}" == "question" || "${INTENT,,}" == "explanation" ]]; then
  SYSTEM_PROMPT="The user has a question, reply to it."
  SIMPLE_PROMPT="Question: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
  # SIMPLE_PROMPT="The user has a question. Start your reply with 'Response: '\n\nQuestion: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
  [[ $ENABLE_MEMORY == true && -n $MEMORY_DATA ]] && SIMPLE_PROMPT+="\n\nHistory:\n${MEMORY_DATA}"

  # Backend Selector
  case $BACKEND in
    # Local Backend: Ollama
    ollama)
      log "\nQuestion mode detected. Calling the Architect ($OLLAMA_ARCHITECT)...\n"
      JSON_PAYLOAD=$(jq -n \
        --arg model "$OLLAMA_ARCHITECT" \
        --arg prompt "$SIMPLE_PROMPT" \
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
      JSON_PAYLOAD=$(jq -n \
        --arg model "$LLAMACPP_MODEL" \
        --arg system "$SIMPLE_PROMPT" \
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
      # RESPONSE=$(LLAMA_CACHE="$LLAMACPP_CACHE" llama-cli -hf "$LLAMACPP_ARCHITECT" $LLAMACPP_FLAGS --temp 0.2 -rea off -p "$SIMPLE_PROMPT" 2>&1 | grep -v '>' | grep "Response:" | tail -n 1 | cut -d' ' -f2)
		  handle_response "$RESPONSE" "$USER_PROMPT"
    ;;

    # External Backend: OpenRouter / Gemini
    gemini)
      log "\n[+] Question mode detected. Calling Gemini ($GEMINI_API_MODEL)...\n"
	    ALL_MESSAGES=$(jq -n \
	      --arg system "$SYSTEM_PROMPT" \
	      --arg user "$SIMPLE_PROMPT" \
	      '[{role: "system", content: $system},{role: "user", content: $user}]'
	    )

	    # The Magic Loop
      while true; do
		    # JSON_PAYLOAD=$(jq -n \
		    #   --arg model "$GEMINI_API_MODEL" \
		    #   --argjson msgs "$ALL_MESSAGES" \
		    #   '{
		    #     model: $model,
		    #     tools: '"$(<$BASE_TOOLS)"',
		    #     messages: $msgs,
		    #     reasoning: {enabled: true}
		    #   }'
		    # )
		    JSON_PAYLOAD=$(jq -n \
		      --arg model "$GEMINI_API_MODEL" \
		      --argjson msgs "$ALL_MESSAGES" \
		      --argjson tools "$TOOLS_CONTENT" \
		      '{
		        model: $model,
		        messages: $msgs,
		        reasoning: {enabled: true}
		      } + if ($tools | length) > 0 then {tools: $tools} else {} end'
		    )

		    # Sending request and store response
		    RAW_RESPONSE=$(api_call "$JSON_PAYLOAD")

		    # Handling raw response
		    if [[ -n $RAW_RESPONSE && ! $RAW_RESPONSE == "null" ]]; then
		      log "\n\n=== RAW RESPONSE ===\n\n"
		      echo "$RAW_RESPONSE" | jq .

		      # Check for errors before continuing
          if jq -e '.error' <<<$RAW_RESPONSE &>/dev/null; then
            err_msg=$(jq -r '.error.message' <<<$RAW_RESPONSE)
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
				  if [[ $ENABLE_MEMORY == true ]]; then
					  log "\n\n=== SAVING TO MEMORY ===\n\n"
					  echo -e "\n---\n\n* Request: ${USER_PROMPT}\n* Response: ${RESPONSE}\n\n---\n" >> "$MEMORY_FILE"
				  fi
			  fi

			  # Handling model requested tools
			  # TODO: Implement Parallel Tools Calls (OpenRouter / Gemini)
			  if [[ -n $TOOLS && ! $TOOLS == "null" ]]; then
				  log "\n\n=== TOOLS REQUEST ===\n\n"
				  echo "$TOOLS" | jq .
				  TOOL_NAME=$(jq -rc '.[0].function.name' <<<$TOOLS)
				  TOOL_ARGS=$(jq -rc '.[0].function.arguments' <<<$TOOLS)
				  TOOL_ID=$(jq -rc '.[0].id' <<<$TOOLS)
				  log "\n[+] AI model wants to run: $TOOL_NAME\n[+] With the following arguments: $TOOL_ARGS\n"
				  TOOL_OUTPUT=$("$TOOLS_HANDLER" "$TOOL_NAME" "$TOOL_ARGS" 2>&1)
				  if [[ -n $TOOL_OUTPUT ]]; then
				    ASSISTANT_MSG=$(jq -rc '.choices[0].message' <<<$RAW_RESPONSE)
				    TOOL_RESPONSE_MSG=$(jq -n --arg id "$TOOL_ID" --arg name "$TOOL_NAME" --arg content "$TOOL_OUTPUT" '{role: "tool", tool_call_id: $id, name: $name, content: $content}')
				    ALL_MESSAGES=$(jq --argjson ast "$ASSISTANT_MSG" --argjson tool "$TOOL_RESPONSE_MSG" '. + [$ast, $tool]' <<<$ALL_MESSAGES)
				    echo -e "\n\n**SENDING NEW MODEL DATA**\n\n" | render_markdown
				  fi

			  # Handling model final response
			  else
				  if [[ -n $RESPONSE && ! $RESPONSE == "null" ]]; then
					  log "\n\n=== FINAL RESPONSE ===\n\n"
					  echo "$RESPONSE" | render_markdown
					  if [[ $ENABLE_MEMORY == true ]]; then
						  log "\n\n=== SAVING TO MEMORY ===\n\n"
						  echo -e "\n---\n\n* Request: ${USER_PROMPT}\n* Response: ${RESPONSE}\n\n---\n" >> "$MEMORY_FILE"
					  fi
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
  COMPARE_PROMPT="The user wants to compare two files, show the main differences.\n\nContext:\n${CONTEXT_DATA}"
  # COMPARE_PROMPT="The user wants to compare two files, show the main differences.\n\nRequest: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"
  # COMPARE_PROMPT="The user wants to compare two files, show the main differences. Start your reply with 'Response:'\n\nRequest: ${USER_PROMPT}\n\nContext:\n${CONTEXT_DATA}"

  # Backend Selector
  case $BACKEND in
	  # Local Backend: Ollama
    ollama)
      log "\nCompare mode detected. Calling the Architect ($OLLAMA_ARCHITECT)...\n"
      JSON_PAYLOAD=$(jq -n \
        --arg model "$OLLAMA_ARCHITECT" \
        --arg prompt "$COMPARE_PROMPT" \
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
      JSON_PAYLOAD=$(jq -n \
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
      JSON_PAYLOAD=$(jq -n \
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
          err_msg=$(jq -r '.error.message' <<<$RAW_RESPONSE)
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
		    if [[ $ENABLE_MEMORY == true ]]; then
		      log "\n\n=== SAVING TO MEMORY ===\n\n"
		      echo -e "\n---\n\n* Request: ${USER_PROMPT}\n* Response: ${RESPONSE}\n\n---\n" >> "$MEMORY_FILE"
		    fi
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
fi

exit 1

### /!\ MAKING SURE THE CODE BELOW DOES NOT RUN AS IT MUST BE REWRITEN /!\ ###

# Route C: Task Mode
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
  log "\n\n=== SAVING TO MEMORY ===\n\n"
  echo -e "\n---\n\n* Task: ${USER_PROMPT}\n* Plan:\n${ACTION_PLAN}\n\n---\n" >> "$MEMORY_FILE"
else
  if [[ $BACKEND == "ollama" ]]; then
    log "\n[1/1] The Coder ($OLLAMA_CODER) will write the code...\n"
    CODER_PROMPT="Follow the user prompt for the given file ($INPUT_FILE). Return only the updated code without anything else. Don't use Markdown.\n\nContext:\n$CONTEXT_DATA"
    RETURNED_CODE=$(ollama run $OLLAMA_FLAGS "$OLLAMA_CODER" <<<$CODER_PROMPT | sed '1d;$d')
  fi
  log "\n\n=== SAVING TO MEMORY ===\n\n"
  echo -e "\n---\n\n* Task: ${CODE_PROMPT}\n\n---\n" >> "$MEMORY_FILE"
fi
if [[ -n $RETURNED_CODE ]]; then
  log "\n\n+++ WRITING CHANGES +++\n\n"
  echo "$RETURNED_CODE" > "${INPUT_FILE}.new"
  log "\n[Finished] Code written in ${INPUT_FILE}.new\n"
else
  log "\n[Done]\n"
fi
