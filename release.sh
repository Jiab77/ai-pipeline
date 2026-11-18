#!/usr/bin/env bash
# ==============================================================================
# release.sh - Tag, push and publish a GitHub release with dist/aide.run
# ==============================================================================
# Simple 'git' and 'gh' wrapper.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 0.0.1
# ==============================================================================

set -euo pipefail

DIST_FILE="dist/aide.run"

# Preflight: refuse to run without a fresh build artifact
[[ -f "$DIST_FILE" ]] || { echo "ERROR: missing $DIST_FILE - run ./make.sh first" >&2; exit 1; }

command -v git >/dev/null 2>&1 || { echo -e "\nERROR: git not found\n" >&2; exit 1; }
command -v gh  >/dev/null 2>&1 || { echo -e "\nERROR: gh not found\n" >&2; exit 1; }

# Contextual warnings (non-blocking)
[[ "$(git branch --show-current)" == "main" ]] || echo "WARN: current branch is not main"
[[ -z "$(git status --porcelain 2>/dev/null)" ]] || echo "WARN: working tree is dirty"

# Tag source: $1 argument, fallback to core.sh header version
TAG="${1:-v$(grep -m1 '# Version' core.sh | awk '{print $3}')}"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo -e "\nERROR: invalid tag '$TAG' (expected ^v[0-9]+\.[0-9]+\.[0-9]+$)\n" >&2
  exit 1
fi

LAST_MSG="$(git log -1 --format=%B)"

# 1. create_tag - annotated, message is the last commit body.
# Idempotent: skip if tag exists and points at HEAD, refuse otherwise.
if [[ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null || true)" == "tag" ]]; then
  if [[ "$(git rev-parse "$TAG^{}" 2>/dev/null)" == "$(git rev-parse HEAD)" ]]; then
    echo -e "\n[=] tag $TAG already exists and points at HEAD - skipping\n"
  else
    echo -e "\nERROR: tag $TAG exists but points elsewhere - refusing\n" >&2
    exit 1
  fi
else
  git tag -a "$TAG" -m "$LAST_MSG"
  echo -e "\n[+] created annotated tag $TAG (message = last commit body)\n"
fi

# 2. push_commit - note: pushes ALL unpushed commits, not just the last one
echo -e "\n[+] Pushing commits to origin main...\n"
git push origin main

# 3. push_tag
echo -e "\n[+] Pushing tag $TAG...\n"
git push origin "$TAG"

# 4. GitHub release - title is the exact commit subject, body is the commit
# message, asset is mandatory, --verify-tag refuses a missing tag.
echo -e "\n[+] Creating GitHub release...\n"
gh release create "$TAG" "$DIST_FILE" \
  --verify-tag \
  --title "$(git log -1 --format=%B | head -1)" \
  --notes-file <(printf '%s' "$LAST_MSG")

# Final verification - asset must be attached
echo -e "\n[+] Verifying GitHub release...\n"
gh release view "$TAG" --json author,name,body,assets \
  --jq '{author: .author.login, name: .name, body: .body, assets: [.assets[].name]}'
