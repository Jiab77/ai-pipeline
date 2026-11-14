#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# =======================================================================================
# engines/image.sh — Text/image-to-image engine
# =======================================================================================
# Generates and edits images through provider adapters. Usable as a sourced
# library or as a standalone CLI with Bash 3.2+.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.1
#
# Contract:
#   generate_image — Generate an image from a text prompt.
#   modify_image   — Edit an existing image, optionally through a mask.
#
# Dependencies: core.sh helpers, jq, curl, file, base64, ffprobe, ffmpeg;
#               exiftool for metadata removal.
#
# Notes: No global session mutation and no automatic paid retry. Generation falls back
#        to pollinations.ai (keyless) when the resolved provider cannot render images,
#        as before; editing never falls back.
#        Provider registry supplies models, bounds and endpoints; adapters supply wire
#        protocols. Missing edit sections use documented adapters, NOT image=true as
#        proof of editing capability. Explicit default.edit=false disables editing.
#        Size omitted during OpenAI edits: request source dimensions if valid.
#        Other edit APIs may choose dimensions; no promise of pixel-exact preservation.
# =======================================================================================

IMG_CONNECT_TIMEOUT=10
IMG_REQUEST_TIMEOUT=180
IMG_STRIP_METADATA=true
IMG_POLL_MAX=120
IMG_POLL_INTERVAL=5

img_error() { printf 'Image: %s\n' "$*" >&2; }
img_warn() {
  if declare -F log_warn >/dev/null; then log_warn "$*"; else printf 'Image: %s\n' "$*" >&2; fi
}
img_help() {
  cat <<'EOF'
Usage: image.sh [edit] [--prompt TEXT] [options]
  --provider NAME --model ID
  --size WxH          Explicit dimensions (takes priority over --ratio)
  --ratio W:H         Exact ratio where pixel constraints allow it
  --resolution TIER   Only on resolution-tier models
  --format png|jpeg|webp
  --image FILE        Required for edit; PNG, JPEG or WebP
  --mask FILE         PNG with alpha, same dimensions; supported models only
Without a generation prompt: "Generate anything you have in mind."
Editing requires a prompt. No resize, upload to third-party storage or paid
retry. Unsupported parameters fail before submission. When the resolved provider
cannot generate images, generation falls back to pollinations.ai (keyless) with
a warning; --provider pollinations selects it explicitly.
EOF
}

# img_b64d() { if [[ $OSTYPE == darwin* ]]; then base64 -D; else base64 -d; fi; }
img_gcd() { local a=$1 b=$2 r; while ((b)); do r=$((a%b)); a=$b; b=$r; done; printf '%s' "$a"; }
img_probe() {
  [[ -f $1 && -r $1 ]] || return 1
  case "$(file -b --mime-type "$1")" in image/png|image/jpeg|image/webp) ;; *) return 1 ;; esac
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height,pix_fmt -of json "$1" |
    jq -e '.streams[0] | select(.width>0 and .height>0)'
}

# GETs never receive API credentials. Authenticated POSTs never follow redirects.
img_http() {
  local method=$1 url=$2 out=$3 code
  shift 3
  local -a opts ; opts=(--silent --show-error --connect-timeout "$IMG_CONNECT_TIMEOUT" --max-time "$IMG_REQUEST_TIMEOUT"
    --proto '=https' --proto-redir '=https' --output "$out" --write-out '%{http_code}')
  [[ ${USE_TOR:-true} == true ]] && opts+=(--proxy "$TOR_PROXY")
  [[ $url == https://* ]] || { img_error 'HTTPS required.'; return 1; }
  if [[ $method == POST || $method == AUTHGET ]]; then
    case "$ip:$url" in
      openai:https://api.openai.com/v1/*|openrouter:https://openrouter.ai/api/v1/*|venice:https://api.venice.ai/api/v1/*|zai:https://api.z.ai/api/paas/v4/*|cyberneurova:https://api.cyberneurova.ai/v1/*|mammouth:https://api.mammouth.ai/v1/*|vercel:https://ai-gateway.vercel.sh/v1/*|vercel_free:https://ai-gateway.vercel.sh/v1/*|huggingface:https://router.huggingface.co/*) ;;
      *) img_error 'Refusing credentials outside the provider API.'; return 1 ;;
    esac
    opts+=(-H "Authorization: Bearer $ikey")
    if [[ $ip == vercel* ]]; then
      [[ -n ${ATTRIBUTION_REFERER:-} ]] && opts+=(-H "http-referer: $ATTRIBUTION_REFERER")
      [[ -n ${ATTRIBUTION_TITLE:-} ]] && opts+=(-H "x-title: $ATTRIBUTION_TITLE")
    fi
  else
    opts+=(--location)
  fi
  if ! code=$(curl "${opts[@]}" "$@" "$url"); then img_error 'Transfer failed; no automatic retry.'; return 1; fi
  case "$code" in 2??) ;; *) img_error "HTTP $code; no output published."; return 1 ;; esac
}
img_post() { img_http POST "$endpoint" "$work/response" -H 'Content-Type: application/json' --data-binary "@$work/request"; }

# Pollinations is keyless and accepts arbitrary dimensions: keep the bounds the
# previous engine used (its --ratio range), and let --size/--ratio or the generic
# 16:9 default decide the framing. The old square 2048x2048 was a constant
# default, never a framing decision; a special case here would be one more
# exception to document.
img_pollinations_defaults() {
  adapter=pollinations
  model="${model:-flux}"
  spec='{"min":512,"max":2880,"step":32,"max_px":4194304}'
}

img_resolve() {
  local section=image mode
  [[ $op == edit ]] && section=edit
  if [[ -z $ip && -r ${STATE_FILE:-} ]]; then
    ip=$(jq -r '[.image,.provider] | map(select(type=="string" and length>0)) | .[0] // empty' "$STATE_FILE") || return 1
  fi
  ip="${ip:-${PROVIDER:-}}"
  if [[ $ip == pollinations ]]; then
    [[ $op == generate ]] || { img_error 'Pollinations edit is not implemented.'; return 1; }
    img_pollinations_defaults; return 0
  fi
  # Automatic keyless fallback for generation, as before: an unresolved, unknown
  # or image-incapable provider yields a pollinations.ai image with a warning
  # instead of failing. Editing never falls back — silently editing through a
  # substitute engine would be worse than a clear error.
  if [[ $op == generate ]] && ! jq -e --arg p "$ip" 'has($p) and .[$p].default.image == true' "$PROVIDERS_CONFIG" >/dev/null; then
    if [[ -z $ip ]]; then
      img_warn 'No image provider resolved — falling back to pollinations.ai.'
    elif jq -e --arg p "$ip" 'has($p)' "$PROVIDERS_CONFIG" >/dev/null; then
      img_warn "Provider '$ip' does not support image generation — falling back to pollinations.ai."
    else
      img_warn "Provider '$ip' is not configured — falling back to pollinations.ai."
    fi
    # The substitute engine has no tier or format control: degrade the options it
    # cannot honour rather than failing the fallback on them.
    if [[ -n $resolution ]]; then
      img_warn "Pollinations has no resolution tier — ignoring '--resolution $resolution'."
      resolution=''
    fi
    if [[ -n $format ]]; then
      img_warn "Pollinations output format is not selectable — ignoring '--format $format'."
      format=''
    fi
    ip=pollinations
    img_pollinations_defaults
    return 0
  fi
  jq -e --arg p "$ip" 'has($p)' "$PROVIDERS_CONFIG" >/dev/null || { img_error 'Unknown provider.'; return 1; }
  if [[ $op == edit ]]; then
    jq -e --arg p "$ip" '.[$p].default.edit != false' "$PROVIDERS_CONFIG" >/dev/null || { img_error 'Editing disabled in registry.'; return 1; }
  fi
  mode=$(jq -r --arg p "$ip" '.[$p].image.mode // "native"' "$PROVIDERS_CONFIG") || return 1
  model="${model:-$(jq -r --arg p "$ip" --arg s "$section" '.[$p][$s].default // empty' "$PROVIDERS_CONFIG")}"
  case "$ip:$op" in
    openai:*) adapter=openai; endpoint="https://api.openai.com/v1/images/generations"; [[ $op == edit ]] && endpoint="https://api.openai.com/v1/images/edits" ;;
    openrouter:*) adapter=openrouter; endpoint=https://openrouter.ai/api/v1/images ;;
    venice:generate) adapter=venice; endpoint=https://api.venice.ai/api/v1/image/generate ;;
    venice:edit) adapter=venice_edit; endpoint=https://api.venice.ai/api/v1/image/edit; model="${model:-firered-image-edit}" ;;
    zai:generate) adapter=zai; endpoint=https://api.z.ai/api/paas/v4/images/generations ;;
    cyberneurova:generate) adapter=cyberneurova; endpoint=https://api.cyberneurova.ai/v1/images/generations ;;
    mammouth:generate) adapter=chat; endpoint=https://api.mammouth.ai/v1/chat/completions ;;
    vercel*:generate)
      endpoint=https://ai-gateway.vercel.sh/v1/images/generations; adapter=vercel
      if [[ $mode == chat ]]; then adapter=chat; endpoint=https://ai-gateway.vercel.sh/v1/chat/completions; fi
    ;;
    vercel*:edit) adapter=vercel; endpoint=https://ai-gateway.vercel.sh/v1/images/edits ;;
    huggingface:generate) adapter=hf; endpoint=https://router.huggingface.co/hf-inference/models ;;
    huggingface:edit) adapter=hf_edit; model="${model:-black-forest-labs/FLUX.2-klein-9B}" ;;
    *) img_error "No documented editing API adapter for '$ip' (app features are not an API contract)."; return 1 ;;
  esac
  model="${model:-$(jq -r --arg p "$ip" '.[$p].image.default // empty' "$PROVIDERS_CONFIG")}"
  [[ -n $model ]] || { img_error 'Missing model.'; return 1; }
  spec=$(jq -c --arg p "$ip" --arg s "$section" --arg m "$model" '.[$p][$s].models[$m] // .[$p].image.models[$m] // {}' "$PROVIDERS_CONFIG") || return 1
  case "$adapter" in
    openai|zai|chat)
      [[ $spec != '{}' ]] || { img_error 'Unregistered model: add its constraints to the registry before use.'; return 1; }
    ;;
  esac
  local configured ; configured=$(jq -r --arg p "$ip" --arg s "$section" '.[$p][$s].endpoint // empty' "$PROVIDERS_CONFIG") || return 1
  # Reject a conflicting endpoint rather than secretly override the registry.
  [[ -z $configured || $configured == "$endpoint" ]] || { img_error "Registry endpoint conflicts with documented $adapter protocol."; return 1; }
  has_provider_key "$ip" || { img_error 'Missing provider key.'; return 1; }
  ikey=$(decrypt_provider_key "$ip") || return 1
  [[ -n $ikey ]] || { img_error 'Empty provider key.'; return 1; }
}

img_inputs() {
  [[ $op == edit ]] || { [[ -z $input && -z $mask ]] || { img_error 'Use modify_image for image inputs.'; return 1; }; return 0; }
  img_probe "$input" > "$work/input-info" || { img_error 'Input is not a readable raster image.'; return 1; }
  # Decode before upload; a recognizable header alone is not sufficient.
  ffmpeg -nostdin -v error -xerror -i "$input" -frames:v 1 -f null - || return 1
  iw=$(jq -r .width "$work/input-info"); ih=$(jq -r .height "$work/input-info")
  mime=$(file -b --mime-type "$input")
  local limit=52428800
  [[ $adapter == venice_edit ]] && limit=26214400
  [[ $(wc -c < "$input") -lt $limit ]] || { img_error 'Input exceeds adapter upload limit.'; return 1; }
  cp "$input" "$work/input" || return 1
  printf 'data:%s;base64,' "$mime" > "$work/reference"
  (set -o pipefail; b64e < "$work/input" >> "$work/reference") || return 1
  if [[ -n $mask ]]; then
    case "$adapter:$model" in openai:gpt-image-*|vercel:openai/gpt-image-*) ;; *) img_error 'Mask unsupported for this adapter/model; refusing whole-image fallback.'; return 1 ;; esac
    [[ $(file -b --mime-type "$mask") == image/png ]] || { img_error 'Mask must be PNG.'; return 1; }
    img_probe "$mask" > "$work/mask-info" || return 1
    jq -e --argjson w "$iw" --argjson h "$ih" '.width==$w and .height==$h and (.pix_fmt|test("rgba|bgra|argb|abgr|yuva|gbrap|ya"))' "$work/mask-info" >/dev/null || {
      img_error 'Mask dimensions/alpha channel invalid.'; return 1;
    }
    [[ $(wc -c < "$mask") -lt 52428800 ]] || return 1
    ffmpeg -nostdin -v error -xerror -i "$mask" -frames:v 1 -f null - || return 1
    cp "$mask" "$work/mask" || return 1
  fi
}

# Exact-ratio integer sizing, with registry bounds; no floating Bash arithmetic.
img_dimensions() {
  local min max step pixels minpx a b g k w h
  min=$(jq -r '.min // 512' <<< "$spec"); max=$(jq -r '.max // 2048' <<< "$spec")
  step=$(jq -r '.step // 32' <<< "$spec"); pixels=$(jq -r '.max_px // 4194304' <<< "$spec"); minpx=1
  # OpenAI docs specify area, not a 1024 minimum on each edge (registry is stale).
  if [[ $model == *gpt-image-2* ]]; then min=16; max=3840; step=16; minpx=655360; pixels=8294400; fi
  for k in "$min" "$max" "$step" "$pixels"; do [[ $k =~ ^[1-9][0-9]{0,8}$ ]] || return 1; done
  if [[ -n $size ]]; then w=${size%x*}; h=${size#*x}
  else
    ratio="${ratio:-16:9}"; a=${ratio%:*}; b=${ratio#*:}; g=$(img_gcd "$a" "$b"); a=$((a/g)); b=$((b/g))
    for ((k=max/(a>b?a:b); k>0; k--)); do
      w=$((a*k)); h=$((b*k))
      if ((w>=min && h>=min && w%step==0 && h%step==0 && w*h<=pixels && w*h>=minpx)); then break; fi
    done
    ((k>0)) || { img_error 'No exact ratio fits the model constraints.'; return 1; }
  fi
  ((w>=min && h>=min && w<=max && h<=max && w%step==0 && h%step==0 && w*h<=pixels && w*h>=minpx)) || {
    img_error 'Requested size violates model constraints; no silent resize.'; return 1;
  }
  if [[ $model == *gpt-image-2* ]]; then ((w<=3*h && h<=3*w)) || return 1; fi
  size="${w}x${h}"
}

img_options() {
  [[ -z $size || $size =~ ^[1-9][0-9]{0,4}x[1-9][0-9]{0,4}$ ]] || { img_error 'Invalid size.'; return 1; }
  [[ -z $ratio || $ratio =~ ^[1-9][0-9]{0,3}:[1-9][0-9]{0,3}$ ]] || { img_error 'Invalid ratio.'; return 1; }
  case "$format" in ''|png|jpeg|webp) ;; *) img_error 'Invalid format.'; return 1 ;; esac
  if [[ -n $size ]]; then ratio=''; resolution=''; fi
  case "$adapter" in
    openai|zai|hf|pollinations)
      [[ -z $resolution ]] || { img_error 'Resolution tier unsupported; use size/ratio.'; return 1; }
      if [[ $op == edit && -z $size && -z $ratio ]]; then size="${iw}x${ih}"; fi
      img_dimensions || return 1
    ;;
    cyberneurova)
      [[ -z $resolution ]] || return 1
      if [[ -n $size ]]; then
        case "$size" in 1024x1024|1344x768|768x1344|1152x896|896x1152) ;; *) img_error 'CyberNeurova size not in documented enum.'; return 1 ;; esac
      else
        ratio="${ratio:-1:1}"
        case "$ratio" in 1:1|16:9|9:16|4:3|3:4) size=$ratio ;; *) return 1 ;; esac
      fi
      ratio=''
    ;;
    chat)
      [[ -z $size && -z $ratio && -z $resolution && -z $format ]] || {
        img_error 'Chat image sizing/format is not documented by this adapter; use native image models for explicit controls.'; return 1;
      }
    ;;
    venice_edit)
      [[ -z $size ]] || { img_error 'Venice edit takes ratio/resolution, not exact pixel size.'; return 1; }
      ((iw*ih>=65536 && iw*ih<=33177600)) || return 1
    ;;
    hf_edit)
      [[ -z $size && -z $ratio && -z $resolution && -z $format ]] || { img_error 'HF edit controls are model-specific; this adapter uses provider defaults.'; return 1; }
    ;;
  esac
  case "$adapter" in
    openai|venice|venice_edit) format="${format:-webp}" ;;
    openrouter) ;;
    vercel)
      if [[ -n $resolution ]]; then
        img_error 'Gateway native tier mapping is model-specific; use --size or omit resolution.'; return 1
      fi
      if [[ $model == openai/gpt-image-* ]]; then
        format="${format:-webp}"
        if [[ $op == edit && -z $size ]]; then size="${iw}x${ih}"; fi
        [[ -z $size ]] || img_dimensions || return 1
      elif [[ -n $format ]]; then img_error 'Format passthrough not documented for this Gateway model.'; return 1; fi
    ;;
    *) [[ -z $format ]] || { img_error 'Output format selection unsupported.'; return 1; } ;;
  esac
}

img_catalogue() {
  local task metadata="$work/models" mapped catalogue_url
  case "$adapter" in
    venice|venice_edit)
      catalogue_url=$(jq -rc .venice.models "$PROVIDERS_CONFIG")
      task=image; [[ $op == edit ]] && task=inpaint
      img_http GET "${catalogue_url}?type=$task" "$metadata" || return 1
      jq -e --arg m "$model" '.data[]|select(.id==$m and .model_spec.offline!=true)|.model_spec.constraints' "$metadata" > "$work/constraints" || return 1
      if jq -e '(.aspectRatios // []|length)>0' "$work/constraints" >/dev/null; then
        [[ -z $size ]] || { img_error 'Venice model only accepts aspect ratio, not exact size.'; return 1; }
        [[ -n $ratio || $op == edit ]] || ratio=16:9
      elif [[ $op == generate ]]; then
        img_dimensions || return 1
      fi
      jq -e --arg a "$ratio" --arg r "$resolution" --argjson n "${#prompt}" '
        ($a=="" or (.aspectRatios // []|index($a))!=null) and
        ($r=="" or (.resolutions // []|index($r))!=null) and
        $n <= (.promptCharacterLimit // 1500)' "$work/constraints" >/dev/null || { img_error 'Unsupported Venice parameters.'; return 1; }
    ;;
    openrouter)
      catalogue_url=$(jq -rc .openrouter.models "$PROVIDERS_CONFIG")
      img_http GET "$catalogue_url" "$metadata" || return 1
      jq -e --arg m "$model" --arg op "$op" '.data[]|select(.id==$m)|
        select($op!="edit" or (.architecture.input_modalities|index("image"))!=null)' "$metadata" > "$work/model" || return 1
      jq -e --arg a "$ratio" --arg r "$resolution" --arg f "$format" '
        def accepts($c;$v): $v=="" or ($c!=null and ($c.type!="enum" or ($c.values|index($v))!=null));
        accepts(.supported_parameters.aspect_ratio;$a) and accepts(.supported_parameters.resolution;$r) and accepts(.supported_parameters.output_format;$f)' "$work/model" >/dev/null || return 1
    ;;
    hf|hf_edit)
      [[ $model =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
      img_http GET "https://huggingface.co/api/models/$model?expand=inferenceProviderMapping" "$metadata" || return 1
      if [[ $op == generate ]]; then
        jq -e '.inferenceProviderMapping["hf-inference"]|.status=="live" and .task=="text-to-image"' "$metadata" >/dev/null || { img_error 'No live HF Inference mapping; no implicit partner switch.'; return 1; }
        endpoint="$endpoint/$model"
      else
        mapped=$(jq -er '.inferenceProviderMapping["fal-ai"]|select(.status=="live" and .task=="image-to-image")|.providerId' "$metadata") || return 1
        [[ $mapped =~ ^[A-Za-z0-9_./-]+$ && $mapped != *..* ]] || return 1
        endpoint="https://router.huggingface.co/fal-ai/$mapped?_subdomain=queue"
      fi
    ;;
    vercel)
      catalogue_url=$(jq -rc .vercel.models "$PROVIDERS_CONFIG")

      # Some catalogue records omit image input despite explicit edit support in
      # the Gateway Images API docs; documented exceptions are narrowly listed.
      img_http GET "$catalogue_url" "$metadata" || return 1
      jq -e --arg m "$model" --arg op "$op" '.data[]|select(.id==$m)|
        select((.modalities.output|index("image"))!=null and ($op!="edit" or
          (.modalities.input|index("image"))!=null or
          (["openai/gpt-image-2","bfl/flux-kontext-pro","bfl/flux-pro-1.0-fill","spacexai/grok-imagine-image"]|index($m))!=null))' "$metadata" >/dev/null || return 1
    ;;
  esac
  return 0
}

img_build() {
  printf '%s' "$prompt" > "$work/prompt" || return 1
  [[ -f $work/reference ]] || : > "$work/reference"
  jq -n --arg m "$model" --rawfile p "$work/prompt" --arg s "$size" --arg a "$ratio" --arg r "$resolution" --arg f "$format" '
    {model:$m,prompt:$p} + (if $s!="" then {size:$s} else {} end) +
    (if $a!="" and $s=="" then {aspect_ratio:$a} else {} end) +
    (if $r!="" then {resolution:$r} else {} end) +
    (if $f!="" then {output_format:$f} else {} end)' > "$work/base" || return 1
  case "$adapter" in
    chat)
      jq --arg p "$ip" '{model,messages:[{role:"user",content:.prompt}],stream:false} +
        (if $p=="mammouth" then {} else {modalities:["text","image"],providerOptions:{gateway:{disallowPromptTraining:true}}} end)' "$work/base" > "$work/request"
    ;;
    venice)
      jq '(if has("size") then (.size|split("x")|map(tonumber)) as $s | .width=$s[0] | .height=$s[1] | del(.size) else . end) |
        .format=.output_format | del(.output_format) | .hide_watermark=true' "$work/base" > "$work/request"
    ;;
    venice_edit)
      jq --rawfile i "$work/reference" '.image=($i|sub("^data:[^;]+;base64,";""))' "$work/base" > "$work/request"
    ;;
    openrouter)
      jq --rawfile i "$work/reference" '. + (if $i!="" then {input_references:[{type:"image_url",image_url:{url:$i}}]} else {} end)' "$work/base" > "$work/request"
    ;;
    hf)
      jq '{inputs:.prompt,parameters:{width:(.size|split("x")[0]|tonumber),height:(.size|split("x")[1]|tonumber)}}' "$work/base" > "$work/request"
    ;;
    hf_edit)
      jq --rawfile i "$work/reference" '{prompt,image_url:$i,image_urls:[$i]}' "$work/base" > "$work/request"
    ;;
    *) cp "$work/base" "$work/request" ;;
  esac
}

img_send() {
  local field=image
  if [[ $op == edit && ( $adapter == openai || $adapter == vercel ) ]]; then
    [[ $adapter == openai ]] && field='image[]'
    local -a form ; form=(-F "prompt=<$work/prompt" --form-string "model=$model"
      -F "$field=@$work/input;type=$mime;filename=input")
    [[ -z $mask ]] || form+=(-F "mask=@$work/mask;type=image/png;filename=mask.png")
    [[ -z $size ]] || form+=(--form-string "size=$size")
    [[ -z $format ]] || form+=(--form-string "output_format=$format")
    [[ -z $ratio && -z $resolution ]] || { img_error 'Multipart edits do not expose ratio/tier in this adapter.'; return 1; }
    img_http POST "$endpoint" "$work/response" "${form[@]}"
  elif [[ $adapter == pollinations ]]; then
    local encoded
    encoded=$(jq -Rs -r '@uri' "$work/prompt") || return 1
    [[ $model =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    img_http GET "https://image.pollinations.ai/prompt/$encoded?width=${size%x*}&height=${size#*x}&model=$model&private=true&nologo=true" "$work/response"
  else
    img_post
  fi
}

img_hf_wait() {
  local path url status i
  path=$(jq -er '.response_url | select(startswith("https://queue.fal.run/")) | ltrimstr("https://queue.fal.run/")' "$work/response") || return 1
  [[ $path =~ ^[A-Za-z0-9_./-]+$ && $path != *..* ]] || return 1
  url="https://router.huggingface.co/fal-ai/$path"
  for ((i=0;i<IMG_POLL_MAX;i++)); do
    img_http AUTHGET "$url/status?_subdomain=queue" "$work/status" || return 1
    status=$(jq -er .status "$work/status") || return 1
    case "$status" in
      COMPLETED) img_http AUTHGET "$url?_subdomain=queue" "$work/response"; return $? ;;
      IN_QUEUE|IN_PROGRESS) sleep "$IMG_POLL_INTERVAL" ;;
      *) img_error "HF edit job stopped: $status"; return 1 ;;
    esac
  done
  img_error 'HF polling limit reached. No automatic resubmission.'; return 1
}

img_save() {
  local type link ext dest
  if img_probe "$work/response" > /dev/null 2>&1; then cp "$work/response" "$work/output" || return 1
  else
    jq -e 'type=="object" and .error==null' "$work/response" >/dev/null || { img_error 'Invalid/error response.'; return 1; }
    jq -er '.data[0].b64_json // (if (.images[0]|type)=="string" then .images[0] else .images[0].url end) // .choices[0].message.images[0].image_url.url //
      .data[0].url // .image.url // empty | select(type=="string" and length>0)' "$work/response" > "$work/result" || return 1
    IFS= read -r -n 8 type < "$work/result"
    if [[ $type == https:// ]]; then
      link=$(<"$work/result")
      img_http GET "$link" "$work/output" || return 1
    else
      (set -o pipefail; sed 's@^data:[^;]*;base64,@@' "$work/result" | b64d > "$work/output") || return 1
    fi
  fi
  img_probe "$work/output" >/dev/null || { img_error 'Response is not a valid raster image.'; return 1; }
  ffmpeg -nostdin -v error -xerror -i "$work/output" -frames:v 1 -f null - || return 1
  type=$(file -b --mime-type "$work/output")
  case "$type" in image/png) ext=png ;; image/jpeg) ext=jpg ;; image/webp) ext=webp ;; *) return 1 ;; esac
  if [[ ${IMG_STRIP_METADATA:-true} == true ]]; then
    exiftool -overwrite_original -all= "$work/output" >/dev/null 2>&1 || { img_error 'Metadata stripping failed; output not published.'; return 1; }
  fi
  dest="${work%/*}/${work##*/}.$ext"
  mv "$work/output" "$dest" || return 1
  if declare -F log_image >/dev/null; then log_image "Image created in '$dest'."; fi
  printf '%s\n' "$dest"
}

img_run() (
  set +x
  set -o pipefail
  umask 077
  local op=$1; shift
  local prompt='' input='' mask='' ip="${IMAGE_PROVIDER:-}" model='' size='' ratio='' resolution='' format=''
  local adapter='' endpoint='' ikey='' spec='' work='' iw ih mime dep
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) img_help; return 0 ;;
      --prompt|--image|--mask|--provider|--model|--size|--ratio|--resolution|--format)
        [[ $# -ge 2 && -n $2 ]] || { img_error "Missing value for $1."; return 1; }
        case "$1" in
          --prompt) prompt=$2 ;; --image) input=$2 ;; --mask) mask=$2 ;; --provider) ip=$2 ;;
          --model) model=$2 ;; --size) size=$2 ;; --ratio) ratio=$2 ;; --resolution) resolution=$2 ;; --format) format=$2 ;;
        esac
        shift 2
      ;;
      --*) img_error "Unknown option $1"; return 1 ;;
      *) [[ -z $prompt ]] || { img_error 'Quote the prompt as one argument.'; return 1; }; prompt=$1; shift ;;
    esac
  done
  if [[ $op == generate ]]; then
    prompt="${prompt:-Generate anything you have in mind.}"
  else
    [[ -n $prompt ]] || { img_error 'Prompt required.'; return 1; }
  fi
  for dep in jq curl file base64 ffprobe ffmpeg; do command -v "$dep" >/dev/null || { img_error "Missing dependency: $dep"; return 1; }; done
  if [[ $IMG_STRIP_METADATA == true ]]; then command -v exiftool >/dev/null || { img_error 'Missing dependency: exiftool'; return 1; }; fi
  # Conservative until a per-adapter verified ZDR contract is selected.
  [[ ${ZDR_ENFORCED:-false} != true ]] || { img_error 'ZDR enforcement has no verified image policy in this staging engine.'; return 1; }
  img_resolve || return 1
  [[ -n ${DATA_STORE:-} ]] || return 1
  mkdir -p "$DATA_STORE/images" || return 1
  work=$(mktemp -d "$DATA_STORE/images/$(date +%Y%m%d-%H%M%S).XXXXXX") || return 1
  trap 'rm -rf "$work"' EXIT
  img_inputs && img_options && img_catalogue && img_build && img_send || return 1
  if [[ $adapter == hf_edit ]]; then img_hf_wait || return 1; fi
  img_save
)

generate_image() { img_run generate "$@"; }
modify_image() { img_run edit "$@"; }

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    img_help ; exit 0
  fi
  IMG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$IMG_ROOT/core.sh" || exit 1
  [[ $(type -t 'load_libs') == 'function' ]] && load_libs
  case "${1:-}" in edit) shift; modify_image "$@" ;; *) generate_image "$@" ;; esac
fi
