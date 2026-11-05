#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2001,SC2016
# ==============================================================================
# tools/web-browse.sh — Stateless Chrome DevTools Protocol browser driver
# ==============================================================================
# Drives Chromium-based browsers through direct CDP WebSocket calls on desktop,
# or mobile devices through ADB forwarding on Termux. No Node.js or Puppeteer.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.1.2
# ==============================================================================

# Options
[[ -e $HOME/.debug ]] && set -x

# Config
TOR_HOST="127.0.0.1"
TOR_PORT=9050
TOR_PROXY="socks5://${TOR_HOST}:${TOR_PORT}"
TOR_PROXY_MOBILE="socks4a://${TOR_HOST}:${TOR_PORT}"

# Global state variables
WS_URL=""
BROWSER_PID=""
BROWSER_BIN=""
USER_DATA_DIR=""
DEBUG_PORT=9222
cdp_seq=0
SUCCESS="true"
ERROR_MSG=""
PAGE_TITLE=""
PAGE_URL=""
SCREENSHOT_PATHS=()
EVAL_RESULTS=()
WS_CLIENT=""

# Internals
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
LIB_DIR="${AIDE_LIB_DIR:-${PROJECT_ROOT}/lib}"
LIB_DEPS=("base64")
LOG_FILE="${SCRIPT_NAME}.log"

# Runtime mode flags
LOCAL_CHROME=false
LAUNCH_MODE="fullscreen"
ADB_MODE=false
ADB_CLEANUP=false

# Log and exit helper
die() {
  echo -e "[ERROR] $*" >&2
  exit 255
}
leave() {
  echo "[ERROR] $*"
  return 1
}

# Helper: Detect OS
is_macos() {
  [[ $OSTYPE == "darwin"* ]]
}

# Helper: Detect Termux
is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] && return 0
  [[ -d "/data/data/com.termux" ]] && return 0
  return 1
}

# Load required libraries
load_libs() {
  local total_libs=0
  local found_libs=0
  local missing_libs=0
  local missing_libs_str=""
  total_libs="${#LIB_DEPS[@]}"
  for d in "${LIB_DEPS[@]}"; do
    if [[ -r "${LIB_DIR}/${d}.sh" && -s "${LIB_DIR}/${d}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${LIB_DIR}/${d}.sh" || die "Failed to load '$d' library."
      ((found_libs++))
    else
      [[ $missing_libs -ne 0 ]] && missing_libs_str+=", "
      missing_libs_str+="$d"
      ((missing_libs++))
    fi
  done
  if [[ $found_libs -ne $total_libs ]]; then
    die "Missing libraries: $missing_libs_str"
  fi
}

# -----------------------------------------------------------------------------
# Portability helpers (stock macOS / BSD differences)
# -----------------------------------------------------------------------------
load_libs

# -----------------------------------------------------------------------------
# Shared Base64 compatibility layer (GNU / BSD)
# -----------------------------------------------------------------------------
# _WB_LIB_DIR="${AIDE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# if [[ ! -r "${_WB_LIB_DIR}/base64.sh" ]]; then
#   echo "[ERROR] base64.sh not found in ${_WB_LIB_DIR} (set AIDE_LIB_DIR=<dir> to override)" >&2
#   exit 1
# fi
# # shellcheck source=/dev/null
# source "${_WB_LIB_DIR}/base64.sh" || exit 1
# unset _WB_LIB_DIR

# ── E2BIG-safe jq plumbing ────────────────────────────────────────────────────
# On Linux a SINGLE argument (argv) or environment variable is capped at
# 131 072 bytes (MAX_ARG_STRLEN). Past that, execve() fails with E2BIG: the
# command is NEVER launched and whatever consumed its output becomes EMPTY.
# jq's --arg/--argjson are exactly that trap: a > 128 KB page payload (console
# logs, evaluate result) silently produced an empty telemetry block instead of
# failing loudly. ⇒ Page content now travels by STDIN. bash builtins (printf)
# are in-process and therefore exempt; only external binaries pay the argv limit.

# JSON-encode a shell string without ever putting it in argv.
json_quote() {
  printf '%s' "$1" | jq -Rs '.'
}

# Assemble the standard telemetry block. Parameters are bash positional
# parameters (in-process: exempt from the argv limit); jq reads them by STDIN.
json_block() {
  local success="$1" logs="$2" results="$3" shots="$4" title="$5" url="$6" error="$7"
  {
    printf '%s\n' "$success" "$logs" "$results" "$shots"
    json_quote "$title"
    json_quote "$url"
    json_quote "$error"
  } | jq -cs '{
      success: .[0],
      consoleLogs: .[1],
      evaluateResults: .[2],
      screenshots: .[3],
      title: .[4],
      url: .[5],
      error: (if .[6] == "" then null else .[6] end)
    }'
}

# Guarantee a valid JSON document before jq consumes it (empty/garbage → default).
json_ok() {
  if [[ -n $1 ]] && jq -e . >/dev/null 2>&1 <<<"$1"; then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

# Cleanup on exit
# shellcheck disable=SC2329
cleanup() {
  # Desktop mode: kill the local browser process and remove its temp profile
  if [[ -n $BROWSER_PID ]]; then
    kill "$BROWSER_PID" 2>/dev/null
    local i
    for ((i=0; i<20; i++)); do
      kill -0 "$BROWSER_PID" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 "$BROWSER_PID" 2>/dev/null
    wait "$BROWSER_PID" 2>/dev/null
  fi
  [[ -n "${USER_DATA_DIR:-}" && -d $USER_DATA_DIR ]] && rm -rf "$USER_DATA_DIR" 2>/dev/null

  # Mobile mode: the ADB forward is idempotent and persistent; removing it is
  # opt-in (--cleanup-adb) so that consecutive runs are near-instant (<200ms).
  if is_termux && [[ -n $ADB_CLEANUP && $ADB_CLEANUP == true ]]; then
    # Restore default settings
    adb shell settings delete global enable_freeform_support
    adb shell settings delete secure force_resizable_activities

    # Remove forwarding
    adb forward --remove tcp:"${DEBUG_PORT:-9222}" 2>/dev/null

    # Kill adb server
    adb kill-server
  fi
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
  params=$(printf '%s' "$expr" | jq -Rs -c '{expression: ., returnByValue: true}')

  local resp
  resp=$(cdp_send "Runtime.evaluate" "$params")
  local exception ; exception=$(jq -rc '.result.exceptionDetails // empty' <<<"$resp" 2>/dev/null)
  if [[ -n $exception ]]; then
    local err_msg ; err_msg=$(jq -rc '.result.exceptionDetails.exception.description // "JavaScript exception"' <<<"$resp" 2>/dev/null)
    leave "$err_msg"
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
    leave "Navigation failed"
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
    local escaped_selector ; escaped_selector="${selector//\\/\\\\}"
    escaped_selector="${escaped_selector//\'/\\\'}"
    escaped_selector=$(sed 's/`/\\`/g' <<< "$escaped_selector")
    for ((k=0; k<retries; k++)); do
      local found ; found=$(cdp_eval "document.querySelector('$escaped_selector') !== null")
      if [[ $found == "true" ]]; then
        return 0
      fi
      sleep 0.2
    done
    leave "Timeout waiting for selector: $selector"
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

  local escaped_selector ; escaped_selector="${selector//\\/\\\\}"
  escaped_selector="${escaped_selector//\'/\\\'}"
  escaped_selector=$(sed 's/`/\\`/g' <<< "$escaped_selector")

  local src="
    (function() {
      const el = document.querySelector('$escaped_selector');
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
    leave "Selector not found for click: $selector"
  fi
  return 0
}

# Action: Type
action_type() {
  local selector="$1"
  local text="$2"

  local escaped_text ; escaped_text=$(jq -rc . <<<"$text")

  local escaped_selector ; escaped_selector="${selector//\\/\\\\}"
  escaped_selector="${escaped_selector//\'/\\\'}"
  escaped_selector=$(sed 's/`/\\`/g' <<< "$escaped_selector")

  local src="
    (function() {
      const el = document.querySelector('$escaped_selector');
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
    leave "Selector not found for typing: $selector"
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

  # Encoding derived from the target filename: Page.captureScreenshot accepts jpeg, png, webp
  # (protocol default is png). Unknown or missing extension keeps the legacy jpeg output.
  # NOTE: "quality" is jpeg-only per the protocol spec, so it is never sent for png/webp.
  local fmt
  case "${path##*.}" in
    [Pp][Nn][Gg])         fmt="png"  ;;
    [Ww][Ee][Bb][Pp])     fmt="webp" ;;
    *)                    fmt="jpeg" ;;
  esac

  local params
  params=$(jq -nc --arg f "$fmt" --arg fp "$full_page" '
    {format: $f}
    + (if $f == "jpeg" then {quality: 80} else {} end)
    + (if $fp == "true" then {captureBeyondViewport: true} else {} end)')

  if [[ -z $params ]]; then
    echo "[ERROR] Failed to build screenshot parameters."
    return 1
  fi

  local resp ; resp=$(cdp_send "Page.captureScreenshot" "$params" "$timeout")
  local base64_data ; base64_data=$(jq -rc '.result.data // empty' <<< "$resp" 2>/dev/null)

  if [[ -z $base64_data ]]; then
    leave "Failed to create screenshot."
  fi

  local dir ; dir=$(dirname "$path")
  mkdir -p "$dir" 2>/dev/null

  echo "$base64_data" | b64d > "$path"

  if [[ ! -r $path ]]; then
    leave "Failed to write screenshot file: $path"
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
    leave "Failed to print PDF"
  fi

  local dir ; dir=$(dirname "$path")
  mkdir -p "$dir" 2>/dev/null

  echo "$base64_data" | b64d > "$path"

  if [[ ! -r $path ]]; then
    leave "Failed to write PDF file: $path"
  fi

  return 0
}

# Action: Evaluate
action_evaluate() {
  local expression="$1"
  local val ; val=$(cdp_eval "$expression")
  if [[ $val == "[ERROR]"* ]]; then
    leave "$val"
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
  local -a candidates ; candidates=()

  # Override browser detection when necessary
  if [[ -n ${BROWSER_BIN:-} ]]; then
    local resolved ; resolved=$(command -v "$BROWSER_BIN" 2>/dev/null)
    if [[ -z $resolved || ! -x $resolved ]]; then
      leave "Invalid browser override: $BROWSER_BIN (not found or not executable)"
    fi
    echo "$resolved"
    return 0
  fi

  if is_macos; then
    candidates=(
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      "/Applications/Chromium.app/Contents/MacOS/Chromium"
      "/Applications/Brave.app/Contents/MacOS/Brave"
    )
  else
    candidates=(
      "/usr/bin/chromium"
      "/usr/bin/chromium-browser"
      "/usr/bin/google-chrome"
      "/usr/bin/google-chrome-stable"
      "/usr/bin/google-chrome-beta"
      "/usr/bin/brave"
      "/usr/bin/brave-browser"
      "/usr/bin/brave-browser-stable"
    )
  fi

  # Add binaries in path
  local -a path_binaries ; path_binaries=(brave brave-browser brave-browser-stable chromium chromium-browser google-chrome google-chrome-stable chrome)
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

# -----------------------------------------------------------------------------
# ADB / MOBILE MODE (duplicated from shizuku research, without Shizuku)
# -----------------------------------------------------------------------------

# Ensure the device is reachable via ADB (wireless debugging auto-detect).
ensure_adb_connected() {
  # If already connected on localhost, skip the (slow) port scan.
  if adb devices 2>/dev/null | grep -q "localhost:"; then
    echo "[ADB] Already connected to device." >&2
    return 0
  fi

  # Reset the ADB server once to guarantee a clean state (mirrors start-shizuku.sh).
  echo "[ADB] Resetting ADB server..." >&2
  adb kill-server &>/dev/null
  adb start-server &>/dev/null
  sleep 1

  if adb devices 2>/dev/null | grep -q "localhost:"; then
    echo "[ADB] Already connected to device." >&2
    return 0
  fi

  echo "[ADB] Detecting wireless debugging port (nmap scan)..." >&2
  local found_port
  found_port=$(nmap -v0 127.0.0.1 -T5 -p30000-65535 -oX - 2>/dev/null \
    | grep -m1 'state="open"' | grep -m1 "<port " | cut -d'"' -f4)

  if [[ -n $found_port ]]; then
    echo "[ADB] Connecting on localhost:${found_port}..." >&2
    adb connect "localhost:${found_port}" &>/dev/null
  else
    echo "{\"success\":false,\"error\":\"Wireless debugging not enabled or port not found\"}" >&2
    return 1
  fi

  if adb devices 2>/dev/null | grep -q "localhost:"; then
    return 0
  fi

  echo "{\"success\":false,\"error\":\"Failed to connect to device via ADB\"}" >&2
  return 1
}

# Open a dedicated, non-intrusive tab and return its websocket debugger URL.
create_new_tab() {
  local start_url="${1:-about:blank}"
  local params ; params=$(printf '%s' "$start_url" | jq -Rs -c '{url: .}')
  local resp ; resp=$(cdp_send "Target.createTarget" "$params" 2>/dev/null)
  local target_id ; target_id=$(jq -rc '.result.targetId // empty' <<<"$resp" 2>/dev/null)
  if [[ -z $target_id ]]; then
    echo ""
    return 1
  fi

  local new_ws
  # NB: $target_id is a CDP target id (bounded hex string) — a justified --arg,
  # unlike page content, which must go through json_quote()/json_block().
  new_ws=$(curl -s --noproxy "*" "http://localhost:${DEBUG_PORT}/json" \
    | jq -rc --arg tid "$target_id" '.[] | select(.type=="page" and .id==$tid) | .webSocketDebuggerUrl' \
    | head -n 1)

  if [[ -z $new_ws ]]; then
    # Fallback: grab the most recently added page target.
    new_ws=$(curl -s --noproxy "*" "http://localhost:${DEBUG_PORT}/json" \
      | jq -rc '.[] | select(.type=="page") | .webSocketDebuggerUrl' | tail -n 1)
  fi

  echo "$new_ws"
}

# Initialize the mobile (Android / Termux) browser session via ADB.
init_android_browser() {
  ensure_adb_connected || exit 1

  local launched=false
  local target_pkg window_mode
  local -a known_browsers ; known_browsers=("org.cromite.cromite" "com.android.chrome" "com.brave.browser" "com.kiwi_browser.browser")

  # When changing launch mode, kill any existing instance to avoid reusing
  # a fullscreen browser for a freeform launch (or vice-versa).
  if [[ ! $LAUNCH_MODE == "fullscreen" ]]; then
    echo "[CDP] Launch mode '$LAUNCH_MODE' — killing any existing browser instance..." >&2
    for browser in "${known_browsers[@]}"; do
      adb shell am force-stop "$browser" 2>/dev/null
    done
  fi

  if adb shell cat /proc/net/unix 2>/dev/null | grep -q "chrome_devtools_remote"; then
    echo "[CDP] Active Chrome DevTools socket detected. Reusing existing browser." >&2
  else
    echo "[CDP] No active socket. Detecting Chromium based browser..." >&2
    for pkg in "${known_browsers[@]}"; do
      if adb shell pm list packages 2>/dev/null | grep -q "$pkg"; then
        target_pkg="$pkg"
        break
      fi
    done

    if [[ -z $target_pkg ]]; then
      echo "{\"success\":false,\"error\":\"No compatible Chromium based browser found on device.\"}" >&2
      exit 1
    fi

    echo "[CDP] Launching $target_pkg..." >&2

    # Check defined launch mode
    case $LAUNCH_MODE in
      fullscreen)
        # Universal Intent launch: no hardcoded Activity name required.
        adb shell am start -a android.intent.action.VIEW -d "about:blank" -p "$target_pkg" &>/dev/null
      ;;
      freeform)
        # Set required settings for controlling browser window position
        adb shell settings put global enable_freeform_support 1
        adb shell settings put secure force_resizable_activities 1

        # Set required window mode
        # - Freeform + Movable = 5 (Works with '-p' and '-n')
        # - Freeform + Fixed = 4 (works only with '-n' because it requires exact activity name)
        #
        # For compatibility reason, only mode 5 will be supported because I don't want to pass
        # my time at finding and testing each specific activity can be used for each supported browsers.
        window_mode=5

        # Start browser in freeform mode (movable, not fixed)
        adb shell am start \
          -a android.intent.action.VIEW \
          -d "about:blank" \
          -p "$target_pkg" \
          --el com.samsung.android.sdk.multiwindow.extra.LAUNCH_BOUNDS_LEFT 200 \
          --el com.samsung.android.sdk.multiwindow.extra.LAUNCH_BOUNDS_TOP 300 \
          --el com.samsung.android.sdk.multiwindow.extra.LAUNCH_BOUNDS_RIGHT 880 \
          --el com.samsung.android.sdk.multiwindow.extra.LAUNCH_BOUNDS_BOTTOM 1500 \
          --windowingMode $window_mode &>/dev/null
      ;;
    esac

    launched=true

    # Poll the kernel socket instead of a fixed sleep (robust on slow devices).
    local ready=false
    for ((i=0; i<30; i++)); do
      if adb shell cat /proc/net/unix 2>/dev/null | grep -q "chrome_devtools_remote"; then
        ready=true
        break
      fi
      sleep 0.2
    done
    if [[ $ready == false ]]; then
      echo "{\"success\":false,\"error\":\"Chrome DevTools socket did not appear after launch\"}" >&2
      exit 1
    fi
  fi

  echo "[CDP] Forwarding tcp:${DEBUG_PORT} -> localabstract:chrome_devtools_remote" >&2
  adb forward tcp:"${DEBUG_PORT}" "localabstract:chrome_devtools_remote" &>/dev/null

  # Wait for the remote debugging endpoint to be fully operational.
  local ready=false
  for ((retry=0; retry<15; retry++)); do
    if curl -s --noproxy "*" "http://localhost:${DEBUG_PORT}/json/version" &>/dev/null; then
      ready=true
      break
    fi
    sleep 0.2
  done
  if [[ $ready == false ]]; then
    echo "{\"success\":false,\"error\":\"Failed to reach Chrome DevTools on port $DEBUG_PORT\"}" >&2
    exit 1
  fi

  # Pick a page target websocket (first available).
  WS_URL=$(curl -s --noproxy "*" "http://localhost:${DEBUG_PORT}/json" \
    | jq -rc '.[] | select(.type == "page") | .webSocketDebuggerUrl' | head -n 1)
  if [[ -z $WS_URL ]]; then
    echo "{\"success\":false,\"error\":\"No active page targets returned by remote debugger\"}" >&2
    exit 1
  fi

  # If we reused an existing browser, open a clean tab so we don't hijack the
  # user's currently active tab.
  if [[ $launched == false ]]; then
    echo "[CDP] Opening a dedicated tab to avoid hijacking the active one..." >&2
    local new_ws ; new_ws=$(create_new_tab "$URL")
    if [[ -n $new_ws ]]; then
      WS_URL="$new_ws"
    else
      echo "[CDP] Warning: could not open a dedicated tab; using the active page target." >&2
    fi
  fi

  # Apply proxy (Tor by default). In mobile mode the browser is already running,
  # so we set it via CDP instead of a launch flag. The device Chrome reaches
  # Termux's Tor on the shared device loopback (127.0.0.1:9050).
  if [[ $NO_TOR == "false" && -z $PROXY ]]; then
    PROXY="$TOR_PROXY_MOBILE"
  fi
  [[ $PROXY == "null" || $PROXY == "false" ]] && PROXY=""
  if [[ -n $PROXY ]]; then
    cdp_send "Network.enable" &>/dev/null
    cdp_send "Network.setProxy" "{\"proxy\":\"$PROXY\"}" &>/dev/null
    echo "[CDP] Proxy set to $PROXY" >&2
  fi
}

# -----------------------------------------------------------------------------
# DESKTOP MODE (unchanged engine, extracted from the original main())
# -----------------------------------------------------------------------------

# Initialize the desktop (local Chromium) browser session.
init_desktop_browser() {
  # Create ephemeral profile directory
  USER_DATA_DIR=$(mktemp -d "/tmp/web-browse-XXXXXX")

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

  local -a args ; args=(
    "--user-data-dir=$USER_DATA_DIR"
    "--remote-debugging-port=$DEBUG_PORT"
    "--no-first-run"
    "--no-default-browser-check"
    "--password-store=basic"
    "--use-mock-keychain"
    "--disable-background-timer-throttling"
    "--disable-backgrounding-occluded-windows"
    "--disable-renderer-backgrounding"
  )

  is_termux && args+=("--no-sandbox" "--disable-setuid-sandbox" "--disable-gpu" "--disable-dev-shm-usage")
  [[ $HEADLESS == "true" ]] && args+=("--headless=new")

  # Apply SOCKS5 proxy (defaults to Tor on 127.0.0.1:9050 if enabled and empty proxy parameter is passed)
  [[ $NO_TOR == "false" && -z $PROXY ]] && PROXY="$TOR_PROXY"
  [[ $PROXY == "null" || $PROXY == "false" ]] && PROXY=""

  if [[ -n $PROXY ]]; then
    args+=("--proxy-server=$PROXY")
    args+=("--proxy-bypass-list=<-loopback>")
  fi

  # Fix Tor proxy DNS leak warning
  [[ $PROXY == socks5* ]] && args+=("--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1")

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
}

# Parse Options
NO_TOR=false
HEADLESS=true
URL=""
PROXY=""
USER_AGENT=""
SCREENSHOT_PATH_CONV=""
WAIT_UNTIL="complete"

# Parse given arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        echo "Usage: $SCRIPT_NAME [options]"
        echo "Options:"
        echo "  -h, --help                            Print this message and exit"
        echo "  -u, --url                             Set target URL"
        echo "  -p, --proxy <url>                     Set proxy URL"
        echo "  --screenshot <path>                   Save screenshot to given path"
        echo "  --viewport <WxH>                      Viewport Width x Height"
        echo "  --headless <true|false>               Headless mode"
        echo "  --browser <name|path>                 Override browser detection"
        echo "  --no-tor                              Disabled Tor proxy"
        echo "  --adb                                 Enable ADB mode"
        echo "  --cleanup-adb                         Cleanup ADB when exit"
        echo "  --local-chrome                        Use local chromium based browser"
        echo "  --launch-mode <fullscreen|freeform>   Set browser launch mode on mobile"
        exit 0
      ;;
      -u|--url) URL="$2" ; shift 2 ;;
      -p|--proxy) PROXY="$2" ; shift 2 ;;
      --viewport)
        VIEWPORT_WIDTH=$(cut -d "x" -f1 <<< "$2")
        VIEWPORT_HEIGHT=$(cut -d "x" -f2 <<< "$2")
        [[ -z $VIEWPORT_WIDTH ]] && VIEWPORT_WIDTH=1280
        [[ -z $VIEWPORT_HEIGHT ]] && VIEWPORT_HEIGHT=800
        shift 2
      ;;
      --screenshot) SCREENSHOT_PATH_CONV="$2" ; shift 2 ;;
      --headless) HEADLESS="${2:-true}" ; shift 2 ;;
      --browser) BROWSER_BIN="$2" ; shift 2 ;;
      --no-tor) NO_TOR=true ; shift ;;
      --adb) ADB_MODE=true ;;
      --local-chrome) LOCAL_CHROME=true ;;
      --cleanup-adb) ADB_CLEANUP=true ;;
      --launch-mode) LAUNCH_MODE="$2" ; shift 2 ;;
      *)
        # Parse standard inputs
        parse_input "$1" ; shift
      ;;
    esac
  done
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
  BROWSER_BIN=$(jq -rc '.browser // empty' <<<"$raw_input")
  VIEWPORT_WIDTH=$(jq -rc '.viewport.width // 1280' <<<"$raw_input")
  VIEWPORT_HEIGHT=$(jq -rc '.viewport.height // 800' <<<"$raw_input")
  PROXY=$(jq -rc '.proxy // empty' <<<"$raw_input")
  USER_AGENT=$(jq -rc '.userAgent // empty' <<<"$raw_input")
  NO_TOR=$(jq -rc '.noTor // .no_tor // "false"' <<<"$raw_input")
  WAIT_UNTIL=$(jq -rc '.waitUntil // "complete"' <<<"$raw_input")
  SCREENSHOT_PATH_CONV=$(jq -rc '.screenshot_path // empty' <<<"$raw_input")

  # Mode overrides coming from the JSON payload (CLI flags take precedence).
  LOCAL_CHROME_JSON=$(jq -rc '.localChrome // false' <<<"$raw_input")
  ADB_MODE_JSON=$(jq -rc '.android // false' <<<"$raw_input")
  LAUNCH_MODE=$(jq -rc '.launch_mode // "fullscreen"' <<<"$raw_input")
  [[ $LOCAL_CHROME_JSON == "true" ]] && LOCAL_CHROME=true
  [[ $ADB_MODE_JSON == "true" ]] && ADB_MODE=true

  # Actions array count
  ACTIONS_COUNT=$(jq '.actions | length' 2>/dev/null <<<"$raw_input")
  [[ -z $ACTIONS_COUNT || $ACTIONS_COUNT == "null" ]] && ACTIONS_COUNT=0
  RAW_ACTIONS="$raw_input"
}

main() {
  local ret_code_navigate ret_code_wait ret_code_click ret_code_type ret_code_press
  local ret_code_screenshot ret_code_pdf ret_code_evaluate ret_code_scroll

  # Parse given arguments
  parse_args "$@"

  if [[ -z $URL ]]; then
    echo "{\"success\":false,\"error\":\"Missing target URL in payload\"}"
    exit 1
  fi

  # ============================================================================
  # INITIALIZATION & BROWSER SPAWNING (hybrid routing)
  # ============================================================================
  local ANDROID_MODE=false
  if is_termux && [[ $LOCAL_CHROME != "true" ]]; then
    ANDROID_MODE=true
  fi
  [[ $ADB_MODE == "true" ]] && ANDROID_MODE=true

  if [[ $ANDROID_MODE == true ]]; then
    init_android_browser
  else
    init_desktop_browser
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
  # (--arg path is fine here: a filesystem path is bounded by PATH_MAX = 4 096 bytes
  #  and can never reach MAX_ARG_STRLEN; only $idx and a path travel in argv.)
  local screenshot_json="[]"
  for idx in "${!SCREENSHOT_PATHS[@]}"; do
    local p="${SCREENSHOT_PATHS[$idx]}"
    screenshot_json=$(jq -c --arg path "$p" --argjson idx "$idx" '. + [{"index": $idx, "path": $path}]' <<<"$screenshot_json")
  done

  # Format evaluate results telemetry array
  # E2BIG-safe (2026-09-12): the running array AND the raw result reach jq by STDIN
  # ("-s" slurps both documents), so a > 128 KB evaluate result can never hit argv.
  local eval_json="[]"
  for idx in "${!EVAL_RESULTS[@]}"; do
    local r="${EVAL_RESULTS[$idx]}"
    eval_json=$(
      {
        printf '%s\n' "$eval_json"
        json_quote "$r"
      } | jq -cs --argjson idx "$idx" '.[0] + [{"index": $idx, "result": .[1]}]'
    )
  done

  # Guard: a malformed payload would make the WHOLE block fail (jq exits non-zero →
  # empty stdout = the very silent failure this fix removes). Never assemble blind.
  console_logs=$(json_ok "$console_logs" "[]")
  eval_json=$(json_ok "$eval_json" "[]")
  screenshot_json=$(json_ok "$screenshot_json" "[]")

  # Output unified standard JSON telemetry block
  # E2BIG-safe (2026-09-12): every content-bearing value goes through json_block(),
  # which hands them to jq by STDIN. Only scalars are left in argv. Output is kept
  # compact (-c): the previous pretty-printed form was strictly larger for the same
  # data, and this block is consumed by jq downstream.
  local final_json jq_rc
  final_json=$(json_block "$SUCCESS" "$console_logs" "$eval_json" "$screenshot_json" \
                          "$PAGE_TITLE" "$PAGE_URL" "$ERROR_MSG") ; jq_rc=$?

  if [[ $jq_rc -ne 0 || -z $final_json ]]; then
    # Never return silently: report the failure instead of pretending success.
    SUCCESS="false"
    ERROR_MSG="Failed to assemble the result block (jq rc=$jq_rc)"
    final_json=$(json_block "false" "[]" "[]" "[]" "" "" "$ERROR_MSG")
  fi

  printf '%s\n' "$final_json"

  [[ $SUCCESS == "false" ]] && exit 1
  exit 0
}

# Logging
echo -e "\n---\n\nDate: $(date '+%Y-%m-%d %H:%M:%S')\nArguments: $*" >> "$LOG_FILE"

main "$@"
