#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# ==============================================================================
# TOOLS SCRIPT FOR LOCAL AGENT (Strictly conforming to schema constraints)
# ==============================================================================
#
# Made by Gemini 3.5 Flash Extended / Improved by Jiab77
#
# Version 0.1.1

# Options
# [[ -e $HOME/.debug ]] && set -x

# Config
LOG_FILE="$(basename "$0" .sh).log"
PIPELINE_FILE="pipeline.sh"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

# Internals
BIN_HTMLQ=$(command -v htmlq 2>/dev/null)

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

# Pure Bash URL Decoder
urldecode() {
  local encoded="${1//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

# Public Functions
# 1. Read file contents with optional line range and line-number prefixing
read_file() {
  local path="."
  local start_line=1
  local end_line
  local append_loc=false
  local total_lines
  local x

  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "start_line") ; [[ -n $x && ! $x == "null" ]] && start_line="$x"
    x=$(parse_args "end_line") ; [[ -n $x && ! $x == "null" ]] && end_line="$x"
    x=$(parse_args "append_loc") ; [[ -n $x && ! $x == "null" ]] && append_loc="$x"
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
  local x

  if [[ -n "$FUNC_ARGS" ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "include") ; [[ -n $x && ! $x == "null" ]] && include="$x"
    x=$(parse_args "exclude") ; [[ -n $x && ! $x == "null" ]] && exclude="$x"
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
  local x

  if [[ -n "$FUNC_ARGS" ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "pattern") ; [[ -n $x && ! $x == "null" ]] && pattern="$x"
    x=$(parse_args "include") ; [[ -n $x && ! $x == "null" ]] && include="$x"
    x=$(parse_args "exclude") ; [[ -n $x && ! $x == "null" ]] && exclude="$x"
    x=$(parse_args "return_line_numbers") ; [[ -n $x && ! $x == "null" ]] && return_line_numbers="$x"
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
  local x

  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "command") ; [[ -n $x && ! $x == "null" ]] && command="$x"
    x=$(parse_args "timeout") ; [[ -n $x && ! $x == "null" ]] && timeout="$x"
    x=$(parse_args "max_output_size") ; [[ -n $x && ! $x == "null" ]] && max_output_size="$x"
  fi

  # Avoid running the pipeline itself while it is running
  [[ $(grep -ci "$PIPELINE_FILE" <<< "$command") -ne 0 ]] && error "Dear model, don't try to run the pipeline itself, it's not made for that. Thank you."

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
  local x

  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "content") ; [[ -n $x && ! $x == "null" ]] && content="$x"
  fi

  # Avoid writing to the pipeline itself while it is running
  [[ $(grep -ci "$PIPELINE_FILE" <<< "$path") -ne 0 ]] && error "Dear model, don't try to write to the pipeline itself, it's not made for that. Thank you."

  mkdir -p "$(dirname "$path")"
  echo -n "$content" > "$path"
}

# 6. Surgical file editing using line-based changes
edit_file() {
  local path="."
  local changes
  local sorted_changes
  local tmp_file
  local mode
  local line_start
  local line_end
  local content
  local total_lines
  local x

  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "changes") ; [[ -n $x && ! $x == "null" ]] && changes="$x"
  fi

  [[ ! -f $path ]] && error "File not found at $path"

  # Avoid editing the pipeline itself while it is running
  [[ $(grep -ci "$PIPELINE_FILE" <<< "$path") -ne 0 ]] && error "Dear model, don't try to edit the pipeline itself, it's not made for that. Thank you."

  if ! jq empty 2>/dev/null <<< "$changes"; then
    echo "Error: Invalid JSON array provided to edit_file" >&2
    return 1
  fi

  # Extract and sort changes in descending line start order (prevents breaking subsequent target index alignment)
  sorted_changes=$(jq -c 'sort_by(.line_start) | reverse | .[]' <<< "$changes")

  # Create backup to temp file
  tmp_file=$(mktemp)
  cp "$path" "$tmp_file"

  # Loop through changes
  while read -r change; do
    [[ -z $change ]] && continue

    mode=$(jq -rc '.mode' <<< "$change")
    line_start=$(jq -rc '.line_start' <<< "$change")
    line_end=$(jq -rc '.line_end' <<< "$change")
    content=$(jq -rc '.content' <<< "$change")
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
  done <<< "$sorted_changes"

  mv "$tmp_file" "$path"
}

# 7. Apply a unified Git diff template
apply_diff() {
  local diff_content
  local x

  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "diff_content") ; [[ -n $x && ! $x == "null" ]] && diff_content="$x"
  fi

  echo "$diff_content" | git apply --whitespace=fix -
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
  local results_json="[]"
  local curl_opts=("-sfSL" "-A" "$USER_AGENT")
  local search_url="https://html.duckduckgo.com"
  local temp_url
  local final_url
  local clean_title
  local clean_snippet
  local x

  [[ -z $BIN_HTMLQ ]] && error "htmlq is required to run web search queries."

  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "query") ; [[ -n $x && ! $x == "null" ]] && query="$x"
  fi

  [[ -z $query ]] && error "The search query is required."

  # URL encode the search term natively inside JQ
  encoded_query=$(jq -nrc --arg q "$query" '$q | @uri')

  # Outbound curl options (socks5h proxy if Tor is active in backend, else direct)
  if timeout 2 bash -c '</dev/tcp/127.0.0.1/9050' &>/dev/null; then
    search_url="https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
    curl_opts+=("-x" "socks5h://127.0.0.1:9050")
  fi

  # Run search query
  html_data=$(curl "${curl_opts[@]}" "${search_url}/html?q=${encoded_query}")
  [[ -z $html_data ]] && error "Could not retrieve search data from DuckDuckGo."

  # Align-extract data streams
  mapfile -t titles < <(htmlq ".result__a" --text <<< "$html_data")
  mapfile -t raw_urls < <(htmlq ".result__a" --attribute href <<< "$html_data")
  mapfile -t snippets < <(htmlq ".result__snippet" --text <<< "$html_data")

  # Loop through search results
  for i in "${!titles[@]}"; do
    temp_url="${raw_urls[$i]}"
    final_url="$temp_url"

    # Decode DuckDuckGo redirections (uddg=...) natively in pure built-in Bash (0 subshells!)
    [[ "$temp_url" =~ uddg=(.*)\& ]] && final_url=$(urldecode "${BASH_REMATCH[1]}")

    # Trim whitespace
    clean_title=$(echo "${titles[$i]}" | xargs)
    clean_snippet=$(echo "${snippets[$i]}" | xargs)

    results_json=$(jq -rc \
      --arg title "$clean_title" \
      --arg url "$final_url" \
      --arg snippet "$clean_snippet" \
      '. + [{"title": $title, "url": $url, "snippet": $snippet}]' <<< "$results_json")
  done

  echo "$results_json"
}

# Bootstrap
[[ $# -eq 0 ]] && error "Missing arguments.\nUsage: $(basename "$0") <function> <arguments>\n"

# Logging
echo -e "\n---\n\nDate: $(date '+%Y-%m-%d %H:%M:%S')\nFunction: ${FUNC_NAME}\nArguments: ${FUNC_ARGS}" >> "$LOG_FILE"

# Dispatcher execution
"$FUNC_NAME" "$FUNC_ARGS"
