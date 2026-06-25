#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# ==============================================================================
# TOOLS SCRIPT FOR LOCAL AGENT (Strictly conforming to schema constraints)
# ==============================================================================
#
# Lead developer & Architect: Jiab77
# AI Sorcerer & Co-Creator: Jarvis (Gemini)
#
# Version 0.3.2 (Dual-Optimized for zero forks & strict macOS/Bash 3.2 compatibility)

# Options
# [[ -e $HOME/.debug ]] && set -x

# Config
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
TOR_HOST="127.0.0.1"
TOR_PORT=9050
HTTP_PORT=9080
TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"
HTTP_PROXY="${TOR_HOST}:${HTTP_PORT}"

# Internals
BIN_HTMLQ=$(command -v htmlq 2>/dev/null)
SCRIPT_DIR="$(realpath "${0%/*}")"
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
TOOLS_DIR="${SCRIPT_DIR}/tools"
WEB_BROWSE="${TOOLS_DIR}/web-browse/web-browse.js"
WEB_FETCH="${TOOLS_DIR}/web-fetch.sh"
LOG_FILE="${SCRIPT_NAME}.log"

# Arguments
FUNC_NAME="$1"
FUNC_ARGS="$2"

# Internal Functions
log() {
  echo -e "$*" >&2
}

error() {
  echo -e "\nError: $*\n" >&2
  exit 255
}

parse_args() {
  local key="$1"
  jq -rc ".${key}" <<<$FUNC_ARGS
}

# Pure Bash URL Decoder (Bash 3.2+ Compatible, 0 Subshells!)
urldecode() {
  local encoded="${1//+/ }"
  printf -v "$2" '%b' "${encoded//%/\\x}"
}

# Public Functions
# 1. Read file contents with optional line range and line-number prefixing
read_file() {
  local path="."
  local start_line=1
  local end_line
  local append_loc=false
  local total_lines
  local path_val start_val end_val append_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' path_val
      IFS= read -r -d '' start_val
      IFS= read -r -d '' end_val
      IFS= read -r -d '' append_val
    } < <(jq -j '.path, "\u0000", (.start_line|tostring), "\u0000", (.end_line|tostring), "\u0000", (.append_loc|tostring), "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $path_val && $path_val != null ]] && path=$path_val
    [[ -n $start_val && $start_val != null ]] && start_line=$start_val
    [[ -n $end_val && $end_val != null ]] && end_line=$end_val
    [[ -n $append_val && $append_val != null ]] && append_loc=$append_val
  fi

  [[ ! -f $path ]] && error "File not found at $path"

  total_lines=$(wc -l < "$path")
  [[ -z $end_line ]] && end_line=$total_lines

  if [[ $append_loc == true ]]; then
    awk -v start="$start_line" -v end="$end_line" '
        NR >= start && NR <= end { printf "%d→ %s\n", NR, $0 }
    ' "$path"
  else
    awk -v start="$start_line" -v end="$end_line" '
        NR >= start && NR <= end { print $0 }
    ' "$path"
  fi
}

# 2. Recursively search for files matching a glob pattern under a folder
file_glob_search() {
  local path="."
  local include="*"
  local exclude
  local path_val include_val exclude_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' path_val
      IFS= read -r -d '' include_val
      IFS= read -r -d '' exclude_val
    } < <(jq -j '.path, "\u0000", .include, "\u0000", .exclude, "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $path_val && $path_val != null ]] && path=$path_val
    [[ -n $include_val && $include_val != null ]] && include=$include_val
    [[ -n $exclude_val && $exclude_val != null ]] && exclude=$exclude_val
  fi

  [[ ! -d $path ]] && error "Directory not found at $path"

  if [[ -n $exclude ]]; then
    find "$path" -maxdepth 10 -type f -wholename "$include" ! -wholename "$exclude"
  else
    find "$path" -maxdepth 10 -type f -wholename "$include"
  fi
}

# 3. Search for a regex pattern in files (grep)
grep_search() {
  local path="."
  local pattern
  local include="*"
  local exclude
  local return_line_numbers=false
  local grep_opts="-E"
  local path_val pattern_val include_val exclude_val return_lines_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' path_val
      IFS= read -r -d '' pattern_val
      IFS= read -r -d '' include_val
      IFS= read -r -d '' exclude_val
      IFS= read -r -d '' return_lines_val
    } < <(jq -j '.path, "\u0000", .pattern, "\u0000", .include, "\u0000", .exclude, "\u0000", (.return_line_numbers|tostring), "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $path_val && $path_val != null ]] && path=$path_val
    [[ -n $pattern_val && $pattern_val != null ]] && pattern=$pattern_val
    [[ -n $include_val && $include_val != null ]] && include=$include_val
    [[ -n $exclude_val && $exclude_val != null ]] && exclude=$exclude_val
    [[ -n $return_lines_val && $return_lines_val != null ]] && return_line_numbers=$return_lines_val
  fi

  [[ $return_line_numbers == true ]] && grep_opts="${grep_opts} -n"

  if [[ -d $path ]]; then
    if [[ -n $exclude ]]; then
      grep $grep_opts -r --include="$include" --exclude="$exclude" "$pattern" "$path"
    else
      grep $grep_opts -r --include="$include" "$pattern" "$path"
    fi
  elif [[ -f $path ]]; then
    grep $grep_opts "$pattern" "$path"
  else
    error "Invalid path $path"
  fi
}

# 4. Execute a system shell command with timeout and strict truncation
exec_shell_command() {
  local command="null"
  local timeout=10
  local max_output_size=16384
  local output
  local exit_code
  local cmd_val timeout_val max_size_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' cmd_val
      IFS= read -r -d '' timeout_val
      IFS= read -r -d '' max_size_val
    } < <(jq -j '.command, "\u0000", (.timeout|tostring), "\u0000", (.max_output_size|tostring), "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $cmd_val && $cmd_val != null ]] && command=$cmd_val
    [[ -n $timeout_val && $timeout_val != null ]] && timeout=$timeout_val
    [[ -n $max_size_val && $max_size_val != null ]] && max_output_size=$max_size_val
  fi
  # Avoid running core pipeline files (core.sh, cli.sh, tools.sh) while running (Zero-Fork matching!)
  if [[ $command == "${SCRIPT_DIR}/"*[cC][oO][rR][eE].[sS][hH]* || $command == "${SCRIPT_DIR}/"*[cC][lL][iI].[sS][hH]* || $command == "${SCRIPT_DIR}/"*[tT][oO][oO][lL][sS].[sS][hH]* || $command == "${SCRIPT_DIR}/"*[pP][iI][pP][eE][lL][iI][nN][eE].[sS][hH]* ]]; then
    error "Dear model, don't try to run core pipeline files, they are not made for that. Thank you."
  fi

  [[ $timeout -lt 1 || $timeout -gt 60 ]] && timeout=10

  output=$(timeout "$timeout" sh -c "$command" 2>&1)
  exit_code=$?

  [[ $exit_code -eq 124 ]] && echo "Command timed out after $timeout seconds."

  if [[ ${#output} -gt $max_output_size ]]; then
    echo "${output:0:$max_output_size}"
    echo -e "\n[Output truncated: exceeded $max_output_size bytes]"
  else
    echo "$output"
  fi
  exit $exit_code
}

# 5. Write or overwrite a file (creates parent directories dynamically)
write_file() {
  local path="."
  local content
  local path_val content_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' path_val
      IFS= read -r -d '' content_val
    } < <(jq -j '.path, "\u0000", .content, "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $path_val && $path_val != null ]] && path=$path_val
    [[ -n $content_val && $content_val != null ]] && content=$content_val
  fi

  # Avoid writing to core pipeline files (core.sh, cli.sh, tools.sh) while running (Zero-Fork matching!)
  if [[ $path == "${SCRIPT_DIR}/"*[cC][oO][rR][eE].[sS][hH]* || $path == "${SCRIPT_DIR}/"*[cC][lL][iI].[sS][hH]* || $path == "${SCRIPT_DIR}/"*[tT][oO][oO][lL][sS].[sS][hH]* || $path == "${SCRIPT_DIR}/"*[pP][iI][pP][eE][lL][iI][nN][eE].[sS][hH]* ]]; then
    error "Dear model, don't try to write to core pipeline files, they are not made for that. Thank you."
  fi

  mkdir -p "$(dirname "$path")"
  echo -n "$content" > "$path"
}

# 6. Surgical file editing using line-based changes
edit_file() {
  local path="."
  local changes
  local tmp_file
  local mode
  local line_start
  local line_end
  local content
  local total_lines
  local path_val changes_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' path_val
      IFS= read -r -d '' changes_val
    } < <(jq -j '.path, "\u0000", (.changes|tostring), "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $path_val && $path_val != null ]] && path=$path_val
    [[ -n $changes_val && $changes_val != null ]] && changes=$changes_val
  fi

  [[ ! -f $path ]] && error "File not found at $path"

  # Avoid editing core pipeline files (core.sh, cli.sh, tools.sh) while running (Zero-Fork matching!)
  if [[ $path == "${SCRIPT_DIR}/"*[cC][oO][rR][eE].[sS][hH]* || $path == "${SCRIPT_DIR}/"*[cC][lL][iI].[sS][hH]* || $path == "${SCRIPT_DIR}/"*[tT][oO][oO][lL][sS].[sS][hH]* || $path == "${SCRIPT_DIR}/"*[pP][iI][pP][eE][lL][iI][nN][eE].[sS][hH]* ]]; then
    error "Dear model, don't try to edit core pipeline files, they are not made for that. Thank you."
  fi

  if ! jq empty 2>/dev/null <<< "$changes"; then
    echo "Error: Invalid JSON array provided to edit_file" >&2
    return 1
  fi

  # Create backup to temp file
  tmp_file=$(mktemp)
  cp "$path" "$tmp_file"

  # Extract and stream sorted changes with null delimiters to execute exactly ONE jq process instead of (1 + 4*N) processes!
  while IFS= read -r -d '' mode && IFS= read -r -d '' line_start && IFS= read -r -d '' line_end && IFS= read -r -d '' content; do
    [[ -z $mode ]] && continue
    total_lines=$(wc -l < "$tmp_file")

    # Handle write at end of file (line_start = -1)
    if [[ $line_start -eq -1 ]]; then
      if [[ $mode == "append" || $mode == "replace" ]]; then
        echo -e "\n${content}" >> "$tmp_file"
      fi
      continue
    fi

    case "$mode" in
      "delete")
        awk -v start="$line_start" -v end="$line_end" 'NR < start || NR > end' "$tmp_file" > "${tmp_file}.bak"
        mv "${tmp_file}.bak" "$tmp_file"
        ;;
      "replace")
        awk -v start="$line_start" -v end="$line_end" -v repl="$content" '
            NR == start { print repl; next }
            NR > start && NR <= end { next }
            { print }
        ' "$tmp_file" > "${tmp_file}.bak"
        mv "${tmp_file}.bak" "$tmp_file"
        ;;
      "append")
        awk -v target="$line_end" -v app="$content" '
            { print }
            NR == target { print app }
        ' "$tmp_file" > "${tmp_file}.bak"
        mv "${tmp_file}.bak" "$tmp_file"
        ;;
    esac
  done < <(jq -j 'sort_by(.line_start) | reverse | .[] | .mode, "\u0000", (.line_start|tostring), "\u0000", (.line_end|tostring), "\u0000", .content, "\u0000"' <<< "$changes")

  mv "$tmp_file" "$path"
}

# 7. Apply a unified Git diff template
apply_diff() {
  local diff_content

  # Avoid patching core pipeline files (core.sh, cli.sh, tools.sh) while running (Zero-Fork matching!)
  if [[ $FUNC_ARGS == "${SCRIPT_DIR}/"*[cC][oO][rR][eE].[sS][hH]* || $FUNC_ARGS == "${SCRIPT_DIR}/"*[cC][lL][iI].[sS][hH]* || $FUNC_ARGS == "${SCRIPT_DIR}/"*[tT][oO][oO][lL][sS].[sS][hH]* || $FUNC_ARGS == "${SCRIPT_DIR}/"*[pP][iI][pP][eE][lL][iI][nN][eE].[sS][hH]* ]]; then
    error "Dear model, don't try to patch core pipeline files, they are not made for that. Thank you."
  fi

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' diff_content
    } < <(jq -j '.diff, "\u0000"' <<< "$FUNC_ARGS")
  fi

  if [[ -n $diff_content && $diff_content != null ]]; then
    echo "$diff_content" | git apply --whitespace=fix -
  fi
}

# 8. Retrieve the current system date and time
get_datetime() {
  date '+%Y-%m-%d %H:%M:%S'
}

# 9. Perform an anonymous web search query on DuckDuckGo using Tor
web_search() {
  local query
  local encoded_query
  local html_data
  local curl_opts=("-sfSL" "-A" "$USER_AGENT")
  local search_url="https://html.duckduckgo.com"
  local temp_url
  local final_url
  local clean_title
  local clean_snippet
  local query_val
  local interleaved=()

  [[ -z $BIN_HTMLQ ]] && error "htmlq is required to run web search queries."

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' query_val
    } < <(jq -j '.query, "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $query_val && $query_val != null ]] && query=$query_val
  fi

  [[ -z $query ]] && error "The search query is required."

  # URL encode the search term natively inside JQ
  encoded_query=$(jq -nrc --arg q "$query" '$q | @uri')

  # Outbound curl options (socks5h proxy if Tor is active in backend, else direct)
  if timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
    search_url="https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
    curl_opts+=("-x" "$TOR_PROXY")
  fi

  # Run search query
  html_data=$(curl "${curl_opts[@]}" "${search_url}/html?q=${encoded_query}")
  [[ -z $html_data ]] && error "Could not retrieve search data from DuckDuckGo."

  # Align-extract data streams
  mapfile -t titles < <(htmlq ".result__a" --text <<< "$html_data")
  mapfile -t raw_urls < <(htmlq ".result__a" --attribute href <<< "$html_data")
  mapfile -t snippets < <(htmlq ".result__snippet" --text <<< "$html_data")

  # Process and interleave results with 100% zero-fork native trimming and URL decoding
  for i in "${!titles[@]}"; do
    temp_url="${raw_urls[$i]}"
    final_url="$temp_url"

    # Decode DuckDuckGo redirections natively in pure built-in Bash (0 subshells!)
    if [[ $temp_url =~ uddg=(.*)\& ]]; then
      urldecode "${BASH_REMATCH[1]}" final_url
    fi

    # Trim leading and trailing whitespaces natively (0 subshells!)
    clean_title="${titles[$i]#"${titles[$i]%%[![:space:]]*}"}"
    clean_title="${clean_title%"${clean_title##*[![:space:]]}"}"

    clean_snippet="${snippets[$i]#"${snippets[$i]%%[![:space:]]*}"}"
    clean_snippet="${clean_snippet%"${clean_snippet##*[![:space:]]}"}"

    interleaved+=("$clean_title" "$final_url" "$clean_snippet")
  done

  # Process all items into a unified JSON array in EXACTLY ONE jq call instead of N calls!
  jq -n '$ARGS.positional | [range(0; length; 3) as $i | {"title": .[$i], "url": .[$i+1], "snippet": .[$i+2]}]' --args "${interleaved[@]}"
}

# 10. Fetch web page contents with high fidelity and specialized routing
web_fetch() {
  local url
  local use_javascript=false
  local proxy="$TOR_PROXY"
  local url_val use_js_val proxy_val

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' url_val
      IFS= read -r -d '' use_js_val
      IFS= read -r -d '' proxy_val
    } < <(jq -j '.url, "\u0000", (.use_javascript|tostring), "\u0000", .proxy, "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $url_val && $url_val != null ]] && url=$url_val
    [[ -n $use_js_val && $use_js_val != null ]] && use_javascript=$use_js_val
    [[ -n $proxy_val && $proxy_val != null ]] && proxy=$proxy_val
  fi

  [[ -z $url ]] && error "The URL parameter is required."

  local opts=()
  [[ $use_javascript == true ]] && opts+=("--js")
  if [[ $proxy == "null" || -z $proxy || $proxy == "false" ]]; then
    opts+=("--no-tor")
  fi

  # Call our optimized smart script
  "$WEB_FETCH" "${opts[@]}" "$url"
}

# 11. Interact with and audit dynamic web pages using Puppeteer
web_browse() {
  local proxy="$HTTP_PROXY"
  local proxy_val
  local updated_args

  if [[ -n $FUNC_ARGS ]]; then
    {
      IFS= read -r -d '' proxy_val
    } < <(jq -j '.proxy, "\u0000"' <<< "$FUNC_ARGS")

    [[ -n $proxy_val && $proxy_val != null ]] && proxy=$proxy_val
  fi

  # If proxy is explicitly false, null, or empty, disable proxy routing
  if [[ $proxy == "null" || $proxy == "false" || -z $proxy ]]; then
    updated_args=$(jq '. + {"noTor": true} | del(.proxy)' <<< "$FUNC_ARGS")
  else
    # Inject the resolved proxy address into the JSON payload for Node.js
    updated_args=$(jq --arg prx "$proxy" '. + {"proxy": $prx}' <<< "$FUNC_ARGS")
  fi

  # Call our optimized Puppeteer script
  "$WEB_BROWSE" "$updated_args"
}

# Bootstrap
[[ $# -eq 0 ]] && error "Missing arguments.\nUsage: ${0##*/} <function> <arguments>\n"

# Logging
echo -e "\n---\n\nDate: $(get_datetime)\nFunction: ${FUNC_NAME}\nArguments: ${FUNC_ARGS}" >> "$LOG_FILE"

# Dispatcher execution
"$FUNC_NAME" "$FUNC_ARGS"
