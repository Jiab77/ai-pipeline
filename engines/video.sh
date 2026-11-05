#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# engines/video.sh — Text/image-to-video engine
# ==============================================================================
# Generates videos from text prompts or source images through provider
# adapters. Usable as a sourced library or as a standalone CLI with Bash 3.2+.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.0
#
# Contract:
#   generate_video — Generate a video from text or an optional source image.
#
# Dependencies: core.sh helpers, jq, curl, file, base64, ffprobe, ffmpeg.
#
# Protocols (every video-capable provider entry is covered at engine level):
#   - venice   : native async queue/retrieve (t2v + i2v), live model catalogue.
#   - zai      : submit /paas/v4/videos/generations, GET async-result/{id},
#                result .video_result[0].url (official docs).
#   - openrouter: /api/v1/videos, polling same id, authenticated content endpoint.
#   - cyberneurova: /v1/videos/generations -> jobId -> status -> stream.
#                t2v only documented; i2v/control params refused locally.
#   - huggingface: HF token -> router.huggingface.co/fal-ai, live
#                inferenceProviderMapping check, explicit fal-ai upstream.
#                Defaults Wan-AI/Wan2.1-T2V-1.3B (t2v) and
#                Wan-AI/Wan2.1-I2V-14B-720P (i2v); queue polling; frames-based
#                (no duration control). fal-ai response_url paths are remapped
#                onto the HF router for status/result.
#   - vercel / vercel_free: raw AI Gateway SDK v4 protocol, no Node required.
#                POST {base}/video-model/start and /video-model/status; the
#                operation object is persisted; headers ai-model-id,
#                ai-video-model-specification-version: 4,
#                ai-gateway-protocol-version: 0.0.1,
#                ai-gateway-auth-method: api-key. Defaults
#                alibaba/wan-v2.6-{t2v,i2v}; the live catalogue validates
#                video_capabilities. Source images are URL-only for Gateway
#                models that require it; no automatic hosting/upload of local
#                sources. URL and base64 results are both supported.
#
# Config: .video.endpoint, .default, .models (existing registry supported).
# Built-in endpoint/default fallbacks cover providers whose registry entry has
# no .video block yet — adding a provider config block extends the engine,
# inventing endpoints does not.
# Optional extensions: .video.defaults.{t2v,i2v}, .models[id].modes,
# .models[id].duration, .models[id].resolution, .models[id].aspect_ratio.
# Venice modes are inferred only from explicit -text-to-video/-image-to-video
# model identifiers when .modes is absent. With no explicit model, the matching
# Venice t2v/i2v family variant is proposed, then checked against the live
# catalogue. Registry values pass through unchanged (casing included — two
# conventions coexist depending on media type).
#
# Submission is NEVER retried automatically (potential duplicate billing).
# Jobs live in data/videos/<unique directory>/job.json, mode 600, without keys
# or input images. --resume <job.json> polls/downloads WITHOUT resubmitting.
# Local signed download URLs in job.json are sensitive: do not share that file.
# ==============================================================================

VIDEO_POLL_INTERVAL=5
VIDEO_POLL_MAX=120
VIDEO_CONNECT_TIMEOUT=10
VIDEO_HTTP_TIMEOUT=120
VIDEO_STRIP_METADATA=true

video_error() { printf 'Video: %s\n' "$*" >&2; }

video_help() {
  cat <<'EOF'
Usage: video.sh [prompt] [options]
  --prompt TEXT       Explicit prompt (also accepts text beginning with --)
  --image FILE|URL    Image-to-video; without image: text-to-video
  --provider NAME    Override video/session provider
  --model NAME       Override model; must support the requested mode
  --duration N[s]    Duration in seconds (5 and 5s both accepted; Z.AI: 5|10,
                     Venice/OpenRouter/CyberNeurova per catalogue)
  --resolution VALUE Provider resolution: e.g. 1080p or 1920x1080 (Z.AI)
  --ratio W:H        Venice/OpenRouter/CyberNeurova aspect ratio (model-dependent)
  --fps N            Z.AI only: 30 or 60
  --frames N         Hugging Face only: fal-ai queue frame count
  --resume JOB.json  Resume an existing job, with current provider credentials
  --help             Show this help

Unsupported providers/modes fail before submission. No paid retry/fallback.
Resume cannot be combined with generation options. Output is a validated MP4.
EOF
}

# Resolve provider and key, but never replace an unsupported provider silently.
load_video_config() {
  if [[ -z $VIDEO_PROVIDER && -r ${STATE_FILE:-} ]]; then
    VIDEO_PROVIDER=$(jq -er '[.video,.provider] | map(select(type=="string" and length>0)) | .[0] // empty' "$STATE_FILE") || return 1
  fi
  VIDEO_PROVIDER="${VIDEO_PROVIDER:-${PROVIDER:-}}"
  case "$VIDEO_PROVIDER" in
    venice|zai|openrouter|huggingface|vercel|vercel_free|cyberneurova) ;;
    *) video_error "Provider '$VIDEO_PROVIDER' has no implemented video protocol."; return 1 ;;
  esac
  if [[ ${ZDR_ENFORCED:-false} == true ]]; then
    video_error "Async video retention has not been approved for ZDR; refusing submission/resume."
    return 1
  fi
  # Registry config when present; documented built-in defaults otherwise
  # (endpoints/models are recorded facts, not guesses).
  local ep ; ep=$(jq -r --arg p "$VIDEO_PROVIDER" '.[$p].video.endpoint // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
  if [[ -n $ep ]]; then
    jq -e --arg p "$VIDEO_PROVIDER" '.[$p].default.video == true' "$PROVIDERS_CONFIG" >/dev/null || {
      video_error "Missing video capability/configuration for '$VIDEO_PROVIDER'."; return 1;
    }
    VIDEO_ENDPOINT=$ep
  else
    case "$VIDEO_PROVIDER" in
      huggingface)        VIDEO_ENDPOINT='https://router.huggingface.co/fal-ai' ;;
      vercel|vercel_free) VIDEO_ENDPOINT='https://ai-gateway.vercel.sh/v4/ai/video-model/start' ;;
      cyberneurova)       VIDEO_ENDPOINT='https://api.cyberneurova.ai/v1/videos/generations' ;;
    esac
  fi
  # Auth is restricted to these documented API endpoints, including on resume.
  case "$VIDEO_PROVIDER:$VIDEO_ENDPOINT" in
    venice:https://api.venice.ai/api/v1/video/queue|zai:https://api.z.ai/api/paas/v4/videos/generations|openrouter:https://openrouter.ai/api/v1/videos|huggingface:https://router.huggingface.co/fal-ai|vercel:https://ai-gateway.vercel.sh/v4/ai/video-model/*|vercel_free:https://ai-gateway.vercel.sh/v4/ai/video-model/*|cyberneurova:https://api.cyberneurova.ai/v1/videos/*) ;;
    *) video_error "Unrecognized video API endpoint; refusing to send credentials."; return 1 ;;
  esac
  has_provider_key "$VIDEO_PROVIDER" || { video_error "Missing provider key."; return 1; }
  VIDEO_API_KEY=$(decrypt_provider_key "$VIDEO_PROVIDER") || return 1
  [[ -n $VIDEO_API_KEY ]] || { video_error "Empty provider key."; return 1; }
}

# Isolated command scope: variables, umask and traps cannot alter image.sh/core.sh.
# Transfer helper writes bodies to disk (MP4 never enters a shell variable).
# Authenticated calls cannot follow redirects to an arbitrary origin.
video_http() {
  local method="$1" url="$2" auth="$3" out="$4" body="${5:-}"
  local code
  local -a opts ; opts=(--silent --show-error --connect-timeout "$VIDEO_CONNECT_TIMEOUT"
    --max-time "$VIDEO_HTTP_TIMEOUT" --proto '=https' --proto-redir '=https'
    --output "$out" --write-out '%{http_code}' --user-agent "${USER_AGENT:-Mozilla/5.0}")
  [[ ${USE_TOR:-true} == true ]] && opts+=(--proxy "$TOR_PROXY")
  if [[ $auth == true ]]; then
    case "$VIDEO_PROVIDER:$url" in
      venice:https://api.venice.ai/api/v1/video/*|zai:https://api.z.ai/api/paas/v4/*|openrouter:https://openrouter.ai/api/v1/videos*|huggingface:https://router.huggingface.co/fal-ai/*|vercel:https://ai-gateway.vercel.sh/v4/ai/video-model/*|vercel_free:https://ai-gateway.vercel.sh/v4/ai/video-model/*|cyberneurova:https://api.cyberneurova.ai/v1/videos/*) ;;
      *) video_error "Refusing authenticated request outside provider API."; return 1 ;;
    esac
    opts+=(-H "Authorization: Bearer $VIDEO_API_KEY")
  else
    # Signed media URLs need no provider key. Only this path follows redirects.
    opts+=(--location)
  fi
  [[ $url == https://* ]] || { video_error "HTTPS required."; return 1; }
  if [[ $method == POST ]]; then
    opts+=(-H 'Content-Type: application/json' --data-binary "@$body")
  fi
  if ! code=$(curl "${opts[@]}" "$url"); then
    video_error "Network/transfer failure; no automatic resubmission."
    return 1
  fi
  case "$code" in
    2??) return 0 ;;
    *) video_error "HTTP $code from video service (response retained in job directory)."; return 1 ;;
  esac
}

video_resolve_request() {
  local modes default_model
  VIDEO_MODE=t2v
  [[ -n $video_image ]] && VIDEO_MODE=i2v
  default_model=$(jq -r --arg p "$VIDEO_PROVIDER" --arg mode "$VIDEO_MODE" \
    '.[$p].video | .defaults[$mode] // .default // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
  VIDEO_MODEL="${video_model:-$default_model}"
  # Provider-specific default models when the registry has none.
  if [[ -z $VIDEO_MODEL ]]; then
    case "$VIDEO_PROVIDER:$VIDEO_MODE" in
      venice:t2v)         VIDEO_MODEL='wan-2.5-preview-text-to-video' ;;
      venice:i2v)         VIDEO_MODEL='wan-2.5-preview-image-to-video' ;;
      zai:*)              VIDEO_MODEL='cogvideox-3' ;;
      openrouter:*)       VIDEO_MODEL='alibaba/wan-2.7' ;;
      huggingface:t2v)    VIDEO_MODEL='Wan-AI/Wan2.1-T2V-1.3B' ;;
      huggingface:i2v)    VIDEO_MODEL='Wan-AI/Wan2.1-I2V-14B-720P' ;;
      vercel:*|vercel_free:*) VIDEO_MODEL="alibaba/wan-v2.6-$VIDEO_MODE" ;;
      cyberneurova:*)     VIDEO_MODEL='artemis-vid' ;;
    esac
  elif [[ $VIDEO_PROVIDER == venice && -z $video_model ]]; then
    case "$VIDEO_MODE:$VIDEO_MODEL" in
      t2v:*-image-to-video*) VIDEO_MODEL="${VIDEO_MODEL/-image-to-video/-text-to-video}" ;;
      i2v:*-text-to-video*) VIDEO_MODEL="${VIDEO_MODEL/-text-to-video/-image-to-video}" ;;
    esac
  fi
  [[ -n $VIDEO_MODEL ]] || { video_error "No model configured for $VIDEO_MODE."; return 1; }
  modes=$(jq -c --arg p "$VIDEO_PROVIDER" --arg m "$VIDEO_MODEL" '.[$p].video.models[$m].modes // []' "$PROVIDERS_CONFIG" 2>/dev/null)
  if [[ $modes != '[]' && -n $modes ]]; then
    jq -e --arg mode "$VIDEO_MODE" 'type == "array" and index($mode) != null' <<< "$modes" >/dev/null || {
      video_error "Model '$VIDEO_MODEL' does not support $VIDEO_MODE."; return 1;
    }
  else
    case "$VIDEO_PROVIDER:$VIDEO_MODEL:$VIDEO_MODE" in
      venice:*-image-to-video*:i2v|venice:*-text-to-video*:t2v|zai:cogvideox-3:*) ;;
      openrouter:*)
        # Explicit models must be registered; do not guess arbitrary capabilities.
        jq -e --arg m "$VIDEO_MODEL" '.openrouter.video.models | has($m)' "$PROVIDERS_CONFIG" >/dev/null || {
          video_error "Unregistered OpenRouter model; configure its modes first."; return 1;
        }
      ;;
      huggingface:*) ;;
      vercel:*|vercel_free:*) ;;
      cyberneurova:artemis-vid:t2v) ;;
      cyberneurova:*) video_error "CyberNeurova video is text-to-video only; no documented image-to-video." ; return 1 ;;
      *) video_error "Model '$VIDEO_MODEL' incompatible with $VIDEO_MODE or capabilities unknown. Select/configure a matching model."; return 1 ;;
    esac
  fi
  VIDEO_DURATION=$(jq -r --arg p "$VIDEO_PROVIDER" --arg m "$VIDEO_MODEL" '.[$p].video.models[$m].duration // 5' "$PROVIDERS_CONFIG" 2>/dev/null)
  VIDEO_DURATION="${video_duration:-$VIDEO_DURATION}"
  VIDEO_DURATION="${VIDEO_DURATION%s}"
  [[ $VIDEO_DURATION =~ ^[1-9][0-9]*$ ]] || { video_error "Duration must be positive integer seconds."; return 1; }
  VIDEO_RESOLUTION=$(jq -r --arg p "$VIDEO_PROVIDER" --arg m "$VIDEO_MODEL" '.[$p].video.models[$m].resolution // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
  VIDEO_RESOLUTION="${video_resolution:-$VIDEO_RESOLUTION}"
  VIDEO_RATIO=$(jq -r --arg p "$VIDEO_PROVIDER" --arg m "$VIDEO_MODEL" '.[$p].video.models[$m].aspect_ratio // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
  VIDEO_RATIO="${video_ratio:-$VIDEO_RATIO}"
  [[ -z $VIDEO_RATIO || $VIDEO_RATIO =~ ^[1-9][0-9]*:[1-9][0-9]*$ ]] || { video_error "Invalid aspect ratio."; return 1; }
  case "$VIDEO_PROVIDER" in
    zai)
      [[ $VIDEO_DURATION == 5 || $VIDEO_DURATION == 10 ]] || { video_error "Z.AI duration: 5 or 10 seconds."; return 1; }
      case "$VIDEO_RESOLUTION" in
        ''|1280x720|720x1280|1024x1024|1920x1080|1080x1920|2048x1080|3840x2160) ;;
        *) video_error "Unsupported Z.AI size."; return 1 ;;
      esac
      [[ -z $VIDEO_RATIO ]] || { video_error "Use Z.AI --resolution WxH, not --ratio."; return 1; }
      [[ -z $video_frames ]] || { video_error "--frames is only supported by Hugging Face."; return 1; }
      VIDEO_FPS="${video_fps:-30}"
      [[ $VIDEO_FPS == 30 || $VIDEO_FPS == 60 ]] || { video_error "Z.AI FPS: 30 or 60."; return 1; }
      [[ ${#video_prompt} -le 512 ]] || { video_error "Z.AI prompt exceeds 512 characters."; return 1; }
    ;;
    venice)
      [[ -z $video_fps ]] || { video_error "--fps is only supported by this engine for Z.AI."; return 1; }
      [[ -z $video_frames ]] || { video_error "--frames is only supported by Hugging Face."; return 1; }
    ;;
    openrouter)
      [[ -z $video_fps ]] || { video_error "--fps is only supported by this engine for Z.AI."; return 1; }
      [[ -z $video_frames ]] || { video_error "--frames is only supported by Hugging Face."; return 1; }
    ;;
    huggingface)
      [[ -z $video_duration ]] || { video_error "Hugging Face fal-ai video is frames-based; use --frames, not --duration."; return 1; }
      [[ -z $video_fps ]] || { video_error "--fps is only supported by this engine for Z.AI."; return 1; }
      [[ -z $video_resolution ]] || { video_error "Hugging Face fal-ai does not expose resolution control."; return 1; }
      VIDEO_FRAMES="${video_frames:-}"
      [[ -z $VIDEO_FRAMES || $VIDEO_FRAMES =~ ^[1-9][0-9]*$ ]] || { video_error "--frames must be a positive integer."; return 1; }
    ;;
    vercel|vercel_free)
      [[ -z $video_fps ]] || { video_error "--fps is only supported by this engine for Z.AI."; return 1; }
      [[ -z $video_frames ]] || { video_error "--frames is only supported by Hugging Face."; return 1; }
    ;;
    cyberneurova)
      [[ -z $video_image ]] && : || return 0  # i2v already rejected above
      [[ -z $video_fps ]] || { video_error "--fps is only supported by this engine for Z.AI."; return 1; }
      [[ -z $video_frames ]] || { video_error "--frames is only supported by Hugging Face."; return 1; }
      [[ -z $video_resolution ]] || { video_error "CyberNeurova video does not expose resolution control."; return 1; }
    ;;
  esac
  return 0
}

# Validate public model constraints before any billable call.
video_validate_model() {
  local metadata="$VIDEO_WORK/models.json" catalogue_url
  case "$VIDEO_PROVIDER" in
    openrouter)
      catalogue_url=$(jq -rc .openrouter.models "$PROVIDERS_CONFIG")
      video_http GET "$catalogue_url" false "$metadata" || return 1
      jq -e --arg m "$VIDEO_MODEL" --argjson d "$VIDEO_DURATION" --arg r "$VIDEO_RESOLUTION" --arg a "$VIDEO_RATIO" '
        def accepts($list; $v): ($list == null or ($list|length) == 0 or ($list|index($v)) != null);
        .data[] | select(.id == $m) |
        accepts(.supported_durations; $d) and
        ($r == "" or accepts(.supported_resolutions; $r)) and
        ($a == "" or accepts(.supported_aspect_ratios; $a))
      ' "$metadata" >/dev/null || { video_error "Model or requested parameters not supported by OpenRouter catalogue."; return 1; }
    ;;
    venice)
      catalogue_url=$(jq -rc .venice.models "$PROVIDERS_CONFIG")
      # Model constraints vary rapidly. Query the canonical model specification.
      video_http GET "${catalogue_url}?type=video" false "$metadata" || return 1
      local constraints="$VIDEO_WORK/constraints.json"
      jq -e --arg m "$VIDEO_MODEL" '.data[] | select(.id == $m and .model_spec.offline != true) |
        .model_spec.constraints' "$metadata" > "$constraints" || {
        video_error "Model absent/offline or missing Venice constraints."; return 1;
      }
      # Only send a ratio when supported. i2v often derives it from the image.
      if [[ -z $VIDEO_RATIO ]]; then
        VIDEO_RATIO=$(jq -r '(.aspect_ratios // []) | if index("16:9") != null then "16:9" else .[0] // empty end' "$constraints") || return 1
      fi
      jq -e --arg mode "$VIDEO_MODE" --arg d "${VIDEO_DURATION}s" --arg r "$VIDEO_RESOLUTION" \
        --arg a "$VIDEO_RATIO" --argjson n "${#video_prompt}" '
        .model_type == (if $mode == "t2v" then "text-to-video" else "image-to-video" end) and
        (.durations | index($d)) != null and
        ($r == "" or (.resolutions | index($r)) != null) and
        ($a == "" or (.aspect_ratios | index($a)) != null) and
        $n <= (.prompt_character_limit // 2500)
      ' "$constraints" >/dev/null || { video_error "Unsupported Venice mode/duration/resolution/ratio or prompt length."; return 1; }
    ;;
    huggingface)
      catalogue_url=$(jq -rc .huggingface.models "$PROVIDERS_CONFIG")
      # Verify the model is live on the router for the requested task, with an
      # explicitly chosen fal-ai upstream. Never trust the catalogue blindly.
      local encoded ; encoded=$(jq -nr --arg m "$VIDEO_MODEL" '$m|@uri') || return 1
      video_http GET "${catalogue_url}/$encoded" false "$metadata" || return 1
      jq -e --arg op "$(if [[ $VIDEO_MODE == t2v ]]; then echo text-to-video; else echo image-to-video; fi)" '
        .inferenceProviderMapping["fal-ai"]? |
        .status == "live" and .task == $op and (.providerId | startswith("fal-ai/"))
      ' "$metadata" >/dev/null || { video_error "Model not live via fal-ai on the HF router for this task."; return 1; }
    ;;
    vercel|vercel_free)
      catalogue_url=$(jq -rc .vercel.models "$PROVIDERS_CONFIG")
      video_http GET "$catalogue_url" false "$metadata" || return 1
      jq -e --arg m "$VIDEO_MODEL" --arg op "$(if [[ $VIDEO_MODE == t2v ]]; then echo text-to-video; else echo image-to-video; fi)" \
        --argjson d "$VIDEO_DURATION" --arg r "$VIDEO_RESOLUTION" --arg a "$VIDEO_RATIO" '
        .data[] | select(.id == $m and .type == "video") | .video_capabilities |
        ((.supported_operations | index($op)) != null) and
        ((.supported_durations_seconds | index($d)) != null) and
        ($r == "" or ((.supported_resolutions | index($r)) != null)) and
        ($a == "" or ((.supported_aspect_ratios | index($a)) != null))
      ' "$metadata" >/dev/null || { video_error "Model or requested parameters not supported by the AI Gateway catalogue."; return 1; }
    ;;
  esac
  return 0
}

# Reference is a private temporary file, read with --rawfile, never argv/base64.
video_prepare_image() {
  local mime
  : > "$VIDEO_WORK/reference"
  [[ -n $video_image ]] || return 0
  if [[ $video_image == https://* ]]; then
    printf '%s' "$video_image" > "$VIDEO_WORK/reference"
  elif [[ -f $video_image && -r $video_image ]]; then
    # CyberNeurova has no documented i2v; refuse before any billable call.
    if [[ $VIDEO_PROVIDER == cyberneurova ]]; then
      video_error "CyberNeurova video is text-to-video only; no documented image input."
      return 1
    fi
    mime=$(file -b --mime-type "$video_image") || return 1
    case "$mime" in
      image/jpeg|image/png) ;;
      image/webp)
        # WebP is accepted by the Venice media pipeline (verified live); Z.AI
        # rejects it — refuse locally with a clear message instead of a 400.
        [[ $VIDEO_PROVIDER == venice ]] || {
          video_error "Provider '$VIDEO_PROVIDER' does not accept WebP input; use a PNG or JPEG image."
          return 1
        }
      ;;
      *) video_error "Use a PNG or JPEG input image."; return 1 ;;
    esac
    if [[ $VIDEO_PROVIDER == zai && $(wc -c < "$video_image") -gt 5242880 ]]; then
      video_error "Z.AI image exceeds 5 MiB."; return 1
    fi
    printf 'data:%s;base64,' "$mime" > "$VIDEO_WORK/reference"
    (set -o pipefail; b64e < "$video_image" >> "$VIDEO_WORK/reference") || return 1
  else
    video_error "Input must be a readable PNG/JPEG file or HTTPS URL."
    return 1
  fi
}

build_video_request() {
  local base="$VIDEO_WORK/base.json"
  # Prompt likewise travels through a file, not a potentially oversized argument.
  printf '%s' "$video_prompt" > "$VIDEO_WORK/prompt" || return 1
  jq -n --arg m "$VIDEO_MODEL" --rawfile p "$VIDEO_WORK/prompt" \
    --argjson d "$VIDEO_DURATION" --arg r "$VIDEO_RESOLUTION" --arg a "$VIDEO_RATIO" \
    '{model:$m,prompt:$p,duration:$d} + (if $r != "" then {resolution:$r} else {} end)
      + (if $a != "" then {aspect_ratio:$a} else {} end)' > "$base" || return 1
  case "$VIDEO_PROVIDER" in
    venice)
      jq --rawfile i "$VIDEO_WORK/reference" '.duration = ((.duration|tostring)+"s") |
        . + (if $i != "" then {image_url:$i} else {} end)' "$base" > "$VIDEO_WORK/request.json"
    ;;
    zai)
      jq --rawfile i "$VIDEO_WORK/reference" --argjson fps "$VIDEO_FPS" '
        (if has("resolution") then .size=.resolution | del(.resolution) else . end) |
        . + {fps:$fps} + (if $i != "" then {image_url:[$i]} else {} end)' "$base" > "$VIDEO_WORK/request.json"
    ;;
    openrouter)
      jq --rawfile i "$VIDEO_WORK/reference" '. + (if $i != "" then
        {frame_images:[{type:"image_url",image_url:{url:$i},frame_type:"first_frame"}]} else {} end)' \
        "$base" > "$VIDEO_WORK/request.json"
    ;;
    huggingface)
      # fal-ai contract: prompt + optional image source; no model/duration keys.
      jq --rawfile i "$VIDEO_WORK/reference" --argjson f "${video_frames:-0}" '
        {prompt:$p} + (if $i != "" then {image_url:$i} else {} end)
        + (if $f > 0 then {frames:$f} else {} end)' "$base" > "$VIDEO_WORK/request.json"
    ;;
    vercel|vercel_free)
      # Gateway SDK v4: model travels in the ai-model-id header; source images
      # are URL-only — a local file is refused upstream, never auto-uploaded.
      if [[ -n $video_image && $video_image != https://* ]]; then
        video_error "Gateway models accept a source URL only; hosting a local file automatically is not supported."
        return 1
      fi
      jq --rawfile i "$VIDEO_WORK/reference" '.n = 1 |
        . + (if $i != "" then {image:{type:"url",url:$i}} else {} end)' "$base" > "$VIDEO_WORK/request.json"
    ;;
    cyberneurova)
      # Documented contract: prompt only (plus server default duration).
      jq '{prompt:.prompt} + del(.resolution, .aspect_ratio)' "$base" > "$VIDEO_WORK/request.json"
    ;;
  esac
}

# Atomic persistence of the server response precedes polling. No API key stored.
video_save_job() {
  jq -n --arg p "$VIDEO_PROVIDER" --arg m "$VIDEO_MODEL" --arg id "$VIDEO_JOB_ID" \
    --arg link "$VIDEO_DOWNLOAD_URL" --arg rurl "$VIDEO_RESULT_URL" \
    --argjson op "${OPERATION_JSON:-null}" \
    '{version:1,provider:$p,model:$m,id:$id,download_url:$link,result_url:$rurl,operation:$op}' \
    > "$VIDEO_WORK/job.tmp" && mv "$VIDEO_WORK/job.tmp" "$VIDEO_WORK/job.json"
}

video_submit() {
  local response="$VIDEO_WORK/submission.json"
  video_http POST "$VIDEO_ENDPOINT" true "$response" "$VIDEO_WORK/request.json" || return 1
  VIDEO_DOWNLOAD_URL=''; VIDEO_RESULT_URL=''; OPERATION_JSON=''
  case "$VIDEO_PROVIDER" in
    venice)
      VIDEO_JOB_ID=$(jq -er '.queue_id | select(type=="string" and length>0)' "$response") || return 1
      VIDEO_DOWNLOAD_URL=$(jq -r '.download_url // empty' "$response") || return 1
    ;;
    cyberneurova)
      VIDEO_JOB_ID=$(jq -er '.jobId | select(type=="string" and length>0)' "$response") || return 1
    ;;
    huggingface)
      # Remap the fal-ai response_url path onto the HF router (queue subdomain).
      local rurl path
      rurl=$(jq -er '.response_url | select(type=="string" and length>0)' "$response") || return 1
      VIDEO_JOB_ID=$(jq -er '.request_id | select(type=="string" and length>0)' "$response") || return 1
      path=${rurl#*://}        # drop scheme
      path=/${path#*/}         # drop host, keep leading path
      VIDEO_RESULT_URL="https://router.huggingface.co/fal-ai${path%%\?*}?_subdomain=queue"
    ;;
    vercel|vercel_free)
      VIDEO_JOB_ID=$(jq -er '.operation.gatewayJobId | select(type=="string" and length>0)' "$response") || return 1
      OPERATION_JSON=$(jq -c '.operation' "$response") || return 1
    ;;
    *) VIDEO_JOB_ID=$(jq -er '.id | select(type=="string" and length>0)' "$response") || return 1 ;;
  esac
  video_save_job || { video_error "Cannot save job; submission response retained. DO NOT resubmit blindly."; return 1; }
  printf 'Video job saved: %s/job.json\n' "$VIDEO_WORK" >&2
}

video_valid_media() {
  [[ -s $1 ]] || return 1
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$1" 2>/dev/null | grep -qx video || return 1
  ffprobe -v error -show_entries format=format_name -of csv=p=0 "$1" 2>/dev/null | grep -q mp4
}

video_finish() {
  local input="$1" output="$VIDEO_WORK/output.mp4" clean="$VIDEO_WORK/clean.mp4"
  video_valid_media "$input" || { video_error "Downloaded data is not a readable MP4 video."; return 1; }
  if [[ $VIDEO_STRIP_METADATA == true ]]; then
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$input" -map 0:v -map '0:a?' \
      -map_metadata -1 -map_chapters -1 -c copy "$clean" || { video_error "Metadata cleanup failed."; return 1; }
    video_valid_media "$clean" || return 1
    mv "$clean" "$output" || return 1
    rm -f "$input"
  else
    mv "$input" "$output" || return 1
  fi
  printf 'Video created: %s\n' "$output"
}

video_poll() {
  local encoded url body='' response status link auth i hfbase vtype vid vdata
  encoded=$(jq -nr --arg id "$VIDEO_JOB_ID" '$id|@uri') || return 1
  case "$VIDEO_PROVIDER" in
    venice)
      url="${VIDEO_ENDPOINT%/queue}/retrieve"
      jq -n --arg m "$VIDEO_MODEL" --arg id "$VIDEO_JOB_ID" '{model:$m,queue_id:$id}' > "$VIDEO_WORK/poll.json" || return 1
      body="$VIDEO_WORK/poll.json"
    ;;
    zai) url="${VIDEO_ENDPOINT%/videos/generations}/async-result/$encoded" ;;
    openrouter) url="$VIDEO_ENDPOINT/$encoded" ;;
    huggingface)
      hfbase=${VIDEO_RESULT_URL%%\?*}
      url="${hfbase}/status?_subdomain=queue"
    ;;
    vercel|vercel_free) url="${VIDEO_ENDPOINT%/*}/status" ;;
    cyberneurova) url="${VIDEO_ENDPOINT%/videos/generations}/videos/status/$VIDEO_JOB_ID" ;;
  esac
  for ((i=0; i<VIDEO_POLL_MAX; i++)); do
    response="$VIDEO_WORK/result"
    if [[ $VIDEO_PROVIDER == venice ]]; then
      video_http POST "$url" true "$response" "$body" || return 1
      if video_valid_media "$response"; then video_finish "$response"; return $?; fi
    elif [[ $VIDEO_PROVIDER == vercel || $VIDEO_PROVIDER == vercel_free ]]; then
      # Gateway status is a POST carrying the persisted operation object.
      jq -n --argjson op "$OPERATION_JSON" '{operation:$op}' > "$VIDEO_WORK/poll.json" || return 1
      video_http POST "$url" true "$response" "$VIDEO_WORK/poll.json" || return 1
    else
      video_http GET "$url" true "$response" || return 1
    fi
    jq -e 'type=="object"' "$response" >/dev/null 2>&1 || { video_error "Invalid polling response."; return 1; }
    link=''
    case "$VIDEO_PROVIDER" in
      venice) status=$(jq -r '.status // empty' "$response"); link="$VIDEO_DOWNLOAD_URL" ;;
      zai) status=$(jq -r '.task_status // empty' "$response"); link=$(jq -r '.video_result[0].url // empty' "$response") ;;
      openrouter) status=$(jq -r '.status // empty' "$response"); link="$VIDEO_ENDPOINT/$encoded/content?index=0"; auth=true ;;
      huggingface)
        status=$(jq -r '.status // empty' "$response")
        if [[ $status == COMPLETED ]]; then
          # Result is fetched with credentials; the media link itself is pre-signed.
          video_http GET "$VIDEO_RESULT_URL" true "$response" || return 1
          link=$(jq -er '.video.url | select(type=="string" and length>0)' "$response") || return 1
          auth=false
        fi
      ;;
      vercel|vercel_free)
        status=$(jq -r '.status // empty' "$response")
        if [[ $status == completed ]]; then
          vtype=$(jq -r '.videos[0].type // empty' "$response")
          case "$vtype" in
            url)
              link=$(jq -er '.videos[0].url | select(type=="string" and length>0)' "$response") || return 1
              auth=false # signed media link: no provider credentials
            ;;
            base64)
              jq -r '.videos[0].data' "$response" | b64d > "$VIDEO_WORK/media.part" || return 1
              video_finish "$VIDEO_WORK/media.part"
              return $?
            ;;
            *) video_error "Completed Gateway job has no usable video payload."; return 1 ;;
          esac
        fi
      ;;
      cyberneurova)
        status=$(jq -r '.status // empty' "$response")
        if [[ $status == completed ]]; then
          vid=$(jq -er '.videoId | select(type=="string" and length>0)' "$response") || return 1
          link="${VIDEO_ENDPOINT%/videos/generations}/videos/$vid/stream"
          auth=true
        fi
      ;;
    esac
    case "$status" in
      COMPLETED|SUCCESS|completed)
        [[ -n $link ]] || { video_error "Completed job has no media URL."; return 1; }
        video_http GET "$link" "$auth" "$VIDEO_WORK/media.part" || return 1
        video_finish "$VIDEO_WORK/media.part"
        return $?
      ;;
      PROCESSING|pending|in_progress|PENDING|IN_PROGRESS|queued|processing) ;;
      *) video_error "Terminal or unknown job status '$status'; response retained, no resubmission."; return 1 ;;
    esac
    if ((i+1 < VIDEO_POLL_MAX)); then sleep "$VIDEO_POLL_INTERVAL"; fi
  done
  video_error "Polling limit reached. Resume the saved job; do not submit again."
  return 1
}

generate_video() (
  # Never trace decrypted keys or private media URLs, even if caller uses -x.
  set +x
  umask 077
  local video_prompt='' video_image='' video_model='' video_duration='' video_resolution='' video_ratio='' video_fps='' video_frames=''
  local resume='' generation_args=false dep root
  local VIDEO_PROVIDER="${VIDEO_PROVIDER:-}" VIDEO_API_KEY='' VIDEO_ENDPOINT=''
  local VIDEO_MODEL VIDEO_MODE VIDEO_DURATION VIDEO_RESOLUTION VIDEO_RATIO VIDEO_FPS
  local VIDEO_WORK='' VIDEO_JOB_ID='' VIDEO_DOWNLOAD_URL='' VIDEO_RESULT_URL='' OPERATION_JSON='' VIDEO_FRAMES=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) video_help; return 0 ;;
      --prompt|--image|--model|--provider|--duration|--resolution|--ratio|--fps|--frames|--resume)
        [[ $# -ge 2 && -n $2 ]] || { video_error "Missing value for $1."; return 1; }
        [[ $1 == --resume ]] || generation_args=true
        case "$1" in
          --prompt) video_prompt="$2" ;; --image) video_image="$2" ;;
          --model) video_model="$2" ;; --provider) VIDEO_PROVIDER="$2" ;;
          --duration) video_duration="$2" ;; --resolution) video_resolution="$2" ;;
          --ratio) video_ratio="$2" ;; --fps) video_fps="$2" ;;
          --frames) video_frames="$2" ;; --resume) resume="$2" ;;
        esac
        shift 2
      ;;
      --*) video_error "Unknown option: $1"; return 1 ;;
      *) [[ -z $video_prompt ]] || { video_error "Quote the prompt as one argument."; return 1; }
        video_prompt="$1"; generation_args=true; shift ;;
    esac
  done
  for dep in jq curl file base64 ffprobe; do
    command -v "$dep" >/dev/null 2>&1 || { video_error "Missing dependency: $dep"; return 1; }
  done
  if [[ $VIDEO_STRIP_METADATA == true ]]; then
    command -v ffmpeg >/dev/null 2>&1 || { video_error "Missing dependency: ffmpeg"; return 1; }
  fi
  [[ -n ${DATA_STORE:-} ]] || { video_error "DATA_STORE is not configured."; return 1; }
  mkdir -p "$DATA_STORE/videos" || return 1
  root=$(cd "$DATA_STORE/videos" && pwd -P) || return 1
  if [[ -n $resume ]]; then
    [[ $generation_args == false && -f $resume && ! -L $resume ]] || { video_error "Resume requires only a regular job.json file."; return 1; }
    VIDEO_WORK=$(cd "$(dirname "$resume")" && pwd -P) || return 1
    [[ $VIDEO_WORK == "$root/"* && ${resume##*/} == job.json ]] || { video_error "Resume must use a job.json under DATA_STORE/videos."; return 1; }
    jq -e '.version==1 and (.id|type=="string" and length>0) and (.model|type=="string")' "$resume" >/dev/null || return 1
    VIDEO_PROVIDER=$(jq -er '.provider' "$resume") || return 1
    VIDEO_MODEL=$(jq -er '.model' "$resume") || return 1
    VIDEO_JOB_ID=$(jq -er '.id' "$resume") || return 1
    VIDEO_DOWNLOAD_URL=$(jq -r '.download_url // empty' "$resume") || return 1
    VIDEO_RESULT_URL=$(jq -r '.result_url // empty' "$resume")
    OPERATION_JSON=$(jq -c '.operation // empty' "$resume")
    [[ -n $OPERATION_JSON ]] || OPERATION_JSON='null'
    load_video_config || return 1
    if video_valid_media "$VIDEO_WORK/output.mp4"; then
      printf 'Video already downloaded: %s/output.mp4\n' "$VIDEO_WORK"
      return 0
    fi
  else
    [[ -n $video_prompt ]] || video_prompt='Create a short video of anything you have in mind.'
    load_video_config || return 1
    video_resolve_request || return 1
    VIDEO_WORK=$(mktemp -d "$root/$(date +%Y%m%d-%H%M%S).XXXXXX") || return 1
    trap 'rm -f "$VIDEO_WORK/reference" "$VIDEO_WORK/prompt" "$VIDEO_WORK/base.json" "$VIDEO_WORK/request.json"' EXIT
    video_prepare_image && video_validate_model && build_video_request || return 1
    video_submit || return 1
    rm -f "$VIDEO_WORK/reference" "$VIDEO_WORK/prompt" "$VIDEO_WORK/base.json" "$VIDEO_WORK/request.json"
  fi
  video_poll
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    video_help ; exit 0
  fi
  VID_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$VID_ROOT/core.sh" || exit 1
  [[ $(type -t 'load_libs') == 'function' ]] && load_libs
  generate_video "$@"
fi
