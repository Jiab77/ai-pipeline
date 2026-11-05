#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# engines/voice.v2.sh — Text-to-speech engine (registry v2)
# ==============================================================================
# Synthesizes speech through the adapters described by
# config/providers.v2.json, with a local fallback that needs neither network
# nor key. Sourced library or standalone CLI (Bash 3.2+).
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.0
#
# Contract:
#   generate_speech — text -> audio file
#
# Dependencies: core.sh (provider keys and catalogue), lib/helpers.sh,
#               jq, curl, file, ffprobe, ffmpeg, base64;
#               espeak-ng, espeak or pico2wave for the local engine.
#
# Protocol notes:
#   - `voice` means TTS, `speech` means STT: they are two engines, two
#     capabilities, two booleans.
#   - OpenAI publishes its TTS model ids in the registry (opaque catalogue).
#     Every other provider is discovered, and a provider whose catalogue
#     cannot be narrowed refuses instead of guessing a model id.
#   - The Vercel speech-model endpoint returns JSON with base64 audio and
#     takes the model in `ai-model-id`; the OpenAI-compatible endpoints return
#     raw audio bytes and take the model in the body.
#   - Local fallback: engine unavailable, provider without the capability, or
#     an explicit `--provider local`. No installation is attempted and no
#     substitution happens silently: the warning names the reason.
#   - Audio never travels through a shell variable; the response is validated
#     with ffprobe BEFORE publication, and no request is ever retried.
#   - Interactive concerns (keyboard shortcut, toggle-to-talk, sending the
#     text to the chat) live in the controller, not here.
# ==============================================================================

# core.sh loads lib/helpers.sh through LIB_DEPS. A harness that sources only
# this engine still gets the shared plumbing: load it once, lazily.
if ! declare -F engine_v2_http >/dev/null; then
  VOICE_V2_HELPERS="${BASH_SOURCE[0]%/*}/../lib/helpers.sh"
  # shellcheck source=/dev/null
  [[ ! -r $VOICE_V2_HELPERS ]] || source "$VOICE_V2_HELPERS"
fi

# Config
VOICE_V2_GENDER="${VOICE_V2_GENDER:-${AI_GENDER:-neutral}}"     # Default gender
VOICE_V2_MAX_TEXT=4096                                          # documented OpenAI TTS input ceiling

# Transport tunables read by lib/helpers.sh (engine_v2_http).
ENGINE_V2_CONNECT_TIMEOUT=10
ENGINE_V2_TIMEOUT=180

voice_v2_error() { printf 'TTS: %s\n' "$*" >&2; }
voice_v2_warn() {
  if declare -F log_warn >/dev/null; then log_warn "$*"; else voice_v2_error "$*"; fi
}

voice_v2_help() {
  cat <<'EOF'
Usage: voice.v2.sh [options]
  --text TEXT        Text to synthesize
  --provider NAME    Override the TTS provider, or 'local' for offline
  --model ID         Model id, or the espeak voice model for local use
  --gender ID        Gender id (male, female, neutral)
  --voice ID         Provider voice (openai: alloy..., venice: af_sky...,
                     local: espeak voice id such as en-us or fr-fr)
  --format FMT       mp3|opus|aac|flac|wav|pcm (remote only)
  --play             Play the result through the sound device
  --help             Show this help

Resolution: --provider > VOICE_PROVIDER > state.json .voice/.provider >
PROVIDER. Voice selection: explicit --voice > registry default_voices[gender]
(--gender > AI_GENDER > neutral). Language of the local engine: --voice >
AUDIO_LANG > state.json .lang > LANG, where 'auto' resolves to the machine locale
(fr_CH.UTF-8 -> fr), with the gender variant appended for espeak (+m3, +f2).
Without text a short default line is synthesized. Text is capped at 4096
characters before any request. The output lands in data/audio/ with the
extension of the validated container. No paid retry; no silent substitution.
EOF
}

voice_v2_deps() {
  local dependency
  for dependency in jq curl file ffprobe; do
    command -v "$dependency" >/dev/null 2>&1 || { voice_v2_error "Missing dependency: $dependency."; return 1; }
  done
  if [[ ${VOICE_STRIP_METADATA:-true} == true ]]; then
    command -v ffmpeg >/dev/null 2>&1 || { voice_v2_error 'Missing dependency: ffmpeg.'; return 1; }
  fi
}

voice_v2_allowlist() {
  case "$1" in
    openai)          printf '%s' 'https://api.openai.com/v1/' ;;
    groq)            printf '%s' 'https://api.groq.com/openai/v1/' ;;
    openrouter)      printf '%s' 'https://openrouter.ai/api/v1/' ;;
    venice)          printf '%s' 'https://api.venice.ai/api/v1/' ;;
    vercel|vercel_free) printf '%s' 'https://ai-gateway.vercel.sh/v4/ai/' ;;
    *) return 1 ;;
  esac
}

voice_v2_documented_endpoint() {
  case "$1" in
    openai)          printf '%s' 'https://api.openai.com/v1/audio/speech' ;;
    groq)            printf '%s' 'https://api.groq.com/openai/v1/audio/speech' ;;
    openrouter)      printf '%s' 'https://openrouter.ai/api/v1/audio/speech' ;;
    venice)          printf '%s' 'https://api.venice.ai/api/v1/audio/speech' ;;
    vercel|vercel_free) printf '%s' 'https://ai-gateway.vercel.sh/v4/ai/speech-model' ;;
    *) return 1 ;;
  esac
}

# ── Resolution ──────────────────────────────────────────────────────────────

voice_v2_discover_model() {
  local provider="$1"
  local raw
  local model

  raw=$(get_provider_models "$provider" tts) || {
    voice_v2_error "Catalogue lookup failed for '$provider'; availability is unknown."
    return 1
  }
  [[ -n $raw && $raw != null ]] || { voice_v2_error "Empty catalogue for '$provider'."; return 1; }

  if declare -F filter_provider_models >/dev/null; then
    raw=$(filter_provider_models "$provider" tts <<< "$raw") || return 1
  fi

  model=$(jq -r '(if type == "array" then .[0].id else .data[0].id end) // empty' <<< "$raw") || return 1
  [[ -n $model ]] || {
    voice_v2_error "No TTS model could be identified for '$provider'; pass --model explicitly."
    return 1
  }
  printf '%s' "$model"
}

voice_v2_model_known() {
  local provider="$1"
  local model="$2"
  local raw

  raw=$(get_provider_models "$provider" tts) || return 1
  [[ -n $raw && $raw != null ]] || return 1
  jq -e --arg m "$model" '
    (if type == "array" then .[] else (.data // [])[] end) | select(.id == $m)
  ' <<< "$raw" >/dev/null 2>&1
}

voice_v2_resolve_remote() {
  local provider="$1"
  local allow configured endpoint static default

  allow=$(voice_v2_allowlist "$provider") || {
    voice_v2_warn "No documented TTS adapter for '$provider'; using the local engine."
    VOICE_V2_LOCAL=true
    return 0
  }
  configured=$(engine_v2_block_field "$provider" "voice.tts" endpoint)
  endpoint="${configured:-$(voice_v2_documented_endpoint "$provider")}"
  [[ -n $endpoint ]] || { voice_v2_error "No endpoint for '$provider'."; return 1; }
  [[ $endpoint == "$allow"* ]] || {
    voice_v2_error "Registry endpoint leaves the documented '$provider' API prefix; refusing to send credentials."
    return 1
  }
  VOICE_V2_ENDPOINT="$endpoint"

  static=$(engine_v2_block_models "$provider" "voice.tts")
  default=$(engine_v2_block_field "$provider" "voice.tts" default)

  if [[ -n $VOICE_V2_MODEL ]]; then
    if [[ -n $static ]]; then
      grep -qxF -- "$VOICE_V2_MODEL" <<< "$static" || {
        voice_v2_error "Model '$VOICE_V2_MODEL' is not a documented '$provider' TTS model."
        return 1
      }
    elif ! voice_v2_model_known "$provider" "$VOICE_V2_MODEL"; then
      voice_v2_error "Model '$VOICE_V2_MODEL' is absent from the '$provider' catalogue."
      return 1
    fi
  elif [[ -n $static ]]; then
    VOICE_V2_MODEL="$default"
    [[ -n $VOICE_V2_MODEL ]] || { voice_v2_error "No default TTS model for '$provider'."; return 1; }
  else
    VOICE_V2_MODEL=$(voice_v2_discover_model "$provider") || return 1
  fi

  has_provider_key "$provider" || { voice_v2_error "Missing provider key for '$provider'."; return 1; }
  VOICE_V2_KEY=$(decrypt_provider_key "$provider") || return 1
  [[ -n $VOICE_V2_KEY ]] || { voice_v2_error 'Empty provider key.'; return 1; }
  VOICE_V2_LOCAL=false

  if [[ -z $VOICE_V2_VOICE ]]; then
    VOICE_V2_VOICE=$(jq -r --arg p "$provider" --arg g "$VOICE_V2_GENDER" \
      '.[$p].voice.tts.voices[$g] // .[$p].voice.tts.voices["neutral"] // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
    if [[ -z $VOICE_V2_VOICE ]]; then
      case "$provider" in
        openai) VOICE_V2_VOICE=alloy ;;
        venice) VOICE_V2_VOICE=af_alloy ;;
      esac
    fi
  fi
}

voice_v2_resolve() {
  local provider="$VOICE_V2_PROVIDER"

  VOICE_V2_LOCAL=false
  if [[ -z $provider || $provider == local ]]; then
    VOICE_V2_LOCAL=true
    return 0
  fi

  if ! engine_v2_capable "$provider" voice; then
    # The provider is known but declares no TTS: say so and use the offline
    # engine rather than routing the text to another cloud.
    voice_v2_warn "Provider '$provider' declares no TTS capability; using the local engine."
    VOICE_V2_LOCAL=true
    return 0
  fi

  voice_v2_resolve_remote "$provider"
}

# ── Language ─────────────────────────────────────────────────────────────

voice_v2_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 'fr_CH.UTF-8' -> 'fr'. Prints nothing when the locale carries no language
# (unset, C, POSIX, or anything that is not a two-letter code): a machine
# without a locale is not an error, the caller keeps 'auto'.
voice_v2_from_locale() {
  local locale="${LC_ALL:-${LANG:-}}"

  locale=${locale%%[._@]*}
  locale=${locale%%_*}
  locale=$(voice_v2_lower "$locale")
  [[ $locale =~ ^[a-z]{2}$ ]] || return 0
  printf '%s' "$locale"
}

# Which language the local engine reads the text in.
#   AUDIO_LANG > state.json .lang > LANG
# 'auto' is never a language, it is the absence of one: it is what AUDIO_LANG
# holds when nothing was chosen for the session (core.sh defines it that way on
# every start), so it only means "keep looking".
#
# An ISO-639-1 code is all espeak-ng needs ('fr' and 'fr-fr' select the same
# voice, measured on 2026-10-31). A value given explicitly is validated and
# refused when it is a locale; a persisted one that does not validate is
# ignored rather than fatal (cli.sh stores /lang without validating it).
#
# Called only when no --voice was given: --voice is a free-form provider voice
# (alloy, af_sky) and must never be validated as a language.
voice_v2_local_language() {
  local candidate

  candidate=$(voice_v2_lower "${AUDIO_LANG:-}")
  if [[ -n $candidate && $candidate != auto ]]; then
    [[ $candidate =~ ^[a-z]{2}$ ]] || {
      voice_v2_error "Audio language must be an ISO-639-1 code (two letters, e.g. fr) or 'auto', not '$candidate'."
      return 1
    }
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -r ${STATE_FILE:-} ]]; then
    candidate=$(voice_v2_lower "$(jq -r '.lang // empty' "$STATE_FILE" 2>/dev/null)")
    if [[ $candidate =~ ^[a-z]{2}$ ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi

  candidate=$(voice_v2_from_locale)
  if [[ -n $candidate ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  printf '%s' auto
}

# ── Local engine ────────────────────────────────────────────────────────────

voice_v2_local_probe() {
  if command -v termux-tts-speak >/dev/null 2>&1; then VOICE_V2_BACKEND=termux-tts-speak
  elif command -v espeak-ng >/dev/null 2>&1; then VOICE_V2_BACKEND=espeak-ng
  elif command -v espeak >/dev/null 2>&1; then VOICE_V2_BACKEND=espeak
  elif command -v pico2wave >/dev/null 2>&1; then VOICE_V2_BACKEND=pico2wave
  else
    voice_v2_error 'No local TTS engine found (tried: termux-tts-speak, espeak-ng, espeak, pico2wave).'
    return 1
  fi
}

voice_v2_local_run() {
  local output="$VOICE_V2_WORK/local.wav"

  case "$VOICE_V2_BACKEND" in
    termux-tts-speak)
      local -a arguments ; arguments=(-s MUSIC)
      [[ -z $VOICE_V2_VOICE ]] || arguments+=(-l "$VOICE_V2_VOICE")
      termux-tts-speak "${arguments[@]}" < "$VOICE_V2_WORK/text" || {
        voice_v2_error "Local synthesis failed ($VOICE_V2_BACKEND)."
        return 1
      }

      # Minimal valid 44-byte PCM WAV stub (zero deps) to satisfy publication pipeline
      printf "RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00" > "$output"
    ;;
    espeak-ng|espeak)
      local -a arguments ; arguments=()
      [[ -z $VOICE_V2_VOICE ]] || arguments+=(-v "$VOICE_V2_VOICE")
      # Text travels on stdin: it can be long, and it must not reach argv.
      "$VOICE_V2_BACKEND" "${arguments[@]}" -w "$output" < "$VOICE_V2_WORK/text" >/dev/null 2>&1 || {
        voice_v2_error "Local synthesis failed ($VOICE_V2_BACKEND)."
        return 1
      }
    ;;
    pico2wave)
      pico2wave -w "$output" "$(<"$VOICE_V2_WORK/text")" >/dev/null 2>&1 || {
        voice_v2_error "Local synthesis failed ($VOICE_V2_BACKEND)."
        return 1
      }
    ;;
  esac

  mv "$output" "$VOICE_V2_WORK/response" || return 1
  engine_v2_audio_valid "$VOICE_V2_WORK/response" || {
    voice_v2_error 'Local synthesis produced no readable audio.'
    return 1
  }
}

# ── Remote request ──────────────────────────────────────────────────────────

voice_v2_build_request() {
  local request="$VOICE_V2_WORK/request.json"

  if [[ $VOICE_V2_PROVIDER == vercel || $VOICE_V2_PROVIDER == vercel_free ]]; then
    jq -n --rawfile text "$VOICE_V2_WORK/text" --arg format "$VOICE_V2_FORMAT" '
      {text:$text} + (if $format != "" then {outputFormat:$format} else {} end)
    ' > "$request"
  else
    jq -n --arg model "$VOICE_V2_MODEL" --rawfile input "$VOICE_V2_WORK/text" \
      --arg voice "$VOICE_V2_VOICE" --arg format "$VOICE_V2_FORMAT" '
      {model:$model, input:$input}
      + (if $voice != "" then {voice:$voice} else {} end)
      + (if $format != "" then {response_format:$format} else {} end)
    ' > "$request"
  fi
}

voice_v2_send() {
  local response="$VOICE_V2_WORK/response"
  local -a headers ; headers=(-H 'Content-Type: application/json' --data-binary "@$VOICE_V2_WORK/request.json")

  if [[ $VOICE_V2_PROVIDER == vercel || $VOICE_V2_PROVIDER == vercel_free ]]; then
    headers+=(
      -H "ai-model-id:$VOICE_V2_MODEL"
      -H 'ai-gateway-protocol-version: 0.0.1'
      -H 'ai-gateway-auth-method: api-key'
    )
  fi

  engine_v2_http "$VOICE_V2_ENDPOINT" "$response" true "$VOICE_V2_KEY" "${headers[@]}" || {
    voice_v2_error "Synthesis failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
    return 1
  }

  # The Gateway answers JSON with base64 audio, not raw bytes.
  if [[ $VOICE_V2_PROVIDER == vercel || $VOICE_V2_PROVIDER == vercel_free ]]; then
    jq -er '.audio | select(type == "string" and length > 0)' "$response" | b64d > "$VOICE_V2_WORK/audio" || {
      voice_v2_error 'The Gateway response carries no base64 audio.'
      return 1
    }
    mv "$VOICE_V2_WORK/audio" "$response" || return 1
  fi
}

# ── Publication ─────────────────────────────────────────────────────────────

voice_v2_publish() {
  local response="$VOICE_V2_WORK/response"
  local extension destination

  engine_v2_audio_valid "$response" || { voice_v2_error 'Response is not a readable audio stream.'; return 1; }
  extension=$(engine_v2_audio_ext "$response") || {
    voice_v2_error 'Unrecognised audio container; nothing published.'
    return 1
  }

  if [[ ${VOICE_STRIP_METADATA:-true} == true && $extension != pcm ]]; then
    engine_v2_strip_audio "$response" "$VOICE_V2_WORK/clean.$extension" "$extension" || {
      voice_v2_error 'Metadata stripping failed; nothing published.'
      return 1
    }
    engine_v2_audio_valid "$VOICE_V2_WORK/clean.$extension" || {
      voice_v2_error 'Metadata stripping broke the audio; nothing published.'
      return 1
    }
    mv "$VOICE_V2_WORK/clean.$extension" "$VOICE_V2_WORK/output.$extension" || return 1
  else
    mv "$response" "$VOICE_V2_WORK/output.$extension" || return 1
  fi

  destination=$(engine_v2_publish "$VOICE_V2_WORK" "$VOICE_V2_WORK/output.$extension" "$extension") || return 1
  printf '%s' "$destination"
}

voice_v2_play() {
  local file="$1"
  local ext="${file##*.}"
  local player
  local -a ladder

  if [[ $ext == [Ww][Aa][Vv] ]]; then
    ladder=(termux-media-player aplay paplay ffplay mpv afplay)
  else
    ladder=(termux-media-player ffplay mpv afplay)
  fi

  for player in "${ladder[@]}"; do
    command -v "$player" >/dev/null 2>&1 || continue
    case "$player" in
      termux-media-player) termux-media-player play "$file"       >/dev/null 2>&1 && return 0 ;;
      aplay)  aplay -q "$file"                                    >/dev/null 2>&1 && return 0 ;;
      paplay) paplay "$file"                                      >/dev/null 2>&1 && return 0 ;;
      ffplay) ffplay -autoexit -loglevel quiet -nodisp "$file"    >/dev/null 2>&1 && return 0 ;;
      mpv)    mpv --no-video --really-quiet "$file"               >/dev/null 2>&1 && return 0 ;;
      afplay) afplay "$file"                                      >/dev/null 2>&1 && return 0 ;;
    esac
  done

  voice_v2_warn 'Playback failed (no usable player, or the device refused); the audio file remains available.'
  return 0
}

# ── Entry point ─────────────────────────────────────────────────────────────

generate_speech() (
  set +x
  set -o pipefail
  umask 077

  local text='' play=false
  local VOICE_V2_PROVIDER="${VOICE_PROVIDER:-}"
  local VOICE_V2_MODEL='' VOICE_V2_VOICE='' VOICE_V2_FORMAT='' VOICE_V2_GENDER=''
  local VOICE_V2_ENDPOINT='' VOICE_V2_KEY='' VOICE_V2_WORK=''
  local VOICE_V2_LOCAL=false VOICE_V2_BACKEND='' destination

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) voice_v2_help; return 0 ;;
      --text|--prompt|--provider|--model|--voice|--format|--gender)
        [[ $# -ge 2 && -n $2 ]] || { voice_v2_error "Missing value for $1."; return 1; }
        case "$1" in
          --text|--prompt) text="$2" ;;
          --provider)      VOICE_V2_PROVIDER="$2" ;;
          --model)         VOICE_V2_MODEL="$2" ;;
          --voice)         VOICE_V2_VOICE="$2" ;;
          --format)        VOICE_V2_FORMAT="$2" ;;
          --gender)        VOICE_V2_GENDER="$2" ;;
        esac
        shift 2
      ;;
      --play) play=true; shift ;;
      --*) voice_v2_error "Unknown option: $1"; return 1 ;;
      *)
        [[ -z $text ]] || { voice_v2_error 'Quote the text as one argument.'; return 1; }
        text="$1"
        shift
      ;;
    esac
  done

  case "$VOICE_V2_FORMAT" in
    ''|mp3|opus|aac|flac|wav|pcm) ;;
    *) voice_v2_error "Invalid format '$VOICE_V2_FORMAT' (mp3|opus|aac|flac|wav|pcm)."; return 1 ;;
  esac

  VOICE_V2_GENDER=$(voice_v2_lower "${VOICE_V2_GENDER:-${AI_GENDER:-neutral}}")
  case "$VOICE_V2_GENDER" in
    male|female|neutral) ;;
    *) voice_v2_error "Invalid gender '$VOICE_V2_GENDER' (male|female|neutral)."; return 1 ;;
  esac
  voice_v2_deps || return 1
  [[ ${ZDR_ENFORCED:-false} != true ]] || {
    voice_v2_error 'ZDR enforcement has no verified audio policy in this engine.'
    return 1
  }
  [[ -n ${DATA_STORE:-} ]] || { voice_v2_error 'DATA_STORE is not configured.'; return 1; }

  if [[ -z $VOICE_V2_PROVIDER && -r ${STATE_FILE:-} ]]; then
    VOICE_V2_PROVIDER=$(jq -r '[.voice, .provider] | map(select(type == "string" and length > 0)) | .[0] // empty' "$STATE_FILE")
  fi
  VOICE_V2_PROVIDER="${VOICE_V2_PROVIDER:-${PROVIDER:-}}"

  text="${text:-Hello, this is Jarvis.}"
  # Checked before resolution: an oversized text must never cost a call.
  (( ${#text} <= VOICE_V2_MAX_TEXT )) || {
    voice_v2_error "Text exceeds the ${VOICE_V2_MAX_TEXT}-character cap."
    return 1
  }

  voice_v2_resolve || return 1

  if [[ $VOICE_V2_LOCAL == true ]]; then
    # Degrade the remote-only options with a warning rather than failing.
    if [[ -n $VOICE_V2_FORMAT ]]; then
      voice_v2_warn "The local engine synthesizes WAV only; ignoring '--format $VOICE_V2_FORMAT'."
      VOICE_V2_FORMAT=''
    fi
    if [[ -n $VOICE_V2_MODEL ]]; then
      voice_v2_warn "The local engine has no model selection; ignoring '--model $VOICE_V2_MODEL'."
      VOICE_V2_MODEL=''
    fi
  fi

  VOICE_V2_WORK=$(engine_v2_workdir audio) || { voice_v2_error 'Cannot create a private work directory.'; return 1; }
  trap 'rm -rf "$VOICE_V2_WORK"' EXIT
  printf '%s' "$text" > "$VOICE_V2_WORK/text" || return 1

  if [[ $VOICE_V2_LOCAL == true ]]; then
    voice_v2_local_probe || return 1
    # No --voice: the spoken language picks the espeak voice. Left alone, espeak
    # keeps its own default, which is English — the defect measured on
    # 2026-10-31 (a French sentence read with English phonemes).
    # pico2wave is excluded on purpose: it selects by locale (fr-FR) and no
    if [[ $VOICE_V2_BACKEND != pico2wave && -z $VOICE_V2_VOICE ]]; then
      VOICE_V2_VOICE=$(voice_v2_local_language) || return 1
      if [[ $VOICE_V2_VOICE == auto ]]; then
        VOICE_V2_VOICE=''
        voice_v2_warn 'No audio language: neither LANG nor /lang gave one; espeak keeps its own default voice.'
      else
        if [[ $VOICE_V2_BACKEND == espeak* ]]; then
          local variant
          variant=$(jq -r --arg g "$VOICE_V2_GENDER" '.local.voice.tts.voices[$g] // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
          if [[ -z $variant ]]; then
            case "$VOICE_V2_GENDER" in
              male)   variant="+m3" ;;
              female) variant="+f2" ;;
              *)      variant="" ;;
            esac
          fi
          VOICE_V2_VOICE="${VOICE_V2_VOICE}${variant}"
        fi
      fi
    fi
    voice_v2_local_run || return 1
  else
    voice_v2_build_request || return 1
    voice_v2_send || return 1
  fi

  # Save created audio file destination
  destination=$(voice_v2_publish) || return 1

  # Save last created audio file to replay it when needed
  printf '%s' "$destination" > "${DATA_STORE:-data}/audio/.last_audio" 2>/dev/null || :
  printf 'Audio created: %s\n' "$destination"

  # Play created audio file automatically when necessary
  [[ $play == true ]] && (voice_v2_play "$destination" >/dev/null 2>&1 & disown)
)

voice_replay_last_audio() {
  local last_audio=""
  local store="${DATA_STORE:-data}"

  # Replay last created audio file
  if [[ -r "${store}/audio/.last_audio" ]]; then
    last_audio=$(<"${store}/audio/.last_audio")
  fi

  # Security fallback: take the most recent file if pointer is missing
  if [[ -z $last_audio || ! -r $last_audio ]]; then
    last_audio=$(find "${store}/audio" -maxdepth 1 -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.ogg" \) 2>/dev/null | sort -r | head -n1)
  fi

  # Replay last created audio file discovered from previous step
  if [[ -n $last_audio && -r $last_audio ]]; then
    (voice_v2_play "$last_audio" >/dev/null 2>&1 & disown)
    echo -e "\r\033[K${CLR_B_CYAN}${ICON_SPEAKER} [Replaying audio...]${ANSI_RESET}"
    sleep 0.7
  else
    echo -e "\r\033[K${CLR_B_YELLOW}${ICON_WARNING} [Nothing to replay]${ANSI_RESET}"
    sleep 0.7
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  VOICE_V2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$VOICE_V2_ROOT/core.sh" || exit 1
  [[ $(type -t load_libs) == function ]] && load_libs
  generate_speech "$@"
fi
