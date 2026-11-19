#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/memory.sh — Shared memory functions
# ==============================================================================
# Provides source-only shared functions
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.0
#
# Contract: LIB_DEPS
#
# Dependencies: core.sh
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${MEMORY_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'memory.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

MEMORY_SH_LOADED=1

# -----------------------------------------------------------------------------
# Cognitive Freedom Memory Engine (Autonomy & Organic Organization)
# -----------------------------------------------------------------------------

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
- **AUTH tag** comes from \`compute_device_tag()\` in the code \`${LIB_DIR##*/}/tag.sh\`.
- The tag changes **per session** — includes UNIX timestamp in the hash
- On Termux: uses \`settings get secure android_id\` (fallback chain)
- On desktop: uses \`/etc/machine-id\` or \`/var/lib/dbus/machine-id\`

## Your Providers
**Total:** $(jq -rc 'keys | length' "${PROVIDERS_CONFIG}")
**List:** $(jq -rc 'keys | join(", ")' "${PROVIDERS_CONFIG}")
**Config file:** \`${CONFIG_DIR##*/}/providers${ENGINE_VERSION}.json\`

## Your Constraints
- **Rules** (\`${LLM_DIR##*/}/rules.md\`) — Non-negotiable safety boundaries
- **Deny-by-default** — Actions require human consent
- **Workspace containment** — No system directory exploration
- **Anti-XPIA** — \`compute_device_tag()\` + \`wrap_external_content()\`

## Your Memory
- **Persistent:** \`${DATA_STORE##*/}/memory/*.md\` — survives session restarts
- **Transient:** \`${DATA_STORE##*/}/messages.json\` — conversation context (pruned on heartbeat)

## Your Tools
- **Full:**  \`${CONFIG_DIR##*/}/tools.json\`
- **Light:**  \`${CONFIG_DIR##*/}/tools-light.json\`

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
  done < <(find "$dir" -path '*/.git' -prune -o -type f -print 2>/dev/null | sort)
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