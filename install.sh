#!/usr/bin/env bash
# shellcheck disable=SC2034
# ==============================================================================
# install.sh — Simple install script
# ==============================================================================
# This script houses the install logic for this project.
#
# Lead Developer & Architect : Jiab77
# AI Sorcerer & Co-Creator   : Jarvis (DeepSeek)
#
# Version: 0.0.0
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
SCRIPT_VERSION="0.0.0"
BIN_FIGLET=$(command -v figlet 2>/dev/null)
BIN_GIT=$(command -v git 2>/dev/null)
PROJECT_DIR=$(basename "$PROJECT_URL")
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
clone_repo() {
  local target_dir="$1"
  local local_dir="$PROJECT_DIR"

  # Check if 'git' is already installed
  [[ -z $BIN_GIT ]] && error "Missing 'git' binary. Please install it and try again."

  # Check if repo folder already exists or not
  [[ -d "$target_dir" || -d "$local_dir" ]] && error "Already installed. Remove the folder '$PROJECT_DIR' and try again."

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
  local install_dir

  if [[ $(id -u) -eq 0 ]]; then
    install_dir="/opt/${PROJECT_DIR}"
  else
    install_dir="${HOME}/${PROJECT_DIR}"
  fi

  # Check if 'git' is already installed
  [[ -z $BIN_GIT ]] && error "Missing 'git' binary. Please install it and try again."

  # Check if repo folder already exists or not
  [[ ! -d "$install_dir" ]] && error "Nothing found. Please install '$PROJECT_DIR' first."

  # Change launch mode
  IS_UPDATE=true

  # Update repo using install_dir
  show_banner
  set_console_title "Updating repo..."
  if [[ -n $install_dir ]]; then
    log ; log_info "Updating repo in '$install_dir'...\n"
    cd "$install_dir" && git pull
    exit $?
  else
    error "Failed to detect '$PROJECT_DIR' folder."
  fi
}

create_binary() {
  local src_dir="$1"
  local bin_dir="$2"
  local bin_name="$3"

  if [[ $# -eq 3 ]]; then
    set_console_title "Installing..."
    log ; log_info "Creating '$bin_name' binary to '$bin_dir' from '$src_dir'...\n"
    cat <<EOF > "${bin_dir}/${bin_name}"
#!/usr/bin/env bash
cd "$src_dir" && bash "${src_dir}/${CLI_FILE}" "\$@"
EOF
    log ; log_info "Adding required permission to '$bin_name' binary...\n"
    chmod -c +x "${bin_dir}/${bin_name}"
  else
    error "Missing required arguments: <src dir> <bin dir> <bin name>"
  fi
}

init_install() {
  local install_dir bin_name bin_dir

  # Default to non-root user
  install_dir="${HOME}/${PROJECT_DIR}"

  # Default binary install dir
  bin_dir=~/.local/bin

  # User is root
  if [[ $(id -u) -eq 0 ]]; then
    install_dir="/opt/${PROJECT_DIR}"
    bin_dir="/usr/local/bin"
  fi

  # Step 1: Display banner
  show_banner

  # Step 2: Clone repo
  clone_repo "$install_dir"

  # Step 3: Create binary
  create_binary "$install_dir" "$bin_dir" "$BIN_NAME" && \
  log ; log_success "Installed."
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