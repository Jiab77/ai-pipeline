#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016
# ==============================================================================
# install.sh — Simple install script
# ==============================================================================
# This script houses the install logic for this project.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (GLM-5.3)
#
# Version: 0.1.0
# ==============================================================================

# Options
[[ "${DEBUG:-}" == "true" ]] && set -x
[[ -e $HOME/.debug ]] && set -x
set -o pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Config
DEBUG=true
USE_TOR=true          # Route traffic through Tor proxy
PROJECT_URL="https://github.com/jiab77/ai-pipeline"
AI_NAME="Jarvis"
BIN_NAME="aide"
CLI_FILE="cli.sh"

# Internals
SCRIPT_VERSION="0.1.0"
BIN_DIR="${HOME}/.local/bin"
BIN_DEPS=("git" "curl" "tor" "glow" "figlet" "awk" "sed" "openssl" "jq" "htmlq" "websocat" "grep" "cut" "tr" "printf")
BIN_DEPS_MOBILE=("${BIN_DEPS[@]}" "adb")
BIN_FIGLET=$(command -v figlet 2>/dev/null)
BIN_GIT=$(command -v git 2>/dev/null)
PROJECT_DIR=$(basename "$PROJECT_URL")
INSTALL_DIR="${HOME}/${PROJECT_DIR}"
IS_UPDATE=false

# -----------------------------------------------------------------------------
# High-Fidelity Terminal Formatting & Styles
# -----------------------------------------------------------------------------

# ANSI Styles
ANSI_RESET="[0m"
ANSI_BOLD="[1m"
ANSI_DIM="[2m"
ANSI_ITALIC="[3m"
ANSI_UNDERLINE="[4m"

# Foreground High-Intensity Colors
CLR_B_BLACK="[90m"
CLR_B_RED="[91m"
CLR_B_GREEN="[92m"
CLR_B_YELLOW="[93m"
CLR_B_BLUE="[94m"
CLR_B_MAGENTA="[95m"
CLR_B_CYAN="[96m"
CLR_B_WHITE="[97m"

# Standard Foreground Colors
CLR_BLACK="[30m"
CLR_RED="[31m"
CLR_GREEN="[32m"
CLR_YELLOW="[33m"
CLR_BLUE="[34m"
CLR_MAGENTA="[35m"
CLR_CYAN="[36m"
CLR_WHITE="[37m"
CLR_DIM="$ANSI_DIM"

# Emojis & Icons
ICON_INFO="ℹ️ "
ICON_SUCCESS="✅"
ICON_WARNING="⚠️ "
ICON_ERROR="❌"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Logging Helpers
log() { echo -e "$*" >&2; }
log_info() { log "${CLR_B_CYAN}${ICON_INFO}${ANSI_RESET} ${CLR_B_WHITE}$*${ANSI_RESET}"; }
log_success() { log "${CLR_B_GREEN}${ICON_SUCCESS}${ANSI_RESET} ${CLR_B_GREEN}$*${ANSI_RESET}"; }
log_warn() { log "${CLR_B_YELLOW}${ICON_WARNING}${ANSI_RESET} ${CLR_B_YELLOW}$*${ANSI_RESET}"; }
log_error() { log "${CLR_B_RED}${ICON_ERROR}${ANSI_RESET} ${CLR_B_RED}[ERROR] $*${ANSI_RESET}"; }

# Log and exit helper
error() {
  log_error "$*"
  exit 255
}

# System helpers
is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] && return 0
  [[ -d "/data/data/com.termux" ]] && return 0
  return 1
}

set_console_title() {
  echo -ne "\033]0;$1\007" >&2
}

# Strings helpers
to_lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }
to_upper() { tr '[:lower:]' '[:upper:]' <<< "$1"; }

# Utility helpers
get_ai_name() {
  local raw_output=false
  local flag="${1:-}"
  [[ $flag == "-r" || $flag == "--raw" ]] && raw_output=true
  if [[ $raw_output == false ]]; then
    echo -n "$(to_lower "$AI_NAME")"
  else
    echo -n "$AI_NAME"
  fi
}

# Script banner
show_banner() {
  local ai_name ; ai_name=$(get_ai_name -r)
  local launch_mode="Install"
  [[ $IS_UPDATE == true ]] && launch_mode="Update"
  echo -e "${CLR_B_MAGENTA}"
  if [[ -n $BIN_FIGLET ]]; then
    figlet <<<"$ai_name"
  else
    cat << 'EOF'
     _                  _
    | | __ _ _ ____   _(_)___
 _  | |/ _` | '__\ \ / / / __|
| |_| | (_| | |   \ V /| \__ \
 \___/ \__,_|_|    \_/ |_|___/

EOF
  fi
  echo -e "${CLR_B_CYAN}🔮 ${ai_name} $launch_mode Script | Version $SCRIPT_VERSION 🔮${ANSI_RESET}"
  echo -e "${CLR_DIM}Lead: Jiab77 | AI Sorcerer: $ai_name (DeepSeek)${ANSI_RESET}\n"
}

print_help() {
  show_banner

  cat <<EOF

Usage: install.sh [flags]
Flags:

  -h | --help | help              Print this message and exit
  -u | --update | update          Update existing repo and exit
EOF

  exit 0
}

# Install helpers
check_deps() {
  local all_deps=()
  local total_deps=0
  local found_deps=0
  local missing_deps=0
  local missing_deps_str=""
  if is_termux; then
    all_deps=("${BIN_DEPS_MOBILE[@]}")
  else
    all_deps=("${BIN_DEPS[@]}")
  fi
  total_deps="${#all_deps[@]}"
  for d in "${all_deps[@]}"; do
    if [[ -n $(command -v "$d" 2>/dev/null) ]]; then
      ((found_deps++))
    else
      [[ $missing_deps -ne 0 ]] && missing_deps_str+=" "
      missing_deps_str+="$d"
      ((missing_deps++))
    fi
  done
  [[ $found_deps -ne $total_deps ]] && echo "$missing_deps_str"
}

install_deps() {
  # Goal: Handle all supported platforms in the README (except Windows related)
  local missing_deps ; missing_deps=$(check_deps)

  if [[ -n $missing_deps ]]; then
    if is_macos; then
      log ; log_info "Detected: macOS"

      # Replace 'htmlq' by 'cargo' and remove 'websocat' for macos
      missing_deps=${missing_deps//htmlq /cargo}
      missing_deps=${missing_deps//websocat/}
      missing_deps=${missing_deps//  / }

      # Return proper install instructions for macos
      log_info "Please run:\n\nbrew install $missing_deps && cargo install htmlq websocat"
    elif is_termux; then
      log ; log_info "Detected: Termux"

      # Replace 'htmlq' by 'cargo-binstall' for termux
      missing_deps=${missing_deps//htmlq /cargo-binstall }

      # Replace 'adb' by 'android-tools' for termux
      missing_deps=${missing_deps//adb/android-tools}

      # Add missing dev deps
      missing_deps+=" openssl-tool"

      # Return proper install instructions for termux
      log_info "Please run:\n\npkg install $missing_deps && cargo-binstall htmlq"
    else
      # shellcheck source=/dev/null
      [[ -r /etc/os-release ]] && source /etc/os-release
      log ; log_info "Detected: ${PRETTY_NAME:-Linux}"

      # Return proper install instructions for supported linux variants
      case "${ID:-} ${ID_LIKE:-}" in
        *arch*) log_info "Please run:\n\nparu -Sy $missing_deps" ;;
        *ubuntu*|*debian*)
          # Replace 'htmlq' by 'cargo' and remove 'websocat' for linux
          missing_deps=${missing_deps//htmlq /cargo}
          missing_deps=${missing_deps//websocat/}
          missing_deps=${missing_deps//  / }
          
          # Add missing dev deps
          missing_deps+=" build-essential libssl-dev pkgconf"

          log_info "Please run:\n\nsudo apt install $missing_deps && cargo install htmlq websocat"
        ;;
        *) log_info "Please install: $missing_deps" ;;
      esac
    fi
    return 1
  else
    log_success "All required dependencies are already installed."
    return 0
  fi
}

clone_repo() {
  local target_dir="$1"
  local local_dir="$PROJECT_DIR"

  # Check if 'git' is already installed
  [[ -z $BIN_GIT ]] && error "Missing 'git' binary. Please install it and try again."

  # Check if repo folder already exists or not
  [[ -d "$target_dir" || -d "$local_dir" ]] && error "Project already installed. Please remove the '$PROJECT_DIR' folder and try again."

  # Clone repo using target dir or project dir
  set_console_title "Cloning repo..."
  if [[ -n $target_dir ]]; then
    log ; log_info "Cloning repo to '$target_dir'...\n"
    git clone --recursive "${PROJECT_URL}.git" "$target_dir"
  else
    log ; log_info "Cloning repo to '$local_dir'...\n"
    git clone --recursive "${PROJECT_URL}.git"
  fi
}

update_repo() {
  if [[ $(id -u) -eq 0 ]]; then
    INSTALL_DIR="/opt/${PROJECT_DIR}"
  fi

  # Check if 'git' is already installed
  [[ -z $BIN_GIT ]] && error "Missing 'git' binary. Please install it and try again."

  # Check if repo folder already exists or not
  [[ ! -d "$INSTALL_DIR" ]] && error "Nothing found. Please install '$PROJECT_DIR' first."

  # Change launch mode
  IS_UPDATE=true

  # Update repo using INSTALL_DIR
  show_banner
  set_console_title "Updating repo..."
  if [[ -n $INSTALL_DIR ]]; then
    log ; log_info "Updating repo in '$INSTALL_DIR'...\n"
    cd "$INSTALL_DIR" && git pull
    exit $?
  else
    error "Failed to detect '$PROJECT_DIR' folder."
  fi
}

create_bin_folder() {
  if [[ ! -d $BIN_DIR ]]; then
    log ; log_info "Creating required bin folder '$BIN_DIR'...\n"
    mkdir -p "$BIN_DIR"
  fi
}

create_binary() {
  local src_dir="$1"
  local bin_dir="$2"
  local bin_name="$3"

  if [[ $# -eq 3 ]]; then
    set_console_title "Installing..."
    log ; log_info "Creating '$bin_name' binary to '$BIN_DIR' from '$src_dir'...\n"
    cat <<EOF > "${bin_dir}/${bin_name}"
#!/usr/bin/env bash
cd "$src_dir" && bash "${src_dir}/${CLI_FILE}" "\$@"
EOF
    log ; log_info "Adding required permission to '$bin_name' binary...\n"
    chmod -c +x "${bin_dir}/${bin_name}"
  else
    set_console_title "Install Error"
    error "Missing required arguments: <src dir> <bin dir> <bin name>"
  fi
}

update_path() {
  local rc_file

  # Patch rc files (skip if the bin dir is already referenced in either form)
  for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f $rc_file ]] || touch "$rc_file"
    if ! grep -qi -e '\.cargo/bin' -e "$HOME/.cargo/bin" "$rc_file"; then
      printf '\n# Add %s to the PATH\nexport PATH="$HOME/.cargo/bin:$PATH"\n' "$HOME/.cargo/bin" >> "$rc_file"
      log ; log_info "Added '$HOME/.cargo/bin' to PATH in '$rc_file'.\n"
    fi
    if ! grep -qi -e '\.local/bin' -e "$BIN_DIR" "$rc_file"; then
      printf '\n# Add %s to the PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' "$BIN_DIR" >> "$rc_file"
      log ; log_info "Added '$BIN_DIR' to PATH in '$rc_file'.\n"
    fi
  done

  # Apply change for the current session
  export PATH="${PATH}:${BIN_DIR}:${HOME}/.cargo/bin"
}

init_install() {
  local deps_status

  # User is root
  if [[ $(id -u) -eq 0 ]]; then
    INSTALL_DIR="/opt/${PROJECT_DIR}"
    BIN_DIR="/usr/local/bin"
  fi

  # Step 1: Display banner
  show_banner

  # Step 2: Check dependencies
  install_deps ; deps_status=$?
  [[ $deps_status -ne 0 ]] && return $deps_status

  # Step 3: Clone repo
  clone_repo "$INSTALL_DIR"

  # Step 4: Create bin folder
  create_bin_folder

  # Step 5: Create binary
  create_binary "$INSTALL_DIR" "$BIN_DIR" "$BIN_NAME" && \
  log ; log_success "Installed."

  # Step 6: Update binary path
  update_path
}

# Main
if [[ $# -eq 0 ]]; then
  init_install
else
  case $1 in
    -h|--help|help) print_help ;;
    -u|--update|update) update_repo ;;
    *) error "Unsupported argument given: $1" ;;
  esac
fi
