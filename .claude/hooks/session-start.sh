#!/bin/bash
# Claude Code on the web のセッション開始時に Godot をインストールする。
# ローカル環境では何もしない。
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

BIN_DIR="$HOME/.local/bin"
GODOT_BIN_DIR="$BIN_DIR" "$CLAUDE_PROJECT_DIR/tools/setup_godot.sh"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# 初回のアセットインポートを済ませておく（.godot/ を生成）。
cd "$CLAUDE_PROJECT_DIR"
"$BIN_DIR/godot" --headless --path . --import >/dev/null 2>&1 || true
