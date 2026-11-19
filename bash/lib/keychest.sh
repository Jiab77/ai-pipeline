#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# ==============================================================================
# lib/keychest.sh — Shared JarNet functions
# ==============================================================================
# Provides source-only shared functions
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.0
#
# Contract: LIB_DEPS
#
# Dependencies: core.sh, lib/nightmare.sh, lib/base64.sh, lib/base82.sh
# Loading: source only; no output or caller shell-option changes on success.
# ==============================================================================

# Idempotent re-sourcing guard
[[ -n "${KEYCHEST_SH_LOADED:-}" ]] && return 0

# Execution guard: this file is sourced, never executed
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'keychest.sh: library must be SOURCED, not executed (source %s)\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

KEYCHEST_SH_LOADED=1

# -----------------------------------------------------------------------------
# Cryptographic Key Chest (ChaCha20 / AES-256-CBC + PBKDF2)
# -----------------------------------------------------------------------------

# Reads master key from disk and decodes it if in Nightmare format
read_master_key() {
  local content
  [[ -s $MASTER_KEY_FILE ]] || return 1
  content=$(<"$MASTER_KEY_FILE") || return 1

  local decoded
  # If content can be decoded by Nightmare, return the decoded secret
  if decoded=$(nm_decode "$content" 2>/dev/null) && [[ -n $decoded ]]; then
    printf '%s' "$decoded"
  else
    # Otherwise, return legacy secret format (direct retrocompatibility)
    printf '%s' "$content"
  fi
}

verify_nightmare_key() {
  local legacy_key="$1"
  local nightmare_str="$2"

  # 1. Check Nightmare decoding
  local decoded_key
  decoded_key=$(nm_decode "$nightmare_str" 2>/dev/null) || return 1
  [[ "$decoded_key" == "$legacy_key" ]] || return 1

  # 2. Canary: real cryptographic round-trip
  local canary="AIDE-CANARY-$RANDOM-$RANDOM"
  local ct pt

  # Encrypt original legacy key (base64 encoded)
  ct=$(printf '%s' "$canary" | openssl enc -aes-256-cbc -pbkdf2 -iter 1000 -e -pass fd:3 -in - 3<<<"$legacy_key" 2>/dev/null | b64e) || return 1
  # Decrypt key from Nightmare
  pt=$(printf '%s' "$ct" | b64d | openssl enc -aes-256-cbc -pbkdf2 -iter 1000 -d -pass fd:3 -in - 3<<<"$decoded_key" 2>/dev/null) || return 1

  [[ "$pt" == "$canary" ]]
}

init_key_chest() {
  if [[ ! -d $KEYS_DIR ]]; then
    mkdir -p "$KEYS_DIR" && chmod 700 "$KEYS_DIR"
  fi
  if [[ ! -s $MASTER_KEY_FILE ]]; then
    # Generate random 32 bits and encode them with Nightmare
    openssl rand -base64 32 | nm_enc_stream > "$MASTER_KEY_FILE" && chmod 600 "$MASTER_KEY_FILE"
  fi
}

migrate_key_chest() {
  local apply=0
  [[ "${1:-}" == "--apply" ]] && apply=1

  log_step "Checking cryptographic key chest status..."

  if [[ ! -s $MASTER_KEY_FILE ]]; then
    log_warn "No master key found at $MASTER_KEY_FILE."
    return 0
  fi

  # Get key content
  local current_content ; current_content=$(<"$MASTER_KEY_FILE")

  # Test if protected by Nightmare
  if nm_decode "$current_content" &>/dev/null; then
    log_success "Master key is already protected by new format."
    if [[ ! -r "${MASTER_KEY_FILE}.bak" ]]; then
      return 0
    else
      echo -en "${CLR_B_YELLOW}${ICON_WARNING}${ANSI_RESET} ${CLR_B_YELLOW}Old Master key file detected! Remove? [Y,N] ❯ ${ANSI_RESET}" >&2
      local del_old_key ; read -r del_old_key
      if [[ $del_old_key == "y" || $del_old_key == "Y" ]]; then
        if rm -f "${MASTER_KEY_FILE}.bak"; then
          log_success "Old Master key backup (${MASTER_KEY_FILE##*/}.bak) removed."
        else
          log_error "Unable to remove old Master key backup file, ${MASTER_KEY_FILE##*/}.bak left untouched."
          return 1
        fi
      fi
      return 0
    fi
  fi

  log_info "Master key is currently in legacy plain format."

  if [[ $apply -eq 0 ]]; then
    log_warn "Plan: Master key will be migrated to new format."
    log_info "Run './cli.sh keys migrate --apply' (or '/migrate --apply') to perform migration."
    return 0
  fi

  # Mode --apply
  log_info "Encrypting master key using new format..."
  local new_nm_content ; new_nm_content=$(nm_encode "$current_content")

  log_step "Running canary verification test..."
  if ! verify_nightmare_key "$current_content" "$new_nm_content"; then
    log_error "Canary verification failed! Migration aborted, key.dat left untouched."
    return 1
  fi

  log_success "Canary test passed! Applying new format..."

  # Security backup
  cp "$MASTER_KEY_FILE" "${MASTER_KEY_FILE}.bak" && chmod 600 "${MASTER_KEY_FILE##*/}.bak"

  # Atomic write
  printf '%s\n' "$new_nm_content" > "${MASTER_KEY_FILE}.tmp"
  chmod 600 "${MASTER_KEY_FILE}.tmp"
  mv "${MASTER_KEY_FILE}.tmp" "$MASTER_KEY_FILE"

  log_success "Master key successfully migrated to new format! (Backup: ${MASTER_KEY_FILE##*/}.bak)"
}

has_provider_key() {
  local provider="$1"
  [[ -r $MASTER_KEY_FILE && -s $MASTER_KEY_FILE && -r "${KEYS_DIR}/${provider}.key" && -s "${KEYS_DIR}/${provider}.key" ]]
}

# Cipher resolution — probe a full encrypt/decrypt round-trip once, then cache.
# LibreSSL (macOS) may lack chacha20 in `enc`, and some builds lack PBKDF2.
# Order: chacha20+PBKDF2 -> aes-256-cbc+PBKDF2 -> aes-256-cbc (legacy KDF).
# Keys are per-machine (local master key): no cross-machine format to preserve.
probe_keyring_cipher() {
  local spec cipher use_pbkdf2 probe probe_back
  local -a kdf
  local master_key ; master_key=$(read_master_key) || return 1

  for spec in "chacha20|1" "aes-256-cbc|1" "aes-256-cbc|0"; do
    cipher="${spec%%|*}"
    use_pbkdf2="${spec##*|}"
    if [[ $use_pbkdf2 == 1 ]]; then kdf=(-pbkdf2 -iter "$PBKDF_ITERATIONS"); else kdf=(); fi
    probe="probe-$RANDOM-$RANDOM"
    probe_back=$(printf '%s' "$probe" \
      | openssl "$cipher" "${kdf[@]}" -e -pass fd:3 -in - 3<<<"$master_key" 2>/dev/null \
      | openssl "$cipher" "${kdf[@]}" -d -pass fd:3 -in - 3<<<"$master_key" 2>/dev/null)
    if [[ $probe_back == "$probe" ]]; then
      KEYRING_CIPHER="$cipher"
      KEYRING_PBKDF2="$use_pbkdf2"
      return 0
    fi
  done
  return 1
}

keyring_kdf() { # fills KDF_ARGS according to the resolved cipher
  if [[ $KEYRING_PBKDF2 == 1 ]]; then
    KDF_ARGS=(-pbkdf2 -iter "$PBKDF_ITERATIONS")
  else
    KDF_ARGS=()
  fi
}

encrypt_provider_key() {
  local provider="$1"
  local raw_key="$2"
  init_key_chest
  [[ -z $KEYRING_CIPHER ]] && probe_keyring_cipher
  if [[ -z $KEYRING_CIPHER ]]; then
    log_error "Key chest: no usable openssl cipher (chacha20 and aes-256-cbc round-trips failed)."
    return 1
  fi
  local master_key ; master_key=$(read_master_key) || return 1
  keyring_kdf
  echo -n "$raw_key" | \
  openssl "$KEYRING_CIPHER" "${KDF_ARGS[@]}" -e -pass fd:3 -in - 3<<<"$master_key" | \
  b64e > "${KEYS_DIR}/${provider}.key"
  chmod 600 "${KEYS_DIR}/${provider}.key"
}

decrypt_provider_key() {
  local provider="$1"
  if has_provider_key "$provider"; then
    [[ -z $KEYRING_CIPHER ]] && probe_keyring_cipher
    [[ -z $KEYRING_CIPHER ]] && return 1
    local master_key ; master_key=$(read_master_key) || return 1
    keyring_kdf
    b64d < "${KEYS_DIR}/${provider}.key" | \
    openssl "$KEYRING_CIPHER" "${KDF_ARGS[@]}" -d -pass fd:3 -in - 3<<<"$master_key" 2>/dev/null
  fi
}

load_provider_key() {
  local target_provider ; target_provider="${1:-$PROVIDER}"
  if has_provider_key "$target_provider"; then
    PROVIDER_API_KEY=$(decrypt_provider_key "$target_provider" 2>/dev/null)
  elif [[ -r $CREDENTIALS ]]; then
    # Fallback to legacy credentials file
    PROVIDER_API_KEY=$(<"$CREDENTIALS")
  fi
}

purge_all_keys() {
  if [[ -d $KEYS_DIR ]]; then
    rm -rf "$KEYS_DIR"
    log_success "Cryptographic key chest has been completely purged."
  else
    log_warn "No key chest found to purge."
  fi
}

interactive_key_setup() {
  local provider="$1"
  local url ; url=$(jq -rc ".${provider}.keys // \"your provider console\"" "$PROVIDERS_CONFIG" 2>/dev/null)

  log ""
  log "${CLR_B_CYAN}🔑 [$(to_upper "$AI_NAME") KEY WIZARD]${ANSI_RESET}"
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log " Your keys will be encrypted locally using ${CLR_B_WHITE}ChaCha20 + PBKDF2${ANSI_RESET}"
  log " and safely stored inside ${CLR_B_WHITE}${KEYS_DIR##*/}/${provider}.key${ANSI_RESET}."
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log "🌐 Provider  : ${CLR_B_YELLOW}$(to_upper "$provider")${ANSI_RESET}"
  log "👉 Obtain Key : ${CLR_B_CYAN}${url}${ANSI_RESET}"
  log ""

  local raw_key
  # TODO: Add a way to leave the loop cleanly
  while [[ -z "$raw_key" ]]; do
    echo -en "🔑 Enter your API Key (input will be masked) ❯ " >&2
    read -rs raw_key
    log   # New line after masked input
    if [[ -z "$raw_key" ]]; then
      log_error "Key cannot be empty. Please try again."
    fi
  done

  # Encrypt and save key
  encrypt_provider_key "$provider" "$raw_key"
  log_success "API key encrypted and sealed successfully inside '${KEYS_DIR##*/}/${provider}.key'."

  # Load new provider key
  load_provider_key "$provider"
}

manage_keys() {
  init_key_chest
  log
  log "${CLR_B_CYAN}🔑 [$(to_upper "$AI_NAME") SOVEREIGN KEY CHEST]${ANSI_RESET}"
  log "${CLR_B_BLACK}──────────────────────────────────────────────────────────────────────────${ANSI_RESET}"
  log " Choose an action to manage your encrypted API keys:"
  log
  log "   ${CLR_B_GREEN}1)${ANSI_RESET} List configured keys (masked)"
  log "   ${CLR_B_GREEN}2)${ANSI_RESET} Configure or update a key"
  log "   ${CLR_B_GREEN}3)${ANSI_RESET} Migrate master key (new format)"
  log "   ${CLR_B_GREEN}4)${ANSI_RESET} Purge entire key chest (security erase)"
  log "   ${CLR_B_GREEN}5)${ANSI_RESET} Exit"
  log
  echo -en "👉 Select choice [1-5] ❯ " >&2
  local choice ; read -r choice
  log

  case "$choice" in
    1)
      log "${CLR_B_CYAN}🔐 Configured Providers:${ANSI_RESET}"
      local p found=false
      for p in $(jq -rc '. | keys | @tsv' "$PROVIDERS_CONFIG" 2>/dev/null); do
        if has_provider_key "$p"; then
          log "  • $(to_upper "$p"): [ ${CLR_B_GREEN}CONFIGURED 🟢${ANSI_RESET} ]"
          found=true
        else
          log "  • $(to_upper "$p"): [ ${CLR_B_RED}NOT CONFIGURED 🔴${ANSI_RESET} ]"
        fi
      done
      if [[ $found == false ]]; then
        log ; log_info "No encrypted keys found in ${KEYS_DIR##*/}/."
      fi
      log
    ;;
    2)
      local index=0
      local total ; total=$(jq -rc '. | keys | length' "$PROVIDERS_CONFIG" 2>/dev/null)
      log "Choose a provider to configure:"
      for p in $(jq -rc '. | keys | @tsv' "$PROVIDERS_CONFIG" 2>/dev/null); do
        ((index++))
        log " ${index}) $(jq -rc ".${p}.name" "$PROVIDERS_CONFIG" 2>/dev/null)"
      done
      log " $((index+1))) Custom Provider"
      log " $((index+2))) Exit"
      log
      echo -en "👉 Selection [1-$((index+2))] ❯ " >&2
      local prov_choice
      read -r prov_choice
      local target_provider
      if [[ $prov_choice -le $total ]]; then
        target_provider=$(jq -rc ". | keys | .[$((prov_choice-1))]" "$PROVIDERS_CONFIG" 2>/dev/null)
      elif [[ $prov_choice == $((index+1)) ]]; then
        echo -en "✍️ Enter custom provider name ❯ " >&2
        read -r target_provider
        target_provider=$(to_lower "$target_provider")
      else
        return
      fi
      if [[ -n "$target_provider" ]]; then
        interactive_key_setup "$target_provider"
      fi
    ;;
    3)
      migrate_key_chest --apply
    ;;
    4)
      echo -en "⚠️ ${CLR_B_RED}Are you absolutely sure you want to purge all keys?${ANSI_RESET} [y/N] ❯ " >&2
      local confirm ; read -r confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        purge_all_keys
      else
        log_info "Purge cancelled."
      fi
    ;;
    *)
      log_info "Exiting Key Chest Manager."
    ;;
  esac
}