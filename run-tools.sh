#!/usr/bin/env bash

# ==============================================================================
# SCRIPT D'OUTILS POUR AGENT LOCAL (Conforme aux contraintes strictes du schéma)
# ==============================================================================
#
# Made by Gemini 3.5 Flash Extended / Improved by Jiab77
#
# Version 0.0.0

# Options
# [[ -e $HOME/.debug ]] && set -x

# Config
LOG_FILE="$(basename "$0" .sh).log"

# Arguments
FUNC_NAME="$1"
FUNC_ARGS="$2"

# Fonctions Internes
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

# Fonctions Publiques
# 1. Lire le contenu d'un fichier avec plage de lignes optionnelle
read_file() {
  # local path="$1"
  # local start_line="${2:-1}"
  # local end_line="${3:-}"
  # local append_loc="${4:-false}"
  
  local path="."
  local start_line=1
  local end_line
  local append_loc=false
  local x
  
  if [[ -n $FUNC_ARGS ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "start_line") ; [[ -n $x && ! $x == "null" ]] && start_line="$x"
    x=$(parse_args "end_line") ; [[ -n $x && ! $x == "null" ]] && end_line="$x"
    x=$(parse_args "append_loc") ; [[ -n $x && ! $x == "null" ]] && append_loc="$x"
  fi

  if [ ! -f "$path" ]; then
    echo "Error: File not found at $path" >&2
    return 1
  fi

  local total_lines=$(wc -l < "$path")
  if [ -z "$end_line" ]; then
    end_line=$total_lines
  fi

  if [ "$append_loc" = "true" ]; then
    awk -v start="$start_line" -v end="$end_line" '
        NR >= start && NR <= end { printf "%d→ %s\n", NR, $0 }
    ' "$path"
  else
    awk -v start="$start_line" -v end="$end_line" '
        NR >= start && NR <= end { print $0 }
    ' "$path"
  fi
}

# 2. Recherche récursive de fichiers via glob pattern
file_glob_search() {
  # local path="$1"
  # local include="${2:-*}"
  # local exclude="${3:-}"

	local path="."
  local include="*"
  local exclude
  local x
  
  if [[ -n "$FUNC_ARGS" ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "include") ; [[ -n $x && ! $x == "null" ]] && include="$x"
    x=$(parse_args "exclude") ; [[ -n $x && ! $x == "null" ]] && exclude="$x"
  fi

  if [ ! -d "$path" ]; then
    echo "Error: Directory not found at $path" >&2
    return 1
  fi

  if [ -n "$exclude" ]; then
    find "$path" -maxdepth 10 -type f -wholename "$include" ! -name "$exclude"
  else
    find "$path" -maxdepth 10 -type f -wholename "$include"
  fi
}

# 3. Recherche par Regex (Grep) dans un chemin (fichier ou dossier)
grep_search() {
  # local path="$1"
  # local pattern="$2"
  # local include="${3:-*}"
  # local exclude="${4:-}"
  # local return_line_numbers="${5:-false}"

  local path="."
  local pattern
  local include="*"
  local exclude
  local return_line_numbers=false
  local x
  
  if [[ -n "$FUNC_ARGS" ]]; then
    x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
    x=$(parse_args "pattern") ; [[ -n $x && ! $x == "null" ]] && pattern="$x"
    x=$(parse_args "include") ; [[ -n $x && ! $x == "null" ]] && include="$x"
    x=$(parse_args "exclude") ; [[ -n $x && ! $x == "null" ]] && exclude="$x"
    x=$(parse_args "return_line_numbers") ; [[ -n $x && ! $x == "null" ]] && return_line_numbers="$x"
  fi

  local grep_opts="-E"
  if [ "$return_line_numbers" = "true" ]; then
    grep_opts="${grep_opts} -n"
  fi

  if [ -d "$path" ]; then
    # Recherche récursive dans un dossier
    if [ -n "$exclude" ]; then
      grep ${grep_opts} -r --include="$include" --exclude="$exclude" "$pattern" "$path"
    else
      grep ${grep_opts} -r --include="$include" "$pattern" "$path"
    fi
  elif [ -f "$path" ]; then
    # Recherche dans un fichier unique
    grep ${grep_opts} "$pattern" "$path"
  else
    echo "Error: Invalid path $path" >&2
    return 1
  fi
}

# 4. Exécuter une commande système avec Timeout et troncature stricte
exec_shell_command() {
  # local command="$1"
  # local timeout_val="${2:-10}"
  # local max_output_size="${3:-16384}"

  local command="null"
  local timeout_val=10
  local max_output_size=16384
  local x
  
  if [[ -n $FUNC_ARGS ]]; then
		x=$(parse_args "command") ; [[ -n $x && ! $x == "null" ]] && command="$x"
		x=$(parse_args "timeout_val") ; [[ -n $x && ! $x == "null" ]] && timeout_val="$x"
		x=$(parse_args "max_output_size") ; [[ -n $x && ! $x == "null" ]] && max_output_size="$x"
  fi
  
  # Avoid running the pipeline itself...
  [[ $(grep -ci "pipeline.sh" <<<$command) -ne 0 ]] && error "Dear model, don't try to run the pipeline itself, it's not made for that. Thank you."

  # Sécurité sur les bornes du timeout
  if [ "$timeout_val" -lt 1 ] || [ "$timeout_val" -gt 60 ]; then timeout_val=10; fi

  local output
  output=$(timeout "$timeout_val" sh -c "$command" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    echo "Command timed out after $timeout_val seconds."
  fi

  # Troncature propre en octets via Bash (sans fuite mémoire)
  if [ ${#output} -gt "$max_output_size" ]; then
    echo "${output:0:$max_output_size}"
    echo -e "\n[Output truncated: exceeded $max_output_size bytes]"
  else
    echo "$output"
  fi
  return $exit_code
}

# 5. Écrire ou écraser un fichier (crée les dossiers parents si nécessaire)
write_file() {
  # local path="$1"
  # local content="$2"

  local path="."
  local content
  local x
  
  if [[ -n $FUNC_ARGS ]]; then
		x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
		x=$(parse_args "content") ; [[ -n $x && ! $x == "null" ]] && content="$x"
  fi

  mkdir -p "$(dirname "$path")"
  echo -n "$content" > "$path"
}

# 6. ÉDITION CHIRURGICALE VIA PARSING JSON (L'outil critique demandé)
edit_file() {
  # local path="$1"
  # local json_changes="$2"

  local path="."
  local json_changes
  local x
  
  if [[ -n $FUNC_ARGS ]]; then
		x=$(parse_args "path") ; [[ -n $x && ! $x == "null" ]] && path="$x"
		x=$(parse_args "json_changes") ; [[ -n $x && ! $x == "null" ]] && json_changes="$x"
  fi

  if [ ! -f "$path" ]; then
    echo "Error: File not found at $path" >&2
    return 1
  fi

  # Vérification de la validité du JSON reçu
  if ! echo "$json_changes" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON array provided to edit_file" >&2
    return 1
  fi

  # Extraction et tri des modifications par ligne décroissante (Reverse Order pour préserver les index)
  local sorted_changes
  sorted_changes=$(echo "$json_changes" | jq -c 'sort_by(.line_start) | reverse | .[]')

  # Création d'un fichier temporaire de travail
  local tmp_file
  tmp_file=$(mktemp)
  cp "$path" "$tmp_file"

  while read -r change; do
    if [ -z "$change" ]; then continue; fi

    local mode=$(echo "$change" | jq -r '.mode')
    local line_start=$(echo "$change" | jq -r '.line_start')
    local line_end=$(echo "$change" | jq -r '.line_end')
    local content=$(echo "$change" | jq -r '.content')
    local total_lines=$(wc -l < "$tmp_file")

    # Gestion de l'écriture en fin de fichier (line_start = -1)
    if [ "$line_start" -eq -1 ]; then
      if [ "$mode" = "append" ] || [ "$mode" = "replace" ]; then
        echo -e "\n$content" >> "$tmp_file"
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

  # Sauvegarde finale
  mv "$tmp_file" "$path"
}

# 7. Appliquer un Diff Git unifié
apply_diff() {
  # local diff_content="$1"

	local diff_content
  local x
  
  if [[ -n $FUNC_ARGS ]]; then
		x=$(parse_args "diff_content") ; [[ -n $x && ! $x == "null" ]] && diff_content="$x"
  fi

  echo "$diff_content" | git apply --whitespace=fix -
}

# 8. Obtenir la date courante
get_datetime() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Bootstrap
[[ $# -eq 0 ]] && error "Missing arguments.\nUsage: $(basename "$0") <function> <arguments>\n"

# Logging
echo -e "\n---\n\nDate: $(date '+%Y-%m-%d %H:%M:%S')\nFunction: ${FUNC_NAME}\nArguments: ${FUNC_ARGS}" >> "$LOG_FILE"

# Choix de la function (je n'aime pas coder en Français...)
"$FUNC_NAME" "$FUNC_ARGS"
