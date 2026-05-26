#!/usr/bin/env bash
# Script to create GitHub repo and push llm_detect_rbnx package.
# Run this manually: bash /Users/howenliu/lab/packages/llm_detect_rbnx/scripts/setup_repo.sh
set -euo pipefail

PKG="/Users/howenliu/lab/packages/llm_detect_rbnx"
TOKEN=$(cat /Users/howenliu/lab/git_token)
GITHUB_USER="lhw2002426"
REPO_NAME="llm_detect_rbnx"

echo "=== Step 1: Creating GitHub repository ==="
RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO_NAME\",\"description\":\"LLM-based object detection robonix package replacing yolo_world_rbnx\",\"private\":false}")

echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print('Repo URL:', d.get('html_url', 'ERROR: '+d.get('message','unknown')))"

echo "=== Step 2: Initializing git repo ==="
cd "$PKG"
git init
git add -A
git commit -m "Initial commit: llm_detect_rbnx - LLM-based object detection replacing yolo_world_rbnx"

echo "=== Step 3: Pushing to GitHub ==="
git remote add origin "https://${TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
git branch -M main
git push -u origin main

echo "=== Done! ==="
echo "Repository: https://github.com/${GITHUB_USER}/${REPO_NAME}"
