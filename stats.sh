#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# stats.sh — Repository code statistics generator
# ==============================================================================
# Generates code statistics with tokei and writes the resulting report to
# data/code-stats.txt.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.0
# Dependencies: tokei
# ==============================================================================

# Config
OUTPUT_FILE="data/code-stats.txt"

# Main
echo -e "\nGenerating code stats...\n"
tokei . --files --exclude web/lib --exclude data --exclude skills --exclude "${0##*/}" > "$OUTPUT_FILE" && cat "$OUTPUT_FILE"
echo -e "\nDone.\n"
