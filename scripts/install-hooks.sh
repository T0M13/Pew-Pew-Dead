#!/usr/bin/env bash
# Run once after cloning: bash scripts/install-hooks.sh
# Installs the post-merge hook so `git pull` auto-refreshes the Godot import cache.
set -e
cd "$(git rev-parse --show-toplevel)"

HOOK=".git/hooks/post-merge"
cp scripts/post-merge.hook "$HOOK"
chmod +x "$HOOK"
echo "Hook installed: $HOOK"
echo "It will run automatically after every git pull."
