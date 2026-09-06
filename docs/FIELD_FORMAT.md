# フィールドのデータ形式（J-1 設計案）— `data/fields/<id>.json`

2026-09-06。F05 を最初の実例として、以降 15 フィールドの雛形にする形式。**実装前の確認用の案。**
仕様（人が読む `docs/field/*.md`）とは別管理。座標・寸法の単位は**タイル**（1 タイル = 32 texel = 1.143 m）で統一し、
プログラムがメートルへ変換する。タイル座標は 2D 地図と同じ左上原点・右が +x・下が +y（ワールドでは x → +X、y → +Z）。

## 1. 全体構造

```json
{
  "format": 1,
  "id": "F05",
  "name": "旧鹿之尾街道 商店街",
  "size": [32, 40],                 // タイル
  "elevation": 2,
  "biome": "old_shopping_street",
  "scene": "res://scenes/fields/f05_kaido.tscn",
  "ground": { "default": "asphalt_old", "patches": [ ... ] },
  "roads": [ ... ],
  "lots": [ ... ],
  "props": [ ... ],
  "collision": { "extra_blocked": [ ... ], "extra_open": [ ... ] },
  "points": [ ... ],
  "exits": [ ... ],
  "areas": [ ... ]
}
```

- `format`: 形式の版。互換性を切るときに上げる。
- 要素はすべて配列 + `id` 付きの辞書。順番に意味を持たせない（生成順は種別ごとに決まっている）。

## 2. 道 `roads`

```json
{ "id": "kaido", "kind": "old_street", "width": 3,
  "line": [[8, 0], [8, 39]] }
{ "id": "alley_w", "kind": "alley", "width": 1, "line": [[0, 15], [8, 15]] }
{ "id": "sando", "kind": "temple_path", "width": 2, "line": [[22, 20], [22, 27]] }
```

- `line`: 中心線の折れ線（タイル）。`width` はタイル。道は **画面の縦（0°）か横（90°）** に走る（前提の変更 1）。
- `kind` → 舗装テクスチャと縁の作りを決める: `old_street`（旧街道: 狭い、歩車の区別が曖昧、側溝蓋）、
  `alley`（路地: 土＋コンクリート）、`temple_path`（参道: 石畳）、`sidewalk`（歩道の帯を独立させたいとき）。
- 通行判定: 道の帯は歩ける。道の外は区画の判定に従う。

## 3. 区画と建物 `lots`

```json
{ "id": "shop_a", "kind": "shop_shutter", "rect": [4, 3, 3, 4],      // x, y, w, h（タイル）。建物の占有矩形
  "front": "E",                     // 正面が向く辺（道側）
  "rotate": 20,                     // 正面をカメラ側へ振る角度（度）。0 = 道と平行。前提の変更 1
  "floors": 2, "roof": "gable", "wall": "weatherboard", "height": 6.0,
  "features": ["shutter", "sign"],  // 正面に付けるもの
  "variant": 1 }                    // 同種の色替え・窓配置のバリエーション
```

- `kind` は建物種別。F05 で要るもの: `shop_shutter`（シャッターの下りた商店）、`shop_wood`（木の引き戸の店）、
  `dagashi`（駄菓子屋。窓から黄色い光）、`temple_gate`（山門）、`temple_hall`（本堂）、`fence_block` / `fence_wall`（塀）、
  `house`（民家）、`bldg_rc`（コンクリートの箱。F05 には無い）。
- `rect` は 2D 地図での占有。生成器は矩形の中心を回転の軸にして `rotate` だけ振る。振って歩道にはみ出す分は
  `collision` に反映する（通行可能幅は生成時に計算して警告する: J-2a）。
- `height` は壁高（m）。省略時は `floors` × 3.0。`roof`: `gable` / `flat` / `hip`（後で）/ `none`。
- 塀は `kind: fence_*` で `rect` を細長く取る（幅 0 は不可、最小 0.15 m は生成器が補正）。

## 4. 配置物 `props`

```json
{ "id": "vend_1", "asset": "obj_vending_machine", "at": [6.5, 18.5], "facing": "E" }
{ "id": "light_1", "asset": "obj_street_light_led", "at": [10.5, 11.5] }
```

- `asset` は `assets/pixellab/objects/<asset>.png`（62 点）。ビルボード（カメラ正対、等倍固定）。
- `at` はタイル座標（小数可 = タイル内の位置）。`facing` は 3/4 視の素材（軽自動車など）の向きの記録用。
  現状は左右反転だけ対応（`W` なら反転）。
- 通行判定: 足元 1 タイルを塞ぐ（`blocking: false` で解除）。

## 5. 通行判定 `collision`

生成規則で自動判定し、例外だけを書く。
- 自動: 道の帯 = 通行可。`lots` の `rect`（回転後の footprint）= 不可。`props` の足元 = 不可。それ以外の地面 = 可。
- `extra_blocked` / `extra_open`: タイル座標の配列で上書き（花壇、段差、通れる隙間など）。
- 生成時に 32×40 のビット図を作り、デバッグ表示（F2）で確認できるようにする。

## 6. 調べ物 `points` と出入口 `exits`

```json
{ "id": "toki_shop", "at": [5, 20], "kind": "shop", "label": "たちばな屋", "facing": "E" }
{ "id": "signpost",  "at": [10, 38], "kind": "sign", "label": "道標" }
```
```json
{ "dir": "W", "at": [0, 15], "to": "F01", "spawn": [1, 15], "label": "路地を抜けて国道の駐車場裏へ" }
```

- `points` は `docs/field/F05_spec.md` の 10 点をそのまま。`kind` は接触時の動作の種類（shop / item / board / sign / door / npc / water）。
  人物（`npc`）は状況で出現するので、出現条件は脚本側（`data/story/`）が持ち、ここには位置だけ。
- `exits` は 4 方位。`at` は接触判定のタイル、`spawn` は入ってきたときの立ち位置。

## 7. 場所 ID `areas`

```json
{ "id": "front_of_dagashi", "rect": [4, 18, 4, 4] }
```
- 会話や環境音の切り替え（「駄菓子屋の前だけ暖かい」）に使う矩形。脚本は場所 ID で参照する。

## 8. 生成の流れとキャッシュ

1. JSON を読む → 検証（未定義の kind / asset、矩形の重なり、出入口が道に接しているか）。
2. 地面（`ground.default` + `patches`）→ 道 → 区画（建物生成器へ）→ 塀 → 配置物 → 調べ物・出入口のマーカー。
3. UV2 と AO を焼く。AO と手続きテクスチャは `user://cache/fields/<id>/` に PNG で保存し、次回は読む（Git 管理外）。
   `-- regen=1` で焼き直し。

## 9. 決めたい点（確認事項）

1. 座標はタイル基準（左上原点）でよいか。ワールドの原点はフィールドの左上（x 右、z 下）に置く。
2. 建物の回転は `rotate`（度）を区画ごとに書く案でよいか。それとも `kind` ごとの既定値 + 例外だけ書くか。
3. `props` の向きは左右反転だけで始めてよいか（3/4 視の車は向きの版が要る）。
4. 通行判定は「自動 + 例外」でよいか。全タイルのビット図を人が書く方式は取らない。
5. キャッシュの置き場は `user://`（ユーザーごと）でよいか。ビルドに同梱するなら `res://cache/` を Git 管理外にする。
