#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2016
# ==============================================================================
# make.sh — Create single binary file 'aide.run'
# ==============================================================================
# Simple 'makeself' wrapper.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.1
# ==============================================================================

# Clean existing artifacts
echo -e "\n[+] Cleaning existing build artifacts...\n"
rm -rf build dist

# Create build folder
echo -e "\n[+] Creating build folder...\n"
mkdir -pv build dist

# Copy required files and folders
echo -e "\n[+] Copying required files and folders...\n"
cp -rv {config,engines,lib,plugins,skills,tools} build/
cp -v AGENTS.md cli.sh core.sh tools.sh build/

# Remove useless files
echo -e "\n[+] Removing useless files...\n"
rm -fv build/config/providers.biollm.json
rm -fv build/config/providers.old.json
rm -fv build/config/state.json

# Run 'makeself' to create the 'aide.run' file
echo -e "\n[+] Creating 'aide.run' binary with 'makeself'...\n"
makeself --notemp --target '$HOME/.cache/aide' --gzip --complevel 9 build dist/aide.run "A.I.D.E. Bash Pipeline" ./cli.sh
