#!/usr/bin/env bash
#
# ==============================================================================
# web-browse.sh — Pure Bash Stateless One-Shot CDP Browser Automation Engine
# ==============================================================================
# Pilots Chromium-based browsers via direct Chrome DevTools Protocol (CDP)
# WebSocket RPC calls. Supports clicking, typing, screenshots, and PDFs.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (Gemini)
#
# Version: 0.0.3
# ==============================================================================

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x

# Global state variables
WS_URL=""
BROWSER_PID=""
USER_DATA_DIR=""
cdp_seq=0
SUCCESS="true"
ERROR_MSG=""
PAGE_TITLE=""
PAGE_URL=""
SCREENSHOT_PATHS=()
EVAL_RESULTS=()
WS_CLIENT=""

# Internals
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
LOG_FILE="${SCRIPT_NAME}.log"

# Helper: Detect OS
is_macos() {
  [[ $OSTYPE == "darwin"* ]]
}

# Helper: Base64 decoding
base64_decode() {
  if is_macos; then
    base64 -D 2>/dev/null
  else
    base64 -d 2>/dev/null
  fi
}

# Cleanup on exit
# shellcheck disable=SC2329
cleanup() {
  # Desktop mode: kill the local browser process and remove its temp profile
  if [[ -n $BROWSER_PID ]]; then
    kill "$BROWSER_PID" 2>/dev/null
    wait "$BROWSER_PID" 2>/dev/null
  fi
  [[ -n $USER_DATA_DIR && -d $USER_DATA_DIR ]] && rm -rf "$USER_DATA_DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

# Helper: Detect WebSocket client
detect_ws_client() {
  if command -v websocat &>/dev/null; then
    WS_CLIENT="websocat"
  elif command -v wscat &>/dev/null; then
    WS_CLIENT="wscat"
  else
    WS_CLIENT=""
  fi
}

# Helper: Send CDP command and return raw JSON response
cdp_send() {
  local method="$1"
  local params="${2:-"{}"}"
  local timeout="${3:-0.5}"  # Default to 0.5 seconds
  ((cdp_seq++))

  # [[ -n $PROXY ]] && timeout=1

  local cmd
  if [[ $params == "{}" || -z $params ]]; then
    cmd=$(printf '{"id":%d,"method":"%s"}' "$cdp_seq" "$method")
  else
    cmd=$(printf '{"id":%d,"method":"%s","params":%s}' "$cdp_seq" "$method" "$params")
  fi

  [[ -z $WS_CLIENT ]] && detect_ws_client
  local resp
  if [[ $WS_CLIENT == "websocat" ]]; then
    resp=$( (echo "$cmd"; sleep "$timeout") | websocat "$WS_URL" 2>/dev/null | tr -d '\r\n' | grep -E '^{"id":'"$cdp_seq"'(,|})')
  elif [[ $WS_CLIENT == "wscat" ]]; then
    resp=$(wscat --connect "$WS_URL" --execute "$cmd" --wait "$timeout" 2>/dev/null | tr -d '\r\n' | grep -E '^<|^{' | sed 's/^< //g' | grep -E '^{"id":'"$cdp_seq"'(,|})')
  fi
  echo "$resp"
}

cdp_eval() {
  local expr="$1"
  local params
  params=$(jq -n -rc --arg expr "$expr" '{expression: $expr, returnByValue: true}')

  local resp
  resp=$(cdp_send "Runtime.evaluate" "$params")
  local exception ; exception=$(jq -rc '.result.exceptionDetails // empty' <<<"$resp" 2>/dev/null)
  if [[ -n $exception ]]; then
    local err_msg ; err_msg=$(jq -rc '.result.exceptionDetails.exception.description // "JavaScript exception"' <<<"$resp" 2>/dev/null)
    echo "ERROR:$err_msg"
    return 1
  fi

  # Return the value
  jq -rc '.result.result.value // empty' <<<"$resp" 2>/dev/null
}

# Inject console logging overrides
# shellcheck disable=SC2016
inject_console_logger() {
  local src='
    window.__captured_logs = window.__captured_logs || [];
    if (!window.__console_patched) {
      window.__console_patched = true;
      const patch = (type) => {
        const orig = console[type];
        console[type] = (...args) => {
          const text = args.map(arg => typeof arg === "object" ? JSON.stringify(arg) : String(arg)).join(" ");
          window.__captured_logs.push({type: type === "log" ? "log" : type === "warn" ? "warning" : "error", text: text});
          if (orig) orig.apply(console, args);
        };
      };
      patch("log");
      patch("warn");
      patch("error");
      window.onerror = (msg, url, line, col) => {
        window.__captured_logs.push({type: "error", text: `${msg} at ${url}:${line}:${col}`});
        return false;
      };
    }
  '
  cdp_eval "$src" >/dev/null
}

# Action: Navigate
action_navigate() {
  local url="$1"
  local wait_until="${2:-complete}"
  local timeout=2   # Default to 2s
  [[ -n $PROXY ]] && timeout=5   # Tor/SOCKS cold-start needs more headroom

  local resp ; resp=$(cdp_send "Page.navigate" "{\"url\":\"$url\"}" "$timeout")
  local frame_id ; frame_id=$(jq -rc '.result.frameId // empty' <<<"$resp" 2>/dev/null)
  if [[ -z $frame_id ]]; then
    echo "ERROR:Navigation failed"
    return 1
  fi

  # Wait for page readiness
  local readyState=""
  local retries=40
  if [[ $wait_until != "domcontentloaded" ]]; then
    for ((k=0; k<retries; k++)); do
      readyState=$(cdp_eval "document.readyState")
      if [[ $readyState == "complete" ]]; then
        break
      fi
      sleep 0.5
    done
  fi

  # Inject console logger immediately
  inject_console_logger

  return 0
}

# Action: Wait
action_wait() {
  local timeout="${1:-2000}"
  local selector="$2"

  if [[ -n $selector ]]; then
    # Wait for selector to exist in DOM
    local retries=$((timeout / 200))
    [[ $retries -eq 0 ]] && retries=1
    for ((k=0; k<retries; k++)); do
      local found ; found=$(cdp_eval "document.querySelector('$selector') !== null")
      if [[ $found == "true" ]]; then
        return 0
      fi
      sleep 0.2
    done
    echo "ERROR:Timeout waiting for selector: $selector"
    return 1
  else
    # Simple timeout sleep
    local sec=$((timeout / 1000))
    local ms=$((timeout % 1000))
    if [[ $ms -gt 0 ]]; then
      sleep "${sec}.${ms}" 2>/dev/null || sleep "$sec"
    else
      sleep "$sec"
    fi
    return 0
  fi
}

# Action: Click
action_click() {
  local selector="$1"

  local src="
    (function() {
      const el = document.querySelector('$selector');
      if (!el) return 'NOT_FOUND';
      el.scrollIntoView({ block: 'center', inline: 'center' });
      const rect = el.getBoundingClientRect();
      const evt = new MouseEvent('click', {
        clientX: rect.left + rect.width / 2,
        clientY: rect.top + rect.height / 2,
        bubbles: true,
        cancelable: true,
        view: window
      });
      el.dispatchEvent(evt);
      el.click();
      return 'SUCCESS';
    })()
  "
  local res ; res=$(cdp_eval "$src")
  if [[ $res == "NOT_FOUND" ]]; then
    echo "ERROR:Selector not found for click: $selector"
    return 1
  fi
  return 0
}

# Action: Type
action_type() {
  local selector="$1"
  local text="$2"

  local escaped_text ; escaped_text=$(jq -rc . <<<"$text")

  local src="
    (function() {
      const el = document.querySelector('$selector');
      if (!el) return 'NOT_FOUND';
      el.scrollIntoView({ block: 'center' });
      el.focus();
      const text = $escaped_text;
      el.value = ''; // clear first
      for (let i = 0; i < text.length; i++) {
        const char = text[i];
        el.value += char;
        el.dispatchEvent(new KeyboardEvent('keydown', { key: char, bubbles: true }));
        el.dispatchEvent(new KeyboardEvent('keypress', { key: char, bubbles: true }));
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new KeyboardEvent('keyup', { key: char, bubbles: true }));
      }
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return 'SUCCESS';
    })()
  "
  local res ; res=$(cdp_eval "$src")
  if [[ $res == "NOT_FOUND" ]]; then
    echo "ERROR:Selector not found for typing: $selector"
    return 1
  fi
  return 0
}

# Action: Press
action_press() {
  local key="$1"

  local src="
    (function() {
      const el = document.activeElement || document.body;
      const key = '$key';
      el.dispatchEvent(new KeyboardEvent('keydown', { key: key, bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keypress', { key: key, bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keyup', { key: key, bubbles: true }));
      return 'SUCCESS';
    })()
  "
  cdp_eval "$src" >/dev/null
  return 0
}

# Action: Screenshot
action_screenshot() {
  local path="$1"
  local full_page="${2:-false}"
  local timeout=15   # Increased default to 15s for Tor resilience (large base64 transmission)

  local params='{"format":"jpeg","quality":80}'
  [[ $full_page == "true" ]] && params='{"format":"jpeg","quality":80,"captureBeyondViewport":true}'

  local resp ; resp=$(cdp_send "Page.captureScreenshot" "$params" "$timeout")
  local base64_data ; base64_data=$(jq -rc '.result.data // empty' <<< "$resp" 2>/dev/null)

  if [[ -z $base64_data ]]; then
    echo "ERROR:Failed to create screenshot."
    return 1
  fi

  local dir ; dir=$(dirname "$path")
  mkdir -p "$dir" 2>/dev/null

  echo "$base64_data" | base64_decode > "$path"

  if [[ ! -r $path ]]; then
    echo "ERROR:Failed to write screenshot file: $path"
    return 1
  fi

  return 0
}

# Action: PDF
action_pdf() {
  local path="$1"
  local format="${2:-A4}"
  local timeout=15   # Increased default to 15s for Tor resilience (large base64 transmission)

  local params='{}'
  if [[ $format == "Letter" ]]; then
    params='{"paperWidth": 8.5, "paperHeight": 11}'
  elif [[ $format == "A4" ]]; then
    params='{"paperWidth": 8.27, "paperHeight": 11.69}'
  fi

  local resp ; resp=$(cdp_send "Page.printToPDF" "$params" "$timeout")
  local base64_data ; base64_data=$(jq -rc '.result.data // empty' <<< "$resp" 2>/dev/null)

  if [[ -z $base64_data ]]; then
    echo "ERROR:Failed to print PDF"
    return 1
  fi

  local dir ; dir=$(dirname "$path")
  mkdir -p "$dir" 2>/dev/null

  echo "$base64_data" | base64_decode > "$path"

  if [[ ! -r $path ]]; then
    echo "ERROR:Failed to write PDF file: $path"
    return 1
  fi

  return 0
}

# Action: Evaluate
action_evaluate() {
  local expression="$1"
  local val ; val=$(cdp_eval "$expression")
  if [[ $val == ERROR:* ]]; then
    echo "$val"
    return 1
  fi
  echo "$val"
  return 0
}

# Action: Scroll
action_scroll() {
  local direction="$1"
  local expr
  case $direction in
    bottom) expr="window.scrollTo(0, document.body.scrollHeight)" ;;
    top)    expr="window.scrollTo(0, 0)" ;;
    down)   expr="window.scrollBy(0, 500)" ;;
    up)     expr="window.scrollBy(0, -500)" ;;
    *)      expr="window.scrollBy(0, 500)" ;;
  esac
  cdp_eval "$expr" >/dev/null
  return 0
}

# Detect Chrome binary candidate paths
detect_chrome_binary() {
  local candidates=()
  if is_macos; then
    candidates=(
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      "/Applications/Chromium.app/Contents/MacOS/Chromium"
    )
  else
    candidates=(
      "/usr/bin/chromium"
      "/usr/bin/chromium-browser"
      "/usr/bin/google-chrome"
      "/usr/bin/google-chrome-stable"
      "/usr/bin/google-chrome-beta"
    )
  fi

  # Add binaries in path
  local path_binaries=(chromium chromium-browser google-chrome google-chrome-stable chrome)
  for pb in "${path_binaries[@]}"; do
    local resolved ; resolved=$(which "$pb" 2>/dev/null)
    [[ -n $resolved && -x $resolved ]] && candidates+=("$resolved")
  done

  for candidate in "${candidates[@]}"; do
    if [[ -n $candidate && -x $candidate ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Parse JSON input string or read from stdin/file
parse_input() {
  local raw_input="$1"
  if [[ -z $raw_input || $raw_input == "-" ]]; then
    raw_input=$(cat)
  elif [[ $raw_input == file://* ]]; then
    local file_path="${raw_input#file://}"
    if [[ -f $file_path ]]; then
      raw_input=$(cat "$file_path")
    else
      echo "{\"success\":false,\"error\":\"File not found: $file_path\"}" >&2
      exit 1
    fi
  fi

  # Parse out values
  URL=$(jq -rc '.url // empty' <<<"$raw_input")
  HEADLESS=$(jq -rc 'if has("headless") then .headless else "true" end' <<<"$raw_input")
  VIEWPORT_WIDTH=$(jq -rc '.viewport.width // 1280' <<<"$raw_input")
  VIEWPORT_HEIGHT=$(jq -rc '.viewport.height // 800' <<<"$raw_input")
  PROXY=$(jq -rc '.proxy // empty' <<<"$raw_input")
  USER_AGENT=$(jq -rc '.userAgent // empty' <<<"$raw_input")
  NO_TOR=$(jq -rc '.noTor // .no_tor // "false"' <<<"$raw_input")
  WAIT_UNTIL=$(jq -rc '.waitUntil // "complete"' <<<"$raw_input")
  SCREENSHOT_PATH_CONV=$(jq -rc '.screenshot_path // empty' <<<"$raw_input")

  # Actions array count
  ACTIONS_COUNT=$(jq '.actions | length' 2>/dev/null <<<"$raw_input")
  [[ -z $ACTIONS_COUNT || $ACTIONS_COUNT == "null" ]] && ACTIONS_COUNT=0
  RAW_ACTIONS="$raw_input"
}

main() {
  local ret_code_navigate ret_code_wait ret_code_click ret_code_type ret_code_press
  local ret_code_screenshot ret_code_pdf ret_code_evaluate ret_code_scroll

  # Parse standard inputs
  parse_input "$1"

  if [[ -z $URL ]]; then
    echo "{\"success\":false,\"error\":\"Missing target URL in payload\"}"
    exit 1
  fi

  # Create ephemeral profile directory
  USER_DATA_DIR=$(mktemp -d "/tmp/web-browse-XXXXXX")
  DEBUG_PORT=9222

  # Check and resolve port collision dynamically
  for ((port=9222; port<9300; port++)); do
    if ! curl -s --noproxy "*" "http://localhost:${port}/json/version" &>/dev/null; then
      DEBUG_PORT=$port
      break
    fi
  done

  # Setup Chrome process arguments
  local browser_bin ; browser_bin=$(detect_chrome_binary)
  if [[ -z $browser_bin ]]; then
    echo "{\"success\":false,\"error\":\"Could not locate any valid Chrome/Chromium installation\"}" >&2
    exit 1
  fi

  local args=(
    "--user-data-dir=$USER_DATA_DIR"
    "--remote-debugging-port=$DEBUG_PORT"
    "--no-first-run"
    "--no-default-browser-check"
    "--disable-background-timer-throttling"
    "--disable-backgrounding-occluded-windows"
    "--disable-renderer-backgrounding"
  )

  [[ -d "/data/data/com.termux" ]] && args+=("--no-sandbox" "--disable-setuid-sandbox" "--disable-gpu" "--disable-dev-shm-usage")
  [[ $HEADLESS == "true" ]] && args+=("--headless=new")

  # Apply SOCKS5 proxy (defaults to Tor on 127.0.0.1:9050 if enabled and empty proxy parameter is passed)
  [[ $NO_TOR == "false" && -z $PROXY ]] && PROXY="socks5://127.0.0.1:9050"
  [[ $PROXY == "null" || $PROXY == "false" ]] && PROXY=""

  if [[ -n $PROXY ]]; then
    args+=("--proxy-server=$PROXY")
    args+=("--proxy-bypass-list=<-loopback>")
  fi

  [[ -n $USER_AGENT ]] && args+=("--user-agent=$USER_AGENT")

  args+=("--window-size=${VIEWPORT_WIDTH},${VIEWPORT_HEIGHT}")
  args+=("about:blank")

  # Launch Chrome process in background
  "$browser_bin" "${args[@]}" 2>/dev/null &
  BROWSER_PID=$!

  # Wait for remote debugging to be fully operational
  local ready=false
  for ((retry=0; retry<30; retry++)); do
    if curl -s --noproxy "*" "http://localhost:${DEBUG_PORT}/json/version" &>/dev/null; then
      ready=true
      break
    fi
    sleep 0.2
  done

  if [[ $ready == "false" ]]; then
    echo "{\"success\":false,\"error\":\"Failed to initialize remote debugger connection on port $DEBUG_PORT\"}" >&2
    exit 1
  fi
  WS_URL=$(curl -s --noproxy "*" "http://localhost:${DEBUG_PORT}/json" | jq -rc '.[] | select(.type == "page") | .webSocketDebuggerUrl' | head -n 1)
  if [[ -z $WS_URL ]]; then
    echo "{\"success\":false,\"error\":\"No active page targets returned by remote debugger\"}" >&2
    exit 1
  fi

  # Initialize connection domains
  cdp_send "Page.enable" >/dev/null
  cdp_send "Runtime.enable" >/dev/null

  # Execute initial navigation
  action_navigate "$URL" "$WAIT_UNTIL"
  ret_code_navigate=$?
  if [[ $ret_code_navigate -ne 0 ]]; then
    SUCCESS="false"
    ERROR_MSG="Initial navigation to $URL failed"
  else
    PAGE_TITLE=$(cdp_eval "document.title")
    PAGE_URL=$(cdp_eval "window.location.href")
  fi

  # Iterate and execute payload actions sequentially
  if [[ $SUCCESS == "true" ]]; then
    for ((i=0; i<ACTIONS_COUNT; i++)); do
      local type ; type=$(jq -rc ".actions[$i].type // empty" <<<"$RAW_ACTIONS")
      local selector ; selector=$(jq -rc ".actions[$i].selector // empty" <<<"$RAW_ACTIONS")
      local text ; text=$(jq -rc ".actions[$i].text // empty" <<<"$RAW_ACTIONS")
      local key ; key=$(jq -rc ".actions[$i].key // empty" <<<"$RAW_ACTIONS")
      local timeout ; timeout=$(jq -rc ".actions[$i].timeout // empty" <<<"$RAW_ACTIONS")
      local path ; path=$(jq -rc ".actions[$i].path // empty" <<<"$RAW_ACTIONS")
      local fullPage ; fullPage=$(jq -rc ".actions[$i].fullPage // false" <<<"$RAW_ACTIONS")
      local expression ; expression=$(jq -rc ".actions[$i].expression // empty" <<<"$RAW_ACTIONS")
      local direction ; direction=$(jq -rc ".actions[$i].direction // empty" <<<"$RAW_ACTIONS")

      case $type in
        navigate)
          action_navigate "$text" "$WAIT_UNTIL"
          ret_code_navigate=$?
          if [[ $ret_code_navigate -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action navigate to $text failed" ; break
          fi
          PAGE_URL=$(cdp_eval "window.location.href")
        ;;
        wait)
          action_wait "$timeout" "$selector"
          ret_code_wait=$?
          if [[ $ret_code_wait -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action wait failed: selector=$selector" ; break
          fi
        ;;
        click)
          action_click "$selector"
          ret_code_click=$?
          if [[ $ret_code_click -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action click failed on selector: $selector" ; break
          fi
        ;;
        type)
          action_type "$selector" "$text"
          ret_code_type=$?
          if [[ $ret_code_type -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action type failed on selector: $selector" ; break
          fi
        ;;
        press)
          action_press "$key"
          ret_code_press=$?
          if [[ $ret_code_press -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action press failed: $key" ; break
          fi
        ;;
        screenshot)
          action_screenshot "$path" "$fullPage"
          ret_code_screenshot=$?
          if [[ $ret_code_screenshot -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action screenshot failed: $path" ; break
          fi
          SCREENSHOT_PATHS+=("$path")
        ;;
        pdf)
          action_pdf "$path" "Letter"
          ret_code_pdf=$?
          if [[ $ret_code_pdf -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action pdf failed: $path" ; break
          fi
        ;;
        evaluate)
          local res ; res=$(action_evaluate "$expression") ; ret_code_evaluate=$?
          if [[ $ret_code_evaluate -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action evaluate failed: $expression" ; break
          fi
          EVAL_RESULTS+=("$res")
        ;;
        scroll)
          action_scroll "$direction"
          ret_code_scroll=$?
          if [[ $ret_code_scroll -ne 0 ]]; then
            SUCCESS="false" ; ERROR_MSG="Action scroll failed: $direction" ; break
          fi
        ;;
        *)
          SUCCESS="false" ; ERROR_MSG="Unknown action type: $type" ; break
        ;;
      esac
    done
  fi

  # Execute screenshot_path convenience action if defined at the top-level
  if [[ $SUCCESS == "true" && -n "$SCREENSHOT_PATH_CONV" ]]; then
    action_screenshot "$SCREENSHOT_PATH_CONV" "true"
    ret_code_screenshot=$?
    if [[ $ret_code_screenshot -eq 0 ]]; then
      SCREENSHOT_PATHS+=("$SCREENSHOT_PATH_CONV")
    else
      SUCCESS="false" ; ERROR_MSG="Screenshot path convenience capture failed"
    fi
  fi

  # Retrieve captured logs
  local raw_logs ; raw_logs=$(cdp_send "Runtime.evaluate" '{"expression":"window.__captured_logs","returnByValue":true}')
  local console_logs ; console_logs=$(jq -rc '.result.result.value // []' <<<"$raw_logs" 2>/dev/null)
  [[ $console_logs == "null" || -z $console_logs ]] && console_logs="[]"

  # Update final metadata titles
  if [[ $SUCCESS == "true" ]]; then
    PAGE_TITLE=$(cdp_eval "document.title")
    PAGE_URL=$(cdp_eval "window.location.href")
  fi

  # Format screenshots telemetry array
  local screenshot_json="[]"
  for idx in "${!SCREENSHOT_PATHS[@]}"; do
    local p="${SCREENSHOT_PATHS[$idx]}"
    screenshot_json=$(jq --arg path "$p" --argjson idx "$idx" '. + [{"index": $idx, "path": $path}]' <<<"$screenshot_json")
  done

  # Format evaluate results telemetry array
  local eval_json="[]"
  for idx in "${!EVAL_RESULTS[@]}"; do
    local r="${EVAL_RESULTS[$idx]}"
    eval_json=$(jq --arg res "$r" --argjson idx "$idx" '. + [{"index": $idx, "result": $res}]' <<<"$eval_json")
  done

  # Output unified standard JSON telemetry block
  jq -n \
    --argjson success "$SUCCESS" \
    --arg title "$PAGE_TITLE" \
    --arg url "$PAGE_URL" \
    --argjson consoleLogs "$console_logs" \
    --argjson evaluateResults "$eval_json" \
    --argjson screenshots "$screenshot_json" \
    --arg error "$ERROR_MSG" \
    '{
      success: $success,
      title: $title,
      url: $url,
      consoleLogs: $consoleLogs,
      evaluateResults: $evaluateResults,
      screenshots: $screenshots,
      error: (if $error == "" then null else $error end)
    }'

  [[ $SUCCESS == "false" ]] && exit 1
  exit 0
}

# Logging
echo -e "\n---\n\nDate: $(date '+%Y-%m-%d %H:%M:%S')\nArguments: $*" >> "$LOG_FILE"

main "$@"
