#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# engines/video.v2.sh — Text/image-to-video engine (registry v2)
# ==============================================================================
# Generates a video from a text prompt or a source image through the protocol
# adapters described by config/providers.v2.json. Sourced library or standalone
# CLI (Bash 3.2+).
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.2.1
#
# Contract:
#   generate_video — text (or image) -> MP4
#
# Dependencies: core.sh (provider keys and catalogue), lib/helpers.sh,
#               jq, curl, file, base64, ffprobe; ffmpeg when metadata
#               stripping is enabled.
#
# Protocol notes:
#   - Every adapter here is asynchronous: submit, persist the job, poll,
#     download. The registry gives the submit endpoint and `protocol: async`;
#     the status path is derived from it because it is documented per
#     provider, not configurable.
#   - Static model ids exist only for the opaque catalogues (zai,
#     cyberneurova). Elsewhere the model comes from the live catalogue, and a
#     requested model must be present there: guessing capability from a name
#     invents a request the provider would reject.
#   - A submission is NEVER retried automatically (duplicate billing). The
#     job lives in DATA_STORE/videos/<unique>/job.json, mode 600, without the
#     provider key and without the source image. `--resume` polls and
#     downloads WITHOUT resubmitting.
#   - A signed media URL never receives the provider key.
# ==============================================================================

# core.sh loads lib/helpers.sh through LIB_DEPS. A harness that sources only
# this engine still gets the shared plumbing: load it once, lazily.
if ! declare -F engine_v2_http >/dev/null; then
  VIDEO_V2_HELPERS="${BASH_SOURCE[0]%/*}/../lib/helpers.sh"
  # shellcheck source=/dev/null
  [[ ! -r $VIDEO_V2_HELPERS ]] || source "$VIDEO_V2_HELPERS"
fi

# Transport tunables read by lib/helpers.sh (engine_v2_http).
ENGINE_V2_CONNECT_TIMEOUT=10
ENGINE_V2_TIMEOUT=180

video_v2_error() { printf 'Video: %s\n' "$*" >&2; }
video_v2_warn() {
  if declare -F log_warn >/dev/null; then log_warn "$*"; else video_v2_error "$*"; fi
}

video_v2_help() {
  cat <<'EOF'
Usage: video.v2.sh [prompt] [options]
  --prompt TEXT       Explicit prompt (also accepts text beginning with --)
  --image FILE|URL    Image-to-video; without image: text-to-video
  --provider NAME     Override the video/session provider
  --model NAME        Override the model; it must belong to that direction
  --duration N[s]     Duration in seconds (5 and 5s both accepted)
  --resolution VALUE  Provider resolution, e.g. 1080p or 1920x1080
  --ratio W:H         Aspect ratio, where the model publishes one
  --fps N             Z.AI only: 30 or 60
  --frames N          Hugging Face only: fal-ai frame count
  --resume JOB.json   Resume a saved job without resubmitting it
  --help              Show this help

Unsupported providers, modes and parameters fail before submission. No paid
retry, no provider substitution. Output is a validated MP4.
EOF
}

video_v2_deps() {
  local dependency
  for dependency in jq curl file base64 ffprobe; do
    command -v "$dependency" >/dev/null 2>&1 || { video_v2_error "Missing dependency: $dependency."; return 1; }
  done
  if [[ ${VIDEO_STRIP_METADATA:-true} == true ]]; then
    command -v ffmpeg >/dev/null 2>&1 || { video_v2_error 'Missing dependency: ffmpeg.'; return 1; }
  fi
}

# ── Registry access ──────────────────────────────────────────────────────────

video_v2_allowlist() {
  case "$1" in
    venice)                  printf '%s' 'https://api.venice.ai/api/v1/' ;;
    zai)                     printf '%s' 'https://api.z.ai/api/paas/v4/' ;;
    openrouter)              printf '%s' 'https://openrouter.ai/api/v1/' ;;
    vercel|vercel_free)      printf '%s' 'https://ai-gateway.vercel.sh/v4/ai/' ;;
    huggingface)             printf '%s' 'https://router.huggingface.co/fal-ai/' ;;
    cyberneurova)            printf '%s' 'https://api.cyberneurova.ai/v1/videos/' ;;
    *) return 1 ;;
  esac
}

video_v2_documented_endpoint() {
  case "$1" in
    venice)       printf '%s' 'https://api.venice.ai/api/v1/video/queue' ;;
    zai)          printf '%s' 'https://api.z.ai/api/paas/v4/videos/generations' ;;
    openrouter)   printf '%s' 'https://openrouter.ai/api/v1/videos' ;;
    vercel|vercel_free) printf '%s' 'https://ai-gateway.vercel.sh/v4/ai/video-model/start' ;;
    huggingface)  printf '%s' 'https://router.huggingface.co/fal-ai' ;;
    cyberneurova) printf '%s' 'https://api.cyberneurova.ai/v1/videos/generations' ;;
    *) return 1 ;;
  esac
}

video_v2_block_present() {
  local provider="$1"
  local block="$2"

  jq -e --arg p "$provider" --arg b "$block" '
    ((.[$p]) // {}) | getpath($b | split(".")) | type == "object"
  ' "$PROVIDERS_CONFIG" >/dev/null 2>&1
}

# ── Provider and model resolution ────────────────────────────────────────────

video_v2_resolve_provider() {
  local provider="$VIDEO_V2_PROVIDER"
  local block="$VIDEO_V2_BLOCK"
  local allow configured endpoint

  [[ -n $provider ]] || { video_v2_error 'No video provider selected.'; return 1; }
  engine_v2_capable "$provider" video || {
    video_v2_error "Provider '$provider' does not offer video generation."
    return 1
  }
  video_v2_block_present "$provider" "$block" || {
    video_v2_error "Provider '$provider' has no documented '$block' block."
    return 1
  }
  allow=$(video_v2_allowlist "$provider") || {
    video_v2_error "No documented video adapter for '$provider'."
    return 1
  }
  configured=$(engine_v2_block_field "$provider" "$block" endpoint)
  endpoint="${configured:-$(video_v2_documented_endpoint "$provider")}"
  [[ -n $endpoint ]] || { video_v2_error "No endpoint for '$provider'."; return 1; }
  # The allowlist carries no trailing slash: `.../fal-ai` is itself a valid
  # base endpoint, and `.../fal-ai/x` a valid full path.
  VIDEO_V2_ALLOW="${allow%/}"
  [[ $endpoint == "$VIDEO_V2_ALLOW" || $endpoint == "$VIDEO_V2_ALLOW"/* ]] || {
    video_v2_error "Registry endpoint leaves the documented '$provider' API prefix; refusing to send credentials."
    return 1
  }
  VIDEO_V2_ENDPOINT="$endpoint"
  VIDEO_V2_PROTOCOL=$(engine_v2_block_field "$provider" "$block" protocol)
  [[ -z $VIDEO_V2_PROTOCOL || $VIDEO_V2_PROTOCOL == async ]] || {
    video_v2_error "Unsupported video protocol '$VIDEO_V2_PROTOCOL'."
    return 1
  }
  [[ ${ZDR_ENFORCED:-false} != true ]] || {
    video_v2_error 'Async video retention has not been approved for ZDR; refusing submission or resume.'
    return 1
  }
}

video_v2_catalogue() {
  local provider="$1"
  local operation="$2"
  local raw

  raw=$(get_provider_models "$provider" "$operation") || {
    video_v2_error "Catalogue lookup failed for '$provider'; availability is unknown."
    return 1
  }
  [[ -n $raw && $raw != null ]] || { video_v2_error "Empty catalogue for '$provider'."; return 1; }

  if declare -F filter_provider_models >/dev/null; then
    raw=$(filter_provider_models "$provider" "$operation" <<< "$raw") || return 1
  fi
  VIDEO_V2_CATALOGUE="$raw"
}

video_v2_catalogue_model() {
  local model="$1"

  jq -e --arg m "$model" '
    if type == "array" then .[] else (.data // [])[] end
    | select(.id == $m)
  ' <<< "$VIDEO_V2_CATALOGUE"
}

video_v2_resolve_model() {
  local provider="$VIDEO_V2_PROVIDER"
  local block="$VIDEO_V2_BLOCK"
  local operation="$VIDEO_V2_OPERATION"
  local static default model mode

  static=$(engine_v2_block_models "$provider" "$block")
  default=$(engine_v2_block_field "$provider" "$block" default)
  model="$VIDEO_V2_MODEL"

  if [[ -n $static ]]; then
    if [[ -n $model ]]; then
      grep -qxF -- "$model" <<< "$static" || {
        video_v2_error "Model '$model' is not a documented '$provider $operation' model."
        return 1
      }
    else
      model="$default"
    fi
  else
    case "$provider" in
      venice|openrouter|vercel|vercel_free|huggingface) ;;
      *) video_v2_error "No static model and no discovery path for '$provider'."; return 1 ;;
    esac
    video_v2_catalogue "$provider" "$operation" || return 1
    if [[ -n $model ]]; then
      video_v2_catalogue_model "$model" >/dev/null || {
        video_v2_error "Model '$model' is absent from the '$provider' $operation catalogue."
        return 1
      }
    else
      if [[ $provider == venice ]]; then
        # Discovery-driven selection: the first catalogue model whose published
        # constraints accept the requested duration (and resolution/ratio when
        # set). catalogue[0] is NOT guaranteed to accept the engine defaults
        # (2026-11-14: gemini i2v durations 4/6/8/10s vs the 5s engine default).
        mode="$([[ $operation == t2v ]] && printf 'text-to-video' || printf 'image-to-video')"
        model=$(jq -r --arg mode "$mode" --arg d "${VIDEO_V2_DURATION}s" \
          --arg r "$VIDEO_V2_RESOLUTION" --arg a "$VIDEO_V2_RATIO" '
          .data[]
          | select((.model_spec.constraints.model_type // "") == $mode)
          | select(((.model_spec.constraints.durations // []) | index($d)) != null)
          | select($r == "" or ((.model_spec.constraints.resolutions // []) | index($r)) != null)
          | select($a == "" or ((.model_spec.constraints.aspect_ratios // []) | index($a)) != null)
          | .id
        ' <<< "$VIDEO_V2_CATALOGUE" | head -n1) || return 1
        [[ -n $model ]] || {
          video_v2_error "No '$provider' $operation model accepts duration '${VIDEO_V2_DURATION}s'${VIDEO_V2_RESOLUTION:+, resolution '$VIDEO_V2_RESOLUTION'}${VIDEO_V2_RATIO:+, ratio '$VIDEO_V2_RATIO'}."
          return 1
        }
      else
        model=$(jq -r '(if type == "array" then .[0].id else .data[0].id end) // empty' <<< "$VIDEO_V2_CATALOGUE") || return 1
        [[ -n $model ]] || { video_v2_error "No $operation model in the '$provider' catalogue."; return 1; }
      fi
    fi
    case "$provider" in
      venice) VIDEO_V2_CONSTRAINTS=$(jq -c '.model_spec.constraints // {}' <<< "$(video_v2_catalogue_model "$model")") || return 1 ;;
      *)      VIDEO_V2_CONSTRAINTS=$(video_v2_catalogue_model "$model") || return 1 ;;
    esac
  fi

  [[ -n $model ]] || { video_v2_error "No model resolved for '$provider $operation'."; return 1; }
  VIDEO_V2_MODEL="$model"
}

# ── Parameter validation (before any billable call) ─────────────────────────

video_v2_options() {
  local provider="$VIDEO_V2_PROVIDER"
  local duration="$VIDEO_V2_DURATION"
  local constraints="$VIDEO_V2_CONSTRAINTS"

  case "$provider" in
    zai)
      case "$duration" in
        5|10) ;;
        *) video_v2_error 'Z.AI accepts a 5 or 10 second duration.'; return 1 ;;
      esac
      case "$VIDEO_V2_RESOLUTION" in
        ''|1280x720|720x1280|1024x1024|1920x1080|1080x1920|2048x1080|3840x2160) ;;
        *) video_v2_error "Unsupported Z.AI size '$VIDEO_V2_RESOLUTION'."; return 1 ;;
      esac
      [[ -z $VIDEO_V2_RATIO ]] || { video_v2_error 'Z.AI takes --resolution WxH, not --ratio.'; return 1; }
      [[ -z $VIDEO_V2_FRAMES ]] || { video_v2_error '--frames is only documented for Hugging Face.'; return 1; }
      VIDEO_V2_FPS="${VIDEO_V2_FPS:-30}"
      case "$VIDEO_V2_FPS" in
        30|60) ;;
        *) video_v2_error 'Z.AI accepts 30 or 60 fps.'; return 1 ;;
      esac
      (( ${#VIDEO_V2_PROMPT} <= 512 )) || { video_v2_error 'Z.AI prompts are limited to 512 characters.'; return 1; }
    ;;
    huggingface)
      [[ -z $VIDEO_V2_FRAMES || $VIDEO_V2_FRAMES =~ ^[1-9][0-9]*$ ]] || {
        video_v2_error '--frames must be a positive integer.'
        return 1
      }
      [[ -z $VIDEO_V2_RESOLUTION ]] || { video_v2_error 'The fal-ai adapter exposes no resolution control.'; return 1; }
      [[ -z $VIDEO_V2_FPS ]] || { video_v2_error '--fps is only documented for Z.AI.'; return 1; }
    ;;
    cyberneurova)
      [[ -z $VIDEO_V2_FPS ]] || { video_v2_error '--fps is only documented for Z.AI.'; return 1; }
      [[ -z $VIDEO_V2_FRAMES ]] || { video_v2_error '--frames is only documented for Hugging Face.'; return 1; }
      [[ -z $VIDEO_V2_RESOLUTION ]] || { video_v2_error 'CyberNeurova exposes no resolution control.'; return 1; }
    ;;
    *)
      [[ -z $VIDEO_V2_FPS ]] || { video_v2_error '--fps is only documented for Z.AI.'; return 1; }
      [[ -z $VIDEO_V2_FRAMES ]] || { video_v2_error '--frames is only documented for Hugging Face.'; return 1; }
    ;;
  esac

  case "$provider" in
    venice)
      # Venice publishes mode, durations, resolutions and ratios per model.
      local wanted="${VIDEO_V2_DURATION}s"
      local reason
      reason=$(jq -r --arg mode "$([[ $VIDEO_V2_OPERATION == t2v ]] && printf 'text-to-video' || printf 'image-to-video')" \
        --arg d "$wanted" --arg r "$VIDEO_V2_RESOLUTION" --arg a "$VIDEO_V2_RATIO" --argjson n "${#VIDEO_V2_PROMPT}" '
        if (.model_type // "") != $mode then
          "operation (model_type: \(.model_type // "none"))"
        elif ((.durations // []) | index($d)) == null then
          "duration \"\($d)\" (accepted: \((.durations // []) | join(", ")))"
        elif ($r != "" and ((.resolutions // []) | index($r)) == null) then
          "resolution \"\($r)\" (accepted: \((.resolutions // []) | join(", ")))"
        elif ($a != "" and ((.aspect_ratios // []) | index($a)) == null) then
          "aspect ratio \"\($a)\" (accepted: \((.aspect_ratios // []) | join(", ")))"
        elif $n > (.prompt_character_limit // 2500) then
          "prompt length (\($n) > \(.prompt_character_limit // 2500) characters)"
        else empty end
      ' <<< "$constraints")
      [[ -z $reason ]] || {
        video_v2_error "Venice model '$VIDEO_V2_MODEL' does not accept this $reason."
        return 1
      }
      if [[ -z $VIDEO_V2_RATIO ]]; then
        VIDEO_V2_RATIO=$(jq -r '(.aspect_ratios // []) | (index("16:9") // 0) as $i | .[$i] // empty' <<< "$constraints")
      fi
    ;;
    openrouter)
      jq -e --argjson d "$VIDEO_V2_DURATION" --arg r "$VIDEO_V2_RESOLUTION" --arg a "$VIDEO_V2_RATIO" '
        def accepts($list; $value): ($list == null) or (($list | length) == 0) or (($list | index($value)) != null);
        accepts(.supported_durations; $d)
        and ($r == "" or accepts(.supported_resolutions; $r))
        and ($a == "" or accepts(.supported_aspect_ratios; $a))
      ' <<< "$constraints" >/dev/null || {
        video_v2_error "OpenRouter model '$VIDEO_V2_MODEL' does not accept these parameters."
        return 1
      }
    ;;
    vercel|vercel_free)
      jq -e --arg op "$([[ $VIDEO_V2_OPERATION == t2v ]] && printf 'text-to-video' || printf 'image-to-video')" \
        --argjson d "$VIDEO_V2_DURATION" --arg r "$VIDEO_V2_RESOLUTION" --arg a "$VIDEO_V2_RATIO" '
        .video_capabilities
        | ((.supported_operations // []) | index($op) != null)
        and ((.supported_durations_seconds // []) | index($d) != null)
        and ($r == "" or ((.supported_resolutions // []) | index($r) != null))
        and ($a == "" or ((.supported_aspect_ratios // []) | index($a) != null))
      ' <<< "$constraints" >/dev/null || {
        video_v2_error "Gateway model '$VIDEO_V2_MODEL' does not accept this mode/duration/resolution/ratio."
        return 1
      }
    ;;
    huggingface)
      # The router must serve this direction through fal-ai for this model.
      local encoded mapping="$VIDEO_V2_WORK/mapping.json"
      encoded=$(jq -nr --arg m "$VIDEO_V2_MODEL" '$m | @uri') || return 1
      # The live API returns inferenceProviderMapping only when expanded.
      engine_v2_http "https://huggingface.co/api/models/${encoded}?expand=inferenceProviderMapping" "$mapping" true "$VIDEO_V2_KEY" || {
        video_v2_error "Hugging Face model lookup failed (HTTP ${ENGINE_V2_HTTP_CODE:-none})."
        return 1
      }
      jq -e --arg op "$([[ $VIDEO_V2_OPERATION == t2v ]] && printf 'text-to-video' || printf 'image-to-video')" '
        .inferenceProviderMapping["fal-ai"]?
        | select(.status == "live" and .task == $op and (.providerId | startswith("fal-ai/")))
      ' "$mapping" >/dev/null || {
        video_v2_error "Model '$VIDEO_V2_MODEL' is not live through fal-ai for $VIDEO_V2_OPERATION."
        return 1
      }
      VIDEO_V2_UPSTREAM=$(jq -r '.inferenceProviderMapping["fal-ai"].providerId' "$mapping") || return 1
    ;;
  esac
}

# ── Request ─────────────────────────────────────────────────────────────────

# A local source image is read into a private file; the bytes never travel
# through argv. An https source is passed by reference, never downloaded.
video_v2_prepare_image() {
  local mime

  : > "$VIDEO_V2_WORK/reference"
  [[ -n $VIDEO_V2_IMAGE ]] || return 0

  if [[ $VIDEO_V2_IMAGE == https://* ]]; then
    printf '%s' "$VIDEO_V2_IMAGE" > "$VIDEO_V2_WORK/reference" || return 1
    return 0
  fi
  if [[ $VIDEO_V2_PROVIDER == vercel || $VIDEO_V2_PROVIDER == vercel_free ]]; then
    video_v2_error 'The Gateway accepts a source URL only; hosting a local file automatically is not supported.'
    return 1
  fi
  [[ -f $VIDEO_V2_IMAGE && -r $VIDEO_V2_IMAGE && ! -L $VIDEO_V2_IMAGE ]] || {
    video_v2_error 'Input image must be a readable PNG/JPEG file or an HTTPS URL.'
    return 1
  }
  mime=$(file -b --mime-type "$VIDEO_V2_IMAGE") || return 1
  case "$mime" in
    image/jpeg|image/png) ;;
    image/webp)
      [[ $VIDEO_V2_PROVIDER == venice ]] || {
        video_v2_error "Provider '$VIDEO_V2_PROVIDER' does not accept WebP input; use PNG or JPEG."
        return 1
      }
    ;;
    *) video_v2_error 'Input image must be PNG, JPEG or WebP.'; return 1 ;;
  esac
  if [[ $VIDEO_V2_PROVIDER == zai ]] && [[ $(wc -c < "$VIDEO_V2_IMAGE") -gt 5242880 ]]; then
    video_v2_error 'Z.AI rejects source images above 5 MiB.'
    return 1
  fi
  printf 'data:%s;base64,' "$mime" > "$VIDEO_V2_WORK/reference" || return 1
  b64e < "$VIDEO_V2_IMAGE" >> "$VIDEO_V2_WORK/reference" || return 1
}

video_v2_build_request() {
  local request="$VIDEO_V2_WORK/request.json"
  local model="$VIDEO_V2_MODEL"
  local reference="$VIDEO_V2_WORK/reference"

  case "$VIDEO_V2_PROVIDER" in
    venice)
      jq -n --arg m "$model" --rawfile p "$VIDEO_V2_WORK/prompt" \
        --arg d "${VIDEO_V2_DURATION}s" --arg r "$VIDEO_V2_RESOLUTION" \
        --arg a "$VIDEO_V2_RATIO" --rawfile i "$reference" '
        {model:$m, prompt:$p, duration:$d}
        + (if $r != "" then {resolution:$r} else {} end)
        + (if $a != "" then {aspect_ratio:$a} else {} end)
        + (if $i != "" then {image_url:$i} else {} end)
      ' > "$request"
    ;;
    zai)
      jq -n --arg m "$model" --rawfile p "$VIDEO_V2_WORK/prompt" \
        --argjson d "$VIDEO_V2_DURATION" --argjson fps "$VIDEO_V2_FPS" \
        --arg s "$VIDEO_V2_RESOLUTION" --rawfile i "$reference" '
        {model:$m, prompt:$p, duration:$d, fps:$fps}
        + (if $s != "" then {size:$s} else {} end)
        + (if $i != "" then {image_url:[$i]} else {} end)
      ' > "$request"
    ;;
    openrouter)
      jq -n --arg m "$model" --rawfile p "$VIDEO_V2_WORK/prompt" \
        --argjson d "$VIDEO_V2_DURATION" --arg r "$VIDEO_V2_RESOLUTION" \
        --arg a "$VIDEO_V2_RATIO" --rawfile i "$reference" '
        {model:$m, prompt:$p, duration:$d}
        + (if $r != "" then {resolution:$r} else {} end)
        + (if $a != "" then {aspect_ratio:$a} else {} end)
        + (if $i != "" then {frame_images:[{type:"image_url", image_url:{url:$i}, frame_type:"first_frame"}]} else {} end)
      ' > "$request"
    ;;
    vercel|vercel_free)
      jq -n --rawfile p "$VIDEO_V2_WORK/prompt" --argjson d "$VIDEO_V2_DURATION" \
        --arg r "$VIDEO_V2_RESOLUTION" --arg a "$VIDEO_V2_RATIO" --rawfile i "$reference" '
        {prompt:$p, duration:$d, n:1}
        + (if $r != "" then {resolution:$r} else {} end)
        + (if $a != "" then {aspect_ratio:$a} else {} end)
        + (if $i != "" then {image:{type:"url", url:$i}} else {} end)
      ' > "$request"
    ;;
    huggingface)
      jq -n --rawfile p "$VIDEO_V2_WORK/prompt" --rawfile i "$reference" \
        --argjson f "${VIDEO_V2_FRAMES:-0}" '
        {prompt:$p}
        + (if $i != "" then {image_url:$i} else {} end)
        + (if $f > 0 then {frames:$f} else {} end)
      ' > "$request"
    ;;
    cyberneurova)
      jq -n --rawfile p "$VIDEO_V2_WORK/prompt" '{prompt:$p}' > "$request"
    ;;
    *) video_v2_error "No request builder for '$VIDEO_V2_PROVIDER'."; return 1 ;;
  esac
}

video_v2_http() {
  local url="$1"
  local output="$2"
  local auth="$3"
  shift 3

  [[ -n $VIDEO_V2_KEY ]] || { video_v2_error 'Missing provider key.'; return 1; }
  engine_v2_http "$url" "$output" "$auth" "$VIDEO_V2_KEY" "$@"
}

video_v2_submit_url() {
  case "$VIDEO_V2_PROVIDER" in
    huggingface)
      # The router addresses the model: /fal-ai/<model> (the fal-ai provider
      # mapping's providerId is what the router serves).
      printf '%s/%s' "${VIDEO_V2_ENDPOINT%/}" "$VIDEO_V2_UPSTREAM"
    ;;
    *) printf '%s' "$VIDEO_V2_ENDPOINT" ;;
  esac
}

video_v2_submit() {
  local response="$VIDEO_V2_WORK/submission.json"
  local url path

  url=$(video_v2_submit_url) || return 1

  case "$VIDEO_V2_PROVIDER" in
    vercel|vercel_free)
      engine_v2_http "$url" "$response" true "$VIDEO_V2_KEY" \
        -H 'Content-Type: application/json' \
        -H "ai-model-id:$VIDEO_V2_MODEL" \
        -H 'ai-video-model-specification-version: 4' \
        -H 'ai-gateway-protocol-version: 0.0.1' \
        -H 'ai-gateway-auth-method: api-key' \
        --data-binary "@$VIDEO_V2_WORK/request.json" || {
        video_v2_error "Submission failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
        return 1
      }
    ;;
    *)
      video_v2_http "$url" "$response" true \
        -H 'Content-Type: application/json' \
        --data-binary "@$VIDEO_V2_WORK/request.json" || {
        video_v2_error "Submission failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
        return 1
      }
    ;;
  esac

  VIDEO_V2_DOWNLOAD_URL=''
  VIDEO_V2_RESULT_URL=''
  VIDEO_V2_OPERATION_JSON=''

  case "$VIDEO_V2_PROVIDER" in
    venice)
      VIDEO_V2_JOB_ID=$(jq -er '.queue_id | select(type == "string" and length > 0)' "$response") || return 1
      VIDEO_V2_DOWNLOAD_URL=$(jq -r '.download_url // empty' "$response") || return 1
    ;;
    zai)
      VIDEO_V2_JOB_ID=$(jq -er '.id | select(type == "string" and length > 0)' "$response") || return 1
    ;;
    openrouter)
      VIDEO_V2_JOB_ID=$(jq -er '.id | select(type == "string" and length > 0)' "$response") || return 1
    ;;
    vercel|vercel_free)
      VIDEO_V2_JOB_ID=$(jq -er '.operation.gatewayJobId | select(type == "string" and length > 0)' "$response") || return 1
      VIDEO_V2_OPERATION_JSON=$(jq -c '.operation' "$response") || return 1
    ;;
    huggingface)
      VIDEO_V2_JOB_ID=$(jq -er '.request_id | select(type == "string" and length > 0)' "$response") || return 1
      path=$(jq -er '.response_url | select(type == "string" and length > 0)' "$response") || return 1
      path="${path#*://}"            # drop the scheme
      path="/${path#*/}"             # drop the host, keep the leading slash
      VIDEO_V2_RESULT_URL="${VIDEO_V2_ALLOW%/}${path%%\?*}"
    ;;
    cyberneurova)
      VIDEO_V2_JOB_ID=$(jq -er '.jobId | select(type == "string" and length > 0)' "$response") || return 1
    ;;
  esac

  video_v2_save_job || {
    video_v2_error 'Cannot persist the job; the submission response is retained. DO NOT resubmit blindly.'
    return 1
  }
}

video_v2_save_job() {
  jq -n --arg p "$VIDEO_V2_PROVIDER" --arg m "$VIDEO_V2_MODEL" --arg id "$VIDEO_V2_JOB_ID" \
    --arg link "$VIDEO_V2_DOWNLOAD_URL" --arg rurl "$VIDEO_V2_RESULT_URL" \
    --argjson op "${VIDEO_V2_OPERATION_JSON:-null}" '
    {version:1, provider:$p, model:$m, id:$id,
     download_url:$link, result_url:$rurl, operation:$op}
  ' > "$VIDEO_V2_WORK/job.tmp" || return 1
  chmod 600 "$VIDEO_V2_WORK/job.tmp" || return 1
  mv "$VIDEO_V2_WORK/job.tmp" "$VIDEO_V2_WORK/job.json"
}

# ── Media ───────────────────────────────────────────────────────────────────

video_v2_valid_media() {
  [[ -s $1 ]] || return 1
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$1" 2>/dev/null | grep -qx video || return 1
  ffprobe -v error -show_entries format=format_name -of csv=p=0 "$1" 2>/dev/null | grep -q mp4
}

video_v2_finish() {
  local input="$1"
  local clean="$VIDEO_V2_WORK/clean.mp4"
  local published

  video_v2_valid_media "$input" || { video_v2_error 'Downloaded data is not a readable MP4.'; return 1; }

  if [[ ${VIDEO_STRIP_METADATA:-true} == true ]]; then
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$input" \
      -map 0:v -map '0:a?' -map_metadata -1 -map_chapters -1 -c copy "$clean" || {
      video_v2_error 'Metadata cleanup failed; nothing published.'
      return 1
    }
    video_v2_valid_media "$clean" || { video_v2_error 'Metadata cleanup broke the MP4.'; return 1; }
    mv "$clean" "$input" || return 1
  fi

  published=$(engine_v2_publish "$VIDEO_V2_WORK" "$input" mp4) || return 1
  printf 'Video created: %s\n' "$published"
}

# ── Polling ─────────────────────────────────────────────────────────────────

video_v2_poll_status() {
  local response="$VIDEO_V2_WORK/result"
  local encoded status link='' auth=true url body=''

  encoded=$(jq -nr --arg id "$VIDEO_V2_JOB_ID" '$id | @uri') || return 1

  case "$VIDEO_V2_PROVIDER" in
    venice)
      url="${VIDEO_V2_ENDPOINT%/queue}/retrieve"
      jq -n --arg m "$VIDEO_V2_MODEL" --arg id "$VIDEO_V2_JOB_ID" \
        '{model:$m, queue_id:$id}' > "$VIDEO_V2_WORK/poll.json" || return 1
      body="$VIDEO_V2_WORK/poll.json"
    ;;
    zai)          url="${VIDEO_V2_ENDPOINT%/videos/generations}/async-result/$encoded" ;;
    openrouter)   url="$VIDEO_V2_ENDPOINT/$encoded" ;;
    huggingface)  url="${VIDEO_V2_RESULT_URL}/status?_subdomain=queue" ;;
    vercel|vercel_free) url="${VIDEO_V2_ENDPOINT%/*}/status" ;;
    cyberneurova) url="${VIDEO_V2_ENDPOINT%/videos/generations}/videos/status/$VIDEO_V2_JOB_ID" ;;
  esac

  [[ $url == "$VIDEO_V2_ALLOW"/* ]] || {
    video_v2_error "Refusing to poll outside the documented '$VIDEO_V2_PROVIDER' API prefix."
    return 1
  }

  if [[ $VIDEO_V2_PROVIDER == venice ]]; then
    video_v2_http "$url" "$response" true -H 'Content-Type: application/json' --data-binary "@$body" || return 1
    if video_v2_valid_media "$response"; then video_v2_finish "$response"; return $?; fi
  elif [[ $VIDEO_V2_PROVIDER == vercel || $VIDEO_V2_PROVIDER == vercel_free ]]; then
    jq -n --argjson op "$VIDEO_V2_OPERATION_JSON" '{operation:$op}' > "$VIDEO_V2_WORK/poll.json" || return 1
    engine_v2_http "$url" "$response" true "$VIDEO_V2_KEY" \
      -H 'Content-Type: application/json' \
      -H 'ai-gateway-protocol-version: 0.0.1' \
      -H 'ai-gateway-auth-method: api-key' \
      --data-binary "@$VIDEO_V2_WORK/poll.json" || {
      video_v2_error "Status request failed (HTTP ${ENGINE_V2_HTTP_CODE:-none})."
      return 1
    }
  else
    video_v2_http "$url" "$response" true || return 1
  fi

  jq -e 'type == "object"' "$response" >/dev/null 2>&1 || {
    video_v2_error 'Invalid polling response.'
    return 1
  }

  case "$VIDEO_V2_PROVIDER" in
    venice)
      status=$(jq -r '.status // empty' "$response")
      link="$VIDEO_V2_DOWNLOAD_URL"
      auth=false
    ;;
    zai)
      status=$(jq -r '.task_status // empty' "$response")
      link=$(jq -r '.video_result[0].url // empty' "$response")
      auth=false
    ;;
    openrouter)
      status=$(jq -r '.status // empty' "$response")
      link="$VIDEO_V2_ENDPOINT/$encoded/content?index=0"
    ;;
    huggingface)
      status=$(jq -r '.status // empty' "$response")
      if [[ $status == COMPLETED ]]; then
        engine_v2_http "$VIDEO_V2_RESULT_URL" "$response" true "$VIDEO_V2_KEY" || {
          video_v2_error "Result request failed (HTTP ${ENGINE_V2_HTTP_CODE:-none})."
          return 1
        }
        link=$(jq -er '.video.url | select(type == "string" and length > 0)' "$response") || return 1
        auth=false
      fi
    ;;
    vercel|vercel_free)
      status=$(jq -r '.status // empty' "$response")
      if [[ $status == completed ]]; then
        case "$(jq -r '.videos[0].type // empty' "$response")" in
          url)
            link=$(jq -er '.videos[0].url | select(type == "string" and length > 0)' "$response") || return 1
            auth=false
          ;;
          base64)
            jq -r '.videos[0].data' "$response" | b64d > "$VIDEO_V2_WORK/media.part" || return 1
            video_v2_finish "$VIDEO_V2_WORK/media.part"
            return $?
          ;;
          *) video_v2_error 'Completed job carries no usable video payload.'; return 1 ;;
        esac
      fi
    ;;
    cyberneurova)
      status=$(jq -r '.status // empty' "$response")
      if [[ $status == completed ]]; then
        local video_id
        video_id=$(jq -er '.videoId | select(type == "string" and length > 0)' "$response") || return 1
        link="${VIDEO_V2_ENDPOINT%/videos/generations}/videos/$video_id/stream"
      fi
    ;;
  esac

  case "$status" in
    COMPLETED|SUCCESS|completed)
      [[ -n $link ]] || { video_v2_error 'Completed job has no media URL.'; return 1; }
      if [[ $auth == true ]]; then
        video_v2_http "$link" "$VIDEO_V2_WORK/media.part" true || return 1
      else
        engine_v2_http "$link" "$VIDEO_V2_WORK/media.part" false '' || {
          video_v2_error "Media download failed (HTTP ${ENGINE_V2_HTTP_CODE:-none})."
          return 1
        }
      fi
      video_v2_finish "$VIDEO_V2_WORK/media.part"
      return $?
    ;;
    PROCESSING|pending|in_progress|PENDING|IN_PROGRESS|queued|processing) ;;
    '')
      video_v2_error 'Polling response carries no status.'
      return 1
    ;;
    *)
      video_v2_error "Terminal or unknown status '$status'; response retained, no resubmission."
      return 1
    ;;
  esac
  return 2  # still pending
}

video_v2_poll() {
  local attempt rc

  for ((attempt = 0; attempt < VIDEO_V2_POLL_MAX; attempt++)); do
    video_v2_poll_status
    rc=$?
    case "$rc" in
      0) return 0 ;;
      2) ;;
      *) return 1 ;;
    esac
    if (( attempt + 1 < VIDEO_V2_POLL_MAX )); then sleep "$VIDEO_V2_POLL_INTERVAL"; fi
  done

  video_v2_error "Polling limit reached; resume '$VIDEO_V2_WORK/job.json' instead of resubmitting."
  return 1
}

# ── Entry point ─────────────────────────────────────────────────────────────

generate_video() (
  set +x
  set -o pipefail
  umask 077

  local prompt='' image='' resume='' generation_args=false
  local VIDEO_V2_PROVIDER="${VIDEO_PROVIDER:-}"
  local VIDEO_V2_MODEL='' VIDEO_V2_OPERATION='' VIDEO_V2_BLOCK=''
  local VIDEO_V2_ENDPOINT='' VIDEO_V2_ALLOW='' VIDEO_V2_PROTOCOL=''
  local VIDEO_V2_KEY='' VIDEO_V2_WORK='' VIDEO_V2_CATALOGUE='' VIDEO_V2_CONSTRAINTS=''
  local VIDEO_V2_UPSTREAM='' VIDEO_V2_JOB_ID='' VIDEO_V2_DOWNLOAD_URL=''
  local VIDEO_V2_RESULT_URL='' VIDEO_V2_OPERATION_JSON=''
  local VIDEO_V2_PROMPT='' VIDEO_V2_IMAGE='' VIDEO_V2_DURATION=''
  local VIDEO_V2_RESOLUTION='' VIDEO_V2_RATIO='' VIDEO_V2_FPS='' VIDEO_V2_FRAMES=''
  local VIDEO_V2_POLL_MAX="${VIDEO_POLL_MAX:-120}"
  local VIDEO_V2_POLL_INTERVAL="${VIDEO_POLL_INTERVAL:-5}"
  local root


  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) video_v2_help; return 0 ;;
      --prompt|--image|--model|--provider|--duration|--resolution|--ratio|--fps|--frames|--resume)
        [[ $# -ge 2 && -n $2 ]] || { video_v2_error "Missing value for $1."; return 1; }
        [[ $1 == --resume ]] || generation_args=true
        case "$1" in
          --prompt)     prompt="$2" ;;
          --image)      image="$2" ;;
          --model)      VIDEO_V2_MODEL="$2" ;;
          --provider)   VIDEO_V2_PROVIDER="$2" ;;
          --duration)   VIDEO_V2_DURATION="$2" ;;
          --resolution) VIDEO_V2_RESOLUTION="$2" ;;
          --ratio)      VIDEO_V2_RATIO="$2" ;;
          --fps)        VIDEO_V2_FPS="$2" ;;
          --frames)     VIDEO_V2_FRAMES="$2" ;;
          --resume)     resume="$2" ;;
        esac
        shift 2
      ;;
      --*) video_v2_error "Unknown option: $1"; return 1 ;;
      *)
        [[ -z $prompt ]] || { video_v2_error 'Quote the prompt as one argument.'; return 1; }
        prompt="$1"
        generation_args=true
        shift
      ;;
    esac
  done

  video_v2_deps || return 1
  [[ -n ${DATA_STORE:-} ]] || { video_v2_error 'DATA_STORE is not configured.'; return 1; }
  mkdir -p "$DATA_STORE/videos" || return 1
  root=$(cd "$DATA_STORE/videos" && pwd -P) || return 1

  # ── Resume: poll a job that already exists, never submit again ───────────
  if [[ -n $resume ]]; then
    [[ $generation_args == false ]] || {
      video_v2_error 'Resume cannot be combined with generation options.'
      return 1
    }
    [[ -f $resume && -r $resume && ! -L $resume ]] || { video_v2_error 'Resume needs a regular job.json file.'; return 1; }
    [[ ${resume##*/} == job.json ]] || { video_v2_error 'Resume expects a file named job.json.'; return 1; }

    VIDEO_V2_WORK=$(cd "$(dirname "$resume")" && pwd -P) || return 1
    [[ $VIDEO_V2_WORK == "$root/"* ]] || {
      video_v2_error 'Resume only accepts a job.json under DATA_STORE/videos.'
      return 1
    }
    jq -e '.version == 1 and (.id | type == "string" and length > 0)' "$resume" >/dev/null || {
      video_v2_error 'Invalid job file.'
      return 1
    }
    VIDEO_V2_PROVIDER=$(jq -er '.provider' "$resume") || return 1
    VIDEO_V2_MODEL=$(jq -er '.model' "$resume") || return 1
    VIDEO_V2_JOB_ID=$(jq -er '.id' "$resume") || return 1
    VIDEO_V2_DOWNLOAD_URL=$(jq -r '.download_url // empty' "$resume") || return 1
    VIDEO_V2_RESULT_URL=$(jq -r '.result_url // empty' "$resume") || return 1
    VIDEO_V2_OPERATION_JSON=$(jq -c '.operation // null' "$resume") || return 1
    VIDEO_V2_OPERATION='t2v'
    VIDEO_V2_BLOCK='video.t2v'
    video_v2_resolve_provider || return 1
    if video_v2_valid_media "$VIDEO_V2_WORK/output.mp4"; then
      printf 'Video already downloaded: %s/output.mp4\n' "$VIDEO_V2_WORK"
      return 0
    fi
    if ! has_provider_key "$VIDEO_V2_PROVIDER"; then
      video_v2_error 'Missing provider key for this job.'
      return 1
    fi
    VIDEO_V2_KEY=$(decrypt_provider_key "$VIDEO_V2_PROVIDER") || return 1
    video_v2_poll
    return $?
  fi

  # ── New generation ───────────────────────────────────────────────────────
  VIDEO_V2_PROMPT="${prompt:-Create a short video of anything you have in mind.}"
  VIDEO_V2_IMAGE="$image"
  VIDEO_V2_OPERATION=t2v
  VIDEO_V2_BLOCK=video.t2v
  if [[ -n $image ]]; then
    VIDEO_V2_OPERATION=i2v
    VIDEO_V2_BLOCK=video.i2v
  fi

  VIDEO_V2_DURATION="${VIDEO_V2_DURATION%s}"
  VIDEO_V2_DURATION="${VIDEO_V2_DURATION:-5}"
  [[ $VIDEO_V2_DURATION =~ ^[1-9][0-9]*$ ]] || { video_v2_error 'Duration must be a positive integer.'; return 1; }
  [[ -z $VIDEO_V2_RATIO || $VIDEO_V2_RATIO =~ ^[1-9][0-9]*:[1-9][0-9]*$ ]] || {
    video_v2_error 'Invalid aspect ratio.'
    return 1
  }

  if [[ -z $VIDEO_V2_PROVIDER && -r ${STATE_FILE:-} ]]; then
    VIDEO_V2_PROVIDER=$(jq -r '[.video, .provider] | map(select(type == "string" and length > 0)) | .[0] // empty' "$STATE_FILE")
  fi
  VIDEO_V2_PROVIDER="${VIDEO_V2_PROVIDER:-${PROVIDER:-}}"

  video_v2_resolve_provider || return 1
  video_v2_resolve_model || return 1

  # The key is needed by the Hugging Face mapping check inside the option
  # validation; the endpoint allowlist above already ran, so no credential
  # can leave towards an undocumented origin.
  has_provider_key "$VIDEO_V2_PROVIDER" || { video_v2_error 'Missing provider key.'; return 1; }
  VIDEO_V2_KEY=$(decrypt_provider_key "$VIDEO_V2_PROVIDER") || return 1

  VIDEO_V2_WORK=$(engine_v2_workdir videos) || { video_v2_error 'Cannot create a private work directory.'; return 1; }
  video_v2_options || return 1

  # The job directory survives so a pending job can be resumed; the request
  # material (prompt, source image) is removed as soon as it is submitted.
  trap 'rm -f "$VIDEO_V2_WORK/reference" "$VIDEO_V2_WORK/prompt" "$VIDEO_V2_WORK/request.json"' EXIT
  printf '%s' "$VIDEO_V2_PROMPT" > "$VIDEO_V2_WORK/prompt" || return 1
  video_v2_prepare_image || return 1
  video_v2_build_request || return 1
  video_v2_submit || return 1
  rm -f "$VIDEO_V2_WORK/reference" "$VIDEO_V2_WORK/prompt" "$VIDEO_V2_WORK/request.json"
  video_v2_poll
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  VIDEO_V2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$VIDEO_V2_ROOT/core.sh" || exit 1
  [[ $(type -t load_libs) == function ]] && load_libs
  generate_video "$@"
fi
