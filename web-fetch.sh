#!/usr/bin/env bash
# ==============================================================================
# SMART WEB_FETCH ENGINE (Pure Bash + API Integration + Robust Fallback)
# ==============================================================================
#
# A smart, ultra-optimized web content fetcher that targets specific public
# APIs (GitHub, GitLab, Wikipedia) for 100% fidelity, and falls back to a clean
# HTML parser using curl & htmlq, or JS headless browser proxy.
#
# Created by Jarvis & Jiab77
#
# Version: 0.1.0
# ==============================================================================

# Options
set -o pipefail

# Config
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
TOR_HOST="127.0.0.1"
TOR_PORT=9050
TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"

# Internals
BIN_HTMLQ=$(command -v htmlq 2>/dev/null)
SCRIPT_FILE="${0##*/}"
SCRIPT_NAME="${SCRIPT_FILE%.*}"
LOG_FILE="${SCRIPT_NAME}.log"

# Proxy SOCKS5 for Tor (if active)
IF_TOR_PROXY=""
if timeout 2 bash -c "</dev/tcp/${TOR_HOST}/${TOR_PORT}" &>/dev/null; then
  IF_TOR_PROXY="$TOR_PROXY"
fi

# Parse Options
USE_JS=false
USE_TOR=true
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tor)
      USE_TOR=false
      shift
      ;;
    -j|--js)
      USE_JS=true
      shift
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
    *)
      if [[ -z $URL ]]; then
        URL="$1"
      else
        echo "Error: Multiple URLs specified." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z $URL ]]; then
  echo "Usage: $0 [options] <URL>"
  echo "Options:"
  echo "  -j, --js      Use JavaScript headless browser (Puppeteer fallback, when available)"
  echo "  --no-tor      Bypass Tor SOCKS5 proxy even if available"
  exit 1
fi

# Determine curl options
CURL_OPTS=("-sfSL" "-A" "$USER_AGENT" "--connect-timeout" "10")
if [[ $USE_TOR == true && -n $IF_TOR_PROXY ]]; then
  CURL_OPTS+=("-x" "$IF_TOR_PROXY")
fi

# Logger function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

if [[ $USE_JS == true ]]; then
  log "JavaScript fallback option is selected but not natively needed for specific REST APIs."
fi

# --- SPECIALIZED API ROUTERS ---

# 1. GITHUB ROUTER
handle_github() {
  local url="$1"
  log "Handling URL as GitHub target: $url"

  # Clean trailing slash or .git using pure Bash parameter expansion
  url="${url%.git}"
  url="${url%/}"

  # Match patterns
  if [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local branch="${BASH_REMATCH[4]}"
    local file_path="${BASH_REMATCH[5]}"

    log "GitHub Blob: owner=$owner repo=$repo branch=$branch file=$file_path"
    
    # Try fetching raw content directly
    local raw_url="https://raw.githubusercontent.com/$owner/$repo/$branch/$file_path"
    local raw_content
    
    if raw_content=$(curl "${CURL_OPTS[@]}" "$raw_url"); then
      # Detect code extension for markdown formatting
      local ext="${file_path##*.}"
      [[ $ext == "$file_path" ]] && ext="text" # no extension

      echo "# 📄 File: $file_path"
      echo "> **Repository:** [$owner/$repo]($url) | **Branch:** \`$branch\`"
      echo ""
      echo "\`\`\`$ext"
      echo "$raw_content"
      echo "\`\`\`"
    else
      echo "Error: Could not retrieve raw file from $raw_url" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/tree/([^/]+)(/(.+))?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local branch="${BASH_REMATCH[4]}"
    local dir_path="${BASH_REMATCH[6]}"

    log "GitHub Tree: owner=$owner repo=$repo branch=$branch dir=$dir_path"

    # Fetch via API contents
    local api_url="https://api.github.com/repos/$owner/$repo/contents/$dir_path?ref=$branch"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      echo "# 📂 Directory: \`/$dir_path\`"
      echo "> **Repository:** [$owner/$repo]($url) | **Ref:** \`$branch\`"
      echo ""
      echo "| Name | Type | Size | Download Link |"
      echo "| --- | --- | --- | --- |"
      
      while read -r row; do
        local name type size download_url
        name=$(jq -rc '.name' <<< "$row")
        type=$(jq -rc '.type' <<< "$row")
        size=$(jq -rc '.size' <<< "$row")
        download_url=$(jq -rc '.download_url' <<< "$row")
        
        # Human readable size
        local size_str="${size} B"
        if [[ $size -gt 1048576 ]]; then
          size_str="$(echo "scale=2; $size / 1048576" | bc) MB"
        elif [[ $size -gt 1024 ]]; then
          size_str="$(echo "scale=2; $size / 1024" | bc) KB"
        fi
        
        if [[ $type == dir ]]; then
          echo "| 📁 $name | \`$type\` | - | - |"
        else
          echo "| 📄 $name | \`$type\` | $size_str | [Raw Link]($download_url) |"
        fi
      done < <(jq -c '.[]' <<< "$json_data")
    else
      echo "Error: Could not retrieve directory listing from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"

    log "GitHub Repo Home: owner=$owner repo=$repo"

    # Fetch metadata and readme
    local meta_url="https://api.github.com/repos/$owner/$repo"
    local readme_url="https://api.github.com/repos/$owner/$repo/readme"

    local meta_json
    if ! meta_json=$(curl "${CURL_OPTS[@]}" "$meta_url"); then
      echo "Error: Could not retrieve repository metadata from $meta_url" >&2
      exit 2
    fi

    # Readme metadata
    local name desc stars forks issues lang license def_branch
    name=$(jq -rc '.name' <<< "$meta_json")
    desc=$(jq -rc '.description' <<< "$meta_json")
    stars=$(jq -rc '.stargazers_count' <<< "$meta_json")
    forks=$(jq -rc '.forks_count' <<< "$meta_json")
    issues=$(jq -rc '.open_issues_count' <<< "$meta_json")
    lang=$(jq -rc '.language' <<< "$meta_json")
    license=$(jq -rc '.license.name // "None"' <<< "$meta_json")
    def_branch=$(jq -rc '.default_branch' <<< "$meta_json")

    # Fetch raw readme
    local readme_content
    readme_content=$(curl "${CURL_OPTS[@]}" -H "Accept: application/vnd.github.raw" "$readme_url" 2>/dev/null)

    echo "# 📦 $owner / $name"
    echo "> **Description:** $desc"
    echo ""
    echo "### 📊 Repository Statistics"
    echo "- ⭐ **Stars:** $stars | 🍴 **Forks:** $forks | 🐛 **Issues:** $issues"
    echo "- 💻 **Language:** $lang | 📄 **License:** $license | 🌿 **Default Branch:** $def_branch"
    echo ""
    echo "---"
    echo ""
    if [[ -n $readme_content ]]; then
      echo "### 📖 README.md"
      echo ""
      echo "$readme_content"
    else
      echo "*No README found or error fetching README.*"
    fi
  else
    echo "Error: Invalid GitHub URL format." >&2
    exit 1
  fi
}

# 1b. RAW GITHUB ROUTER
handle_raw_github() {
  local url="$1"
  log "Handling URL as Raw GitHub target: $url"

  # Remove protocol and domain
  local path="${url#*://*/}"  # e.g., "Jiab77/ai-pipeline/refs/heads/main/README.md"

  local owner="${path%%/*}"
  local temp="${path#*/}"
  local repo="${temp%%/*}"
  local remaining="${temp#*/}"    # e.g., "refs/heads/main/README.md" or "main/README.md"

  local branch file_path
  if [[ $remaining =~ ^(refs/(heads|tags|pull)/[^/]+)/(.*) ]]; then
    branch="${BASH_REMATCH[1]}"   # "refs/heads/main"
    file_path="${BASH_REMATCH[3]}" # "README.md"
  else
    branch="${remaining%%/*}"
    file_path="${remaining#*/}"
  fi

  log "Raw GitHub Parse: owner=$owner repo=$repo branch=$branch file=$file_path"

  local raw_content
  if raw_content=$(curl "${CURL_OPTS[@]}" "$url"); then
    local ext="${file_path##*.}"
    [[ $ext == "$file_path" ]] && ext="text" # no extension

    echo "# 📄 File: $file_path"
    echo "> **Repository:** [$owner/$repo]($url) | **Branch/Reference:** \`$branch\`"
    echo ""
    echo "\`\`\`$ext"
    echo "$raw_content"
    echo "\`\`\`"
  else
    echo "Error: Could not retrieve raw file from $url" >&2
    exit 2
  fi
}

# 2. GITLAB ROUTER
handle_gitlab() {
  local url="$1"
  log "Handling URL as GitLab target: $url"

  # Clean trailing slash or .git using pure Bash parameter expansion
  url="${url%.git}"
  url="${url%/}"

  if [[ $url =~ (.*)/-/raw/([^/]+)/(.*) ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local branch="${BASH_REMATCH[2]}"
    local file_path="${BASH_REMATCH[3]}"
    
    local project_path="${raw_project_path#*://*/}"
    local owner="${project_path%/*}"
    local repo="${project_path##*/}"

    log "GitLab Raw: owner=$owner repo=$repo branch=$branch file=$file_path"

    local raw_content
    if raw_content=$(curl "${CURL_OPTS[@]}" "$url"); then
      local ext="${file_path##*.}"
      [[ $ext == "$file_path" ]] && ext="text"

      echo "# 📄 File: $file_path (GitLab Raw)"
      echo "> **Repository:** [$owner/$repo]($raw_project_path) | **Branch:** \`$branch\`"
      echo ""
      echo "\`\`\`$ext"
      echo "$raw_content"
      echo "\`\`\`"
    else
      echo "Error: Could not retrieve raw file from $url" >&2
      exit 2
    fi

  elif [[ $url =~ (.*)/-/blob/([^/]+)/(.*) ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local branch="${BASH_REMATCH[2]}"
    local file_path="${BASH_REMATCH[3]}"
    
    local project_path="${raw_project_path#*://*/}"
    local owner="${project_path%/*}"
    local repo="${project_path##*/}"

    log "GitLab Blob: owner=$owner repo=$repo branch=$branch file=$file_path"

    local raw_url="${raw_project_path}/-/raw/${branch}/${file_path}"
    local raw_content

    if raw_content=$(curl "${CURL_OPTS[@]}" "$raw_url"); then
      local ext="${file_path##*.}"
      [[ $ext == "$file_path" ]] && ext="text"

      echo "# 📄 File: $file_path (GitLab)"
      echo "> **Repository:** [$owner/$repo]($raw_project_path) | **Branch:** \`$branch\`"
      echo ""
      echo "\`\`\`$ext"
      echo "$raw_content"
      echo "\`\`\`"
    else
      echo "Error: Could not retrieve raw file from $raw_url" >&2
      exit 2
    fi

  elif [[ $url =~ (.*)/-/tree/([^/]+)(/(.*))? ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local branch="${BASH_REMATCH[2]}"
    local dir_path="${BASH_REMATCH[4]}"
    
    local project_path="${raw_project_path#*://*/}"
    local owner="${project_path%/*}"
    local repo="${project_path##*/}"
    local encoded_project="${project_path////%2F}"

    log "GitLab Tree: owner=$owner repo=$repo branch=$branch dir=$dir_path"

    local api_url="https://gitlab.com/api/v4/projects/$encoded_project/repository/tree?ref=$branch&path=$dir_path"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      echo "# 📂 Directory (GitLab): \`/$dir_path\`"
      echo "> **Repository:** [$owner/$repo]($raw_project_path) | **Ref:** \`$branch\`"
      echo ""
      echo "| Name | Type | Link |"
      echo "| --- | --- | --- |"

      while read -r row; do
        [[ -z $row ]] && continue
        local name type path_item
        name=$(jq -rc '.name' <<< "$row")
        type=$(jq -rc '.type' <<< "$row")
        path_item=$(jq -rc '.path' <<< "$row")

        if [[ $type == tree ]]; then
          echo "| 📁 $name | \`directory\` | [View](${raw_project_path}/-/tree/$branch/$path_item) |"
        else
          echo "| 📄 $name | \`file\` | [Raw](${raw_project_path}/-/raw/$branch/$path_item) |"
        fi
      done < <(jq -c '.[]' <<< "$json_data" 2>/dev/null)
    else
      echo "Error: Could not retrieve directory listing from GitLab API ($api_url)" >&2
      exit 2
    fi

  else
    local project_path="${url#*://*/}"
    local owner="${project_path%/*}"
    local repo="${project_path##*/}"
    local encoded_project="${project_path////%2F}"

    log "GitLab Repo Home: owner=$owner repo=$repo"

    local api_url="https://gitlab.com/api/v4/projects/$encoded_project"
    
    local meta_json
    if ! meta_json=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      echo "Error: Could not retrieve GitLab project metadata from $api_url" >&2
      exit 2
    fi

    local name desc stars forks def_branch web_url readme_url_web
    name=$(jq -rc '.name' <<< "$meta_json")
    desc=$(jq -rc '.description' <<< "$meta_json")
    stars=$(jq -rc '.star_count' <<< "$meta_json")
    forks=$(jq -rc '.forks_count' <<< "$meta_json")
    def_branch=$(jq -rc '.default_branch' <<< "$meta_json")
    web_url=$(jq -rc '.web_url' <<< "$meta_json")
    readme_url_web=$(jq -rc '.readme_url // empty' <<< "$meta_json")

    echo "# 🦊 $owner / $name (GitLab)"
    echo "> **Description:** $desc"
    echo ""
    echo "### 📊 Project Statistics"
    echo "- ⭐ **Stars:** $stars | 🍴 **Forks:** $forks"
    echo "- 🌿 **Default Branch:** $def_branch | 🌐 **Web:** [$web_url]($web_url)"
    echo ""
    echo "---"
    echo ""

    if [[ -n $readme_url_web ]]; then
      local readme_raw_url="${readme_url_web//\/-\/blob\//\/-\/raw\/}"
      local readme_content
      readme_content=$(curl "${CURL_OPTS[@]}" "$readme_raw_url" 2>/dev/null)
      if [[ -n $readme_content ]]; then
        echo "### 📖 README"
        echo ""
        echo "$readme_content"
      else
        echo "*No README content could be retrieved.*"
      fi
    else
      echo "*No README found on GitLab project.*"
    fi
  fi
}

# 3. WIKIPEDIA ROUTER
handle_wikipedia() {
  local url="$1"
  log "Handling URL as Wikipedia target: $url"

  if [[ $url =~ ^https?://([a-z0-9-]+)\.wikipedia\.org/wiki/([^?#]+) ]]; then
    local lang="${BASH_REMATCH[1]}"
    local title_encoded="${BASH_REMATCH[2]}"
    
    log "Wikipedia: lang=$lang title_encoded=$title_encoded"

    # Query Wikipedia REST API / api.php
    local api_url="https://${lang}.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext&exlimit=1&titles=${title_encoded}&format=json&redirects=1"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      # Extract real title and text content
      local title content
      title=$(jq -rc '.query.pages | to_entries[0].value.title' <<< "$json_data")
      content=$(jq -rc '.query.pages | to_entries[0].value.extract' <<< "$json_data")

      echo "# 🌐 Wikipedia: $title ($lang)"
      echo "> **Source Page:** [$url]($url)"
      echo ""
      echo "---"
      echo ""
      if [[ -n $content && $content != null ]]; then
        echo "$content"
      else
        echo "*Could not retrieve article summary or page is empty.*"
      fi
    else
      echo "Error: Could not retrieve Wikipedia article from $api_url" >&2
      exit 2
    fi
  else
    echo "Error: Unsupported Wikipedia URL format." >&2
    exit 1
  fi
}

# 3b. MARKDOWN PROBE FALLBACK ROUTER
handle_markdown_fallback() {
  local url="$1"
  log "Checking for Markdown direct availability or probe: $url"

  # Strip hash fragments and query parameters
  local q="?"
  local base_url="${url%%#*}"
  base_url="${base_url%%"$q"*}"
  local clean_url="${base_url%/}"
  local target_url="$url"
  local is_direct_md=false

  if [[ $clean_url == *.md ]]; then
    target_url="$url"
    is_direct_md=true
  else
    target_url="${clean_url}.md"
  fi

  # Fetch contents
  local response_body
  if response_body=$(curl "${CURL_OPTS[@]}" "$target_url" 2>/dev/null) && [[ -n $response_body ]]; then
    # Anti-SPA and Anti-HTML check: inspect first few hundred characters for HTML tags
    local body_chunk="${response_body:0:1000}"
    local body_chunk_lc
    body_chunk_lc=$(echo "$body_chunk" | tr '[:upper:]' '[:lower:]')

    if [[ $body_chunk_lc == *"<doctype"* ]] ||        [[ $body_chunk_lc == *"<html"* ]] ||        [[ $body_chunk_lc == *"<body"* ]] ||        [[ $body_chunk_lc == *"<head"* ]]; then
      log "Probe URL $target_url returned HTML instead of raw Markdown."
      return 1
    fi

    # SUCCESS!
    log "Markdown version found dynamically at: $target_url"

    local page_title="${clean_url##*/}"
    page_title="${page_title//-/ }"
    page_title="${page_title//_/ }"
    # Simple word capitalization using awk
    page_title="$(echo "$page_title" | awk '{for(i=1;i<=NF;i++){sub(substr($i,1,1),toupper(substr($i,1,1)),$i);}}1')"

    echo "# 📄 Document: $page_title"
    echo "> **Source URL:** [$url]($url)"
    if [[ $is_direct_md == false ]]; then
      echo "> **Markdown Source:** [$target_url]($target_url)"
    fi
    echo ""
    echo "---"
    echo ""
    echo "$response_body"
    return 0
  else
    log "Probe for Markdown at $target_url failed."
    return 1
  fi
}

# 4. GENERAL FALLBACK ROUTER (Using htmlq)
handle_fallback() {
  local url="$1"

  # Fetch raw HTML
  local html_data
  if ! html_data=$(curl "${CURL_OPTS[@]}" "$url") || [[ -z $html_data ]]; then
    echo "Error: Failed to retrieve HTML from $url" >&2
    exit 2
  fi

  # Check if htmlq is installed
  if [[ -n $BIN_HTMLQ ]]; then
    # Parse page title
    local title desc main_text
    title=$(htmlq "title" --text <<< "$html_data" | xargs)
    [[ -z $title ]] && title="Webpage"

    # Parse meta description
    desc=$(htmlq "meta[name=description]" --attribute content <<< "$html_data" 2>/dev/null | xargs)
    if [[ -z $desc ]]; then
      desc=$(htmlq "meta[property=\"og:description\"]" --attribute content <<< "$html_data" 2>/dev/null | xargs)
    fi

    # Extract clean text from headings and paragraphs in order
    main_text=$(htmlq "h1, h2, h3, h4, p" --text <<< "$html_data" 2>/dev/null)

    echo "# 🌐 $title"
    echo "> **URL:** [$url]($url)"
    if [[ -n $desc ]]; then
      echo "> **Description:** $desc"
    fi
    echo ""
    echo "---"
    echo ""
    if [[ -n $main_text ]]; then
      echo "$main_text"
    else
      echo "*No text content could be extracted. The page might rely heavily on JavaScript.*"
    fi
  else
    # Simple fallback: dump raw page text using a simple regex / sed strip
    echo "# 🌐 Raw Webpage Content (htmlq not available)"
    echo "> **URL:** [$url]($url)"
    echo ""
    echo "---"
    echo ""
    echo "$html_data" | sed -e 's/<[^>]*>//g' | sed -e '/^[[:space:]]*$/d' | head -n 100
    echo -e "\n[Output truncated: please install 'htmlq' for high fidelity rendering]"
  fi
}

# --- MAIN ROUTING LOGIC ---

if [[ $URL =~ (www\.)?github\.com ]]; then
  handle_github "$URL"
elif [[ $URL =~ raw\.githubusercontent\.com ]]; then
  handle_raw_github "$URL"
elif [[ $URL =~ (www\.)?gitlab\.com ]]; then
  handle_gitlab "$URL"
elif [[ $URL =~ [a-z0-9-]+\.wikipedia\.org ]]; then
  handle_wikipedia "$URL"
else
  if ! handle_markdown_fallback "$URL"; then
    handle_fallback "$URL"
  fi
fi
