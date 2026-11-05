#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# engines/speech.v2.sh — Speech-to-text engine (registry v2)
# ==============================================================================
# Transcribes an audio file through the adapters described by
# config/providers.v2.json, with a local whisper.cpp fallback. Sourced library
# or standalone CLI (Bash 3.2+).
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.0
#
# Contract:
#   transcribe_audio — audio file -> text
#
# Dependencies: core.sh (provider keys and catalogue), lib/helpers.sh,
#               jq, curl, file, ffprobe, base64;
#               whisper-cli (whisper.cpp) for the local engine.
#
# Protocol notes:
#   - `speech` is STT and `voice` is TTS: two engines, two booleans. This
#     engine never synthesizes and never talks to the audio/speech endpoint.
#   - Three wire shapes, declared by `voice.stt.protocol`:
#       multipart : file field + model + optional language (OpenAI-compatible)
#       binary    : raw audio bytes to the model path (Hugging Face router)
#       JSON      : base64 audio in the body (Vercel Gateway, OpenRouter's
#                   documented `input_audio` form)
#     An absent protocol is not a guess: the provider's documented default is
#     named explicitly below.
#   - The input is validated locally (container + audio stream) before any
#     upload, and an empty transcript is an error: nothing is ever sent to the
#     chat on the caller's behalf.
#   - No paid retry, no silent substitution. Recording, the keyboard shortcut
#     and the automatic prompt submission belong to the controller.
# ==============================================================================

# core.sh loads lib/helpers.sh through LIB_DEPS. A harness that sources only
# this engine still gets the shared plumbing: load it once, lazily.
if ! declare -F engine_v2_http >/dev/null; then
  SPEECH_V2_HELPERS="${BASH_SOURCE[0]%/*}/../lib/helpers.sh"
  # shellcheck source=/dev/null
  [[ ! -r $SPEECH_V2_HELPERS ]] || source "$SPEECH_V2_HELPERS"
fi

SPEECH_V2_MAX_UPLOAD=26214400   # 25 MiB documented transcription cap

# Transport tunables read by lib/helpers.sh (engine_v2_http).
ENGINE_V2_CONNECT_TIMEOUT=10
ENGINE_V2_TIMEOUT=180

speech_v2_error() { printf 'STT: %s\n' "$*" >&2; }
speech_v2_warn() {
  if declare -F log_warn >/dev/null; then log_warn "$*"; else speech_v2_error "$*"; fi
}

speech_v2_help() {
  cat <<'EOF'
Usage: speech.v2.sh --audio FILE [options]
  --audio FILE       Audio file to transcribe (required)
  --provider NAME    Override the STT provider, or 'local' for whisper.cpp
  --model ID         Model id, or the whisper.cpp GGUF model path locally
  --language CODE    ISO-639-1 hint (two letters, e.g. fr)
  --help             Show this help

Resolution: --provider > SPEECH_PROVIDER > VOICE_PROVIDER > state.json
.speech/.provider > PROVIDER. Language: --language > AUDIO_LANG > state.json
.lang > LANG, where 'auto' resolves to the machine locale (fr_CH.UTF-8 -> fr).
The transcript is printed on stdout and saved next to the work directory in
data/audio/. An empty transcript is an error. No paid retry; no silent
substitution.
EOF
}

speech_v2_deps() {
  local dependency
  for dependency in jq curl file ffprobe; do
    command -v "$dependency" >/dev/null 2>&1 || { speech_v2_error "Missing dependency: $dependency."; return 1; }
  done
}

speech_v2_allowlist() {
  case "$1" in
    openai)          printf '%s' 'https://api.openai.com/v1/' ;;
    groq)            printf '%s' 'https://api.groq.com/openai/v1/' ;;
    openrouter)      printf '%s' 'https://openrouter.ai/api/v1/' ;;
    venice)          printf '%s' 'https://api.venice.ai/api/v1/' ;;
    zai)             printf '%s' 'https://api.z.ai/api/paas/v4/' ;;
    vercel|vercel_free) printf '%s' 'https://ai-gateway.vercel.sh/v4/ai/' ;;
    huggingface)     printf '%s' 'https://router.huggingface.co/hf-inference/models' ;;
    *) return 1 ;;
  esac
}

speech_v2_documented_endpoint() {
  case "$1" in
    openai)          printf '%s' 'https://api.openai.com/v1/audio/transcriptions' ;;
    groq)            printf '%s' 'https://api.groq.com/openai/v1/audio/transcriptions' ;;
    openrouter)      printf '%s' 'https://openrouter.ai/api/v1/audio/transcriptions' ;;
    venice)          printf '%s' 'https://api.venice.ai/api/v1/audio/transcriptions' ;;
    zai)             printf '%s' 'https://api.z.ai/api/paas/v4/audio/transcriptions' ;;
    vercel|vercel_free) printf '%s' 'https://ai-gateway.vercel.sh/v4/ai/transcription-model' ;;
    huggingface)     printf '%s' 'https://router.huggingface.co/hf-inference/models' ;;
    *) return 1 ;;
  esac
}

# The registry declares `multipart` and `binary` explicitly. When it declares
# nothing, the documented wire shape of that provider applies: JSON with
# base64 audio on the Gateway speech surfaces, multipart on the
# OpenAI-compatible ones.
speech_v2_default_protocol() {
  case "$1" in
    vercel|vercel_free|openrouter) printf '%s' 'json' ;;
    *)                             printf '%s' 'multipart' ;;
  esac
}

# ── Resolution ──────────────────────────────────────────────────────────────

speech_v2_discover_model() {
  local provider="$1"
  local raw
  local model

  raw=$(get_provider_models "$provider" stt) || {
    speech_v2_error "Catalogue lookup failed for '$provider'; availability is unknown."
    return 1
  }
  [[ -n $raw && $raw != null ]] || { speech_v2_error "Empty catalogue for '$provider'."; return 1; }

  if declare -F filter_provider_models >/dev/null; then
    raw=$(filter_provider_models "$provider" stt <<< "$raw") || return 1
  fi

  model=$(jq -r '(if type == "array" then .[0].id else .data[0].id end) // empty' <<< "$raw") || return 1
  [[ -n $model ]] || {
    speech_v2_error "No STT model could be identified for '$provider'; pass --model explicitly."
    return 1
  }
  printf '%s' "$model"
}

speech_v2_model_known() {
  local provider="$1"
  local model="$2"
  local raw

  raw=$(get_provider_models "$provider" stt) || return 1
  [[ -n $raw && $raw != null ]] || return 1
  jq -e --arg m "$model" '
    (if type == "array" then .[] else (.data // [])[] end) | select(.id == $m)
  ' <<< "$raw" >/dev/null 2>&1
}

speech_v2_resolve_remote() {
  local provider="$1"
  local allow configured endpoint static default

  allow=$(speech_v2_allowlist "$provider") || {
    speech_v2_warn "No documented STT adapter for '$provider'; using the local engine."
    SPEECH_V2_LOCAL=true
    return 0
  }
  configured=$(engine_v2_block_field "$provider" "voice.stt" endpoint)
  endpoint="${configured:-$(speech_v2_documented_endpoint "$provider")}"
  [[ -n $endpoint ]] || { speech_v2_error "No endpoint for '$provider'."; return 1; }
  [[ $endpoint == "$allow"* ]] || {
    speech_v2_error "Registry endpoint leaves the documented '$provider' API prefix; refusing to send credentials."
    return 1
  }
  SPEECH_V2_ENDPOINT="$endpoint"

  SPEECH_V2_PROTOCOL=$(engine_v2_block_field "$provider" "voice.stt" protocol)
  SPEECH_V2_PROTOCOL="${SPEECH_V2_PROTOCOL:-$(speech_v2_default_protocol "$provider")}"
  case "$SPEECH_V2_PROTOCOL" in
    multipart|binary|json) ;;
    *) speech_v2_error "Unsupported STT protocol '$SPEECH_V2_PROTOCOL'."; return 1 ;;
  esac

  static=$(engine_v2_block_models "$provider" "voice.stt")
  default=$(engine_v2_block_field "$provider" "voice.stt" default)

  if [[ -n $SPEECH_V2_MODEL ]]; then
    if [[ -n $static ]]; then
      grep -qxF -- "$SPEECH_V2_MODEL" <<< "$static" || {
        speech_v2_error "Model '$SPEECH_V2_MODEL' is not a documented '$provider' STT model."
        return 1
      }
    elif [[ $provider != huggingface ]] && ! speech_v2_model_known "$provider" "$SPEECH_V2_MODEL"; then
      # Hugging Face publishes a Hub listing, not the router surface: the
      # router is authoritative there, so an explicit model is trusted.
      speech_v2_error "Model '$SPEECH_V2_MODEL' is absent from the '$provider' catalogue."
      return 1
    fi
  elif [[ -n $static ]]; then
    SPEECH_V2_MODEL="$default"
    [[ -n $SPEECH_V2_MODEL ]] || { speech_v2_error "No default STT model for '$provider'."; return 1; }
  elif [[ $provider == huggingface ]]; then
    # The registry declares the hf-inference listing (`.inference`): the first
    # ASR model it lists is the default, so a caller no longer needs a repo id.
    SPEECH_V2_MODEL=$(engine_v2_inference_model "$provider" inference 'automatic-speech-recognition') || {
      speech_v2_error "Unable to read the '$provider' inference catalogue; pass --model."
      return 1
    }
    [[ -n $SPEECH_V2_MODEL ]] || {
      speech_v2_error "The '$provider' inference catalogue lists no ASR model; pass --model."
      return 1
    }
  else
    SPEECH_V2_MODEL=$(speech_v2_discover_model "$provider") || return 1
  fi

  has_provider_key "$provider" || { speech_v2_error "Missing provider key for '$provider'."; return 1; }
  SPEECH_V2_KEY=$(decrypt_provider_key "$provider") || return 1
  [[ -n $SPEECH_V2_KEY ]] || { speech_v2_error 'Empty provider key.'; return 1; }
  SPEECH_V2_LOCAL=false
}

speech_v2_resolve() {
  local provider="$SPEECH_V2_PROVIDER"

  SPEECH_V2_LOCAL=false
  if [[ -z $provider || $provider == local ]]; then
    SPEECH_V2_LOCAL=true
    return 0
  fi

  if ! engine_v2_capable "$provider" speech; then
    speech_v2_warn "Provider '$provider' declares no STT capability; using the local engine."
    SPEECH_V2_LOCAL=true
    return 0
  fi

  speech_v2_resolve_remote "$provider"
}

# ── Language ─────────────────────────────────────────────────────────────

speech_v2_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 'fr_CH.UTF-8' -> 'fr'. Prints nothing when the locale carries no language
# (unset, C, POSIX, or anything that is not a two-letter code): a machine
# without a locale is not an error, the caller keeps 'auto'.
speech_v2_from_locale() {
  local locale="${LC_ALL:-${LANG:-}}"

  locale=${locale%%[._@]*}
  locale=${locale%%_*}
  locale=$(speech_v2_lower "$locale")
  [[ $locale =~ ^[a-z]{2}$ ]] || return 0
  printf '%s' "$locale"
}

# Which language the audio is transcribed in.
#   --language > AUDIO_LANG > state.json .lang > LANG
# 'auto' is never a language, it is the absence of one:
#   - AUDIO_LANG holds 'auto' when nothing was chosen for the session (core.sh
#     defines it that way on every start);
#   - the --language flag is filled with AUDIO_LANG by tools.sh, so 'auto' there
#     means "not specified" too, never "detect it for this call". Treating it as
#     explicit would make state.json .lang unreachable and drop a /lang <code>.
# 'auto' therefore only says "keep looking", and LANG is the last source.
#
# An ISO-639-1 code only: a value given explicitly is validated and refused
# when it is a locale; a persisted one that does not validate is ignored
# rather than fatal (cli.sh stores /lang without validating it).
speech_v2_resolve_language() {
  local candidate value

  candidate=$(speech_v2_lower "${SPEECH_V2_LANGUAGE:-}")
  value=$(speech_v2_lower "${AUDIO_LANG:-}")
  for candidate in "$candidate" "$value"; do
    [[ -n $candidate && $candidate != auto ]] || continue
    [[ $candidate =~ ^[a-z]{2}$ ]] || {
      speech_v2_error "Language must be an ISO-639-1 code (two letters, e.g. fr) or 'auto', not '$candidate'."
      return 1
    }
    printf '%s' "$candidate"
    return 0
  done

  if [[ -r ${STATE_FILE:-} ]]; then
    candidate=$(speech_v2_lower "$(jq -r '.lang // empty' "$STATE_FILE" 2>/dev/null)")
    if [[ $candidate =~ ^[a-z]{2}$ ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi

  candidate=$(speech_v2_from_locale)
  if [[ -n $candidate ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  printf '%s' auto
}

# ── Local engine ────────────────────────────────────────────────────────────

speech_v2_local_run() {
  local prefix="$SPEECH_V2_WORK/transcript"

  command -v whisper-cli >/dev/null 2>&1 || {
    speech_v2_error 'Local STT requires whisper-cli (whisper.cpp). No installation is attempted.'
    return 1
  }
  [[ -n $SPEECH_V2_MODEL ]] || {
    speech_v2_error 'Local whisper.cpp needs a model path via --model or WHISPER_CPP_MODEL.'
    return 1
  }

  local -a arguments ; arguments=(-m "$SPEECH_V2_MODEL" -f "$SPEECH_V2_INPUT" -of "$prefix" -otxt)
  [[ -z $SPEECH_V2_LANGUAGE ]] || arguments+=(-l "$SPEECH_V2_LANGUAGE")

  whisper-cli "${arguments[@]}" >/dev/null 2>&1 || {
    speech_v2_error 'whisper-cli failed; no transcript produced.'
    return 1
  }
  [[ -s "${prefix}.txt" ]] || { speech_v2_error 'whisper-cli produced no transcript.'; return 1; }

  jq -n --rawfile text "${prefix}.txt" '{text:$text}' > "$SPEECH_V2_WORK/response.json" || return 1
}

# ── Remote request ──────────────────────────────────────────────────────────

speech_v2_prepare_input() {
  local mime extension

  [[ -f $SPEECH_V2_AUDIO && -r $SPEECH_V2_AUDIO && ! -L $SPEECH_V2_AUDIO ]] || {
    speech_v2_error 'Audio input is not a readable file.'
    return 1
  }
  mime=$(file -b --mime-type "$SPEECH_V2_AUDIO") || return 1
  case "$mime" in
    audio/*|video/webm|video/mp4) ;;
    *) speech_v2_error 'Input is not an audio file.'; return 1 ;;
  esac
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$SPEECH_V2_AUDIO" 2>/dev/null \
    | grep -qx audio || { speech_v2_error 'Input contains no readable audio stream.'; return 1; }

  if [[ $SPEECH_V2_LOCAL != true ]]; then
    [[ $(wc -c < "$SPEECH_V2_AUDIO") -le $SPEECH_V2_MAX_UPLOAD ]] || {
      speech_v2_error 'Input exceeds the 25 MiB transcription cap.'
      return 1
    }
  fi

  extension="${SPEECH_V2_AUDIO##*.}"
  [[ $extension =~ ^[a-zA-Z0-9]{1,5}$ ]] || {
    case "$mime" in
      audio/mpeg) extension=mp3 ;;
      audio/flac|audio/x-flac) extension=flac ;;
      audio/x-wav|audio/wav|audio/wave) extension=wav ;;
      audio/ogg) extension=ogg ;;
      *) extension=bin ;;
    esac
  }
  SPEECH_V2_MIME="$mime"
  SPEECH_V2_INPUT="$SPEECH_V2_WORK/input.$extension"
  cp -- "$SPEECH_V2_AUDIO" "$SPEECH_V2_INPUT" || return 1
}

speech_v2_send() {
  local response="$SPEECH_V2_WORK/response.json"
  local encoded_file format

  case "$SPEECH_V2_PROTOCOL" in
    multipart)
      local -a form ; form=(
        -F "file=@$SPEECH_V2_INPUT;type=$SPEECH_V2_MIME"
        --form-string "model=$SPEECH_V2_MODEL"
        -F 'response_format=json'
      )
      [[ -z $SPEECH_V2_LANGUAGE ]] || form+=(--form-string "language=$SPEECH_V2_LANGUAGE")
      engine_v2_http "$SPEECH_V2_ENDPOINT" "$response" true "$SPEECH_V2_KEY" "${form[@]}" || {
        speech_v2_error "Transcription failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
        return 1
      }
    ;;
    binary)
      engine_v2_http "$SPEECH_V2_ENDPOINT/$SPEECH_V2_MODEL" "$response" true "$SPEECH_V2_KEY" \
        --data-binary "@$SPEECH_V2_INPUT" || {
        speech_v2_error "Transcription failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
        return 1
      }
    ;;
    json)
      # E2BIG: base64 travels via temp file + --rawfile, NEVER via --arg/argv
      # (same house rule as the media path, core.sh:1178). A single argv string is
      # capped at 128 KB (MAX_ARG_STRLEN) — any real audio file blows past it.
      encoded_file="$SPEECH_V2_WORK/audio.b64"
      b64e < "$SPEECH_V2_INPUT" | tr -d '\r\n' > "$encoded_file" || return 1
      if [[ $SPEECH_V2_PROVIDER == vercel || $SPEECH_V2_PROVIDER == vercel_free ]]; then
        jq -n --rawfile audio "$encoded_file" --arg mime "$SPEECH_V2_MIME" --arg language "$SPEECH_V2_LANGUAGE" '
          {audio:$audio, mediaType:$mime}
          + (if $language != "" then {language:$language} else {} end)
        ' > "$SPEECH_V2_WORK/request.json" || return 1
        engine_v2_http "$SPEECH_V2_ENDPOINT" "$response" true "$SPEECH_V2_KEY" \
          -H 'Content-Type: application/json' \
          -H "ai-model-id:$SPEECH_V2_MODEL" \
          -H 'ai-gateway-protocol-version: 0.0.1' \
          -H 'ai-gateway-auth-method: api-key' \
          --data-binary "@$SPEECH_V2_WORK/request.json" || {
          speech_v2_error "Transcription failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
          return 1
        }
      else
        format="${SPEECH_V2_MIME#audio/}"
        [[ $format != x-wav ]] || format=wav
        jq -n --arg model "$SPEECH_V2_MODEL" --rawfile audio "$encoded_file" --arg format "$format" \
          --arg language "$SPEECH_V2_LANGUAGE" '
          {model:$model, input_audio:{data:$audio, format:$format}}
          + (if $language != "" then {language:$language} else {} end)
        ' > "$SPEECH_V2_WORK/request.json" || return 1
        engine_v2_http "$SPEECH_V2_ENDPOINT" "$response" true "$SPEECH_V2_KEY" \
          -H 'Content-Type: application/json' \
          --data-binary "@$SPEECH_V2_WORK/request.json" || {
          speech_v2_error "Transcription failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
          return 1
        }
      fi
    ;;
  esac
}

# ── Publication ─────────────────────────────────────────────────────────────

speech_v2_publish() {
  local destination

  jq -e 'type == "object"' "$SPEECH_V2_WORK/response.json" >/dev/null 2>&1 || {
    speech_v2_error 'Invalid transcription response.'
    return 1
  }
  jq -er '.text | select(type == "string" and length > 0)' "$SPEECH_V2_WORK/response.json" \
    > "$SPEECH_V2_WORK/transcript.txt" || {
    # An empty transcript is an error, never an automatic prompt.
    speech_v2_error 'Transcription is empty; nothing will be sent to the chat.'
    return 1
  }

  destination=$(engine_v2_publish "$SPEECH_V2_WORK" "$SPEECH_V2_WORK/transcript.txt" txt) || return 1
  cat "$destination"
}

# ── Entry point ─────────────────────────────────────────────────────────────

transcribe_audio() (
  set +x
  set -o pipefail
  umask 077

  local audio=''
  local SPEECH_V2_PROVIDER="${SPEECH_PROVIDER:-${VOICE_PROVIDER:-}}"
  # The whisper.cpp model path is a LOCAL runtime fact: it must never be
  # mistaken for a remote model id. Only --model feeds the remote resolver.
  local local_whisper_model="${WHISPER_CPP_MODEL:-}"
  local SPEECH_V2_MODEL=''
  local SPEECH_V2_ENDPOINT='' SPEECH_V2_PROTOCOL='' SPEECH_V2_KEY=''
  local SPEECH_V2_WORK='' SPEECH_V2_AUDIO='' SPEECH_V2_INPUT=''
  local SPEECH_V2_MIME='' SPEECH_V2_LANGUAGE='' SPEECH_V2_LOCAL=false


  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) speech_v2_help; return 0 ;;
      --audio|--provider|--model|--language)
        [[ $# -ge 2 && -n $2 ]] || { speech_v2_error "Missing value for $1."; return 1; }
        case "$1" in
          --audio)    audio="$2" ;;
          --provider) SPEECH_V2_PROVIDER="$2" ;;
          --model)    SPEECH_V2_MODEL="$2" ;;
          --language) SPEECH_V2_LANGUAGE="$2" ;;
        esac
        shift 2
      ;;
      --*) speech_v2_error "Unknown option: $1"; return 1 ;;
      *) speech_v2_error "Unexpected argument: $1"; return 1 ;;
    esac
  done

  [[ -n $audio ]] || { speech_v2_error 'Transcription requires --audio FILE.'; return 1; }
  # --language > AUDIO_LANG > state.json .lang > auto, resolved before any
  # dependency or network work: a rejected value must cost nothing.
  SPEECH_V2_LANGUAGE=$(speech_v2_resolve_language) || return 1

  speech_v2_deps || return 1
  [[ ${ZDR_ENFORCED:-false} != true ]] || {
    speech_v2_error 'ZDR enforcement has no verified audio policy in this engine.'
    return 1
  }
  [[ -n ${DATA_STORE:-} ]] || { speech_v2_error 'DATA_STORE is not configured.'; return 1; }

  if [[ -z $SPEECH_V2_PROVIDER && -r ${STATE_FILE:-} ]]; then
    SPEECH_V2_PROVIDER=$(jq -r '[.speech, .voice, .provider] | map(select(type == "string" and length > 0)) | .[0] // empty' "$STATE_FILE")
  fi
  SPEECH_V2_PROVIDER="${SPEECH_V2_PROVIDER:-${PROVIDER:-}}"

  speech_v2_resolve || return 1

  # A remote model was resolved above; a local transcription takes the
  # whisper.cpp model path, from --model first, then the environment.
  if [[ $SPEECH_V2_LOCAL == true ]]; then
    SPEECH_V2_MODEL="${SPEECH_V2_MODEL:-$local_whisper_model}"
  fi

  SPEECH_V2_AUDIO="$audio"
  # 'auto' is not portable: whisper-cli documents '-l auto', groq answers 400
  # on it, and the OpenAI-compatible endpoints auto-detect when the field is
  # absent. So 'auto' only ever travels to the local engine.
  if [[ $SPEECH_V2_LOCAL != true && $SPEECH_V2_LANGUAGE == auto ]]; then
    SPEECH_V2_LANGUAGE=''
  fi
  SPEECH_V2_WORK=$(engine_v2_workdir audio) || { speech_v2_error 'Cannot create a private work directory.'; return 1; }
  trap 'rm -rf "$SPEECH_V2_WORK"' EXIT

  speech_v2_prepare_input || return 1

  if [[ $SPEECH_V2_LOCAL == true ]]; then
    speech_v2_local_run || return 1
  else
    speech_v2_send || return 1
  fi

  speech_v2_publish
)

voice_toggle_record() {
  local record_dir

  if [[ $VOICE_RECORD_ACTIVE == false ]]; then
    # ── STATE 1: Start recording ──────────────────────────────────────────
    record_dir="${TMPDIR:-/tmp}"

    if is_termux; then
      VOICE_RECORD_FILE="${record_dir}/voice_input.m4a"
      rm -f "$VOICE_RECORD_FILE"
      # Termux capture: mono 16kHz AAC (safety timeout 60s)
      termux-microphone-record -f "$VOICE_RECORD_FILE" -l 60 -e aac -r 16000 -c 1 -b 32 >/dev/null 2>&1
    else
      VOICE_RECORD_FILE="${record_dir}/voice_input.wav"
      rm -f "$VOICE_RECORD_FILE"
      # Desktop ALSA / Sox capture
      if command -v arecord >/dev/null 2>&1; then
        arecord -q -f S16_LE -r 16000 -c 1 "$VOICE_RECORD_FILE" >/dev/null 2>&1 &
        VOICE_RECORD_PID=$!
      elif command -v sox >/dev/null 2>&1; then
        rec -q -r 16000 -c 1 "$VOICE_RECORD_FILE" >/dev/null 2>&1 &
        VOICE_RECORD_PID=$!
      else
        echo -en "\n${CLR_B_RED}${ICON_ERROR} No recording tool found (arecord/sox).${ANSI_RESET}\n"
        return 1
      fi
    fi

    VOICE_RECORD_ACTIVE=true
    # Re-arm: next Alt+V will execute handler AND trigger accept-line (\n)
    bind '"\ev": "\C-x\C-v\n"' 2>/dev/null
    echo -e "\r\033[K${CLR_B_RED}${ICON_MIC} [Recording... press Alt+V to stop & transcribe]${ANSI_RESET}"

  else
    # ── STATE 2: Stop & Transcribe ────────────────────────────────────────
    VOICE_RECORD_ACTIVE=false
    # Disarm: revert Alt+V back to standard trigger
    bind '"\ev": "\C-x\C-v"' 2>/dev/null
    echo -e "\r\033[K${CLR_B_CYAN}${ICON_WAIT} [Transcribing audio...]${ANSI_RESET}"

    if is_termux; then
      termux-microphone-record -q >/dev/null 2>&1
    else
      [[ -n $VOICE_RECORD_PID ]] && kill -INT "$VOICE_RECORD_PID" 2>/dev/null
      wait "$VOICE_RECORD_PID" 2>/dev/null
      unset VOICE_RECORD_PID
    fi

    # Verify audio file presence and size
    if [[ -s $VOICE_RECORD_FILE ]]; then
      local transcript
      # Call STT v2 engine
      transcript=$(transcribe_audio --audio "$VOICE_RECORD_FILE" 2>/dev/null)

      if [[ -n $transcript ]]; then
        # Clear temporary indicator line
        echo -en "\r\033[K"
        # Inject directly into Readline buffer
        READLINE_LINE="$transcript"
        READLINE_POINT=${#READLINE_LINE}
      else
        echo -en "\r\033[K${CLR_B_YELLOW}${ICON_WARNING} Empty or inaudible transcription.${ANSI_RESET}\n"
        READLINE_LINE=""
        READLINE_POINT=0
      fi
    else
      echo -en "\r\033[K${CLR_B_YELLOW}${ICON_WARNING} No audio captured.${ANSI_RESET}\n"
      READLINE_LINE=""
      READLINE_POINT=0
    fi

    rm -f "$VOICE_RECORD_FILE"
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  SPEECH_V2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$SPEECH_V2_ROOT/core.sh" || exit 1
  [[ $(type -t load_libs) == function ]] && load_libs
  transcribe_audio "$@"
fi
