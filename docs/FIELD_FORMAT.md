# フィールドのデータ形式 — `data/fields/<id>.json`（形式 1）

2026-09-06。J-1 の設計案に K-1〜K-3 の修正を反映した確定版。F05 が最初の実例。
仕様（人が読む `docs/field/*.md`）とは別管理。実装は `scripts/field/field_data.gd`（読み込み・検証・通行判定）、
`scripts/field/field_builder.gd`（生成）、`scripts/field/field_scene.gd`（歩く・カメラ・調べ物）。

## 0. 座標系と単位

- **単位はタイル**（1 タイル = 32 texel = 1.143 m）。小数可。寸法もタイル。メートルが要る値には `_m` を付ける（`height_m`）。
- **タイル座標は 2D 地図と同じ左上原点。右が +x、下が +y。**
- **ワールドへの対応: 地図の +x → ワールド +X、地図の +y（下）→ ワールド +Z。** 高さは +Y。
  Godot のカメラは −Z が前方なので、「地図の上（北）」= ワールド −Z = field_yaw 0 のときカメラの前方（画面の上）。
- タイル (tx, ty) の中心はワールド ((tx + 0.5)·T, 0, (ty + 0.5)·T)、T = 1.143。矩形 `[x, y, w, h]` はタイル境界に乗る。

## 1. 全体構造

```json
{
  "format": 1,
  "id": "F05", "name": "旧鹿之尾街道 商店街",
  "size": [32, 40], "elevation": 2, "biome": "old_shopping_street",
  "scene": "res://scenes/fields/f05_kaido.tscn",
  "field_yaw": 30,
  "ground": { "default": "lot_concrete", "patches": [ {"id": "temple_yard", "rect": [18, 4, 13, 16], "tex": "gravel"} ] },
  "roads":  [ ... ], "lots": [ ... ], "props": [ ... ],
  "collision": { "extra_blocked": [], "extra_open": [] },
  "points": [ ... ], "exits": [ ... ], "areas": [ ... ]
}
```

- `field_yaw`（度）: **フィールド全体をカメラに対して回す角度（K-1）。** 0 = 地図の北が画面の上。正で地図が時計回り（上から見て）に回る。
  **符号で夕方の見え方が決まる。** 規範値の太陽（方位 165、カメラ基準）は奥から手前への逆光で、狭い通りに日が入るのは通りが
  太陽の向きから ±15° 以内のときだけ。南北の通りなら −15 付近（F05 で実測。`docs/lookdev/PHASE8.md` J-2a）。
  また俯角 42° では、通りがカメラ前方から 30° 以上振れると手前の 2 階建てが主人公を隠す。
  建物は個別に回さない。道が 30° なら奥へ抜け、直交する商店の正面は 60° 側を向く。
- 要素はすべて `id` 付きの辞書の配列。順番に意味を持たせない。

## 2. 道 `roads`

```json
{ "id": "kaido", "kind": "old_street", "width": 3, "line": [[8, 0], [8, 39]] }
{ "id": "alley_w", "kind": "alley", "width": 2, "line": [[0, 15], [8, 15]] }
{ "id": "sando", "kind": "temple_path", "width": 2, "line": [[22, 20], [22, 22]] }
```

- `line` は中心線の折れ線（タイル、軸に平行な線分）。`width` はタイル。道の帯は通行可。
- `kind` → 舗装テクスチャ: `old_street`（旧街道: 狭い舗装、歩車の区別が曖昧、片側に側溝）、`alley`（路地: 土＋コンクリート）、
  `temple_path`（参道: 石畳）、`road`（車道。白線あり）。

## 3. 区画と建物 `lots`

```json
{ "id": "shop_a", "kind": "shop_shutter", "rect": [4, 2, 3, 4], "front": "E",
  "floors": 2, "roof": "gable", "wall": "weatherboard", "variant": 1,
  "rotate": 0, "when": null }
```

| キー | 意味 |
| --- | --- |
| `kind` | 建物種別（下表） |
| `rect` | 占有矩形（タイル） |
| `front` | 正面が向く辺 `N/E/S/W`（道側）。正面に扉・シャッター・看板・窓が付く |
| `floors` | 階数。壁高は `height_m` があればそれ、無ければ floors × 3.0 m |
| `roof` | `gable`（切妻。棟は正面と平行）/ `flat` / `none` |
| `wall` | 壁の材質: `weatherboard` / `mortar` / `concrete` / `namako` / `plaster` |
| `variant` | 同種の色替え・窓配置の番号 |
| `rotate` | 区画ごとの回転（度）。**既定 0。** 戸建て（F02・F13）で変化を付ける例外用 |
| `when` | 状態変化のフック（第 7 節）。無ければ常時 |

建物種別（F05 で実装済み）: `shop_shutter`（シャッターの下りた商店）、`shop_wood`（木の引き戸の店）、`dagashi`（駄菓子屋。窓から黄色い光、営業中の看板）、
`house`（民家）、`temple_hall`（本堂。白壁と瓦、高い軒）、`temple_gate`（山門。柱と屋根だけ、通り抜けられる）、
`fence_wall`（寺の塀: 白壁と瓦の笠）、`fence_block`（ブロック塀）、`bldg_rc`（コンクリートの箱）。
塀は `rect` を細長く取る（幅 1 タイル未満は生成器が 0.2 m に補正）。`temple_gate` の矩形は通行可（他は不可）。

## 4. 配置物 `props`

```json
{ "id": "vend_1", "asset": "obj_vending_machine", "at": [7.5, 18.5], "facing": "E", "when": null }
```

- `asset` は `data/assets/objects.json`（第 5 節）のキー。寸法・当たり判定・発光はそこから引く。フィールド側は `asset` と `at` だけで済む。
- `at` はタイル座標（小数可）。`facing` は 4 方位で記録する（`N/E/S/W`）。現状は `W` のとき左右反転するだけ。後で 4 方向版の素材へ差し替える。
- `when`: 第 7 節。

## 5. アセット定義 `data/assets/objects.json`（K-2b）

```json
{ "obj_vending_machine": { "file": "assets/pixellab/objects/obj_vending_machine.png",
    "kind": "billboard", "height_m": 1.83, "footprint": [1, 1], "blocking": true,
    "emissive": { "color": [1.0, 0.95, 0.85], "energy": 1.2, "offset_m": [0, 1.2, 0.3], "range_m": 4.0 } } }
```

- `kind`: `billboard`（カメラ正対、等倍固定）/ `plate`（壁に貼る板）/ `decal`（地面に貼る板）。
- `height_m` は素材の px / 28。`footprint` は足元の占有タイル（当たり判定）。`blocking: false` で通り抜け可。
- `emissive` があれば、夕方・夜のプリセットで OmniLight3D を `offset_m` に置く（街灯、駄菓子屋の窓）。色は光源にだけ彩度を許す（ART_SPEC 第 7 節）。

## 6. 通行判定 `collision`

自動判定 + 例外。
- 自動: 道の帯 = 可。`lots` の矩形 = 不可（`temple_gate` は可）。`props` の `footprint` = 不可（`blocking: false` を除く）。
  地面の残り = 可。フィールドの外 = 不可。
- `extra_blocked` / `extra_open`: タイル座標の配列で上書き。
- 生成時に size のビット図を作る。デバッグ表示（F2）で確認できる。
- **検証（起動時と `tests/field_validate.gd`）**: 未定義の kind / asset / tex、矩形の重なり（lots 同士）、出入口が通行可タイルに接しているか、
  **連結性: 全ての出入口と調べ物（の隣接タイル）が、最初の出入口から歩いて到達できるか**（ビット図の塗りつぶし。K-2d）。

## 7. 状態変化のフック `when`（K-2a）

`lots` と `props` の任意キー。**フラグ名の文字列**。フラグが立っているときだけ生成（表示）する。

```json
{ "id": "poster_3", "asset": "obj_poster", "at": [12.5, 8.0], "when": "f06_missing_3" }
{ "id": "poster_3_off", "asset": "obj_poster_faded", "at": [12.5, 8.0], "when": "!f06_missing_3" }
```

- `!` 始まりは否定。フラグの意味と発火条件は脚本側（`data/story/`）が持ち、フィールドは「立ったら出る」を宣言するだけ。
- フィールドの生成時に `FieldScene.flags`（脚本の状態から渡す辞書）で評価する。フラグが変わったら該当要素だけ作り直す（`rebuild_conditional()`）。
- F05 の例: `toki_npc` は `when: "toki_present"`（脚本側のフラグ。今は手動で立てるだけ）。

## 8. 調べ物 `points`・出入口 `exits`・場所 ID `areas`

```json
{ "id": "toki_shop", "at": [5, 20], "kind": "shop", "label": "たちばな屋" }
{ "dir": "W", "at": [0, 15], "to": "F01", "spawn": [1, 15], "label": "路地を抜けて国道の駐車場裏へ" }
{ "id": "front_of_dagashi", "rect": [4, 18, 5, 4] }
```

- `points` は `docs/field/F05_spec.md` の 10 点をそのまま。座標は建物の上でもよく、接触は「隣接する通行可タイルに立って 1.5 タイル以内」。
- `exits` は 4 方位。`at` は接触タイル、`spawn` は入ってきたときの立ち位置。
- `areas` は会話・環境音の切り替え用の矩形。

## 9. 生成とキャッシュ（K-3 の 5）

1. JSON を読む → 検証（第 6 節）。
2. 地面 → 道 → 区画（建物生成器）→ 塀 → 配置物・光源 → 調べ物と出入口のマーカー → `field_yaw` で全体を回す。
3. AO を焼き、`res://cache/fields/<id>/`（Git 管理外）に PNG と manifest（JSON のハッシュ + 生成器の版）を保存する。
   次回はハッシュが一致すれば読む。`-- regen=1` で焼き直し。
4. **配布ビルドは `res://cache/` を焼き込んで同梱する**（エクスポート設定で `cache/**` を含める）。プレイヤーがフィールドに入るたびに
   ベイクで止まらないため。`user://` は開発時の再生成用に使わない（`res://` だけ）。

再生成の手順:
```sh
godot --headless --path . --script res://tools/bake_fields.gd            # キャッシュが古いフィールドだけ焼いて res://cache/fields/ に保存
godot --headless --path . --script res://tools/bake_fields.gd -- all     # 全フィールドを焼き直す（配布ビルド前）
godot --headless --path . --script res://tests/field_validate.gd         # 全フィールドの検証（kind / asset / 重なり / 連結性）
godot --path . res://scenes/fields/f05_kaido.tscn -- regen=1             # 1 フィールドだけ焼き直して起動
```
