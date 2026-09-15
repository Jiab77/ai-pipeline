#!/usr/bin/env bash

# Config
OUTPUT_FILE="data/code-stats.txt"

# Main
echo -e "\nGenerating code stats...\n"
tokei . --files --exclude web/lib --exclude data --exclude skills --exclude "${0##*/}" > "$OUTPUT_FILE" && cat "$OUTPUT_FILE"
echo -e "\nDone.\n"
