#!/usr/bin/env bash
# Godot をダウンロードして `godot` コマンドとして使えるようにするスクリプト。
# バージョンはリポジトリ直下の .godot-version で固定している。
#
# 使い方:
#   ./tools/setup_godot.sh            # ~/.local/bin/godot にインストール
#   GODOT_INSTALL_DIR=/opt/godot ./tools/setup_godot.sh
#
# 何度実行しても安全（インストール済みなら何もしない）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/.godot-version")"   # 例: 4.7.2-stable
INSTALL_DIR="${GODOT_INSTALL_DIR:-$HOME/.local/godot}"
BIN_DIR="${GODOT_BIN_DIR:-$HOME/.local/bin}"

ARCHIVE="Godot_v${VERSION}_linux.x86_64.zip"
BINARY="Godot_v${VERSION}_linux.x86_64"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"

TARGET="$INSTALL_DIR/$VERSION/$BINARY"

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  echo "このスクリプトは Linux x86_64 専用です。https://godotengine.org/download から手動でインストールしてください。" >&2
  exit 1
fi

if [ -x "$TARGET" ] && "$TARGET" --version >/dev/null 2>&1; then
  echo "Godot ${VERSION} はインストール済みです: $TARGET"
else
  echo "Godot ${VERSION} をダウンロードします..."
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  curl -fsSL --retry 4 --retry-delay 2 -o "$WORK/$ARCHIVE" "$BASE_URL/$ARCHIVE"
  curl -fsSL --retry 4 --retry-delay 2 -o "$WORK/SHA512-SUMS.txt" "$BASE_URL/SHA512-SUMS.txt"

  echo "チェックサムを検証します..."
  (cd "$WORK" && grep " $ARCHIVE\$" SHA512-SUMS.txt | sha512sum -c -)

  unzip -q -o "$WORK/$ARCHIVE" -d "$WORK"
  mkdir -p "$INSTALL_DIR/$VERSION"
  mv "$WORK/$BINARY" "$TARGET"
  chmod +x "$TARGET"
  echo "インストールしました: $TARGET"
fi

mkdir -p "$BIN_DIR"
ln -sf "$TARGET" "$BIN_DIR/godot"
echo "コマンドを作成しました: $BIN_DIR/godot -> $TARGET"

if ! command -v godot >/dev/null 2>&1 || [ "$(command -v godot)" != "$BIN_DIR/godot" ]; then
  echo "PATH に $BIN_DIR を追加してください:  export PATH=\"$BIN_DIR:\$PATH\""
fi

"$BIN_DIR/godot" --version
