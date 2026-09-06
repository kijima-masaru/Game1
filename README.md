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
python tools/lookdev_walk.py           # スプライトのスケール変動（歩行テスト、GIF 出力）
```

素材制作のルールは [docs/ART_SPEC.md](docs/ART_SPEC.md)。

## 街路 1 ブロックの縦切り（本番の作り）

```sh
godot --path . res://scenes/block.tscn -- time=evening                       # 商店・民家・ビル + PixelLab オブジェクト
godot --path . res://scenes/block.tscn -- time=noon tex=pixellab street_angle=90 occl=fade player=-4,2
```

所見は [docs/lookdev/PHASE6.md](docs/lookdev/PHASE6.md)。建物生成 `scripts/town/building_gen.gd`、テクスチャ `scripts/town/pixel_textures.gd`、AO `scripts/town/ao_baker.gd`。

## フィールド（本番のデータ駆動の街）

歩ける範囲のマスク `data/fields/<ID>_walkable.png`（1 px = 1 タイル、唯一の真実）と `data/fields/<id>.json`（建物リスト・配置物・調べ物・出入口）から
`scripts/field/` が街を組む（形式は [docs/FIELD_FORMAT.md](docs/FIELD_FORMAT.md)）。建物の位置と向きは外周から自動で決まり、
ミニマップはマスクから直接描く。建物の高さは遮蔽の式（必要距離 = (高さ − 1.7) / tan 30°）で自動的に決まる。F05 旧鹿之尾街道 商店街が最初の 1 枚。

```bash
godot --path . res://scenes/fields/f05_kaido.tscn -- time=evening          # 歩く（WASD 画面基準、E 調べる、F1 デバッグ、F2 通行判定と区画）
godot --path . res://scenes/fields/f05_kaido.tscn -- field_yaw=30 sun_az=230 regen=1   # 回転・太陽方位を試す / AO を焼き直す
godot --headless --path . --script res://tests/field_validate.gd           # データの検証（道幅・連結性・narrow）
godot --headless --path . --script res://tools/bake_fields.gd -- all       # 全フィールドの AO キャッシュを焼き直す
```

生成物（AO・手続きテクスチャ）は `cache/fields/<ID>/`（Git 管理外）に置き、キー（JSON・マスク・テクスチャ版のハッシュ）が変われば起動時に焼き直す。
記録は [docs/lookdev/PHASE9.md](docs/lookdev/PHASE9.md)。

## 縦切りプロトタイプ（8/1〜8/3）

```sh
godot --path . res://scenes/proto.tscn                                  # 遊ぶ（E 話す / N 手帳 / F1 デバッグ / T 日を終える）
godot --headless --path . --script res://tests/story_exhaustive.gd     # 3 日分の全選択肢を総当たり（約 80 秒）
```

状態管理の設計は [docs/DESIGN_STATE.md](docs/DESIGN_STATE.md)、遊び方とテスト結果は [docs/PROTO.md](docs/PROTO.md)。

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
tools/lookdev_walk.py スプライト歩行テスト（A〜D 条件、GIF、MAD）
docs/ART_SPEC.md     素材制作仕様（lookdev の結論）
scenes/proto.tscn    縦切りプロトタイプ（scripts/proto.gd）
scripts/story/       状態管理エンジンと脚本ランナー
data/story/proto.json 3 日分の脚本
tests/story_exhaustive.gd 脚本の総当たりテスト
docs/DESIGN_STATE.md 状態管理の設計
docs/PROTO.md        プロトタイプの遊び方・テスト結果・脚本の作業量
scenes/block.tscn    街路 1 ブロックの縦切り（scripts/block.gd）
scripts/town/        建物生成・手続きテクスチャ・AO ベイク
assets/pixellab/     PixelLab 素材の流用テスト用コピー
docs/lookdev/        検証の所見と比較シート
tools/setup_godot.sh Godot のインストール（Linux）
tools/setup_godot.ps1 Godot のインストール（Windows）
tools/check.sh       検証スクリプト
.claude/             Claude Code on the web 用の起動フック（Godot を自動インストール）
```

## Claude Code on the web

`.claude/hooks/session-start.sh` がセッション開始時に Godot を自動インストールするので、
Web セッション内でも `godot` コマンドがそのまま使えます。
