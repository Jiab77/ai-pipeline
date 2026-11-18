#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# engines/voice.sh — Speech synthesis and transcription engine
# ==============================================================================
# Synthesizes speech and transcribes audio through remote providers or local
# fallbacks. Usable as a sourced library or as a standalone CLI with Bash 3.2+.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.0
#
# Contract:
#   generate_speech  — Synthesize speech from text.
#   transcribe_audio — Transcribe an audio input to text.
#
# Dependencies: core.sh helpers, jq, curl, file, ffprobe;
#               ffmpeg for metadata stripping;
#               espeak-ng/espeak/pico2wave and whisper for local fallbacks.
#
# Protocols implemented (documented OpenAI-compatible audio endpoints):
#   - openai : POST /v1/audio/speech          (JSON -> binary audio)
#              POST /v1/audio/transcriptions  (multipart -> JSON {text})
#   - groq   : POST /openai/v1/audio/speech, /openai/v1/audio/transcriptions
#   - venice : POST /api/v1/audio/speech, /api/v1/audio/transcriptions
# Any other provider falls back to the LOCAL engine (with a warning) until its
# adapter exists: adding a provider config block (.tts/.stt with endpoint/
# default) extends the engine — inventing endpoints does not. Capabilities are
# per direction (.default.tts / .default.stt): a provider can speak without
# listening. Explicit default.<cap>=false on a provider that HAS a block
# refuses (the config speaks for the operator).
#
# Local fallback (offline, keyless — the pollinations symmetry of voice, but
# stronger: no network, no key, no outbound OPSEC footprint):
#   - TTS: espeak-ng / espeak / pico2wave -> WAV (voice id = espeak voice,
#     e.g. en-us, fr-fr; model/format options are degraded with a warning)
#   - STT: openai-whisper CLI on CPU (model id: tiny/base/small..., default
#     tiny). --language is honoured by whisper.
#
# Audio NEVER travels through a shell variable (NUL truncation lesson):
# request and response bodies live in private files inside an isolated work
# directory; the response is validated with ffprobe BEFORE publication and
# the output lands NEXT TO the work dir (which the EXIT trap removes) so
# downstream media detection keeps working (image.sh contract). Playback goes
# to the audio DEVICE (ALSA/Pulse/PipeWire), never stdout — it escapes the
# dispatcher $(...) capture, so the human hears it whoever triggers the tool
# call (lesson #37, corrected chafa analogy).
#
# Requests are NEVER retried automatically. No global session mutation.
# Unsupported voice/format values fail at the API, never silently.
# Dependencies: core.sh helpers, jq, curl, file, ffprobe;
#               ffmpeg for metadata stripping; espeak-ng/espeak/pico2wave and
#               whisper for the local fallbacks (probed at use, cloak pattern).
# ==============================================================================

VOICE_CONNECT_TIMEOUT=10
VOICE_HTTP_TIMEOUT=180
VOICE_STRIP_METADATA=true
VOICE_MAX_INPUT=4096        # documented OpenAI TTS input cap
VOICE_MAX_UPLOAD=26214400   # 25 MiB documented transcription upload cap

voc_error() { printf 'Voice: %s\n' "$*" >&2; }
voc_warn() {
  if declare -F log_warn >/dev/null; then log_warn "$*"; else printf 'Voice: %s\n' "$*" >&2; fi
}

voc_help() {
  cat <<'EOF'
Usage: voice.sh [stt] [options]
  --text TEXT         Text to synthesize (generate_speech / TTS)
  --audio FILE        Audio file to transcribe (transcribe_audio / stt)
  --provider NAME     Override the voice provider, or 'local' to force offline
  --model ID          Model (openai: gpt-4o-mini-tts / whisper-1,
                      groq: playai-tts / whisper-large-v3,
                      venice: tts-kokoro / registry, local stt: whisper model)
  --voice ID          Provider voice (openai: alloy...; venice: af_sky...;
                      local: espeak voice id such as en-us or fr-fr)
  --format FMT        mp3|opus|aac|flac|wav|pcm (remote TTS only)
  --language CODE     ISO-639-1 hint for transcription (e.g. fr)
  --play              Play the synthesized audio through the sound device

Resolution: --provider > $VOICE_PROVIDER > state.json (.voice // .provider)
> $PROVIDER. Without text: a short default line is synthesized. Text is
capped at 4096 characters, uploads at 25 MiB; both rejected locally before
any request. Unsupported providers/modes fail before any call — no paid
retry, no provider substitution beyond the documented local fallback.
Output lands in data/audio/ with the extension matching the validated
container. Playback targets the sound device, not stdout.
EOF
}

# Authenticated calls go ONLY to the documented audio API origins, never
# follow redirects, and every body — request and response — stays on disk.
voc_http() {
  local method=$1 url=$2 auth=$3 out=$4; shift 4
  local code
  local -a opts ; opts=(--silent --show-error --connect-timeout "$VOICE_CONNECT_TIMEOUT" --max-time "$VOICE_HTTP_TIMEOUT"
    --proto '=https' --proto-redir '=https' --output "$out" --write-out '%{http_code}')
  [[ ${USE_TOR:-true} == true ]] && opts+=(--proxy "$TOR_PROXY")
  [[ $url == https://* ]] || { voc_error 'HTTPS required.'; return 1; }
  if [[ $auth == true ]]; then
    case "$VOICE_PROVIDER:$url" in
      openai:https://api.openai.com/v1/audio/*|\
      groq:https://api.groq.com/openai/v1/audio/*|\
      venice:https://api.venice.ai/api/v1/audio/*) ;;
      *) voc_error 'Refusing credentials outside the documented provider audio API.'; return 1 ;;
    esac
    opts+=(-H "Authorization: Bearer $VOICE_API_KEY")
  fi
  # Content-Type and body/form are caller-supplied: JSON posts pass a header
  # + --data-binary, transcription posts pass -F pairs (curl sets the boundary).
  if ! code=$(curl "${opts[@]}" "$@" "$url"); then
    voc_error 'Transfer failed; no automatic retry.'
    return 1
  fi
  case "$code" in
    2??) return 0 ;;
    *) voc_error "HTTP $code; no output published."; return 1 ;;
  esac
}

# Degrade the options the local engine cannot honour (same spirit as the
# pollinations fallback of image.sh) and switch to the offline path.
voc_fallback_local() {
  if [[ -n $VOICE_PROVIDER && -r ${PROVIDERS_CONFIG:-} ]] \
     && jq -e --arg p "$VOICE_PROVIDER" 'has($p)' "$PROVIDERS_CONFIG" >/dev/null 2>&1; then
    voc_warn "Provider '$VOICE_PROVIDER' has no documented $VOICE_MODE API — using the local engine."
  else
    voc_warn "No $VOICE_MODE provider resolved — using the local engine."
  fi
  if [[ $VOICE_MODE == tts ]]; then
    if [[ $format_given == true ]]; then
      voc_warn "Local engine synthesizes WAV only — ignoring '--format $format'."
      format=''
    fi
    [[ $voice_given == true ]] || voice=''
    if [[ $model_given == true ]]; then
      voc_warn "Local TTS has no model selection — ignoring '--model $model'."
    fi
    model=''
  else
    # whisper model id (tiny/base/small/medium/large or a path).
    model="${model:-tiny}"
  fi
  VOICE_PROVIDER=local
  VOICE_ADAPTER=local
}

# Provider + capability + key resolution. Sets VOICE_ADAPTER=local|remote and,
# for remote, VOICE_ENDPOINT/VOICE_MODEL (+VOICE_NAME for TTS) and the key.
load_voice_config() {
  local cap=$VOICE_MODE configured=''
  if [[ $VOICE_PROVIDER == local ]]; then VOICE_ADAPTER=local; return 0; fi
  if [[ -z $VOICE_PROVIDER && -r ${STATE_FILE:-} ]]; then
    VOICE_PROVIDER=$(jq -er '[.voice,.provider] | map(select(type=="string" and length>0)) | .[0] // empty' "$STATE_FILE") || return 1
  fi
  VOICE_PROVIDER="${VOICE_PROVIDER:-${PROVIDER:-}}"
  # Explicit registry block: the operator configured this provider for this
  # direction — its capability flag must be true, otherwise refuse.
  if [[ -n $VOICE_PROVIDER && -r ${PROVIDERS_CONFIG:-} ]]; then
    configured=$(jq -r --arg p "$VOICE_PROVIDER" --arg c "$cap" '.[$p][$c].endpoint // empty' "$PROVIDERS_CONFIG" 2>/dev/null) || return 1
  fi
  if [[ -n $configured ]]; then
    jq -e --arg p "$VOICE_PROVIDER" --arg c "$cap" '.[$p].default[$c] == true' "$PROVIDERS_CONFIG" >/dev/null || {
      voc_error "Provider '$VOICE_PROVIDER' has a $cap block but default.$cap is not enabled."; return 1;
    }
    VOICE_ENDPOINT=$configured
  else
    case "$VOICE_PROVIDER:$cap" in
      openai:tts) VOICE_ENDPOINT='https://api.openai.com/v1/audio/speech' ;;
      groq:tts)   VOICE_ENDPOINT='https://api.groq.com/openai/v1/audio/speech' ;;
      venice:tts) VOICE_ENDPOINT='https://api.venice.ai/api/v1/audio/speech' ;;
      openai:stt) VOICE_ENDPOINT='https://api.openai.com/v1/audio/transcriptions' ;;
      groq:stt)   VOICE_ENDPOINT='https://api.groq.com/openai/v1/audio/transcriptions' ;;
      venice:stt) VOICE_ENDPOINT='https://api.venice.ai/api/v1/audio/transcriptions' ;;
      *)
        # No documented remote protocol for this direction: fall back to the
        # local engine (offline, keyless) instead of failing.
        voc_fallback_local
        return 0
      ;;
    esac
  fi
  # Registry refinements, then documented built-in defaults.
  model="${model:-$(jq -r --arg p "$VOICE_PROVIDER" --arg c "$cap" '.[$p][$c].default // empty' "$PROVIDERS_CONFIG" 2>/dev/null)}"
  if [[ $cap == tts ]]; then
    voice="${voice:-$(jq -r --arg p "$VOICE_PROVIDER" '.[$p].tts.voice // empty' "$PROVIDERS_CONFIG" 2>/dev/null)}"
  fi
  case "$VOICE_PROVIDER:$cap" in
    openai:tts) model="${model:-gpt-4o-mini-tts}"; voice="${voice:-alloy}" ;;
    groq:tts)   model="${model:-playai-tts}";      voice="${voice:-Fritz-PlayAI}" ;;
    venice:tts) model="${model:-tts-kokoro}";      voice="${voice:-af_sky}" ;;
    openai:stt) model="${model:-whisper-1}" ;;
    groq:stt)   model="${model:-whisper-large-v3}" ;;
    venice:stt) model="${model:-}" ;;
  esac
  [[ -n $model ]] || { voc_error "No model configured for $VOICE_PROVIDER $cap; add it to the registry or pass --model."; return 1; }
  # A registry endpoint must stay on the documented API origin — voc_http
  # would refuse credentials elsewhere; reject a conflicting value loudly.
  case "$VOICE_ENDPOINT" in
    https://api.openai.com/v1/audio/*|https://api.groq.com/openai/v1/audio/*|https://api.venice.ai/api/v1/audio/*) ;;
    *) voc_error "Registry endpoint conflicts with the documented $VOICE_PROVIDER audio protocol."; return 1 ;;
  esac
  has_provider_key "$VOICE_PROVIDER" || { voc_error "Missing provider key for '$VOICE_PROVIDER'."; return 1; }
  VOICE_API_KEY=$(decrypt_provider_key "$VOICE_PROVIDER") || return 1
  [[ -n $VOICE_API_KEY ]] || { voc_error 'Empty provider key.'; return 1; }
  VOICE_ADAPTER=remote
}

# Validation-first: a recognizable header alone is not sufficient.
voc_valid_audio() {
  [[ -s $1 ]] || return 1
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$1" 2>/dev/null | grep -qx audio
}

voc_ext_of() {
  local fmt
  fmt=$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$1" 2>/dev/null)
  case "$fmt" in
    *mp3*) printf 'mp3' ;;
    *wav*) printf 'wav' ;;
    *flac*) printf 'flac' ;;
    *ogg*|*opus*) printf 'ogg' ;;
    *aac*) printf 'aac' ;;
    *s16le*|*u16le*|*pcm*|*rawvideo*) printf 'pcm' ;;
    *m4a*|*ipod*|*mov*|*mp4*) printf 'm4a' ;;
    *) return 1 ;;
  esac
}

# play_audio <file> — send audio to the DEVICE (ALSA/PulseAudio/PipeWire),
# never stdout. The stream escapes the dispatcher capture: the human hears it
# even when a tool call triggers playback (lesson #37). A WAV can go to the
# lightweight native players; compressed containers need a decoder player.
play_audio() {
  local f="$1" mime
  [[ -s $f && -r $f ]] || { voc_error "Cannot read audio file '$f'."; return 1; }
  mime=$(file -b --mime-type "$f")
  case "$mime" in
    audio/x-wav|audio/wav|audio/wave)
      if command -v aplay >/dev/null 2>&1; then
        aplay -q "$f" >/dev/null 2>&1
      elif command -v paplay >/dev/null 2>&1; then
        paplay "$f" >/dev/null 2>&1
      elif command -v ffplay >/dev/null 2>&1; then
        ffplay -autoexit -loglevel quiet -nodisp "$f" >/dev/null 2>&1
      elif command -v afplay >/dev/null 2>&1; then
        afplay "$f" >/dev/null 2>&1
      else
        voc_error 'No WAV player found (tried: aplay, paplay, ffplay, afplay).'; return 1
      fi
    ;;
    *)
      if command -v ffplay >/dev/null 2>&1; then
        ffplay -autoexit -loglevel quiet -nodisp "$f" >/dev/null 2>&1
      elif command -v mpv >/dev/null 2>&1; then
        mpv --no-video --really-quiet "$f" >/dev/null 2>&1
      elif command -v afplay >/dev/null 2>&1; then
        afplay "$f" >/dev/null 2>&1
      else
        voc_error 'No audio player found (tried: ffplay, mpv, afplay).'; return 1
      fi
    ;;
  esac
}

# Local TTS — file-based synthesis only (an artifact is part of the contract).
voc_local_tts_probe() {
  if command -v espeak-ng >/dev/null 2>&1; then VOC_LOCAL_TTS=espeak-ng
  elif command -v espeak >/dev/null 2>&1; then VOC_LOCAL_TTS=espeak
  elif command -v pico2wave >/dev/null 2>&1; then VOC_LOCAL_TTS=pico2wave
  else
    voc_error 'No local TTS engine found (tried: espeak-ng, espeak, pico2wave).'
    return 1
  fi
}

voc_local_tts_run() {
  local wav="$VOICE_WORK/local.wav"
  case "$VOC_LOCAL_TTS" in
    espeak-ng|espeak)
      local -a vargs ; vargs=()
      [[ -z $voice ]] || vargs+=(-v "$voice")
      "$VOC_LOCAL_TTS" "${vargs[@]}" -w "$wav" < "$VOICE_WORK/input" >/dev/null 2>&1 \
        || { voc_error "Local synthesis failed ($VOC_LOCAL_TTS)."; return 1; }
    ;;
    pico2wave)
      pico2wave -w "$wav" "$(cat "$VOICE_WORK/input")" >/dev/null 2>&1 \
        || { voc_error 'Local synthesis failed (pico2wave).'; return 1; }
    ;;
  esac
  mv "$wav" "$VOICE_WORK/response" || return 1
  voc_valid_audio "$VOICE_WORK/response" || { voc_error 'Local synthesis produced no readable audio.'; return 1; }
}

# Local STT via the openai-whisper CLI. Its output name follows the input
# stem: work/input.<ext> -> work/input.txt, normalized to the same JSON
# response contract as the remote adapters.
voc_local_stt_run() {
  command -v whisper >/dev/null 2>&1 || { voc_error 'No local STT engine found (whisper).'; return 1; }
  whisper "$VOICE_WORK/input.$stt_ext" --model "$model" --task transcribe \
    --output_format txt --output_dir "$VOICE_WORK" >/dev/null 2>&1 \
    || { voc_error 'Local whisper failed.'; return 1; }
  [[ -s "$VOICE_WORK/input.txt" ]] || { voc_error 'Local whisper produced no transcript.'; return 1; }
  jq -n --rawfile t "$VOICE_WORK/input.txt" '{text:$t}' > "$VOICE_WORK/response" || return 1
}

# Validate the input BEFORE any request; a recognizable header is not enough.
voc_stt_inputs() {
  [[ -f $audio_in && -r $audio_in ]] || { voc_error 'Input is not a readable file.'; return 1; }
  mime=$(file -b --mime-type "$audio_in") || return 1
  case "$mime" in
    audio/*|video/webm|video/mp4) ;;
    *) voc_error 'Input is not an audio file.'; return 1 ;;
  esac
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$audio_in" 2>/dev/null \
    | grep -qx audio || { voc_error 'Input contains no readable audio stream.'; return 1; }
  if [[ $VOICE_ADAPTER == remote ]]; then
    [[ $(wc -c < "$audio_in") -le $VOICE_MAX_UPLOAD ]] || { voc_error 'Input exceeds the 25 MiB transcription cap.'; return 1; }
  fi
  stt_ext="${audio_in##*.}"
  [[ $stt_ext =~ ^[a-zA-Z0-9]{1,5}$ ]] || {
    case "$mime" in
      audio/mpeg) stt_ext=mp3 ;;
      audio/flac|audio/x-flac) stt_ext=flac ;;
      audio/x-wav|audio/wav|audio/wave) stt_ext=wav ;;
      audio/ogg) stt_ext=ogg ;;
      *) stt_ext=bin ;;
    esac
  }
  cp -- "$audio_in" "$VOICE_WORK/input.$stt_ext" || return 1
}

voc_tts_build() {
  # Text travels through a file (--rawfile), never an oversized argument.
  jq -n --arg m "$model" --rawfile t "$VOICE_WORK/input" --arg v "$voice" --arg f "$format" \
    '{model:$m,input:$t} + (if $v != "" then {voice:$v} else {} end)
       + (if $f != "" then {response_format:$f} else {} end)' > "$VOICE_WORK/request.json"
}

voc_save_audio() {
  local ext dest
  voc_valid_audio "$VOICE_WORK/response" || { voc_error 'Response is not a readable audio stream.'; return 1; }
  ext=$(voc_ext_of "$VOICE_WORK/response") || { voc_error 'Unrecognized audio container; output not published.'; return 1; }
  # The strip target needs a real extension: ffmpeg infers the muxer from it.
  local clean="$VOICE_WORK/clean.$ext"
  if [[ $VOICE_STRIP_METADATA == true && $ext != pcm ]]; then
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$VOICE_WORK/response" \
      -map 0:a -map_metadata -1 -map_chapters -1 -c:a copy "$clean" \
      || { voc_error 'Metadata stripping failed; output not published.'; return 1; }
    voc_valid_audio "$clean" || { voc_error 'Metadata stripping broke the audio; output not published.'; return 1; }
    mv "$clean" "$VOICE_WORK/output.$ext" || return 1
  else
    mv "$VOICE_WORK/response" "$VOICE_WORK/output.$ext" || return 1
  fi
  dest="${VOICE_WORK%/*}/${VOICE_WORK##*/}.$ext"
  mv "$VOICE_WORK/output.$ext" "$dest" || return 1
  printf '%s' "$dest"
}

voc_save_transcript() {
  local text dest
  jq -e 'type=="object"' "$VOICE_WORK/response" >/dev/null 2>&1 \
    || { voc_error 'Invalid transcription response.'; return 1; }
  text=$(jq -er '.text | select(type=="string" and length>0)' "$VOICE_WORK/response") \
    || { voc_error 'No transcript in response.'; return 1; }
  printf '%s\n' "$text" > "$VOICE_WORK/output.txt" || return 1
  dest="${VOICE_WORK%/*}/${VOICE_WORK##*/}.txt"
  mv "$VOICE_WORK/output.txt" "$dest" || return 1
  printf 'Transcript saved: %s\n' "$dest" >&2
  printf '%s\n' "$text"
}

# Isolated command scope: variables, umask and traps cannot alter core.sh.
voc_run() (
  set +x
  set -o pipefail
  umask 077
  local op=$1; shift
  local text='' audio_in='' voice='' model='' format='' language='' play=false
  local voice_given=false model_given=false format_given=false
  local VOICE_PROVIDER="${VOICE_PROVIDER:-}" VOICE_API_KEY='' VOICE_ENDPOINT=''
  local VOICE_MODEL='' VOICE_NAME='' VOICE_MODE='' VOICE_WORK='' VOICE_ADAPTER=''
  local VOC_LOCAL_TTS='' mime='' stt_ext='' dest dep
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) voc_help; return 0 ;;
      --text|--prompt|--audio|--voice|--model|--format|--provider|--language)
        [[ $# -ge 2 && -n $2 ]] || { voc_error "Missing value for $1."; return 1; }
        case "$1" in
          --text|--prompt) text=$2 ;; --audio) audio_in=$2 ;;
          --voice) voice=$2; voice_given=true ;;
          --model) model=$2; model_given=true ;;
          --format) format=$2; format_given=true ;;
          --provider) VOICE_PROVIDER=$2 ;; --language) language=$2 ;;
        esac
        shift 2
      ;;
      --play) play=true; shift ;;
      --*) voc_error "Unknown option: $1"; return 1 ;;
      *) [[ -z $text ]] || { voc_error 'Quote the text as one argument.'; return 1; }; text=$1; shift ;;
    esac
  done
  VOICE_MODE=tts; [[ $op == stt ]] && VOICE_MODE=stt
  for dep in jq curl file ffprobe; do
    command -v "$dep" >/dev/null 2>&1 || { voc_error "Missing dependency: $dep."; return 1; }
  done
  if [[ $VOICE_STRIP_METADATA == true ]]; then
    command -v ffmpeg >/dev/null 2>&1 || { voc_error 'Missing dependency: ffmpeg.'; return 1; }
  fi
  if [[ $op == tts ]]; then
    case "$format" in ''|mp3|opus|aac|flac|wav|pcm) ;; *) voc_error "Invalid format '$format' (mp3|opus|aac|flac|wav|pcm)."; return 1 ;; esac
    [[ -z $audio_in ]] || { voc_error 'Audio input belongs to transcribe_audio.'; return 1; }
    [[ -z $language ]] || { voc_error '--language belongs to transcribe_audio.'; return 1; }
  else
    [[ -n $audio_in ]] || { voc_error 'Transcription requires --audio FILE.'; return 1; }
    [[ -z $text ]] || { voc_error 'Use --text with generate_speech.'; return 1; }
    [[ -z $format ]] || { voc_error 'Transcription takes no --format.'; return 1; }
    [[ -z $language || $language =~ ^[a-zA-Z]{2}$ ]] || { voc_error "Language must be an ISO-639-1 code (e.g. fr)."; return 1; }
  fi
  # Conservative until a per-adapter verified ZDR contract is selected.
  [[ ${ZDR_ENFORCED:-false} != true ]] || { voc_error 'ZDR enforcement has no verified audio policy in this engine.'; return 1; }
  [[ -n ${DATA_STORE:-} ]] || { voc_error 'DATA_STORE is not configured.'; return 1; }
  mkdir -p "$DATA_STORE/audio" || return 1
  load_voice_config || return 1
  if [[ $VOICE_MODE == tts && $VOICE_ADAPTER == remote && ${#text} -gt $VOICE_MAX_INPUT ]]; then
    voc_error "Text exceeds the ${VOICE_MAX_INPUT}-character cap."
    return 1
  fi
  VOICE_WORK=$(mktemp -d "$DATA_STORE/audio/$(date +%Y%m%d-%H%M%S).XXXXXX") || return 1
  trap 'rm -rf "$VOICE_WORK"' EXIT
  if [[ $op == tts ]]; then
    text="${text:-Hello, this is Jarvis.}"
    printf '%s' "$text" > "$VOICE_WORK/input" || return 1
    if [[ $VOICE_ADAPTER == local ]]; then
      voc_local_tts_probe && voc_local_tts_run || return 1
    else
      voc_tts_build && voc_http POST "$VOICE_ENDPOINT" true "$VOICE_WORK/response" \
        -H 'Content-Type: application/json' --data-binary "@$VOICE_WORK/request.json" || return 1
    fi
    dest=$(voc_save_audio) || return 1
    if [[ $play == true ]] && ! play_audio "$dest"; then
      voc_warn 'Playback failed; the audio file remains available.'
    fi
    printf 'Audio created: %s\n' "$dest"
  else
    voc_stt_inputs || return 1
    if [[ $VOICE_ADAPTER == local ]]; then
      voc_local_stt_run || return 1
    else
      local -a form ; form=(-F "file=@$VOICE_WORK/input.$stt_ext;type=$mime" --form-string "model=$model")
      [[ -z $language ]] || form+=(--form-string "language=$language")
      form+=(-F 'response_format=json')
      voc_http POST "$VOICE_ENDPOINT" true "$VOICE_WORK/response" "${form[@]}" || return 1
    fi
    voc_save_transcript
  fi
)

generate_speech() { voc_run tts "$@"; }
transcribe_audio() { voc_run stt "$@"; }

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    voc_help ; exit 0
  fi
  VOC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$VOC_ROOT/core.sh" || exit 1
  [[ $(type -t 'load_libs') == 'function' ]] && load_libs
  case "${1:-}" in
    stt) shift; transcribe_audio "$@" ;;
    *) generate_speech "$@" ;;
  esac
fi
