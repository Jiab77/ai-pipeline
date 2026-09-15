#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2001,SC2094
# ==============================================================================
# image.sh — Image Rendering Engine (Hybrid Library / Standalone CLI)
# ==============================================================================
# Config-driven image generation, decoupled from the chat provider.
#
# Reads the `image` object from providers.json for the active image provider:
#   .image.mode      "native" (POST on image endpoint) | "chat" (chat/completions + modalities)
#   .image.endpoint  base endpoint (native mode only)
#   .image.default   default model id
#   .image.models    { "<id>": { "size_mode": "size_string"|"pixel"|"aspect_ratio", ... } }
#   .image.output    "url" | "base64" | "binary"
#
# Sizing bounds come from the model config (min/max/step/max_px) — nothing hardcoded.
# When the active provider does not support images (default.image != true),
# generation falls back to pollinations.ai (free, keyless).
#
# Hybrid script (same pattern as core.sh):
#   • sourced  → functions only, zero side effects (cli.sh composition root,
#                tools.sh generate_image wrapper)
#   • executed → standalone CLI: sources core.sh helpers, then generate_image
#                with CLI flags. Provider resolution falls back to state.json
#                (see load_image_config) — no session variables needed.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (DeepSeek)
#
# Version: 0.1.0
# ==============================================================================

# Options
# [[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x
# set -o pipefail

# -----------------------------------------------------------------------------
# Config (fallback defaults only)
# -----------------------------------------------------------------------------
DEFAULT_FORMAT="webp"
DEFAULT_WIDTH=2048
DEFAULT_HEIGHT=2048
DEFAULT_RATIO="16:9"
DEFAULT_RESOLUTION="2K"

# Default sizing bounds when the model config does not provide them
IMG_DEF_MIN=512
IMG_DEF_MAX=2048
IMG_DEF_STEP=32
IMG_DEF_MAX_PX=4194304

# Strip provider metadata (EXIF) from generated images when true
STRIP_METADATA=true

# -----------------------------------------------------------------------------
# Math helpers
# -----------------------------------------------------------------------------
gcd() { local a=$1 b=$2 c; while ((b)); do c=$a; a=$b; b=$((c%b)); done; echo "$a"; }
lcm() { echo $(($1 * $2 / $(gcd "$1" "$2"))); }

# -----------------------------------------------------------------------------
# get_perfect_size <ratio> <min> <max> <step> <max_px>
#   Largest WxH (exact ratio) with both dimensions multiples of <step>,
#   within [min,max] and <= max_px total pixels.
# -----------------------------------------------------------------------------
get_perfect_size() {
  local ratio="$1" min="$2" max="$3" step="$4" max_px="$5"
  local a="${ratio%:*}" b="${ratio#*:}"

  [[ -z $a || -z $b || $b -eq 0 ]] && { log_error "Invalid ratio: $ratio"; return 1; }

  local gcd_w gcd_h k_step
  gcd_w=$(gcd "$a" "$step"); gcd_h=$(gcd "$b" "$step")
  k_step=$(lcm $((step/gcd_w)) $((step/gcd_h)))

  local w0=$((a * k_step)) h0=$((b * k_step))
  local max_k_w=$((max / w0)) max_k_h=$((max / h0))
  local max_k_area
  max_k_area=$(awk "BEGIN{printf \"%d\",int(sqrt($max_px/($w0*$h0)))}")

  local max_k=$((max_k_w < max_k_h ? max_k_w : max_k_h))
  max_k=$((max_k < max_k_area ? max_k : max_k_area))
  local min_k_w=$(((min + w0 - 1) / w0))
  local min_k_h=$(((min + h0 - 1) / h0))
  local min_k=$((min_k_w > min_k_h ? min_k_w : min_k_h))

  for ((k = max_k; k >= min_k; k--)); do
    if ((w0 * k * h0 * k <= max_px)); then
      printf '%d%s%d' "$((w0*k))" "x" "$((h0*k))"
      return 0
    fi
  done
  return 1
}

# -----------------------------------------------------------------------------
# get_file_type
#   Find the right mime and define the right extension for the generated image.
# -----------------------------------------------------------------------------
get_file_type() {
  local f="$1" mime ext new
  mime=$(file -b --mime-type "$f" 2>/dev/null)
  case "$mime" in
    image/gif) ext=".gif" ;;
    image/jpeg) ext=".jpg"  ;;
    image/png)  ext=".png"  ;;
    image/webp) ext=".webp" ;;
    *)          echo "$f"; return 0 ;;
  esac
  new="${f%.*}${ext}"
  [[ "$new" != "$f" ]] && mv -f "$f" "$new"
  echo "$new"
}

# -----------------------------------------------------------------------------
# compute_dimensions <min> <max> <step> <max_px>
#   Return canonical "WxH" for size_string/pixel modes.
#   Honors an explicit --size, otherwise computes the perfect size for the ratio.
# -----------------------------------------------------------------------------
compute_dimensions() {
  local min="$1" max="$2" step="$3" max_px="$4"
  local ratio="${image_ratio:-$DEFAULT_RATIO}"

  [[ -n $image_size ]] && { echo "$image_size"; return 0; }

  local dims
  if ! dims=$(get_perfect_size "$ratio" "$min" "$max" "$step" "$max_px"); then
    log_error "No valid size for ratio '$ratio' within ${min}-${max}px (step ${step}, max ${max_px}px)."
    return 1
  fi
  echo "$dims"
}

# -----------------------------------------------------------------------------
# load_image_config
#   Resolve the image provider and read its `image` config into IMAGE_* globals.
#   Sets IMAGE_FALLBACK=true when the provider has no image capability.
# -----------------------------------------------------------------------------
load_image_config() {
  local has_image

  # Resolve the image provider (first match wins):
  #   1. explicit --provider   → already stored in IMAGE_PROVIDER by generate_image()
  #   2. $IMAGE_PROVIDER       → session state (/image <provider>)
  #   3. config/state.json     → active provider mirror. Readable from ANY context
  #                              (forked tools.sh process, standalone CLI) where
  #                              session variables are invisible.
  #   4. $PROVIDER             → live session variable (last resort)
  #   5. pollinations fallback → when the resolved provider cannot render images
  #
  # state.json is deliberately checked BEFORE $PROVIDER: sourcing core.sh seeds
  # PROVIDER with a hardcoded module-level default ("vercel") which would
  # resurrect the ghost provider in standalone mode. state.json is kept in sync
  # with the session by set_state() (boot, /provider, /model) — in-session both
  # are equivalent; file-only contexts have nothing else to read.

  if [[ -z $IMAGE_PROVIDER && -n ${STATE_FILE:-} && -r $STATE_FILE ]]; then
    IMAGE_PROVIDER=$(jq -rc '.image // .provider // empty' "$STATE_FILE" 2>/dev/null)
  fi
  [[ -z $IMAGE_PROVIDER ]] && IMAGE_PROVIDER=$(jq -rc '.provider // empty' "$STATE_FILE" 2>/dev/null)
  [[ -z $IMAGE_PROVIDER && -n ${PROVIDER:-} ]] && IMAGE_PROVIDER="$PROVIDER"

  has_image=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].default.image // false' "$PROVIDERS_CONFIG" 2>/dev/null)

  if [[ $has_image != "true" ]]; then
    IMAGE_FALLBACK=true
    IMAGE_MODE="" IMAGE_ENDPOINT="" IMAGE_OUTPUT="" IMAGE_DEFAULT_MODEL="" IMAGE_API_KEY=""
    return 0
  fi

  IMAGE_FALLBACK=false
  IMAGE_MODE=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].image.mode // "native"' "$PROVIDERS_CONFIG" 2>/dev/null)
  IMAGE_ENDPOINT=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].image.endpoint // empty' "$PROVIDERS_CONFIG" 2>/dev/null)
  IMAGE_OUTPUT=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].image.output // "url"' "$PROVIDERS_CONFIG" 2>/dev/null)
  IMAGE_DEFAULT_MODEL=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].image.default // empty' "$PROVIDERS_CONFIG" 2>/dev/null)

  # Load the image provider key in isolation (does not clobber PROVIDER_API_KEY)
  IMAGE_API_KEY=""
  if has_provider_key "$IMAGE_PROVIDER"; then
    IMAGE_API_KEY=$(decrypt_provider_key "$IMAGE_PROVIDER" 2>/dev/null)
  fi
}

# -----------------------------------------------------------------------------
# get_image_model <requested_model>
#   Resolve the final model: explicit --model > config default.
# -----------------------------------------------------------------------------
get_image_model() {
  local requested="$1"
  [[ -n $requested ]] && { echo "$requested"; return 0; }
  echo "$IMAGE_DEFAULT_MODEL"
}

# -----------------------------------------------------------------------------
# get_model_sizing <model>
#   Emit tab-separated: size_mode \t min \t max \t step \t max_px \t resolution
#   (defaults applied when the model config omits them).
# -----------------------------------------------------------------------------
get_model_sizing() {
  local model="$1"
  # NUL-delimited output — @tsv silently shifts EVERY field by one
  # as soon as an empty value sits in the middle, and `//` does NOT catch "" (only null/false).
  jq -j \
    --arg p "$IMAGE_PROVIDER" \
    --arg m "$model" \
    --arg r "$DEFAULT_RESOLUTION" \
    '.[$p].image.models[$m] as $c
    | [ $c.size_mode // "size_string",
        ($c.min // '"$IMG_DEF_MIN"'),
        ($c.max // '"$IMG_DEF_MAX"'),
        ($c.step // '"$IMG_DEF_STEP"'),
        ($c.max_px // '"$IMG_DEF_MAX_PX"'),
        (($c.resolution // $r) | if type == "array" then .[0] else . end) ]
    | .[] | ., "\u0000"
    ' "$PROVIDERS_CONFIG" 2>/dev/null
}

# -----------------------------------------------------------------------------
# get_output_name
#   Timestamped + slugged output path under data/images.
# -----------------------------------------------------------------------------
get_output_name() {
  local out_dir="${DATA_STORE}/images"
  local ts slug
  mkdir -p "$out_dir"
  ts=$(date +%Y%m%d-%H%M%S)
  slug=$(printf '%s' "$image_prompt" | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-32)
  echo "${out_dir}/${ts}-${slug}"
}

# -----------------------------------------------------------------------------
# build_image_request <model> <prompt> <size_mode> <min> <max> <step> <max_px> <resolution>
#   Set IMAGE_PAYLOAD + IMAGE_URL globals.
# -----------------------------------------------------------------------------
build_image_request() {
  local model="$1" prompt="$2" size_mode="$3" min="$4" max="$5" step="$6" max_px="$7" resolution="$8"
  local dims w h fmt_field

  # Binary output => HF Inference style: model in path, body {inputs, parameters}
  if [[ $IMAGE_OUTPUT == "binary" ]]; then
    if [[ $size_mode == "pixel" ]]; then
      dims=$(compute_dimensions "$min" "$max" "$step" "$max_px") || return 1
      w="${dims%x*}"; h="${dims#*x}"
      IMAGE_PAYLOAD=$(jq -cn --arg p "$prompt" --arg w "$w" --arg h "$h" \
        '{inputs:$p, parameters:{width:($w|tonumber), height:($h|tonumber)}}'
      )
    else
      IMAGE_PAYLOAD=$(jq -cn --arg p "$prompt" '{inputs:$p}')
    fi
    IMAGE_URL="${IMAGE_ENDPOINT}/${model}"
    return 0
  fi

  # Chat mode => chat/completions + modalities (OpenAI-compatible image output).
  # The image(s) come back in choices[0].message.images[] as data-URIs.
  # NOTE: aspect ratio / sizing are NOT controllable on this path — the model
  # decides the output resolution server-side (Gemini image models).
  if [[ $IMAGE_MODE == "chat" ]]; then
    IMAGE_PAYLOAD=$(jq -cn \
      --arg m "$model" \
      --arg p "$prompt" \
      '{model:$m, messages:[{role:"user", content:$p}], modalities:["text","image"], stream:false}'
    )

    # Vercel AI Gateway: ZDR/DPT provider options (mirror of core.sh api_call vercel* branch)
    if [[ $IMAGE_PROVIDER == vercel* ]]; then
      [[ ${ZDR_ENFORCED:-} == true ]] && IMAGE_PAYLOAD=$(jq -rc '.providerOptions.gateway.zeroDataRetention = true' <<< "$IMAGE_PAYLOAD" 2>/dev/null)
      IMAGE_PAYLOAD=$(jq -rc '.providerOptions.gateway.disallowPromptTraining = true' <<< "$IMAGE_PAYLOAD" 2>/dev/null)
    fi

    IMAGE_URL=$(jq -r --arg p "$IMAGE_PROVIDER" '.[$p].url' "$PROVIDERS_CONFIG" 2>/dev/null)
    return 0
  fi

  # Native OpenAI-compatible image endpoint
  case "$size_mode" in
    size_string)
      dims=$(compute_dimensions "$min" "$max" "$step" "$max_px") || return 1
      IMAGE_PAYLOAD=$(jq -cn \
        --arg m "$model" \
        --arg p "$prompt" \
        --arg s "$dims" \
        '{model:$m, prompt:$p, size:$s}'
      )
    ;;
    pixel)
      dims=$(compute_dimensions "$min" "$max" "$step" "$max_px") || return 1
      w="${dims%x*}"; h="${dims#*x}"
      IMAGE_PAYLOAD=$(jq -cn \
        --arg m "$model" \
        --arg p "$prompt" \
        --arg w "$w" \
        --arg h "$h" \
        '{model:$m, prompt:$p, width:($w|tonumber), height:($h|tonumber)}'
      )
    ;;
    aspect_ratio)
      IMAGE_PAYLOAD=$(jq -cn \
        --arg m "$model" \
        --arg p "$prompt" \
        --arg a "${image_ratio:-$DEFAULT_RATIO}" \
        --arg r "${resolution:-$DEFAULT_RESOLUTION}" \
        '{model:$m, prompt:$p, aspect_ratio:$a, resolution:$r}'
      )
    ;;
    *)
      log_error "Unsupported size_mode: $size_mode"
      return 1
    ;;
  esac

  # Venice native: hide the watermark (OPSEC — default shows "Venice" bottom-left).
  # Applies to all native sizing modes (size_string/pixel/aspect_ratio).
  if [[ $IMAGE_PROVIDER == venice* ]]; then
    IMAGE_PAYLOAD=$(jq -c '.hide_watermark = true' <<< "$IMAGE_PAYLOAD")
  fi

  # Output format selection (see DEFAULT_FORMAT). The request field name differs
  # per provider: `format` (Venice) vs `output_format` (OpenAI / OpenRouter).
  # DEFAULT_FORMAT is only sent when the provider supports a choice — otherwise
  # the field is omitted (server decides). A warning is raised only when an
  # explicit --format was requested for a provider that cannot honor it.
  case "$IMAGE_PROVIDER" in
    venice)             fmt_field="format" ;;
    openai|openrouter*) fmt_field="output_format" ;;
  esac

  if [[ -n $fmt_field ]]; then
    IMAGE_PAYLOAD=$(jq -c --arg k "$fmt_field" --arg f "${image_format:-$DEFAULT_FORMAT}" '.[$k] = $f' <<< "$IMAGE_PAYLOAD")
  elif [[ -n $image_format ]]; then
    log_warn "Provider '$IMAGE_PROVIDER' cannot select output format — ignoring '--format $image_format'."
  fi

  IMAGE_URL="$IMAGE_ENDPOINT"
}

# -----------------------------------------------------------------------------
# save_image_response <raw_res> <out_file>
#   Decode/parse the response according to IMAGE_OUTPUT (url | base64).
# -----------------------------------------------------------------------------
save_image_response() {
  local img_url b64
  local raw_res="$1" out_file="$2"
  local curl_opts=("-sSL")

  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  case "$IMAGE_OUTPUT" in
    url)
      img_url=$(jq -r '.data[0].url // .message.images[0].url // empty' <<< "$raw_res" 2>/dev/null)
      if [[ -z $img_url || $img_url == "null" ]]; then
        log_error "No image URL found in response."
        return 1
      fi
      curl "${curl_opts[@]}" "$img_url" -o "$out_file"
    ;;
    base64)
      b64=$(jq -r '.data[0].b64_json // .images[0] // .choices[0].message.images[0].image_url.url // .message.images[0].b64_json // empty' <<< "$raw_res" 2>/dev/null)
      if [[ -z $b64 || $b64 == "null" ]]; then
        log_error "No base64 image found in response."
        return 1
      fi
      # Chat mode returns data-URIs ("data:image/png;base64,...") — strip the prefix.
      case "$b64" in
        data:*) b64="${b64#*;base64,}" ;;
      esac
      printf '%s' "$b64" | b64d > "$out_file" 2>/dev/null
    ;;
    *)
      log_error "Unsupported image output mode: $IMAGE_OUTPUT"
      return 1
    ;;
  esac

  clean_image_metadata "$out_file"
}

# -----------------------------------------------------------------------------
# run_image_request <payload> <url> <out_file>
#   Perform the actual HTTP request. Binary output is written directly to disk.
# -----------------------------------------------------------------------------
run_image_request() {
  local payload="$1" url="$2" out_file="$3"
  local curl_opts=("-sSL")
  local auth_args=()
  local raw_res tmp_file api_err

  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  [[ -n $IMAGE_API_KEY ]] && auth_args+=("-H" "Authorization: Bearer ${IMAGE_API_KEY}")

  # Vercel AI Gateway attribution headers (mirror of core.sh api_call vercel* branch)
  [[ $IMAGE_PROVIDER == vercel* ]] && auth_args+=("-H" "http-referer: ${ATTRIBUTION_REFERER:-}" "-H" "x-title: ${ATTRIBUTION_TITLE:-}")

  if [[ $IMAGE_OUTPUT == "binary" ]]; then
    # Write to a temp file first, then decide: JSON = provider error (surface it),
    # otherwise = actual image (rename into place). Prevents a JSON error body
    # (deprecated model, depleted credits, ...) from being saved as a broken .png.
    tmp_file=$(mktemp "$(dirname "$out_file")/.img.XXXXXX") || { log_error "Failed to create temp file."; return 1; }

    if ! curl "${curl_opts[@]}" "$url" -H "Content-Type: application/json" "${auth_args[@]}" -A "${USER_AGENT:-Mozilla/5.0}" -d @- -o "$tmp_file" <<< "$payload"; then
      rm -f "$tmp_file"
      log_error "Image request failed (network error)."
      return 1
    fi

    # Detect a JSON response (provider error) vs a real image binary.
    if jq -e . "$tmp_file" >/dev/null 2>&1; then
      api_err=$(jq -r '(.error | if type == "object" then .message else . end) // empty' "$tmp_file" 2>/dev/null)
      if [[ -n $api_err && $api_err != "null" ]]; then
        log_error "Image API error: $api_err"
      else
        log_error "Image API returned JSON instead of an image: $(tr '\n' ' ' < "$tmp_file")"
      fi
      rm -f "$tmp_file"
      return 1
    fi

    # Rename temp file to final name and clean EXIF data
    mv "$tmp_file" "$out_file" && \
    clean_image_metadata "$out_file"

  else
    raw_res=$(curl "${curl_opts[@]}" "$url" -H "Content-Type: application/json" "${auth_args[@]}" -A "${USER_AGENT:-Mozilla/5.0}" -d @- <<< "$payload")

    # Surface the provider's own API error (e.g. insufficient credits) instead of a generic parse failure
    api_err=$(jq -r '(.error | if type == "object" then .message else . end) // empty' <<< "$raw_res" 2>/dev/null)
    if [[ -n $api_err ]]; then
      log_error "Image API error: $api_err"
      return 1
    fi

    save_image_response "$raw_res" "$out_file"
  fi
}

# -----------------------------------------------------------------------------
# clean_image_metadata <file>
#   Privacy pass: strip provider metadata (EXIF) from a generated image.
#   Controlled by $STRIP_METADATA (default: true). Uses exiftool when available
#   (in-place strip, no re-encode), else falls back to a stream-copy re-mux
#   with ffmpeg (-map_metadata -1, pixels untouched). Warns when neither tool
#   is installed. Binary detection: probe both BIN_EXF and BIN_FFM.
#   Never fails the generation: always returns 0.
# -----------------------------------------------------------------------------
clean_image_metadata() {
  local img_file="$1" bin_exif bin_ffm

  # Normalize the extension to match the REAL file type before anything else.
  img_file=$(get_file_type "$img_file")

  if [[ $STRIP_METADATA == true && -r $img_file ]]; then
    bin_exif=$(command -v exiftool 2>/dev/null)
    bin_ffm=$(command -v ffmpeg 2>/dev/null)

    if [[ -n $bin_exif ]]; then
      # -all= strips every metadata block; -overwrite_original skips the backup copy
      "$bin_exif" -overwrite_original -all= "$img_file" >/dev/null 2>&1 \
        || log_warn "Privacy: exiftool failed — '$img_file' may still carry provider metadata."
    elif [[ -n $bin_ffm ]]; then
      # NOTE: stream-copy strips container metadata (mp4/mkv/png chunks) but NOT
      # JPEG APP1 EXIF segments — they live inside the copied bitstream.
      local tmp_file="${img_file%.*}.clean.${img_file##*.}"
      if "$bin_ffm" -hide_banner -loglevel error -y -i "$img_file" -map_metadata -1 -c copy "$tmp_file" && ! grep -aq 'Exif' "$tmp_file"; then
        mv -f "$tmp_file" "$img_file"
      else
        rm -f "$tmp_file"
        log_warn "Privacy: ffmpeg cannot strip EXIF from this format — '$img_file' keeps provider metadata. Install exiftool to handle it."
      fi
    else
      log_warn "Privacy: neither exiftool nor ffmpeg installed — '$img_file' keeps provider metadata (model name)."
    fi
  fi

  [[ -f $img_file ]] && log_image "Image created in '$img_file'."
  return 0
}

# -----------------------------------------------------------------------------
# generate_pollinations
#   Keyless fallback: GET image.pollinations.ai with width/height params.
# -----------------------------------------------------------------------------
generate_pollinations() {
  local encoded w h dims out_file
  local curl_opts=("-sSL")

  [[ $USE_TOR == true ]] && curl_opts+=("-x" "$TOR_PROXY")

  encoded=$(sed -e 's/ /%20/g' <<< "$image_prompt")
  w="$DEFAULT_WIDTH"; h="$DEFAULT_HEIGHT"

  if [[ -n $image_size ]]; then
    w="${image_size%x*}"; h="${image_size#*x}"
  elif [[ -n $image_ratio && $image_ratio != "1:1" ]]; then
    dims=$(get_perfect_size "$image_ratio" 512 2880 32 4194304)
    w="${dims%x*}"; h="${dims#*x}"
  fi

  out_file=$(get_output_name)

  log_brain "Generating image from prompt in fixed [768x768]..."
  log_debug "Using prompt: $image_prompt"
  log_debug "Using provider: pollinations.ai (fallback)"
  log   # Cosmetic empty line
  curl "${curl_opts[@]}" "https://image.pollinations.ai/prompt/${encoded}?width=${w}&height=${h}&nologo=true" -o "$out_file" && \
  clean_image_metadata "$out_file"
}

# -----------------------------------------------------------------------------
# generate_image <prompt> [--ratio 16:9] [--size WxH] [--model X] [--provider Y] [--resolution 1K|2K|4K] [--format png|jpeg|webp]
# -----------------------------------------------------------------------------
generate_image() {
  # --- Parse arguments ---
  local image_prompt image_ratio image_size image_model image_provider image_resolution image_format

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prompt)     image_prompt="$2"; shift 2 ;;
      --ratio)      image_ratio="$2"; shift 2 ;;
      --size)       image_size="$2"; shift 2 ;;
      --provider)   image_provider="$2"; shift 2 ;;
      --model)      image_model="$2"; shift 2 ;;
      --resolution) image_resolution="$2"; shift 2 ;;
      --format)     image_format="$2"; shift 2 ;;
      *)            image_prompt="$1"; shift ;;
    esac
  done

  [[ -z $image_prompt ]] && image_prompt="Be creative and generate whatever comes to your mind."

  # --- Resolve provider + config ---
  [[ -n $image_provider ]] && IMAGE_PROVIDER="$image_provider"
  load_image_config

  # --- Keyless fallback when the provider has no image capability ---
  if [[ $IMAGE_FALLBACK == true ]]; then
    log_warn "Provider '$IMAGE_PROVIDER' does not support image generation — falling back to pollinations.ai."
    generate_pollinations
    return $?
  fi

  # --- Resolve model + sizing ---
  local model size_mode min max step max_px model_resolution resolution
  model=$(get_image_model "$image_model")
  # NUL-delimited split — matched to get_model_sizing()'s `jq -j` output above.
  {
    IFS= read -r -d '' size_mode
    IFS= read -r -d '' min
    IFS= read -r -d '' max
    IFS= read -r -d '' step
    IFS= read -r -d '' max_px
    IFS= read -r -d '' model_resolution
  } < <(get_model_sizing "$model")
  # Explicit --resolution overrides the model's configured default
  resolution="${image_resolution:-$model_resolution}"

  # --- Build request ---
  local payload url out_file
  build_image_request "$model" "$image_prompt" "$size_mode" "$min" "$max" "$step" "$max_px" "$resolution" || return 1
  payload="$IMAGE_PAYLOAD"; url="$IMAGE_URL"

  # --- Output path ---
  out_file=$(get_output_name)

  log_brain "Generating image from prompt in [${image_ratio:-$DEFAULT_RATIO}]..."
  log_debug "Using prompt: $image_prompt"
  log_debug "Using provider: $IMAGE_PROVIDER (model: $model, mode: $IMAGE_MODE, output: $IMAGE_OUTPUT)"

  # --- Execute ---
  run_image_request "$payload" "$url" "$out_file"
}


# -----------------------------------------------------------------------------
# Hybrid entry point — sourced (library) or executed (standalone CLI)
#
#   ./image.sh "prompt" [--ratio 16:9] [--size WxH] [--model X] [--provider Y]
#
# Sourced (cli.sh composition root / tools.sh wrapper): functions only, zero
# side effects. Executed: minimal bootstrap — source core.sh for shared helpers
# (logging, keyring, paths), then generate_image with CLI flags. Provider
# resolution falls back to config/state.json (see load_image_config).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  IMG_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -r "${IMG_PROJECT_ROOT}/core.sh" ]]; then
    # shellcheck source=/dev/null
    source "${IMG_PROJECT_ROOT}/core.sh"
  else
    echo "Error: core.sh library not found at: ${IMG_PROJECT_ROOT}/core.sh" >&2
    exit 1
  fi
  generate_image "$@"
fi

