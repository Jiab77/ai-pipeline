#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# engines/image.v2.sh — Image generation and editing engine (registry v2)
# ==============================================================================
# Generates or edits an image through the protocol adapters described by
# config/providers.v2.json. Sourced library or standalone CLI (Bash 3.2+).
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.2.2
#
# Contract:
#   generate_image — text -> image
#   modify_image   — image (+ optional mask) -> image
#
# Dependencies: core.sh (provider keys and catalogue), lib/helpers.sh,
#               jq, curl, file, base64, ffprobe, ffmpeg; exiftool only when
#               metadata stripping is enabled.
#
# Protocol notes:
#   - The registry carries the endpoint and the wire protocol. It carries
#     static model ids only for the four opaque catalogues (openai,
#     mammouth, zai, cyberneurova); every other provider is discovered at
#     call time, because a maintained model list rots.
#   - One logical operation may have several wire paths, and the choice is
#     made per model, never per provider:
#       OpenAI T2I  : Images API for an image model, Responses
#                     `image_generation` for any other model.
#       Vercel T2I  : Chat Completions for a multimodal language model,
#                     Images API for an image-only model.
#   - No paid retry, no silent provider substitution, no invented endpoint.
#     A request is only sent after the destination matched the provider's
#     documented API prefix.
# ==============================================================================

# core.sh loads lib/helpers.sh through LIB_DEPS. A harness that sources only
# this engine (and any caller that sourced core first but not the libs) still
# gets the shared plumbing: load it once, lazily, when it is missing.
if ! declare -F engine_v2_http >/dev/null; then
  IMG_V2_HELPERS="${BASH_SOURCE[0]%/*}/../lib/helpers.sh"
  # shellcheck source=/dev/null
  [[ ! -r $IMG_V2_HELPERS ]] || source "$IMG_V2_HELPERS"
fi

# Transport tunables are read by lib/helpers.sh (engine_v2_http); the engine
# Transport tunables are read by lib/helpers.sh (engine_v2_http); the engine
# only has to state them for its own calls.
ENGINE_V2_CONNECT_TIMEOUT=10
ENGINE_V2_TIMEOUT=180

img_v2_error() { printf 'Image: %s\n' "$*" >&2; }
img_v2_warn() {
  if declare -F log_warn >/dev/null; then log_warn "$*"; else img_v2_error "$*"; fi
}

img_v2_help() {
  cat <<'EOF'
Usage: image.v2.sh [edit] [--prompt TEXT] [options]
  --provider NAME --model ID
  --size WxH           Exact dimensions (takes priority over --ratio)
  --ratio W:H          Aspect ratio where the adapter accepts one
  --format png|jpeg|webp
  --image FILE         Required for edit; PNG, JPEG or WebP
  --mask FILE          PNG with alpha, same dimensions; OpenAI-compatible only
  --help               Show this help

Generation without a prompt uses a short default line. Editing always needs a
prompt. Unsupported parameters fail before anything is submitted: no silent
resize, no automatic retry, no provider substitution.
EOF
}

img_v2_deps() {
  local dependency
  for dependency in jq curl file base64 ffprobe ffmpeg; do
    command -v "$dependency" >/dev/null 2>&1 || { img_v2_error "Missing dependency: $dependency."; return 1; }
  done
}

# img_v2_operation <generate|edit> — the catalogue operation name (t2i/i2i).
# img_v2_operation <generate|edit> — the catalogue operation name (t2i/i2i).
img_v2_operation() {
  case "$1" in
    generate) IMG_V2_OPERATION=t2i ;;
    edit)     IMG_V2_OPERATION=i2i ;;
    *) return 1 ;;
  esac
}

# Filtering is shared doctrine (lib/helpers.sh). It is applied only where the
# catalogue carries the modality AND the filter keeps the discriminator the
# adapter needs. Vercel T2I is the counter-example: its filter keeps image
# output, which drops the `type=language` model that selects Chat Completions,
# so that provider is queried unfiltered.
img_v2_catalogue() {
  local provider="$1"
  local operation="$2"
  local raw

  raw=$(get_provider_models "$provider" "$operation") || {
    img_v2_error "Catalogue lookup failed for '$provider'; availability is unknown."
    return 1
  }
  [[ -n $raw && $raw != null ]] || { img_v2_error "Empty catalogue for '$provider'."; return 1; }

  if [[ $provider == venice || $provider == openrouter* ]] && declare -F filter_provider_models >/dev/null; then
    raw=$(filter_provider_models "$provider" "$operation" <<< "$raw") || return 1
  fi

  IMG_V2_CATALOGUE="$raw"
}

# img_v2_catalogue_model <model> — writes the catalogue record of <model>.
img_v2_catalogue_model() {
  local model="$1"

  jq -e --arg m "$model" '
    if type == "array" then .[] else (.data // [])[] end
    | select(.id == $m)
  ' <<< "$IMG_V2_CATALOGUE"
}

img_v2_allowlist() {
  case "$1" in
    openai)                       printf '%s' 'https://api.openai.com/v1/' ;;
    openrouter|openrouter_free)   printf '%s' 'https://openrouter.ai/api/v1/' ;;
    venice)                       printf '%s' 'https://api.venice.ai/api/v1/' ;;
    zai)                          printf '%s' 'https://api.z.ai/api/paas/v4/' ;;
    cyberneurova)                 printf '%s' 'https://api.cyberneurova.ai/v1/' ;;
    mammouth)                     printf '%s' 'https://api.mammouth.ai/v1/' ;;
    vercel|vercel_free)           printf '%s' 'https://ai-gateway.vercel.sh/v1/' ;;
    huggingface)                  printf '%s' 'https://router.huggingface.co/' ;;
    *) return 1 ;;
  esac
}

# img_v2_endpoint <documented default> — the registry endpoint when it is
# declared, the documented default otherwise. A declared endpoint that leaves
# the provider's API prefix is refused, never silently overridden.
img_v2_endpoint() {
  local documented="$1"
  local configured="$IMG_V2_CONFIGURED"
  local endpoint="${configured:-$documented}"

  [[ -n $endpoint ]] || { img_v2_error "No endpoint for '$IMG_V2_PROVIDER'."; return 1; }
  [[ $endpoint == https://* ]] || { img_v2_error 'Image endpoints must be HTTPS.'; return 1; }
  [[ $endpoint == "$IMG_V2_ALLOW"* ]] || {
    img_v2_error "Registry endpoint leaves the documented '$IMG_V2_PROVIDER' API prefix; refusing to send credentials."
    return 1
  }
  IMG_V2_ENDPOINT="$endpoint"
}

img_v2_resolve() {
  local provider="$IMG_V2_PROVIDER"
  local operation="$IMG_V2_OP"
  local capability block model record kind base

  case "$operation" in
    generate) capability=image; block=image.t2i ;;
    edit)     capability=edit;  block=image.i2i ;;
    *) img_v2_error "Unknown image operation '$operation'."; return 1 ;;
  esac

  engine_v2_capable "$provider" "$capability" || {
    img_v2_error "Provider '$provider' does not offer $capability for images."
    return 1
  }

  IMG_V2_ALLOW=$(img_v2_allowlist "$provider") || {
    img_v2_error "No documented image adapter for '$provider'."
    return 1
  }
  IMG_V2_CONFIGURED=$(engine_v2_block_field "$provider" "$block" endpoint)
  IMG_V2_PROTOCOL=$(engine_v2_block_field "$provider" "$block" protocol)
  IMG_V2_STATIC=$(engine_v2_block_models "$provider" "$block")
  IMG_V2_DEFAULT=$(engine_v2_block_field "$provider" "$block" default)
  model="$IMG_V2_MODEL"

  case "$provider:$operation" in
    # ── OpenAI: two documented T2I paths ────────────────────────────────
    openai:generate)
      if [[ -z $model ]]; then
        model="$IMG_V2_DEFAULT"
        IMG_V2_ADAPTER=openai_images
        img_v2_endpoint 'https://api.openai.com/v1/images/generations' || return 1
      elif [[ -n $IMG_V2_STATIC ]] && grep -qxF -- "$model" <<< "$IMG_V2_STATIC"; then
        IMG_V2_ADAPTER=openai_images
        img_v2_endpoint 'https://api.openai.com/v1/images/generations' || return 1
      else
        # Not an image model: the Responses API renders through its
        # image_generation tool. Documented path, not a fallback.
        IMG_V2_ADAPTER=openai_responses
        IMG_V2_CONFIGURED=''
        IMG_V2_ALLOW='https://api.openai.com/v1/'
        img_v2_endpoint "$(engine_v2_documentation openai url)" || return 1
      fi
    ;;
    openai:edit)
      model="${model:-$IMG_V2_DEFAULT}"
      IMG_V2_ADAPTER=openai_edits
      img_v2_endpoint 'https://api.openai.com/v1/images/edits' || return 1
    ;;

    # ── OpenRouter: one Images endpoint for both directions ─────────────
    openrouter*:generate|openrouter*:edit)
      img_v2_operation "$operation" || return 1
      img_v2_catalogue "$provider" "$IMG_V2_OPERATION" || return 1
      if [[ -z $model ]]; then
        model=$(jq -r '(if type == "array" then .[0].id else .data[0].id end) // empty' <<< "$IMG_V2_CATALOGUE") || return 1
        [[ -n $model ]] || { img_v2_error "No $operation model in the '$provider' catalogue."; return 1; }
      else
        img_v2_catalogue_model "$model" >/dev/null || {
          img_v2_error "Model '$model' is not part of the '$provider' $operation catalogue."
          return 1
        }
      fi
      IMG_V2_ADAPTER=openrouter
      img_v2_endpoint 'https://openrouter.ai/api/v1/images' || return 1
    ;;

    # ── Venice: catalogue carries models, ratios and prompt limits ───────
    venice:generate|venice:edit)
      img_v2_operation "$operation" || return 1
      img_v2_catalogue "$provider" "$IMG_V2_OPERATION" || return 1
      if [[ -z $model ]]; then
        model=$(jq -r '(if type == "array" then .[0].id else .data[0].id end) // empty' <<< "$IMG_V2_CATALOGUE") || return 1
        [[ -n $model ]] || { img_v2_error "No $operation model in the Venice catalogue."; return 1; }
      fi
      record=$(img_v2_catalogue_model "$model") || {
        img_v2_error "Model '$model' is not part of the Venice $operation catalogue."
        return 1
      }
      jq -e '.model_spec.offline != true' <<< "$record" >/dev/null || {
        img_v2_error "Venice model '$model' is offline."
        return 1
      }
      IMG_V2_CONSTRAINTS=$(jq -c '.model_spec.constraints // {}' <<< "$record") || return 1
      if [[ $operation == generate ]]; then
        IMG_V2_ADAPTER=venice
        img_v2_endpoint 'https://api.venice.ai/api/v1/image/generate' || return 1
      else
        IMG_V2_ADAPTER=venice_edit
        img_v2_endpoint 'https://api.venice.ai/api/v1/image/edit' || return 1
      fi
    ;;

    # ── Opaque catalogues: the registry is the only model source ────────
    zai:generate)
      model="${model:-$IMG_V2_DEFAULT}"
      IMG_V2_ADAPTER=zai
      img_v2_endpoint 'https://api.z.ai/api/paas/v4/images/generations' || return 1
    ;;
    cyberneurova:generate)
      model="${model:-$IMG_V2_DEFAULT}"
      IMG_V2_ADAPTER=cyberneurova
      img_v2_endpoint 'https://api.cyberneurova.ai/v1/images/generations' || return 1
    ;;
    mammouth:generate)
      model="${model:-$IMG_V2_DEFAULT}"
      [[ $IMG_V2_PROTOCOL == chat ]] || { img_v2_error "Mammouth image protocol must be 'chat'."; return 1; }
      IMG_V2_ADAPTER=mammouth_chat
      IMG_V2_CONFIGURED=''
      img_v2_endpoint "$(engine_v2_documentation mammouth url)" || return 1
    ;;

    # ── Vercel: Gateway path chosen per model metadata ───────────────────
    vercel*:generate)
      [[ -n $model ]] || {
        img_v2_error "The Gateway exposes several image paths; select a model with --model."
        return 1
      }
      img_v2_catalogue "$provider" all || return 1
      record=$(img_v2_catalogue_model "$model") || {
        img_v2_error "Model '$model' is absent from the '$provider' catalogue."
        return 1
      }
      kind=$(jq -r '.type // empty' <<< "$record")
      if [[ $kind == language ]]; then
        IMG_V2_ADAPTER=vercel_chat
        base=$(jq -r --arg p "$provider" '.[$p].url // empty' "$PROVIDERS_CONFIG")
        IMG_V2_CONFIGURED=''
        img_v2_endpoint "$base" || return 1
      else
        [[ $kind == image ]] || {
          img_v2_error "Model '$model' is not an image-producing Gateway model."
          return 1
        }
        IMG_V2_ADAPTER=vercel_images
        IMG_V2_CONFIGURED=''
        base=$(jq -r --arg p "$provider" '.[$p].url // empty' "$PROVIDERS_CONFIG")
        base="${base%/chat/completions}/images/generations"
        img_v2_endpoint "$base" || return 1
      fi
    ;;
    vercel*:edit)
      [[ -n $model ]] || {
        img_v2_error "The Gateway edit path is model-specific; select a model with --model."
        return 1
      }
      img_v2_catalogue "$provider" all || return 1
      img_v2_catalogue_model "$model" >/dev/null || {
        img_v2_error "Model '$model' is absent from the '$provider' catalogue."
        return 1
      }
      IMG_V2_ADAPTER=vercel_edits
      img_v2_endpoint 'https://ai-gateway.vercel.sh/v1/images/edits' || return 1
    ;;

    # ── Hugging Face: raw bytes from the hf-inference router ────────────
    huggingface:generate)
      if [[ -z $model ]]; then
        model=$(engine_v2_inference_model "$provider" inference 'text-to-image') || {
          img_v2_error "Unable to read the '$provider' inference catalogue; pass --model."
          return 1
        }
        [[ -n $model ]] || {
          img_v2_error "The '$provider' inference catalogue lists no text-to-image model; pass --model."
          return 1
        }
      fi
      [[ $model =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
        img_v2_error "Invalid Hugging Face model id."
        return 1
      }
      IMG_V2_ADAPTER=huggingface
      IMG_V2_CONFIGURED=$(engine_v2_block_field "$provider" "$block" endpoint)
      IMG_V2_CONFIGURED="${IMG_V2_CONFIGURED%/}/$model"
      img_v2_endpoint "https://router.huggingface.co/hf-inference/models/$model" || return 1
    ;;

    *)
      img_v2_error "No documented '$operation' adapter for provider '$provider'."
      return 1
    ;;
  esac

  [[ -n $model ]] || { img_v2_error "No model resolved for '$provider $operation'."; return 1; }
  IMG_V2_MODEL="$model"

  has_provider_key "$provider" || { img_v2_error "Missing provider key for '$provider'."; return 1; }
  IMG_V2_KEY=$(decrypt_provider_key "$provider") || return 1
  [[ -n $IMG_V2_KEY ]] || { img_v2_error 'Empty provider key.'; return 1; }
}

# ── Input side ───────────────────────────────────────────────────────────────

img_v2_probe() {
  local file="$1"

  [[ -f $file && -r $file && ! -L $file ]] || return 1
  case "$(file -b --mime-type "$file")" in
    image/png|image/jpeg|image/webp) ;;
    *) return 1 ;;
  esac
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json "$file" 2>/dev/null \
    | jq -e '.streams[0] | select(.width > 0 and .height > 0)'
}

# A recognizable header is not enough: the decoder must accept the file.
img_v2_decodable() { ffmpeg -nostdin -v error -xerror -i "$1" -frames:v 1 -f null - >/dev/null 2>&1; }

img_v2_prepare_input() {
  local file="$1"
  local info="$IMG_V2_WORK/input-info"
  local mime
  local limit=52428800

  img_v2_probe "$file" > "$info" || { img_v2_error 'Input is not a readable raster image.'; return 1; }
  img_v2_decodable "$file" || { img_v2_error 'Input image cannot be decoded.'; return 1; }
  [[ $(wc -c < "$file") -lt $limit ]] || { img_v2_error 'Input exceeds the adapter upload limit.'; return 1; }

  IMG_V2_INPUT_W=$(jq -r '.streams[0].width' "$info")
  IMG_V2_INPUT_H=$(jq -r '.streams[0].height' "$info")
  mime=$(file -b --mime-type "$file")
  cp -- "$file" "$IMG_V2_WORK/input" || return 1
  printf 'data:%s;base64,' "$mime" > "$IMG_V2_WORK/reference" || return 1
  b64e < "$IMG_V2_WORK/input" >> "$IMG_V2_WORK/reference" || return 1
}

img_v2_prepare_mask() {
  local mask="$1"

  [[ -n $mask ]] || return 0
  if [[ $IMG_V2_ADAPTER != openai_edits ]]; then
    img_v2_error 'Mask inpainting is only documented for the OpenAI Images Edits path; refusing a whole-image edit.'
    return 1
  fi
  [[ $(file -b --mime-type "$mask") == image/png ]] || { img_v2_error 'Mask must be PNG.'; return 1; }

  local info="$IMG_V2_WORK/mask-info"
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height,pix_fmt -of json "$mask" > "$info" 2>/dev/null || {
    img_v2_error 'Mask is not a readable PNG.'
    return 1
  }
  jq -e --argjson w "$IMG_V2_INPUT_W" --argjson h "$IMG_V2_INPUT_H" '
    .streams[0] | .width == $w and .height == $h
    and (.pix_fmt | test("rgba|bgra|argb|abgr|yuva|gbrap|ya"))
  ' "$info" >/dev/null || {
    img_v2_error 'Mask dimensions or alpha channel do not match the input.'
    return 1
  }
  img_v2_decodable "$mask" || { img_v2_error 'Mask cannot be decoded.'; return 1; }
  cp -- "$mask" "$IMG_V2_WORK/mask" || return 1
}

# ── Options ──────────────────────────────────────────────────────────────────

img_v2_options() {
  local width height

  if [[ -n $IMG_V2_SIZE ]]; then
    [[ $IMG_V2_SIZE =~ ^([1-9][0-9]{0,4})x([1-9][0-9]{0,4})$ ]] || {
      img_v2_error 'Invalid size; expected WxH.'
      return 1
    }
    width="${BASH_REMATCH[1]}"
    height="${BASH_REMATCH[2]}"
    # Native image APIs take multiples of 16 inside a bounded range; a
    # dimension outside them is a request the provider would reject.
    (( width % 16 == 0 && height % 16 == 0 && width >= 16 && height >= 16
       && width <= 4096 && height <= 4096 )) || {
      img_v2_error "Size '${IMG_V2_SIZE}' violates the documented dimension grid (multiples of 16, 16-4096)."
      return 1
    }
  fi

  [[ -z $IMG_V2_RATIO || $IMG_V2_RATIO =~ ^[1-9][0-9]{0,3}:[1-9][0-9]{0,3}$ ]] || {
    img_v2_error 'Invalid ratio; expected W:H.'
    return 1
  }
  case "$IMG_V2_FORMAT" in
    ''|png|jpeg|webp) ;;
    *) img_v2_error 'Invalid format; expected png, jpeg or webp.'; return 1 ;;
  esac

  # Reject a parameter the adapter does not document instead of dropping it.
  case "$IMG_V2_ADAPTER" in
    openai_images|zai|cyberneurova|vercel_images) [[ -z $IMG_V2_RATIO ]] || {
      img_v2_error "This adapter takes --size, not --ratio."
      return 1
    } ;;
    openai_edits|vercel_edits) [[ -z $IMG_V2_RATIO ]] || {
      img_v2_error "Multipart edits take --size, not --ratio."
      return 1
    } ;;
    venice|venice_edit)
      [[ -z $IMG_V2_SIZE ]] || { img_v2_error 'Venice accepts --ratio, not exact pixel dimensions.'; return 1; }
    ;;
    openrouter)
      [[ -z $IMG_V2_SIZE ]] || { img_v2_error 'OpenRouter takes --ratio/--format, not exact dimensions.'; return 1; }
    ;;
    vercel_chat|mammouth_chat|huggingface)
      [[ -z $IMG_V2_SIZE && -z $IMG_V2_RATIO && -z $IMG_V2_FORMAT ]] || {
        img_v2_error "Sizing and format are not exposed by this adapter; the provider applies its defaults."
        return 1
      }
    ;;
  esac

  # Square default for avatar intent.
  # Applied AFTER adapter validation: 1:1 is injected only on adapters that
  # document --ratio; every other adapter keeps the provider default instead of
  # crashing on a sizing parameter it does not expose.
  if [[ ${IMG_V2_SQUARE_DEFAULT:-} == 1 && -z $IMG_V2_RATIO && -z $IMG_V2_SIZE ]]; then
    case $IMG_V2_ADAPTER in
      venice|openrouter) IMG_V2_RATIO='1:1' ;;
      # openai/zai/vercel_images (→ --size only) et vercel_chat/mammouth_chat/
      # huggingface (→ aucun sizing) : défaut provider, jamais de crash.
    esac
  fi


  # An edit reuses the source dimensions only when they fit the documented
  # grid; otherwise the provider default is left in charge instead of forcing
  # a size the API would reject.
  if [[ $IMG_V2_ADAPTER == openai_edits || $IMG_V2_ADAPTER == vercel_edits ]] \
     && [[ -z $IMG_V2_SIZE && -z $IMG_V2_RATIO ]] \
     && [[ $IMG_V2_INPUT_W =~ ^[1-9][0-9]*$ && $IMG_V2_INPUT_H =~ ^[1-9][0-9]*$ ]] \
     && (( IMG_V2_INPUT_W % 16 == 0 && IMG_V2_INPUT_H % 16 == 0 )); then
    IMG_V2_SIZE="${IMG_V2_INPUT_W}x${IMG_V2_INPUT_H}"
  fi
}
# Venice publishes its ratios and prompt ceiling in the model constraints.
img_v2_venice_options() {
  local constraints="$IMG_V2_CONSTRAINTS"

  [[ -n $constraints ]] || return 0
  if jq -e '(.aspectRatios // []) | length > 0' <<< "$constraints" >/dev/null 2>&1; then
    if [[ -n $IMG_V2_RATIO ]]; then
      jq -e --arg r "$IMG_V2_RATIO" '(.aspectRatios // []) | index($r) != null' <<< "$constraints" >/dev/null || {
        img_v2_error "Venice model does not accept the ratio '$IMG_V2_RATIO'."
        return 1
      }
    else
      IMG_V2_RATIO=$(jq -r '(.aspectRatios // []) | (index("16:9") // 0) as $i | .[$i]' <<< "$constraints") || return 1
    fi
  fi

  jq -e --argjson n "${#IMG_V2_PROMPT}" '
    (.promptCharacterLimit // 1500) >= $n
  ' <<< "$constraints" >/dev/null || {
    img_v2_error 'Prompt exceeds the model character limit.'
    return 1
  }
}

# ── Request ──────────────────────────────────────────────────────────────────

img_v2_build_request() {
  local prompt_file="$IMG_V2_WORK/prompt"
  local request="$IMG_V2_WORK/request.json"
  local model="$IMG_V2_MODEL"

  # An empty reference means text-to-image; jq --rawfile still needs the file.
  [[ -f $IMG_V2_WORK/reference ]] || : > "$IMG_V2_WORK/reference"

  case "$IMG_V2_ADAPTER" in
    openai_images)
      jq -n --arg m "$model" --rawfile p "$prompt_file" --arg s "$IMG_V2_SIZE" --arg f "$IMG_V2_FORMAT" '
        {model:$m, prompt:$p}
        + (if $s != "" then {size:$s} else {} end)
        + (if $f != "" then {output_format:$f} else {} end)
      ' > "$request" || return 1
    ;;
    openai_responses)
      jq -n --arg m "$model" --rawfile p "$prompt_file" '
        {model:$m,
         input:[{role:"user", content:[{type:"input_text", text:$p}]}],
         tools:[{type:"image_generation"}]}
      ' > "$request" || return 1
    ;;
    vercel_chat)
      jq -n --arg m "$model" --rawfile p "$prompt_file" '
        {model:$m,
         messages:[{role:"user", content:$p}],
         modalities:["text","image"],
         stream:false}
      ' > "$request" || return 1
    ;;
    vercel_images)
      jq -n --arg m "$model" --rawfile p "$prompt_file" --arg s "$IMG_V2_SIZE" --arg f "$IMG_V2_FORMAT" '
        {model:$m, prompt:$p}
        + (if $s != "" then {size:$s} else {} end)
        + (if $f != "" then {output_format:$f} else {} end)
      ' > "$request" || return 1
    ;;
    mammouth_chat)
      jq -n --arg m "$model" --rawfile p "$prompt_file" '
        {model:$m,
         messages:[{role:"user", content:$p}],
         modalities:["text","image"],
         stream:false}
      ' > "$request" || return 1
    ;;
    openrouter)
      jq -n --arg m "$model" --rawfile p "$prompt_file" --rawfile i "$IMG_V2_WORK/reference" '
        {model:$m, prompt:$p}
        + (if $i != "" then {input_references:[{type:"image_url", image_url:{url:$i}}]} else {} end)
      ' > "$request" || return 1
    ;;
    venice)
      jq -n --arg m "$model" --rawfile p "$prompt_file" --arg r "$IMG_V2_RATIO" --arg f "$IMG_V2_FORMAT" '
        {model:$m, prompt:$p, hide_watermark:true}
        + (if $r != "" then {aspect_ratio:$r} else {} end)
        + (if $f != "" then {format:$f} else {} end)
      ' > "$request" || return 1
    ;;
    venice_edit)
      jq -n --arg m "$model" --rawfile p "$prompt_file" --rawfile i "$IMG_V2_WORK/reference" --arg r "$IMG_V2_RATIO" '
        {model:$m, prompt:$p, image:($i | sub("^data:[^;]+;base64,"; ""))}
        + (if $r != "" then {aspect_ratio:$r} else {} end)
      ' > "$request" || return 1
    ;;
    zai|cyberneurova)
      jq -n --arg m "$model" --rawfile p "$prompt_file" --arg s "$IMG_V2_SIZE" '
        {model:$m, prompt:$p}
        + (if $s != "" then {size:$s} else {} end)
      ' > "$request" || return 1
    ;;
    huggingface)
      jq -n --rawfile p "$prompt_file" '{inputs:$p}' > "$request" || return 1
    ;;
    openai_edits|vercel_edits)
      # Multipart: the form fields are the request body, there is no JSON.
      return 0
    ;;
    *) img_v2_error "No request builder for adapter '$IMG_V2_ADAPTER'."; return 1 ;;
  esac
}

img_v2_send() {
  local response="$IMG_V2_WORK/response"

  case "$IMG_V2_ADAPTER" in
    openai_edits|vercel_edits)
      local field='image'
      local -a form ; form=()
      [[ $IMG_V2_ADAPTER == openai_edits ]] && field='image[]'
      form=(
        -F "prompt=<$IMG_V2_WORK/prompt"
        --form-string "model=$IMG_V2_MODEL"
        -F "$field=@$IMG_V2_WORK/input;type=$IMG_V2_MIME;filename=input"
      )
      if [[ -f $IMG_V2_WORK/mask ]]; then
        form+=(-F "mask=@$IMG_V2_WORK/mask;type=image/png;filename=mask.png")
      fi
      [[ -z $IMG_V2_SIZE ]] || form+=(--form-string "size=$IMG_V2_SIZE")
      [[ -z $IMG_V2_FORMAT ]] || form+=(--form-string "output_format=$IMG_V2_FORMAT")
      engine_v2_http "$IMG_V2_ENDPOINT" "$response" true "$IMG_V2_KEY" "${form[@]}" || {
        img_v2_error "Submission failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
        return 1
      }
    ;;
    *)
      engine_v2_http "$IMG_V2_ENDPOINT" "$response" true "$IMG_V2_KEY" \
        -H 'Content-Type: application/json' --data-binary "@$IMG_V2_WORK/request.json" || {
        img_v2_error "Submission failed (HTTP ${ENGINE_V2_HTTP_CODE:-none}); no retry, no substitution."
        return 1
      }
    ;;
  esac
}

# ── Response ─────────────────────────────────────────────────────────────────

# Every documented shape: raw image bytes, base64 JSON, URL JSON, Responses
# image_generation output, Chat message images with a data URL.
img_v2_result_reference() {
  local response="$1"

  jq -r '
    def usable: select(type == "string" and length > 0);
    [
      (try (.data[0].b64_json) catch empty),
      (try (.data[0].url) catch empty),
      ((try (.images[0]) catch null) | if type == "string" then . else empty end),
      (try (.images[0].url) catch empty),
      (try ([.output[] | select(.type == "image_generation_call") | .result][0]) catch empty),
      (try (.choices[0].message.images[0].image_url.url) catch empty),
      (try (.image.url) catch empty)
    ] | map(usable) | (.[0] // empty)
  ' "$response" 2>/dev/null
}

img_v2_save() {
  local response="$IMG_V2_WORK/response"
  local output="$IMG_V2_WORK/output"
  local reference extension destination

  if img_v2_probe "$response" >/dev/null 2>&1; then
    cp -- "$response" "$output" || return 1
  else
    jq -e 'type == "object" and (.error == null)' "$response" >/dev/null 2>&1 || {
      img_v2_error 'Provider returned an error object; nothing was published.'
      return 1
    }
    reference=$(img_v2_result_reference "$response") || return 1
    [[ -n $reference ]] || { img_v2_error 'Response carries no image reference.'; return 1; }

    case "$reference" in
      https://*)
        # Signed media link: no provider credentials on a foreign origin.
        engine_v2_http "$reference" "$output" false '' || {
          img_v2_error "Image download failed (HTTP ${ENGINE_V2_HTTP_CODE:-none})."
          return 1
        }
      ;;
      data:*)
        printf '%s' "${reference#*,}" | b64d > "$output" || return 1
      ;;
      *)
        printf '%s' "$reference" | b64d > "$output" || return 1
      ;;
    esac
  fi

  img_v2_probe "$output" >/dev/null 2>&1 || { img_v2_error 'Response is not a valid raster image.'; return 1; }
  img_v2_decodable "$output" || { img_v2_error 'Response image cannot be decoded.'; return 1; }

  case "$(file -b --mime-type "$output")" in
    image/png)  extension=png ;;
    image/jpeg) extension=jpg ;;
    image/webp) extension=webp ;;
    *) img_v2_error 'Unsupported output container.'; return 1 ;;
  esac

  if [[ ${IMG_STRIP_METADATA:-true} == true ]]; then
    command -v exiftool >/dev/null 2>&1 || { img_v2_error 'Missing dependency: exiftool.'; return 1; }
    exiftool -overwrite_original -all= "$output" >/dev/null 2>&1 || {
      img_v2_error 'Metadata stripping failed; output not published.'
      return 1
    }
  fi

  destination=$(engine_v2_publish "$IMG_V2_WORK" "$output" "$extension") || return 1
  EXIF_DEST="$destination"
}

# ── Entry points ─────────────────────────────────────────────────────────────

img_v2_run() (
  set +x
  set -o pipefail
  umask 077

  local operation="$1"
  shift

  local prompt='' input='' mask=''
  local IMG_V2_PROVIDER="${IMAGE_PROVIDER:-}"
  local IMG_V2_OPERATION='' IMG_V2_CATALOGUE=''
  local IMG_V2_MODEL='' IMG_V2_OP="$operation" IMG_V2_ADAPTER=''
  local IMG_V2_ENDPOINT='' IMG_V2_ALLOW='' IMG_V2_CONFIGURED='' IMG_V2_PROTOCOL=''
  local IMG_V2_STATIC='' IMG_V2_DEFAULT='' IMG_V2_KEY='' IMG_V2_WORK=''
  local IMG_V2_SIZE='' IMG_V2_RATIO='' IMG_V2_FORMAT=''
  local IMG_V2_PROMPT='' IMG_V2_INPUT_W='' IMG_V2_INPUT_H='' IMG_V2_MIME=''
  local IMG_V2_CONSTRAINTS='' EXIF_DEST=''

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) img_v2_help; return 0 ;;
      --prompt|--image|--mask|--provider|--model|--size|--ratio|--format)
        [[ $# -ge 2 && -n $2 ]] || { img_v2_error "Missing value for $1."; return 1; }
        case "$1" in
          --prompt)   prompt="$2" ;;
          --image)    input="$2" ;;
          --mask)     mask="$2" ;;
          --provider) IMG_V2_PROVIDER="$2" ;;
          --model)    IMG_V2_MODEL="$2" ;;
          --size)     IMG_V2_SIZE="$2" ;;
          --ratio)    IMG_V2_RATIO="$2" ;;
          --format)   IMG_V2_FORMAT="$2" ;;
        esac
        shift 2
      ;;
      --resolution)
        img_v2_error 'Resolution tiers are model-specific; use --size instead.'
        return 1
      ;;
      --*) img_v2_error "Unknown option: $1"; return 1 ;;
      *)
        [[ -z $prompt ]] || { img_v2_error 'Quote the prompt as one argument.'; return 1; }
        prompt="$1"
        shift
      ;;
    esac
  done

  if [[ -z $IMG_V2_PROVIDER && -r ${STATE_FILE:-} ]]; then
    IMG_V2_PROVIDER=$(jq -r '[.image, .provider] | map(select(type == "string" and length > 0)) | .[0] // empty' "$STATE_FILE")
  fi
  IMG_V2_PROVIDER="${IMG_V2_PROVIDER:-${PROVIDER:-}}"
  [[ -n $IMG_V2_PROVIDER ]] || { img_v2_error 'No image provider selected.'; return 1; }

  case "$operation" in
    generate)
      prompt="${prompt:-Generate anything you have in mind.}"
      [[ -z $input && -z $mask ]] || { img_v2_error 'Use modify_image for image inputs.'; return 1; }
    ;;
    edit)
      [[ -n $prompt ]] || { img_v2_error 'Editing requires a prompt.'; return 1; }
      [[ -n $input ]] || { img_v2_error 'Editing requires --image FILE.'; return 1; }
    ;;
  esac

  img_v2_deps || return 1
  [[ ${ZDR_ENFORCED:-false} != true ]] || {
    img_v2_error 'ZDR enforcement has no verified image policy in this engine.'
    return 1
  }

  img_v2_resolve || return 1
  IMG_V2_PROMPT="$prompt"

  IMG_V2_WORK=$(engine_v2_workdir images) || { img_v2_error 'Cannot create a private work directory.'; return 1; }
  trap 'rm -rf "$IMG_V2_WORK"' EXIT

  printf '%s' "$prompt" > "$IMG_V2_WORK/prompt" || return 1

  if [[ $operation == edit ]]; then
    img_v2_prepare_input "$input" || return 1
    IMG_V2_MIME=$(file -b --mime-type "$IMG_V2_WORK/input")
    img_v2_prepare_mask "$mask" || return 1
  fi

  case "$IMG_V2_ADAPTER" in
    venice|venice_edit) img_v2_venice_options || return 1 ;;
  esac
  img_v2_options || return 1
  img_v2_build_request || return 1
  img_v2_send || return 1
  img_v2_save || return 1

  if declare -F log_image >/dev/null; then
    log_image "Image created in '$EXIF_DEST'."
  fi
  printf '%s\n' "$EXIF_DEST"
)

generate_image() { img_v2_run generate "$@"; }
modify_image() { img_v2_run edit "$@"; }

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  IMG_V2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$IMG_V2_ROOT/core.sh" || exit 1
  [[ $(type -t load_libs) == function ]] && load_libs
  case "${1:-}" in
    edit) shift; modify_image "$@" ;;
    --help|-h) img_v2_help ;;
    *) generate_image "$@" ;;
  esac
fi
