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

## 見え方の検証シーン（lookdev）

「3D背景 + ドット絵スプライト」方式の見え方を確かめる検証シーン。
時間帯・投影・トーンマップ・DOF・Glow などをキーとコマンドライン引数で切り替えられる。
所見と比較シートは [docs/lookdev/REPORT.md](docs/lookdev/REPORT.md)。

```sh
godot --path . res://scenes/lookdev.tscn
godot --path . res://scenes/lookdev.tscn -- time=evening proj=ortho tonemap=aces
python tools/lookdev_shots.py          # 設定違いを一括撮影して比較シートを作る（実機が必要）
python tools/lookdev_calib.py ambient  # 環境光スイープと路面の点測定（較正）
python tools/measure.py refs/reference_evening.png docs/lookdev/shots/best_p3.png --hist out.png
python tools/lookdev_c.py c1|c2|c3    # 投影・シマー・モアレの計測（フェーズ 3）
```

参考画像は `refs/` に置く（Git 管理外）。

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
scenes/lookdev.tscn  見え方の検証シーン（scripts/lookdev.gd）
tools/lookdev_shots.py 検証シーンの一括撮影と比較シート作成
tools/lookdev_calib.py 較正スイープ（環境光・壁アルベド・トーンマップ）と点測定
tools/measure.py     明度分布・日陰面積率・色相統計・ヒストグラム
tools/lookdev_c.py   ピクセル整合の計測（FOV スイープ・シマー MAD・モアレ）
docs/lookdev/        検証の所見と比較シート
tools/setup_godot.sh Godot のインストール（Linux）
tools/setup_godot.ps1 Godot のインストール（Windows）
tools/check.sh       検証スクリプト
.claude/             Claude Code on the web 用の起動フック（Godot を自動インストール）
```

## Claude Code on the web

`.claude/hooks/session-start.sh` がセッション開始時に Godot を自動インストールするので、
Web セッション内でも `godot` コマンドがそのまま使えます。
