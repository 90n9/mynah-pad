#!/bin/bash
# test.sh — checks that don't need the app running:
#   1. Store.merge (Tests/main.swift)
#   2. mynahpad-mcp over stdio, against a throwaway home directory
# Usage: scripts/test.sh
#
# Binaries and the throwaway home go under dist/test/ (gitignored).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJECT_DIR/MynahPad"
WORK="$PROJECT_DIR/dist/test"
mkdir -p "$WORK"

echo "→ Store.merge"
swiftc -swift-version 5 \
  "$SRC/Models/Folder.swift" "$SRC/Models/Note.swift" \
  "$SRC/Models/NotesFile.swift" "$SRC/Models/Store.swift" \
  "$PROJECT_DIR/Tests/main.swift" -o "$WORK/merge-tests"
"$WORK/merge-tests"

echo "→ mynahpad-mcp"
swiftc -swift-version 5 \
  "$SRC/Models/Folder.swift" "$SRC/Models/Note.swift" "$SRC/Models/NotesFile.swift" \
  "$PROJECT_DIR/MynahPadMCP/main.swift" -o "$WORK/mynahpad-mcp"

# CFFIXED_USER_HOME points Foundation's home directory at a fresh temp dir, so
# the helper never touches the real ~/.config/mynahpad.
FAKE_HOME="$(mktemp -d "$WORK/home.XXXXXX")"
CFFIXED_USER_HOME="$FAKE_HOME" python3 "$PROJECT_DIR/scripts/mcp-check.py" "$WORK/mynahpad-mcp" "$FAKE_HOME"
