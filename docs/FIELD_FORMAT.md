# フィールドデータ形式（形式 2、フェーズ 9 M-2d）

フィールドは **歩ける範囲を先に描き、その外周に建物を並べる**。人が書くのは次の 2 つ。

| ファイル | 役割 |
| --- | --- |
| `data/fields/<ID>_walkable.png` | **唯一の真実。** 歩ける範囲のマスク（1 px = 1 タイル）。当たり判定・ミニマップ・建物の配置はすべてここから導く |
| `data/fields/<id>.json` | 建物のリスト（種別・間口・階数・順番）、地面のテクスチャ、配置物、調べ物、出入口、領域 |

生成物（区画の矩形、AO、手続きテクスチャ）は Git 管理外の `cache/fields/<ID>/` に置く。読み込みは `scripts/field/field_data.gd`、
配置は `field_layout.gd`、3D 化は `field_builder.gd`、ミニマップは `minimap.gd`。

## 0. 座標

- タイル座標。**左上原点、右 +x、下 +y**（地図画像と同じ）。1 タイル = 1.143 m（`FieldData.TILE`）。
- ワールドは x → +X、y → +Z。北 = −Z = 地図の上。
- `field_yaw`（度）でフィールド全体をカメラに対して回す。0 = 地図の北が画面の上、正で地図が時計回り（上から見て）。
  建物は個別に回さない。入力は画面基準（W = 画面の上）。
- 「カメラの方向」はフィールドのローカルで `(-sin field_yaw, cos field_yaw)` の向き（タイル）。遮蔽の式（第 6 節）はこれで判定する。

## 1. 歩行可能マスク `<ID>_walkable.png`

大きさは `size` と同じ（F05 なら 32×40 px）。**値は厳密に 4 つだけ**（R = G = B、アルファ 255）。それ以外の値が 1 画素でもあれば
読み込みを失敗させ、座標と色を出す（アンチエイリアス付きのブラシや再保存に注意。最近傍・丸めはしない）。

| 値 | 種別 | 意味 |
| --- | --- | --- |
| 255 | `walk` | 歩ける（主要）。**道幅は 6 タイル以上**（検証で縦横どちらかの連続長が 6 未満だとエラー） |
| 192 | `narrow` | 歩ける裏路地・袋小路。幅の制限なし。調べ物・NPC・出入口も置ける（フェーズ 13 R-3）。隠れは実行時のフェードで解く |
| 128 | `open` | 歩けない空き地（側溝・植込み・駐車場・水面）。建物は置かず塀や建物の正面を向ける。`ground.open` のテクスチャ（patches で上書き可） |
| 0 | `blocked` | 歩けない。歩ける範囲か空き地に接するタイルが建物の候補地になる |

**手前側の列には 1 タイルの `open` の帯を通りとの間に置く**（第 6 節の式で、平屋の軒 2.3 m は 1.0 m 以内の歩けるタイルの頭を隠すため）。

ミニマップは `walk` / `narrow` / `open` をそのまま描く（建物は描かない）。

## 2. JSON の構造

```json
{
  "format": 2,
  "id": "F05", "name": "旧鹿之尾街道 商店街", "size": [32, 40], "elevation": 2, "biome": "old_shopping_street",
  "scene": "res://scenes/fields/f05_kaido.tscn",
  "field_yaw": 45,
  "sun_az": { "evening": 232 },
  "walkable": "res://data/fields/F05_walkable.png",
  "ground":   { "walk": "old_street", "narrow": "alley", "open": "gravel", "default": "lot_ground",
                "patches": [ { "id": "temple_yard", "rect": [19, 5, 12, 12], "tex": "gravel" } ] },
  "edge_fill": [ { "rect": [17, 4, 15, 14], "kind": "fence_wall", "reserve": true },
                 { "rect": [0, 0, 32, 40], "kind": "fence_block" } ],
  "buildings": [ ... ],
  "props": [ ... ], "collision": { "extra_blocked": [], "extra_open": [] },
  "points": [ ... ], "exits": [ ... ], "areas": [ ... ]
}
```

- `sun_az`: 時間帯ごとの太陽方位（度、カメラ基準。lookdev の `TIMES` と同じ定義）。**field_yaw とは独立。** 無い時間帯はプリセット値。
  F05 は夕方 232 で通りに西日が入る（`sun_az=` 引数で試して決める）。
- `ground`: 種別ごとの地面テクスチャ。`patches` は矩形で上書き（境内の砂利、参道の石畳など）。
- `edge_fill`: 建物が付かなかった外周を何で埋めるか。文字列（全体）か、矩形ごとのリスト（先に一致したものが勝つ）。
  `reserve: true` の領域には順番待ちの建物を置かない（`near` 指定は置ける）。境内の土塀に使う。
  kind は `fence_block`（ブロック塀 1.2 m）/ `fence_wall`（土塀 1.8 m + 瓦）/ `hedge`（生垣 1.0 m）/ `none`。

## 3. 建物 `buildings`

**位置と向きは書かない。** 歩ける範囲の外周（黒タイルのうち歩けるタイルに接するもの）を向きごとの直線の列に分け、
リストの順に間口ぶんずつ詰める。正面は自動で歩ける側を向く。

```json
{ "id": "dagashi",   "kind": "dagashi",      "width": 3, "floors": 2, "wall": "weatherboard", "near": [12, 20] },
{ "id": "temple_hall", "kind": "temple_hall", "width": 10, "depth": 5, "height_m": 4.5, "wall": "plaster", "near": [24, 4] },
{ "id": "temple_gate", "kind": "temple_gate", "width": 3, "depth": 1, "front": "S", "at": [22, 17] },
{ "kind": "shop_wood", "width": 4, "floors": 2, "wall": "mortar" },
{ "kind": "house",     "width": 3, "floors": 1, "wall": "mortar", "gap": 1 }
```

| キー | 意味 |
| --- | --- |
| `kind` | `shop_shutter` / `shop_wood` / `dagashi` / `house` / `temple_hall` / `temple_gate` / `bldg_rc` / `store`（大型店: 看板の帯 `sign` = red/blue/yellow/white、自動ドア、庇、陸屋根）/ `apartment`（団地: 各階の窓とベランダ）/ `civic`（RC の公共施設: 庇付き入口）/ 塀 3 種 |
| `width` | 間口（タイル）。既定 3 |
| `depth` | 奥行きの上限（タイル）。既定 3。裏に別の道や場外があれば自動で縮む。**2 未満しか取れない場所には置かない**（塀になる） |
| `floors` / `height_m` | 階数か軒高（m）。平屋 = 軒 2.3 + 棟 0.7 = 3.0 m、2 階建て = 軒 5.3 + 棟 1.4 = 6.7 m。地図と spec のまま書く（フェーズ 13 から式では落とさない） |
| `contiguous` | 既定 true。同じ列で接する建物と軒高をそろえ、妻側の軒を出さず一続きの屋根にする（旧商店街の長屋）。false で独立した建物 |
| `gap` | この建物の前に空けるタイル数（路地・駐車場）。既定 0 = 隙間なし |
| `wall` / `roof` / `variant` | 外壁（`weatherboard` / `mortar` / `namako` / `plaster` / `concrete`）、屋根（`gable` / `flat` / `none`）、見た目の揺らぎ |
| `near` | 「この付近の外周に置く」（タイル）。ランドマークに使う。最寄りの空いた外周タイルを含む位置に置き、入らなければ間口を縮める |
| `at` | 通り抜けできる構造物（`temple_gate`）だけの例外。歩けるタイルの上に直接置く。`front` も書く |
| `when` | フラグ名（`!` で否定）。物語側が立てる。偽なら置かない |
| `id` | 省略可。調べ物との対応や報告に使う |

配置の順: `at` → `near` → 残りを列の順（E 向き → W 向き → S 向き → N 向き、それぞれ座標順）。余ったら警告。
足りない外周は `edge_fill` の塀。

### 3b. 塀・生垣の明示 `barriers`（フェーズ 11）

空き地（128）の上に置く塀・生垣・金網・ガードレール。矩形の細い方の軸に沿って薄い箱を立てる。近景の帯の 2 列目に置くのが基本。

```json
"barriers": [ { "kind": "hedge", "rect": [4, 0, 1, 12] }, { "kind": "guardrail", "rect": [11, 0, 1, 48] } ]
```

kind: `hedge`（1.0 m）/ `fence_block`（1.2 m）/ `fence_wall`（1.8 m）/ `wire_fence`（1.5 m）/ `guardrail`（0.8 m）。矩形が 128 以外の画素を含むと検証エラー。

## 4. 配置物 `props`（形式 1 と同じ）

`{ "id", "asset", "at": [x, y]（小数可）, "facing": "N|E|S|W"（今は W だけ左右反転）, "blocking", "when" }`。
`asset` は `data/assets/objects.json` のキー（file / kind / height_m / footprint / blocking / emissive）。
**歩けるタイルの上に置く**（足元の footprint が通行不可になる）。

## 5. 調べ物・出入口・領域（形式 1 と同じ）

- `points`: `{ "id", "at", "kind", "label", "when" }`。周囲 2 タイル以内に到達できる主要タイルが要る。narrow の上は不可。
- `exits`: `{ "dir", "at", "to", "spawn", "label" }`。`walk` の上に置く。
- `areas`: `{ "id", "rect", "kind" }`。`kind: "narrow"` は矩形内を裏路地扱い（マスクの灰と同じ効果）。

## 6. 遮蔽（フェード）、遮蔽の式（助言）、近景の帯

- **隠れは実行時のフェードで解く（フェーズ 13 R-2）。** 主人公の頭（1.6 m）と腰（0.9 m）とカメラを結ぶ線分に当たる建物・塀は α 0.35、線分から 0.6 m 以内の配置物は α 0.5 に、入り 0.15 秒・戻り 0.35 秒で減衰する。シルエットは残す。
- 遮蔽の式 必要距離 = (高さ − 1.7) / tan 30° は**配置の助言**。検証は「主人公を隠しうる建物」と「隠される歩行可能タイル」の数を報告するだけで、階数は落とさない。
- 近景の帯: 歩ける範囲の西・南（カメラ側）に 2 タイル、東・北に 1 タイルの帯（128）。1 列目は歩道、2 列目に生垣・ブロック塀・金網・ガードレール（`barriers`）。建物は通りの両側に、階数・向き・位置は地図と spec のまま。
- 屋根の画面比・建物正面・遮蔽フレーム数は診断値（`areamask=1`、`walk_demo=1`）。目標にはしない。
- 検証 `tests/field_validate.gd`: 未定義の kind / asset / テクスチャ、出入口が歩けるタイル上か、narrow 上の調べ物・出入口、
  道幅（主要タイルで 6 未満）、最初の出入口からの塗りつぶしで全出入口・全調べ物に届くか、置けなかった建物（警告）。
- 実行時は主人公の頭（1.6 m）とカメラを結ぶ線分が実際の面（壁・屋根の板）に当たったときだけ透過する。塀は対象外。
- `areamask=1` で面積マスク（赤 = 側壁、黄 = 正面、緑 = 屋根、青 = 地面、桃 = フィールド外）を描き、屋根 30 % 以下・正面 15 % 以上を確認する。

## 7. 生成とキャッシュ

1. マスク → 種別 → 外周の列 → 建物の割り当て（`FieldLayout`）→ 区画の矩形
2. 地面（種別ごとの行の連続区間を 1 面に）→ 区画（建物生成器）→ 塀 → 配置物・光源 → `field_yaw` で全体を回す
3. AO はキー（JSON・マスク・objects.json のハッシュ + テクスチャ版 + field_yaw）で `res://cache/fields/<ID>/` に保存。一致すれば読む

```bash
godot --path . res://scenes/fields/f05_kaido.tscn -- time=evening               # 歩く
godot --path . res://scenes/fields/f05_kaido.tscn -- regen=1                    # AO を焼き直す
godot --path . res://scenes/fields/f05_kaido.tscn -- field_yaw=30 sun_az=230    # 回転と太陽方位を試す
godot --headless --path . --script res://tests/field_validate.gd                # 検証
godot --headless --path . --script res://tools/bake_fields.gd -- all            # 全フィールドの AO を焼き直す（配布前）
```

引数: `field=` `field_yaw=` `sun_az=` `time=` `shot=` `regen=1` `flags=a,b` `player=x,y` `target=x,y` `walk_demo=1` `quit_after_demo=1`
`areamask=1` `measure=1`（地面の範囲と視錐台内の配置物の数）`render=480x270`（描画解像度）`occl=fade|none`。操作: WASD/矢印（画面基準）、E 調べる、F1 デバッグ、F2 通行判定と区画、Esc。
