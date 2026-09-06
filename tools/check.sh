#!/usr/bin/env bash
# プロジェクトの検証をヘッドレスで実行する（CI とローカルの両方で使用）。
#   1. アセットのインポート
#   2. GDScript の構文チェック
#   3. スモークテスト（メインシーンをロードして起動確認）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
GODOT="${GODOT:-godot}"

echo "== Godot バージョン"
"$GODOT" --version

echo "== インポート"
"$GODOT" --headless --path . --import >/dev/null

echo "== GDScript 構文チェック"
status=0
while IFS= read -r -d '' script; do
  if "$GODOT" --headless --path . --check-only --script "$script" >/dev/null 2>&1; then
    echo "  ok   $script"
  else
    echo "  NG   $script"
    "$GODOT" --headless --path . --check-only --script "$script" || true
    status=1
  fi
done < <(find scripts tests -name '*.gd' -print0 | sort -z)
[ "$status" -eq 0 ]

echo "== スモークテスト"
"$GODOT" --headless --path . --script res://tests/smoke_test.gd

echo "== すべて成功"
