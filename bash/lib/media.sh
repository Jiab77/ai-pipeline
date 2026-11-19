#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# lib/media.sh — Shared JarNet functions
# ==============================================================================
# Provides source-only shared functions
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.0
#
# Contract: LIB_DEPS
#
# Dependencies: core.sh, lib/base64.sh
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${MEDIA_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'media.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

MEDIA_SH_LOADED=1

# -----------------------------------------------------------------------------
# Media helpers
# -----------------------------------------------------------------------------

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
media_to_b64() {
  b64e < "$1" > "$TEMP_BASE64_OUTPUT"
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