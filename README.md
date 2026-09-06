# Game1

[Godot Engine](https://godotengine.org/) 4.7.2 で作るゲームプロジェクトです。

## 必要なもの

- Godot **4.7.2 stable**（バージョンは `.godot-version` で固定）

## セットアップ

### Linux (x86_64)

```sh
./tools/setup_godot.sh
export PATH="$HOME/.local/bin:$PATH"   # 未設定なら
godot --version
```

スクリプトは公式リリースをダウンロードし、SHA-512 で検証してから
`~/.local/godot/` に配置し、`~/.local/bin/godot` にコマンドを作ります。

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup_godot.ps1
```

Linux 版と同じく公式リリースをダウンロードし、SHA-512 で検証してから
`%USERPROFILE%\.local\godot\` に配置し、`%USERPROFILE%\.local\bin\` に `godot` コマンド
（PowerShell / cmd 用の `godot.cmd` と Git Bash 用の `godot`）を作ります。
`%USERPROFILE%\.local\bin` がユーザー環境変数 Path に無い場合は追加してください。
コマンドはコンソール版 exe を呼ぶので、ターミナルに標準出力が流れます。

### macOS

[公式ダウンロードページ](https://godotengine.org/download) から
**4.7.2 stable** を入手し、エディタでこのフォルダの `project.godot` を開いてください。

## 実行

```sh
godot --path .            # ゲームを起動
godot --path . --editor   # エディタで開く
```

## 検証（CI と同じ内容）

```sh
./tools/check.sh
```

アセットのインポート、GDScript の構文チェック、ヘッドレスのスモークテストを行います。
GitHub Actions でも push / PR ごとに同じ検証が走ります。

## 構成

```
project.godot        プロジェクト設定
scenes/main.tscn     メインシーン
scripts/main.gd      メインシーンのスクリプト
tests/smoke_test.gd  ヘッドレスのスモークテスト
tools/setup_godot.sh Godot のインストール（Linux）
tools/setup_godot.ps1 Godot のインストール（Windows）
tools/check.sh       検証スクリプト
.claude/             Claude Code on the web 用の起動フック（Godot を自動インストール）
```

## Claude Code on the web

`.claude/hooks/session-start.sh` がセッション開始時に Godot を自動インストールするので、
Web セッション内でも `godot` コマンドがそのまま使えます。
