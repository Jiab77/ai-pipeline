#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# lib/helpers.sh — Shared project functions
# ==============================================================================
# Provides source-only shared functions
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.0.0
#
# Contract: TBD
#
# Dependencies: TBD
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Log and exit helper
die() {
  echo -e "\nError: $*\n" >&2
  exit 255
}

# Filtering helper
#
# Narrows a provider catalogue to the models matching one operation.
#
# Why a per-provider case and not a generic filter: there is no common
# modality key across the catalogues. Each provider states its capability
# at a different place, so the filter names that place explicitly.
#
# A provider whose catalogue carries no modality at all is NOT filtered
# down to an empty list: it fails with a clear message, because "no
# metadata" is not "no capability". Filtering by model name would be
# guessing.
#
# Operation vocabulary (direction X2Y):
#   chat  text  -> text        i2t  image -> text
#   t2i   text  -> image       v2t  video -> text
#   i2i   image -> image       tts  text  -> speech
#   t2v   text  -> video       stt  speech -> text
#   i2v   image -> video
#
# `vision` and `asr` are accepted as legacy aliases of `i2t` and `stt`
# until the schema enum is updated.
filter_provider_models() {
  local provider="$1"
  local operation="$2"

  # No operation requested: return the provider catalogue unchanged.
  [[ -z $operation ]] && {
    cat
    return 0
  }

  case "$provider:$operation" in

  # "all" means no filtering, for every provider: it is a query parameter,
  # never a model attribute, so there is nothing to select on.
  *:all)
    cat
  ;;

  # ── Venice ──────────────────────────────────────────────────────────
  # reads: type (all|text|image|inpaint|video|tts|asr)
  #
  # Every direction is filtered locally, even the ones core.sh already
  # narrows with ?type=. The local filter is the authoritative one: the
  # URL mapping has no ?type= branch for stt, so trusting the query would
  # return the whole catalogue as if it were speech-to-text.
  venice:chat)
    jq '.data |= map(select(.type == "text"))'
  ;;

  venice:t2i)
    jq '.data |= map(select(.type == "image"))'
  ;;

  venice:i2i)
    jq '.data |= map(select(.type == "inpaint"))'
  ;;

  venice:tts)
    jq '.data |= map(select(.type == "tts"))'
  ;;

  venice:stt|venice:asr)
    jq '.data |= map(select(.type == "asr"))'
  ;;

  # reads: model_spec.constraints.model_type (one video list, two directions)
  venice:t2v)
    jq '.data |= map(select(
      .model_spec.constraints.model_type == "text-to-video"
    ))'
  ;;

  venice:i2v)
    jq '.data |= map(select(
      .model_spec.constraints.model_type == "image-to-video"
    ))'
  ;;

  # reads: model_spec.capabilities.supportsVision
  venice:i2t|venice:vision)
    jq '.data |= map(select(
      .model_spec.capabilities.supportsVision == true
    ))'
  ;;

  # reads: model_spec.capabilities.supportsVideoInput
  venice:v2t)
    jq '.data |= map(select(
      .model_spec.capabilities.supportsVideoInput == true
    ))'
  ;;

  # ── OpenRouter ──────────────────────────────────────────────────────
  # reads: architecture.input_modalities / architecture.output_modalities
  openrouter*:chat)
    jq '.data |= map(select(
      ((.architecture.output_modalities // []) | index("text")) != null
    ))'
  ;;

  openrouter*:i2t|openrouter*:vision)
    jq '.data |= map(select(
      ((.architecture.input_modalities // []) | index("image")) != null
    ))'
  ;;

  openrouter*:v2t)
    jq '.data |= map(select(
      ((.architecture.input_modalities // []) | index("video")) != null
    ))'
  ;;

  openrouter*:t2i)
    jq '.data |= map(select(
      ((.architecture.output_modalities // []) | index("image")) != null
    ))'
  ;;

  openrouter*:i2i)
    jq '.data |= map(select(
      ((.architecture.input_modalities // []) | index("image")) != null and
      ((.architecture.output_modalities // []) | index("image")) != null
    ))'
  ;;

  openrouter*:t2v)
    jq '.data |= map(select(
      ((.architecture.output_modalities // []) | index("video")) != null
    ))'
  ;;

  openrouter*:i2v)
    jq '.data |= map(select(
      ((.architecture.input_modalities // []) | index("image")) != null and
      ((.architecture.output_modalities // []) | index("video")) != null
    ))'
  ;;

  # Speech output is spelled "audio" in some communities and "speech" in
  # others (Groq below reads "speech"); both mean the same direction.
  openrouter*:tts)
    jq '.data |= map(select(
      (((.architecture.output_modalities // []) | index("audio")) != null)
      or (((.architecture.output_modalities // []) | index("speech")) != null)
    ))'
  ;;

  # reads: input_modalities (audio in), output_modalities (transcription).
  # Was missing: OpenRouter is declared `speech:true` and documents
  # /api/v1/audio/transcriptions, so an unfiltered lookup would treat the
  # whole chat catalogue as speech-to-text.
  openrouter*:stt|openrouter*:asr)
    jq '.data |= map(select(
      (((.architecture.input_modalities // []) | index("audio")) != null)
      and (
        (((.architecture.output_modalities // []) | index("transcription")) != null)
        or (((.architecture.output_modalities // []) | index("text")) != null)
      )
    ))'
  ;;

  # ── Vercel ──────────────────────────────────────────────────────────
  # reads: type, modalities.input, modalities.output, video_capabilities
  vercel*:chat)
    jq '.data |= map(select(.type == "language"))'
  ;;

  vercel*:i2t|vercel*:vision)
    jq '.data |= map(select(
      ((.modalities.input // []) | index("image")) != null
    ))'
  ;;

  vercel*:v2t)
    jq '.data |= map(select(
      ((.modalities.input // []) | index("video")) != null
    ))'
  ;;

  vercel*:t2i)
    jq '.data |= map(select(.type == "image"))'
  ;;

  # reads: modalities.input + modalities.output (both image)
  vercel*:i2i)
    jq '.data |= map(select(
      ((.modalities.input // []) | index("image")) != null and
      ((.modalities.output // []) | index("image")) != null
    ))'
  ;;

  vercel*:t2v)
    jq '.data |= map(select(
      .type == "video" and
      ((.video_capabilities.supported_operations // []) |
        index("text-to-video")) != null
    ))'
  ;;

  vercel*:i2v)
    jq '.data |= map(select(
      .type == "video" and
      ((.video_capabilities.supported_operations // []) |
        index("image-to-video")) != null
    ))'
  ;;

  vercel*:tts)
    jq '.data |= map(select(.type == "speech"))'
  ;;

  vercel*:stt|vercel*:asr)
    jq '.data |= map(select(.type == "transcription"))'
  ;;

  # ── Groq ────────────────────────────────────────────────────────────
  # reads: input_modalities / output_modalities
  groq:chat)
    jq '.data |= map(select(
      ((.output_modalities // ["text"]) | index("text")) != null
    ))'
  ;;

  groq:i2t|groq:vision)
    jq '.data |= map(select(
      ((.input_modalities // []) | index("image")) != null
    ))'
  ;;

  groq:v2t)
    jq '.data |= map(select(
      ((.input_modalities // []) | index("video")) != null
    ))'
  ;;

  # reads: output_modalities = "speech" for TTS, "transcription" for STT
  groq:tts)
    jq '.data |= map(select(
      ((.output_modalities // []) | index("speech")) != null
    ))'
  ;;

  groq:stt|groq:asr)
    jq '.data |= map(select(
      ((.output_modalities // []) | index("transcription")) != null
    ))'
  ;;

  # ── DeepSeek ────────────────────────────────────────────────────────
  # reads: input_modalities / output_modalities
  deepseek:chat)
    jq '.data |= map(select(
      ((.output_modalities // ["text"]) | index("text")) != null
    ))'
  ;;

  deepseek:i2t|deepseek:vision)
    jq '.data |= map(select(
      ((.input_modalities // []) | index("image")) != null
    ))'
  ;;

  # ── Kimi ────────────────────────────────────────────────────────────
  # reads: modalities.input / modalities.output, supports_image_in
  kimi:chat)
    cat
  ;;

  kimi:i2t|kimi:vision)
    jq '.data |= map(select(
      .supports_image_in == true or
      ((.modalities.input // []) | index("image")) != null
    ))'
  ;;

  kimi:v2t)
    jq '.data |= map(select(
      ((.modalities.input // []) | index("video")) != null
    ))'
  ;;

  # ── CyberNeurova ────────────────────────────────────────────────────
  # reads: supports_image_in / supports_video_in
  cyberneurova:chat)
    cat
  ;;

  cyberneurova:i2t|cyberneurova:vision)
    jq '.data |= map(select(.supports_image_in == true))'
  ;;

  cyberneurova:v2t)
    jq '.data |= map(select(.supports_video_in == true))'
  ;;

  # ── OpenRoute ───────────────────────────────────────────────────────
  # reads: supports_image_in / input_modalities
  openroute:chat)
    cat
  ;;

  openroute:i2t|openroute:vision)
    jq '.data |= map(select(
      .supports_image_in == true or
      ((.input_modalities // []) | index("image")) != null
    ))'
  ;;

  # ── Anthropic ───────────────────────────────────────────────────────
  # reads: capabilities.image_input.supported
  anthropic:chat)
    cat
  ;;

  anthropic:i2t|anthropic:vision)
    jq '.data |= map(select(
      .capabilities.image_input.supported == true
    ))'
  ;;

  # ── Hugging Face ────────────────────────────────────────────────────
  # reads: pipeline_tag (Hub listing — not the chat surface)
  huggingface:*)
    local pipeline_tag
    case "$operation" in
      chat)       pipeline_tag="text-generation" ;;
      i2t|vision) pipeline_tag="image-text-to-text" ;;
      v2t)        pipeline_tag="video-text-to-text" ;;
      t2i)        pipeline_tag="text-to-image" ;;
      i2i)        pipeline_tag="image-to-image" ;;
      t2v)        pipeline_tag="text-to-video" ;;
      i2v)        pipeline_tag="image-to-video" ;;
      tts)        pipeline_tag="text-to-speech" ;;
      stt|asr)    pipeline_tag="automatic-speech-recognition" ;;
      *)          die "Operation filtering is not available for provider '$provider' and operation '$operation'." ;;
    esac

    jq --arg tag "$pipeline_tag" '
      if type == "array"
      then map(select(.pipeline_tag == $tag))
      else .
      end
    '
  ;;

  # ── Providers without any modality in their catalogue ───────────────
  # openai, mammouth, zai and zai_plan publish ids (and sometimes pricing)
  # but never the model modality. There is nothing to filter on, and
  # guessing from the model name would invent capability.
  *)
    die "Operation filtering is not available for provider '$provider' and operation '$operation'."
  ;;

  esac
}


# ------------------------------------------------------------------------------
# Engine v2 plumbing
# ------------------------------------------------------------------------------
# What the media and vocal engines repeat without any protocol in it: the
# capability gate, a private work directory, a transfer whose body never
# enters a shell variable, and the publication of a validated artefact next
# to that directory. What stays in each engine is what actually differs: the
# destination allowlist, the request body and the response shape.
#
# Deliberately absent: HTTP destinations. One allowlist written for every
# engine would authorise a key on endpoints no adapter documented.

# engine_v2_block_field <provider> <block> <field>
# Reads one field of a directional block (image.t2i, video.t2v, voice.tts...).
# Empty when the provider, the block or the field is absent: an absent fact is
# not a default value, and each engine decides what absence means.
engine_v2_block_field() {
  local provider="$1"
  local block="$2"
  local field="$3"

  [[ -r ${PROVIDERS_CONFIG:-} ]] || return 1
  jq -r --arg p "$provider" --arg b "$block" --arg f "$field" '
    ((.[$p]) // {})
    | ((getpath($b | split("."))) // {})
    | (.[$f] // empty)
  ' "$PROVIDERS_CONFIG" 2>/dev/null
}

# engine_v2_block_models <provider> <block>
# One static model id per line. Present only for the catalogues that publish
# no modality (openai, mammouth, zai, cyberneurova); every other provider is
# discovered at call time, so this returns nothing there.
engine_v2_block_models() {
  local provider="$1"
  local block="$2"

  [[ -r ${PROVIDERS_CONFIG:-} ]] || return 1
  jq -r --arg p "$provider" --arg b "$block" '
    ((.[$p]) // {})
    | ((getpath($b | split("."))) // {})
    | (.models // [])[]
  ' "$PROVIDERS_CONFIG" 2>/dev/null
}

# engine_v2_documentation <provider> <field>
# Free-form provider facts that are not part of a directional block: the chat
# `url`, the model catalogue URL, an API version.
engine_v2_documentation() {
  local provider="$1"
  local field="$2"

  [[ -r ${PROVIDERS_CONFIG:-} ]] || return 1
  jq -r --arg p "$provider" --arg f "$field" '((.[$p]) // {}) | (.[$f] // empty)' \
    "$PROVIDERS_CONFIG" 2>/dev/null
}

# engine_v2_inference_model <provider> <field> <pipeline_tag>
# Picks the first model whose `pipeline_tag` matches, from a Hub-style listing
# declared in the registry (Hugging Face: `.inference`, the hf-inference
# surface). The listing is public, so the call carries NO credentials: a
# catalogue read must never be the reason a key leaves the machine. Prints the
# model id, or nothing when the listing is absent or lists no such tag — the
# caller names the failure, because only it knows the direction at stake.
engine_v2_inference_model() {
  local provider="$1"
  local field="$2"
  local tag="$3"
  local url body

  url=$(engine_v2_documentation "$provider" "$field") || return 1
  [[ -n $url ]] || return 1

  body=$(mktemp) || return 1
  if ! engine_v2_http "$url" "$body" false ''; then
    rm -f "$body"
    printf 'catalogue unreachable (HTTP %s)' "${ENGINE_V2_HTTP_CODE:-none}" >&2
    return 1
  fi
  # A rate-limited Hub answers HTML instead of an array; name that instead of
  # leaking a jq parse error to the user.
  if [[ $(head -c 1 "$body") != '[' ]]; then
    rm -f "$body"
    printf 'catalogue returned HTML, not JSON (rate limit?)' >&2
    return 1
  fi
  jq -r --arg t "$tag" '[.[] | select(.pipeline_tag == $t)][0].id // empty' "$body"
  rm -f "$body"
}

# engine_v2_capable <provider> <capability>
# The booleans are the only human capability decision: true means the provider
# is allowed for that operation and the engine resolves a real model.
engine_v2_capable() {
  local provider="$1"
  local capability="$2"

  [[ -n $provider && -r ${PROVIDERS_CONFIG:-} ]] || return 1
  jq -e --arg p "$provider" --arg c "$capability" \
    'has($p) and (.[$p].default[$c] == true)' \
    "$PROVIDERS_CONFIG" >/dev/null 2>&1
}

# engine_v2_workdir <family>
# Prints a private directory under DATA_STORE/<family>. The caller owns the
# EXIT trap: the artefact must be published OUTSIDE it before the trap runs.
engine_v2_workdir() {
  local family="$1"
  local dir

  [[ -n ${DATA_STORE:-} ]] || return 1
  mkdir -p "$DATA_STORE/$family" || return 1
  dir=$(mktemp -d "$DATA_STORE/$family/$(date +%Y%m%d-%H%M%S).XXXXXX") || return 1
  printf '%s' "$dir"
}

# engine_v2_publish <work> <file> <extension>
# Moves a validated artefact next to the work directory and prints its path.
engine_v2_publish() {
  local work="$1"
  local file="$2"
  local extension="$3"
  local destination

  [[ -n $work && -n $extension && -f $file && ! -L $file ]] || return 1
  destination="${work%/*}/${work##*/}.$extension"
  mv "$file" "$destination" || return 1
  printf '%s' "$destination"
}

# engine_v2_http <url> <output> <auth> <key> [curl arguments...]
# Transport only: HTTPS, no redirect on an authenticated call, Tor when the
# pipeline enables it, response body on disk, HTTP code left in
# ENGINE_V2_HTTP_CODE. The CALLER matches <url> against its own documented
# allowlist before calling: that decision is provider-specific.
engine_v2_http() {
  local url="$1"
  local output="$2"
  local auth="$3"
  local key="$4"
  local code
  local rc
  shift 4

  ENGINE_V2_HTTP_CODE=''
  [[ $url == https://* ]] || return 1

  local -a options ; options=(
    --silent --show-error
    --connect-timeout "${ENGINE_V2_CONNECT_TIMEOUT:-10}"
    --max-time "${ENGINE_V2_TIMEOUT:-180}"
    --proto '=https' --proto-redir '=https'
    --output "$output" --write-out '%{http_code}'
  )
  if [[ ${USE_TOR:-true} == true && -n ${TOR_PROXY:-} ]]; then
    options+=(--proxy "$TOR_PROXY")
  fi

  if [[ $auth == true ]]; then
    [[ -n $key ]] || return 1
    options+=(-H "Authorization: Bearer $key")
  else
    options+=(--location)
  fi

  code=$(curl "${options[@]}" "$@" "$url")
  rc=$?
  # Read by every caller to report the failing status; not used here.
  # shellcheck disable=SC2034
  ENGINE_V2_HTTP_CODE="$code"
  [[ $rc -eq 0 ]] || return 1
  case "$code" in 2??) return 0 ;; *) return 1 ;; esac
}

# engine_v2_audio_valid <file>
engine_v2_audio_valid() {
  local file="$1"

  [[ -s $file ]] || return 1
  ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_type -of csv=p=0 "$file" 2>/dev/null | grep -qx audio
}

# engine_v2_audio_ext <file> — container extension, empty when unrecognised.
engine_v2_audio_ext() {
  local file="$1"
  local format

  format=$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$file" 2>/dev/null) || return 1
  case "$format" in
    *mp3*) printf 'mp3' ;;
    *wav*) printf 'wav' ;;
    *flac*) printf 'flac' ;;
    *ogg*|*opus*) printf 'ogg' ;;
    *aac*) printf 'aac' ;;
    *ipod*|*m4a*|*mov*|*mp4*) printf 'm4a' ;;
    *s16le*|*u16le*|*pcm*|*rawvideo*) printf 'pcm' ;;
    *) return 1 ;;
  esac
}

# engine_v2_strip_audio <input> <output> <extension>
# ffmpeg infers the muxer from the output extension, hence <extension>.
# Stream copy: the samples are untouched, the tags are gone.
engine_v2_strip_audio() {
  local input="$1"
  local output="$2"
  local extension="$3"

  [[ $extension != pcm ]] || return 1
  ffmpeg -nostdin -hide_banner -loglevel error -y -i "$input" \
    -map 0:a -map_metadata -1 -map_chapters -1 -c:a copy "$output"
}
