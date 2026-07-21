#!/usr/bin/env bash
#
# ==============================================================================
# web-fetch.sh — Smart Web Crawler & Static Parser Engine (DRY Refactor)
# ==============================================================================
# Domain-specific web crawler targeting public APIs (GitHub, GitLab, Codeberg,
# Wikipedia) for 100% fidelity, with fallback to HTML parsing. Zero-Node.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (hy3)
#
# Version: 0.4.1
# ==============================================================================

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x
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

# Strings helpers
to_lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }
to_upper() { tr '[:lower:]' '[:upper:]' <<< "$1"; }

# Logger function
log() {
  echo -e "\n---\n\nDate: $(date '+%Y-%m-%d %H:%M:%S')\nArguments: $*" >> "$LOG_FILE"
}

if [[ $USE_JS == true ]]; then
  log "JavaScript fallback option is selected but not natively needed for specific REST APIs."
fi

# -----------------------------------------------------------------------------
# SHARED RENDERING HELPERS (DRY)
# -----------------------------------------------------------------------------

# Strip trailing .git and slash from a URL
clean_url() {
  local u="$1"
  u="${u%.git}"
  u="${u%/}"
  echo "$u"
}

# Human-readable byte size (requires `bc`)
human_size() {
  local size="$1"
  local size_str="${size} B"
  if [[ $size -gt 1048576 ]]; then
    size_str="$(echo "scale=2; $size / 1048576" | bc) MB"
  elif [[ $size -gt 1024 ]]; then
    size_str="$(echo "scale=2; $size / 1024" | bc) KB"
  fi
  echo "$size_str"
}

# Render a raw file block (used by all providers)
#   $1 = file_path
#   $2 = title_suffix (e.g. "" or " (GitLab)" or " (Codeberg Raw)")
#   $3 = meta_line (the full "> **Repository:** ..." markdown line)
#   $4 = raw_content
render_raw_file() {
  local file_path="$1"
  local title_suffix="$2"
  local meta_line="$3"
  local raw_content="$4"
  local ext="${file_path##*.}"
  [[ $ext == "$file_path" ]] && ext="text" # no extension
  echo "# 📄 File: $file_path$title_suffix"
  echo "$meta_line"
  echo ""
  echo "\`\`\`$ext"
  echo "$raw_content"
  echo "\`\`\`"
}

# Render a directory listing table
#   $1 = header_title   (e.g. "Directory" / "Directory (Codeberg)" / "Directory (GitLab)")
#   $2 = meta_line
#   $3 = json_data
#   $4 = mode          ("size" -> GitHub/Codeberg | "link" -> GitLab)
#   $5 = dir_view_base (size mode: if set, dirs show [View]($5/$name); else "-")
#   $6 = raw_project_path (link mode only)
#   $7 = branch            (link mode only)
render_dir_table() {
  local header_title="$1"
  local meta_line="$2"
  local json_data="$3"
  local mode="$4"
  local dir_view_base="${5:-}"
  local raw_project_path="${6:-}"
  local branch="${7:-}"
  echo "# 📂 $header_title"
  echo "$meta_line"
  echo ""
  if [[ $mode == "size" ]]; then
    echo "| Name | Type | Size | Download Link |"
    echo "| --- | --- | --- | --- |"
    while read -r row; do
      [[ -z $row ]] && continue
      local name type size download_url size_str
      name=$(jq -rc '.name' <<< "$row")
      type=$(jq -rc '.type' <<< "$row")
      size=$(jq -rc '.size' <<< "$row")
      download_url=$(jq -rc '.download_url // empty' <<< "$row")
      size_str=$(human_size "$size")
      if [[ $type == dir ]]; then
        if [[ -n $dir_view_base ]]; then
          echo "| 📁 $name | \`$type\` | - | [View](${dir_view_base}/${name}) |"
        else
          echo "| 📁 $name | \`$type\` | - | - |"
        fi
      else
        echo "| 📄 $name | \`$type\` | $size_str | [Raw Link]($download_url) |"
      fi
    done < <(jq -rc '.[]' <<< "$json_data" 2>/dev/null)
  else
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
    done < <(jq -rc '.[]' <<< "$json_data" 2>/dev/null)
  fi
}

# Render a single issue / PR / MR card
#   $1 = json_data
#   $2 = provider_label (e.g. "GitHub" / "Codeberg")
#   $3 = emoji          (e.g. "🐛" / "🏔️")
#   $4 = type_label     (e.g. "ISSUES" / "PULL" / "Issue" / "Pull Request")
#   $5 = number
#   $6 = owner
#   $7 = repo
#   $8 = author_field   (e.g. ".user.login" / ".user.username")
#   $9 = base_url       (e.g. "https://github.com/$owner/$repo")
render_issue_card() {
  local json_data="$1"
  local provider_label="$2"
  local emoji="$3"
  local type_label="$4"
  local number="$5"
  local owner="$6"
  local repo="$7"
  local author_field="$8"
  local base_url="$9"
  local title state author body comments created_at html_url
  title=$(jq -rc '.title' <<< "$json_data")
  state=$(jq -rc '.state' <<< "$json_data")
  author=$(jq -rc "$author_field" <<< "$json_data")
  comments=$(jq -rc '.comments // 0' <<< "$json_data")
  created_at=$(jq -rc '.created_at' <<< "$json_data")
  html_url=$(jq -rc '.html_url' <<< "$json_data")
  body=$(jq -rc '.body // ""' <<< "$json_data")
  echo "# $emoji $provider_label $type_label #$number: $title"
  echo "> **Repository:** [$owner/$repo]($base_url) | **Author:** @$author | **State:** \`$state\`"
  echo "> **Created at:** $created_at | **Comments:** $comments | **Web URL:** [$html_url]($html_url)"
  echo ""
  echo "---"
  echo ""
  if [[ -n $body && $body != "null" ]]; then
    echo "$body"
  else
    echo "*No description provided.*"
  fi
}

# Render a list table (open issues / PRs / MRs)
#   $1 = title
#   $2 = meta_line
#   $3 = json_data
#   $4 = mode       ("comments" | "simple" | "branches")
#   $5 = id_field   (e.g. ".number" / ".iid")
#   $6 = author_field
#   $7 = url_field  (e.g. ".html_url" / ".web_url")
render_list_table() {
  local title="$1"
  local meta_line="$2"
  local json_data="$3"
  local mode="$4"
  local id_field="$5"
  local author_field="$6"
  local url_field="$7"
  echo "# 📋 $title"
  echo "$meta_line"
  echo ""
  case "$mode" in
    comments)
      echo "| # | Title | Author | Comments | Created At |"
      echo "| --- | --- | --- | --- | --- |"
      ;;
    simple)
      echo "| # | Title | Author | Created At |"
      echo "| --- | --- | --- | --- |"
      ;;
    branches)
      echo "| # | Title | Author | Branches | Created At |"
      echo "| --- | --- | --- | --- | --- |"
      ;;
  esac
  while read -r row; do
    [[ -z $row ]] && continue
    local id title author created_at url
    id=$(jq -rc "$id_field" <<< "$row")
    title=$(jq -rc '.title' <<< "$row")
    author=$(jq -rc "$author_field" <<< "$row")
    created_at=$(jq -rc '.created_at' <<< "$row")
    url=$(jq -rc "$url_field" <<< "$row")
    title="${title//|/\\|}"
    case "$mode" in
      comments)
        local comments
        comments=$(jq -rc '.comments // 0' <<< "$row")
        echo "| [#$id]($url) | $title | @$author | $comments | $created_at |"
        ;;
      simple)
        echo "| [#$id]($url) | $title | @$author | $created_at |"
        ;;
      branches)
        local source_branch target_branch
        source_branch=$(jq -rc '.source_branch' <<< "$row")
        target_branch=$(jq -rc '.target_branch' <<< "$row")
        echo "| [#$id]($url) | $title | @$author | \`$source_branch\` ➔ \`$target_branch\` | $created_at |"
        ;;
    esac
  done < <(jq -rc '.[]' <<< "$json_data" 2>/dev/null)
}

# Render a SourceHut hub project page from its HTML
#   $1 = html_data
#   $2 = label   (e.g. "SourceHut Project" / "SourceHut Project (Fallback from blob 404)")
#   $3 = hub_url
render_sourcehut_hub() {
  local html_data="$1"
  local label="$2"
  local hub_url="$3"
  local title desc main_text
  title=$(htmlq "title" --text <<< "$html_data" | xargs)
  desc=$(htmlq ".header-extension" --text <<< "$html_data" | xargs)
  main_text=$(htmlq ".markdown" --text <<< "$html_data" 2>/dev/null)
  echo "# 🌌 $label: $title"
  if [[ -n $desc ]]; then
    echo "> **Description:** $desc"
  fi
  echo "> **Source Page:** [$hub_url]($hub_url)"
  echo "---"
  echo ""
  if [[ -n $main_text ]]; then
    echo "### 📖 Project README"
    echo ""
    echo "$main_text"
  else
    echo "*No README found on project page.*"
  fi
}

# --- SPECIALIZED API ROUTERS ---

# 1. GITHUB ROUTER
handle_github() {
  local url="$1"
  log "Handling URL as GitHub target: $url"

  url=$(clean_url "$url")

  if [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local branch="${BASH_REMATCH[4]}"
    local file_path="${BASH_REMATCH[5]}"

    log "GitHub Blob: owner=$owner repo=$repo branch=$branch file=$file_path"

    local raw_url="https://raw.githubusercontent.com/$owner/$repo/$branch/$file_path"
    local raw_content

    if raw_content=$(curl "${CURL_OPTS[@]}" "$raw_url"); then
      render_raw_file "$file_path" "" "> **Repository:** [$owner/$repo]($url) | **Branch:** \`$branch\`" "$raw_content"
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

    local api_url="https://api.github.com/repos/$owner/$repo/contents/$dir_path?ref=$branch"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_dir_table "Directory: \`/$dir_path\`" "> **Repository:** [$owner/$repo]($url) | **Ref:** \`$branch\`" "$json_data" "size" ""
    else
      echo "Error: Could not retrieve directory listing from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"

    log "GitHub Repo Home: owner=$owner repo=$repo"

    local meta_url="https://api.github.com/repos/$owner/$repo"
    local readme_url="https://api.github.com/repos/$owner/$repo/readme"

    local meta_json
    if ! meta_json=$(curl "${CURL_OPTS[@]}" "$meta_url"); then
      echo "Error: Could not retrieve repository metadata from $meta_url" >&2
      exit 2
    fi

    local name desc stars forks issues lang license def_branch
    name=$(jq -rc '.name' <<< "$meta_json")
    desc=$(jq -rc '.description' <<< "$meta_json")
    stars=$(jq -rc '.stargazers_count' <<< "$meta_json")
    forks=$(jq -rc '.forks_count' <<< "$meta_json")
    issues=$(jq -rc '.open_issues_count' <<< "$meta_json")
    lang=$(jq -rc '.language' <<< "$meta_json")
    license=$(jq -rc '.license.name // "None"' <<< "$meta_json")
    def_branch=$(jq -rc '.default_branch' <<< "$meta_json")

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

  elif [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local type="${BASH_REMATCH[4]}"
    local number="${BASH_REMATCH[5]}"

    log "GitHub Issue/PR: owner=$owner repo=$repo type=$type number=$number"

    local api_url="https://api.github.com/repos/$owner/$repo/issues/$number"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_issue_card "$json_data" "GitHub" "🐛" "$(to_upper "$type")" "$number" "$owner" "$repo" ".user.login" "https://github.com/$owner/$repo"

      local comments
      comments=$(jq -rc '.comments' <<< "$json_data")
      if [[ $comments -gt 0 ]]; then
        local comments_url="https://api.github.com/repos/$owner/$repo/issues/$number/comments"
        local comments_json
        if comments_json=$(curl "${CURL_OPTS[@]}" "$comments_url" 2>/dev/null); then
          echo ""
          echo "---"
          echo "### 💬 Discussion Thread ($comments comments)"
          echo ""
          while read -r comment; do
            [[ -z $comment ]] && continue
            local c_author c_body c_date
            c_author=$(jq -rc '.user.login' <<< "$comment")
            c_date=$(jq -rc '.created_at' <<< "$comment")
            c_body=$(jq -rc '.body' <<< "$comment")
            echo "#### 👤 @$c_author ($c_date)"
            echo "$c_body"
            echo ""
            echo "---"
          done < <(jq -rc '.[]' <<< "$comments_json" 2>/dev/null)
        fi
      fi
    else
      echo "Error: Could not retrieve issue/PR from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)/(issues|pulls)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local type="${BASH_REMATCH[4]}"

    log "GitHub Issues/PRs List: owner=$owner repo=$repo type=$type"

    local endpoint="issues"
    [[ $type == "pulls" ]] && endpoint="pulls"

    local api_url="https://api.github.com/repos/$owner/$repo/$endpoint?state=open"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      local list_title="Open Issues"
      [[ $type == "pulls" ]] && list_title="Open Pull Requests"
      render_list_table "GitHub $list_title: $owner/$repo" "> **Repository:** [github.com/$owner/$repo](https://github.com/$owner/$repo)" "$json_data" "comments" ".number" ".user.login" ".html_url"
    else
      echo "Error: Could not retrieve $type list from API ($api_url)" >&2
      exit 2
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

  local path="${url#*://*/}"

  local owner="${path%%/*}"
  local temp="${path#*/}"
  local repo="${temp%%/*}"
  local remaining="${temp#*/}"

  local branch file_path
  if [[ $remaining =~ ^(refs/(heads|tags|pull)/[^/]+)/(.*) ]]; then
    branch="${BASH_REMATCH[1]}"
    file_path="${BASH_REMATCH[3]}"
  else
    branch="${remaining%%/*}"
    file_path="${remaining#*/}"
  fi

  log "Raw GitHub Parse: owner=$owner repo=$repo branch=$branch file=$file_path"

  local raw_content
  if raw_content=$(curl "${CURL_OPTS[@]}" "$url"); then
    render_raw_file "$file_path" "" "> **Repository:** [$owner/$repo]($url) | **Branch/Reference:** \`$branch\`" "$raw_content"
  else
    echo "Error: Could not retrieve raw file from $url" >&2
    exit 2
  fi
}

# 1c. GITHUB GIST ROUTER
handle_gist() {
  local url="$1"
  log "Handling URL as GitHub Gist target: $url"

  url=$(clean_url "$url")

  local owner gist_id
  if [[ $url =~ ^https?://(www\.)?gist\.github\.com/([^/]+)/([^/]+) ]]; then
    owner="${BASH_REMATCH[2]}"
    gist_id="${BASH_REMATCH[3]}"
  elif [[ $url =~ ^https?://gist\.githubusercontent\.com/([^/]+)/([^/]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    gist_id="${BASH_REMATCH[2]}"
  else
    echo "Error: Invalid GitHub Gist URL format." >&2
    exit 1
  fi

  log "Gist: owner=$owner gist_id=$gist_id"

  local api_url="https://api.github.com/gists/$gist_id"
  local json_data

  if ! json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
    echo "Error: Could not retrieve gist metadata from $api_url" >&2
    exit 2
  fi

  local g_description g_owner g_created g_updated g_comments
  g_description=$(jq -rc '.description // ""' <<< "$json_data")
  g_owner=$(jq -rc '.owner.login // "anonymous"' <<< "$json_data")
  g_created=$(jq -rc '.created_at // ""' <<< "$json_data")
  g_updated=$(jq -rc '.updated_at // ""' <<< "$json_data")
  g_comments=$(jq -rc '.comments // 0' <<< "$json_data")

  echo "# 📝 GitHub Gist: $gist_id"
  echo "> **Author:** @$g_owner | **Created:** $g_created | **Updated:** $g_updated | **Comments:** $g_comments"
  if [[ -n $g_description ]]; then
    echo "> **Description:** $g_description"
  fi
  echo "> **Source:** [$url]($url)"
  echo ""
  echo "---"
  echo ""

  local fc=0
  while read -r f_obj; do
    [[ -z $f_obj ]] && continue
    local f_name f_lang f_size f_content f_raw_url ext
    f_name=$(jq -rc '.filename' <<< "$f_obj")
    f_lang=$(jq -rc '.language // ""' <<< "$f_obj")
    f_size=$(jq -rc '.size // 0' <<< "$f_obj")
    f_content=$(jq -rc '.content // ""' <<< "$f_obj")
    f_raw_url=$(jq -rc '.raw_url // ""' <<< "$f_obj")

    fc=$((fc + 1))
    ext="${f_name##*.}"
    [[ $ext == "$f_name" ]] && ext="text"
    echo "## 📄 File $fc: $f_name"
    [[ -n $f_lang ]] && echo "> **Language:** $f_lang | **Size:** $(human_size "$f_size") | **Raw:** [$f_raw_url]($f_raw_url)"
    echo ""
    echo "\`\`\`$ext"
    echo "$f_content"
    echo "\`\`\`"
    echo ""
  done < <(jq -rc '.files[]' <<< "$json_data" 2>/dev/null)

  if [[ $g_comments -gt 0 ]]; then
    local comments_url="https://api.github.com/gists/$gist_id/comments"
    local comments_json
    if comments_json=$(curl "${CURL_OPTS[@]}" "$comments_url" 2>/dev/null); then
      echo "---"
      echo "### 💬 Discussion Thread ($g_comments comments)"
      echo ""
      while read -r comment; do
        [[ -z $comment ]] && continue
        local c_author c_body c_date
        c_author=$(jq -rc '.user.login' <<< "$comment")
        c_date=$(jq -rc '.created_at' <<< "$comment")
        c_body=$(jq -rc '.body' <<< "$comment")
        echo "#### 👤 @$c_author ($c_date)"
        echo "$c_body"
        echo ""
        echo "---"
      done < <(jq -rc '.[]' <<< "$comments_json" 2>/dev/null)
    fi
  fi
}

# 2. GITLAB ROUTER
handle_gitlab() {
  local url="$1"
  log "Handling URL as GitLab target: $url"

  url=$(clean_url "$url")

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
      render_raw_file "$file_path" " (GitLab Raw)" "> **Repository:** [$owner/$repo]($raw_project_path) | **Branch:** \`$branch\`" "$raw_content"
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
      render_raw_file "$file_path" " (GitLab)" "> **Repository:** [$owner/$repo]($raw_project_path) | **Branch:** \`$branch\`" "$raw_content"
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
      render_dir_table "Directory (GitLab): \`/$dir_path\`" "> **Repository:** [$owner/$repo]($raw_project_path) | **Ref:** \`$branch\`" "$json_data" "link" "" "$raw_project_path" "$branch"
    else
      echo "Error: Could not retrieve directory listing from GitLab API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ (.*)/-/issues/([0-9]+)/? ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local issue_iid="${BASH_REMATCH[2]}"
    local project_path="${raw_project_path#*://*/}"
    local encoded_project="${project_path////%2F}"

    log "GitLab Single Issue: project=$project_path issue_iid=$issue_iid"

    local api_url="https://gitlab.com/api/v4/projects/$encoded_project/issues/$issue_iid"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_issue_card "$json_data" "GitLab" "🦊" "Issue" "$issue_iid" "${project_path%/*}" "${project_path##*/}" ".author.username" "$raw_project_path"
    else
      echo "Error: Could not retrieve GitLab issue from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ (.*)/-/merge_requests/([0-9]+)/? ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local mr_iid="${BASH_REMATCH[2]}"
    local project_path="${raw_project_path#*://*/}"
    local encoded_project="${project_path////%2F}"

    log "GitLab Merge Request: project=$project_path mr_iid=$mr_iid"

    local api_url="https://gitlab.com/api/v4/projects/$encoded_project/merge_requests/$mr_iid"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      local title state author body created_at web_url source_branch target_branch
      title=$(jq -rc '.title' <<< "$json_data")
      state=$(jq -rc '.state' <<< "$json_data")
      author=$(jq -rc '.author.username' <<< "$json_data")
      created_at=$(jq -rc '.created_at' <<< "$json_data")
      web_url=$(jq -rc '.web_url' <<< "$json_data")
      body=$(jq -rc '.description // ""' <<< "$json_data")
      source_branch=$(jq -rc '.source_branch' <<< "$json_data")
      target_branch=$(jq -rc '.target_branch' <<< "$json_data")

      echo "# 🦊 GitLab Merge Request #$mr_iid: $title"
      echo "> **Project:** [$project_path]($raw_project_path) | **Author:** @$author | **State:** \`$state\`"
      echo "> **Branches:** \`$source_branch\` ➔ \`$target_branch\`"
      echo "> **Created at:** $created_at | **Web URL:** [$web_url]($web_url)"
      echo ""
      echo "---"
      echo ""
      if [[ -n $body && $body != "null" ]]; then
        echo "$body"
      else
        echo "*No description provided.*"
      fi
    else
      echo "Error: Could not retrieve GitLab merge request from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ (.*)/-/issues/?$ ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local project_path="${raw_project_path#*://*/}"
    local encoded_project="${project_path////%2F}"

    log "GitLab Issues List: project=$project_path"

    local api_url="https://gitlab.com/api/v4/projects/$encoded_project/issues?state=opened"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_list_table "GitLab Open Issues: $project_path" "> **Project:** [$project_path]($raw_project_path)" "$json_data" "simple" ".iid" ".author.username" ".web_url"
    else
      echo "Error: Could not retrieve GitLab issues list from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ (.*)/-/merge_requests/?$ ]]; then
    local raw_project_path="${BASH_REMATCH[1]}"
    local project_path="${raw_project_path#*://*/}"
    local encoded_project="${project_path////%2F}"

    log "GitLab MRs List: project=$project_path"

    local api_url="https://gitlab.com/api/v4/projects/$encoded_project/merge_requests?state=opened"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_list_table "GitLab Open Merge Requests: $project_path" "> **Project:** [$project_path]($raw_project_path)" "$json_data" "branches" ".iid" ".author.username" ".web_url"
    else
      echo "Error: Could not retrieve GitLab MRs list from API ($api_url)" >&2
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

# 4. CODEBERG ROUTER (Forgejo/Gitea compatible)
handle_codeberg() {
  local url="$1"
  log "Handling URL as Codeberg target: $url"

  url=$(clean_url "$url")

  if [[ $url =~ ^https?://(www.)?codeberg.org/([^/]+)/([^/]+)/raw/(branch|commit|tag)/([^/]+)/(.+)$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local ref_type="${BASH_REMATCH[4]}"
    local ref="${BASH_REMATCH[5]}"
    local file_path="${BASH_REMATCH[6]}"

    log "Codeberg Raw: owner=$owner repo=$repo ref_type=$ref_type ref=$ref file=$file_path"

    local raw_content
    if raw_content=$(curl "${CURL_OPTS[@]}" "$url"); then
      render_raw_file "$file_path" " (Codeberg Raw)" "> **Repository:** [$owner/$repo]($url) | **Ref:** \`$ref\`" "$raw_content"
    else
      echo "Error: Could not retrieve raw file from $url" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www.)?codeberg.org/([^/]+)/([^/]+)/src/(branch|commit|tag)/([^/]+)/(.+)$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local ref_type="${BASH_REMATCH[4]}"
    local ref="${BASH_REMATCH[5]}"
    local file_path="${BASH_REMATCH[6]}"

    log "Codeberg Src: owner=$owner repo=$repo ref_type=$ref_type ref=$ref file=$file_path"

    local raw_url="https://codeberg.org/$owner/$repo/raw/$ref_type/$ref/$file_path"
    local raw_content

    if raw_content=$(curl "${CURL_OPTS[@]}" "$raw_url"); then
      render_raw_file "$file_path" " (Codeberg)" "> **Repository:** [$owner/$repo](${url%%/src/*}) | **Ref:** \`$ref\`" "$raw_content"
    else
      local api_url="https://codeberg.org/api/v1/repos/$owner/$repo/contents/$file_path?ref=$ref"
      local json_data
      if json_data=$(curl "${CURL_OPTS[@]}" "$api_url" 2>/dev/null); then
        if jq -e 'type == "array"' <<< "$json_data" >/dev/null 2>&1; then
          render_dir_table "Directory (Codeberg): \`/$file_path\`" "> **Repository:** [$owner/$repo](${url%%/src/*}) | **Ref:** \`$ref\`" "$json_data" "size" "$url"
        else
          echo "Error: Could not retrieve raw file or directory listing from Codeberg." >&2
          exit 2
        fi
      else
        echo "Error: Could not retrieve raw file from $raw_url" >&2
        exit 2
      fi
    fi

  elif [[ $url =~ ^https?://(www.)?codeberg.org/([^/]+)/([^/]+)/src/([^/]+)/(.+)$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local ref="${BASH_REMATCH[4]}"
    local file_path="${BASH_REMATCH[5]}"

    log "Codeberg Src (Implicit Ref): owner=$owner repo=$repo ref=$ref file=$file_path"

    local api_url="https://codeberg.org/api/v1/repos/$owner/$repo/contents/$file_path?ref=$ref"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url" 2>/dev/null); then
      if jq -e 'type == "array"' <<< "$json_data" >/dev/null 2>&1; then
        render_dir_table "Directory (Codeberg): \`/$file_path\`" "> **Repository:** [$owner/$repo](${url%%/src/*}) | **Ref:** \`$ref\`" "$json_data" "size" "$url"
      else
        local raw_url="https://codeberg.org/$owner/$repo/raw/branch/$ref/$file_path"
        local raw_content
        if raw_content=$(curl "${CURL_OPTS[@]}" "$raw_url"); then
          render_raw_file "$file_path" " (Codeberg)" "> **Repository:** [$owner/$repo](${url%%/src/*}) | **Ref:** \`$ref\`" "$raw_content"
        else
          echo "Error: Could not retrieve raw file from $raw_url" >&2
          exit 2
        fi
      fi
    else
      echo "Error: Could not retrieve info for $file_path" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?codeberg\.org/([^/]+)/([^/]+)/issues/([0-9]+)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local number="${BASH_REMATCH[4]}"

    log "Codeberg Single Issue: owner=$owner repo=$repo number=$number"

    local api_url="https://codeberg.org/api/v1/repos/$owner/$repo/issues/$number"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_issue_card "$json_data" "Codeberg" "🏔️" "Issue" "$number" "$owner" "$repo" ".user.username" "https://codeberg.org/$owner/$repo"
    else
      echo "Error: Could not retrieve Codeberg issue from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?codeberg\.org/([^/]+)/([^/]+)/pulls/([0-9]+)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    local number="${BASH_REMATCH[4]}"

    log "Codeberg Single Pull Request: owner=$owner repo=$repo number=$number"

    local api_url="https://codeberg.org/api/v1/repos/$owner/$repo/pulls/$number"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_issue_card "$json_data" "Codeberg" "🏔️" "Pull Request" "$number" "$owner" "$repo" ".user.username" "https://codeberg.org/$owner/$repo"
    else
      echo "Error: Could not retrieve Codeberg pull request from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?codeberg\.org/([^/]+)/([^/]+)/issues/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"

    log "Codeberg Issues List: owner=$owner repo=$repo"

    local api_url="https://codeberg.org/api/v1/repos/$owner/$repo/issues?state=open&type=issues"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_list_table "Codeberg Open Issues: $owner/$repo" "> **Repository:** [codeberg.org/$owner/$repo](https://codeberg.org/$owner/$repo)" "$json_data" "comments" ".number" ".user.username" ".html_url"
    else
      echo "Error: Could not retrieve Codeberg issues list from API ($api_url)" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://(www\.)?codeberg\.org/([^/]+)/([^/]+)/pulls/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"

    log "Codeberg Pull Requests List: owner=$owner repo=$repo"

    local api_url="https://codeberg.org/api/v1/repos/$owner/$repo/pulls?state=open"
    local json_data
    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
      render_list_table "Codeberg Open Pull Requests: $owner/$repo" "> **Repository:** [codeberg.org/$owner/$repo](https://codeberg.org/$owner/$repo)" "$json_data" "simple" ".number" ".user.username" ".html_url"
    else
      echo "Error: Could not retrieve Codeberg pulls list from API ($api_url)" >&2
      exit 2
    fi

  else
    if [[ $url =~ ^https?://(www.)?codeberg.org/([^/]+)/([^/]+)/?$ ]]; then
      local owner="${BASH_REMATCH[2]}"
      local repo="${BASH_REMATCH[3]}"

      log "Codeberg Repo Home: owner=$owner repo=$repo"

      local api_url="https://codeberg.org/api/v1/repos/$owner/$repo"
      local meta_json
      if ! meta_json=$(curl "${CURL_OPTS[@]}" "$api_url"); then
        echo "Error: Could not retrieve repository metadata from $api_url" >&2
        exit 2
      fi

      local name desc stars forks issues lang license def_branch web_url
      name=$(jq -rc '.name' <<< "$meta_json")
      desc=$(jq -rc '.description' <<< "$meta_json")
      stars=$(jq -rc '.stars_count' <<< "$meta_json")
      forks=$(jq -rc '.forks_count' <<< "$meta_json")
      issues=$(jq -rc '.open_issues_count' <<< "$meta_json")
      lang=$(jq -rc '.language' <<< "$meta_json")
      license=$(jq -rc '.license // "None"' <<< "$meta_json")
      def_branch=$(jq -rc '.default_branch' <<< "$meta_json")
      web_url=$(jq -rc '.html_url' <<< "$meta_json")

      echo "# 🏔️ Codeberg: $owner / $name"
      echo "> **Description:** $desc"
      echo ""
      echo "### 📊 Repository Statistics"
      echo "- ⭐ **Stars:** $stars | 🍴 **Forks:** $forks | 🐛 **Issues:** $issues"
      echo "- 💻 **Language:** $lang | 📄 **License:** $license | 🌿 **Default Branch:** $def_branch"
      echo "- 🌐 **Web:** [$web_url]($web_url)"
      echo ""
      echo "---"
      echo ""

      local readme_url="https://codeberg.org/$owner/$repo/raw/branch/$def_branch/README.md"
      local readme_content
      if readme_content=$(curl "${CURL_OPTS[@]}" "$readme_url" 2>/dev/null); then
        echo "### 📖 README.md"
        echo ""
        echo "$readme_content"
      else
        readme_url="https://codeberg.org/$owner/$repo/raw/branch/$def_branch/readme.md"
        if readme_content=$(curl "${CURL_OPTS[@]}" "$readme_url" 2>/dev/null); then
          echo "### 📖 readme.md"
          echo ""
          echo "$readme_content"
        else
          echo "*No README found or error fetching README.*"
        fi
      fi
    else
      echo "Error: Invalid Codeberg URL format." >&2
      exit 1
    fi
  fi
}

# 5. SOURCEHUT ROUTER
handle_sourcehut() {
  local url="$1"
  log "Handling URL as SourceHut target: $url"

  local sourcehut_curl_opts=()
  for opt in "${CURL_OPTS[@]}"; do
    if [[ $opt == "$USER_AGENT" ]]; then
      sourcehut_curl_opts+=("curl/7.81.0")
    else
      sourcehut_curl_opts+=("$opt")
    fi
  done

  url=$(clean_url "$url")

  if [[ $url =~ ^https?://(www.)?sr.ht/~([^/]+)/([^/]+)/?$ ]]; then
    local owner="~${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    log "SourceHut Hub Project: owner=$owner repo=$repo"

    local hub_url="https://sr.ht/$owner/$repo/"
    local html_data
    if html_data=$(curl "${sourcehut_curl_opts[@]}" "$hub_url") && [[ -n $html_data ]]; then
      render_sourcehut_hub "$html_data" "SourceHut Project" "$hub_url"
      return 0
    else
      echo "Error: Could not retrieve SourceHut Hub project from $hub_url" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://git.sr.ht/~([^/]+)/([^/]+)/blob/([^/]+)/(.+)$ ]]; then
    local owner="~${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    local branch="${BASH_REMATCH[3]}"
    local file_path="${BASH_REMATCH[4]}"

    log "SourceHut Raw/Blob: owner=$owner repo=$repo branch=$branch file=$file_path"

    local raw_content
    if raw_content=$(curl "${sourcehut_curl_opts[@]}" "$url" 2>/dev/null); then
      render_raw_file "$file_path" " (SourceHut)" "> **Repository:** [$owner/$repo](${url%%/blob/*}) | **Branch:** \`$branch\`" "$raw_content"
    else
      log "Git raw/blob returned 404, falling back to Hub project page..."
      local hub_url="https://sr.ht/$owner/$repo/"
      local html_data
      if html_data=$(curl "${sourcehut_curl_opts[@]}" "$hub_url" 2>/dev/null) && [[ -n $html_data ]]; then
        render_sourcehut_hub "$html_data" "SourceHut Project (Fallback from blob 404)" "$hub_url"
        return 0
      else
        echo "Error: Could not retrieve raw file from $url or Hub fallback from $hub_url" >&2
        exit 2
      fi
    fi

  elif [[ $url =~ ^https?://git.sr.ht/~([^/]+)/([^/]+)/tree/([^/]+)/item/(.+)$ ]]; then
    local owner="~${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    local branch="${BASH_REMATCH[3]}"
    local file_path="${BASH_REMATCH[4]}"

    log "SourceHut Tree Item: owner=$owner repo=$repo branch=$branch file=$file_path"

    local raw_url="https://git.sr.ht/$owner/$repo/blob/$branch/$file_path"
    local raw_content
    if raw_content=$(curl "${sourcehut_curl_opts[@]}" "$raw_url" 2>/dev/null); then
      render_raw_file "$file_path" " (SourceHut)" "> **Repository:** [$owner/$repo](${url%%/tree/*}) | **Branch:** \`$branch\`" "$raw_content"
    else
      echo "Error: Could not retrieve raw file from $raw_url" >&2
      exit 2
    fi

  elif [[ $url =~ ^https?://git.sr.ht/~([^/]+)/([^/]+)/?$ ]]; then
    local owner="~${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"

    log "SourceHut Repo Home: owner=$owner repo=$repo"

    local html_data
    if html_data=$(curl "${sourcehut_curl_opts[@]}" "$url" 2>/dev/null); then
      local title def_branch clone_url
      title=$(htmlq "title" --text <<< "$html_data" | xargs)
      def_branch=$(htmlq 'meta[name="vcs:default-branch"]' --attribute content <<< "$html_data" 2>/dev/null | head -n 1)
      [[ -z $def_branch ]] && def_branch="master"

      clone_url=$(htmlq 'meta[name="vcs:clone"]' --attribute content <<< "$html_data" 2>/dev/null | head -n 1)

      echo "# 🌌 SourceHut: $title"
      if [[ -n $clone_url ]]; then
        echo "> **Clone:** \`git clone $clone_url\`"
      fi
      echo "> **Default Branch:** \`$def_branch\`"
      echo "---"
      echo ""

      local readme_url="https://git.sr.ht/$owner/$repo/blob/$def_branch/README.md"
      local readme_content
      if readme_content=$(curl "${sourcehut_curl_opts[@]}" "$readme_url" 2>/dev/null); then
        echo "### 📖 README.md"
        echo ""
        echo "$readme_content"
      else
        readme_url="https://git.sr.ht/$owner/$repo/blob/$def_branch/readme.md"
        if readme_content=$(curl "${sourcehut_curl_opts[@]}" "$readme_url" 2>/dev/null); then
          echo "### 📖 readme.md"
          echo ""
          echo "$readme_content"
        else
          local main_text
          main_text=$(htmlq "p, h1, h2, h3, h4, pre" --text <<< "$html_data" 2>/dev/null)
          if [[ -n $main_text ]]; then
            echo "$main_text"
          else
            echo "*No README found and page could not be parsed.*"
          fi
        fi
      fi
    else
      log "Git repo home returned 404, falling back to Hub project page..."
      local hub_url="https://sr.ht/$owner/$repo/"
      if html_data=$(curl "${sourcehut_curl_opts[@]}" "$hub_url" 2>/dev/null) && [[ -n $html_data ]]; then
        render_sourcehut_hub "$html_data" "SourceHut Project (Fallback from Git 404)" "$hub_url"
        return 0
      else
        echo "Error: Could not retrieve repository home from $url or Hub fallback from $hub_url" >&2
        exit 2
      fi
    fi
  else
    echo "Error: Invalid SourceHut URL format." >&2
    exit 1
  fi
}

# 6. WIKIPEDIA ROUTER
handle_wikipedia() {
  local url="$1"
  log "Handling URL as Wikipedia target: $url"

  if [[ $url =~ ^https?://([a-z0-9-]+)\.wikipedia\.org/wiki/([^?#]+) ]]; then
    local lang="${BASH_REMATCH[1]}"
    local title_encoded="${BASH_REMATCH[2]}"

    log "Wikipedia: lang=$lang title_encoded=$title_encoded"

    local api_url="https://${lang}.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext&exlimit=1&titles=${title_encoded}&format=json&redirects=1"
    local json_data

    if json_data=$(curl "${CURL_OPTS[@]}" "$api_url"); then
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

# 7. MARKDOWN PROBE FALLBACK ROUTER
handle_markdown_fallback() {
  local url="$1"
  log "Checking for Markdown direct availability or probe: $url"

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

  local response_body
  if response_body=$(curl "${CURL_OPTS[@]}" "$target_url" 2>/dev/null) && [[ -n $response_body ]]; then
    local body_chunk="${response_body:0:1000}"
    local body_chunk_lc
    body_chunk_lc=$(echo "$body_chunk" | tr '[:upper:]' '[:lower:]')

    if [[ $body_chunk_lc == *"<doctype"* ]] || \
       [[ $body_chunk_lc == *"<html"* ]] || \
       [[ $body_chunk_lc == *"<body"* ]] || \
       [[ $body_chunk_lc == *"<head"* ]]; then
        log "Probe URL $target_url returned HTML instead of raw Markdown."
        return 1
    fi

    log "Markdown version found dynamically at: $target_url"

    local page_title="${clean_url##*/}"
    page_title="${page_title//-/ }"
    page_title="${page_title//_/ }"
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

# 8. GENERAL FALLBACK ROUTER (Using htmlq)
handle_fallback() {
  local url="$1"

  local html_data
  if ! html_data=$(curl "${CURL_OPTS[@]}" "$url") || [[ -z $html_data ]]; then
    echo "Error: Failed to retrieve HTML from $url" >&2
    exit 2
  fi

  if [[ -n $BIN_HTMLQ ]]; then
    local title desc main_text
    title=$(htmlq "title" --text <<< "$html_data" | xargs)
    [[ -z $title ]] && title="Webpage"

    desc=$(htmlq "meta[name=description]" --attribute content <<< "$html_data" 2>/dev/null | xargs)
    if [[ -z $desc ]]; then
      desc=$(htmlq "meta[property=\"og:description\"]" --attribute content <<< "$html_data" 2>/dev/null | xargs)
    fi

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

if [[ $URL =~ gist.github.com ]] || [[ $URL =~ gist.githubusercontent.com ]]; then
  handle_gist "$URL"
elif [[ $URL =~ (www.)?github.com ]]; then
  handle_github "$URL"
elif [[ $URL =~ raw.githubusercontent.com ]]; then
  handle_raw_github "$URL"
elif [[ $URL =~ (www.)?gitlab.com ]]; then
  handle_gitlab "$URL"
elif [[ $URL =~ (www.)?codeberg.org ]]; then
  handle_codeberg "$URL"
elif [[ $URL =~ (www.)?(git.)?sr.ht ]]; then
  handle_sourcehut "$URL"
elif [[ $URL =~ [a-z0-9-]+.wikipedia.org ]]; then
  handle_wikipedia "$URL"
else
  if ! handle_markdown_fallback "$URL"; then
    handle_fallback "$URL"
  fi
fi
