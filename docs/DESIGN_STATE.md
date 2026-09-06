# 状態管理の設計（F-1 → G-1 修正版）— 『磐戸町奇譚』の「知っている / 開示した / 言った / 疑われている」

2026-09-06。G-1 の修正を反映した版。F-2（3 日・NPC 2 人）の実装はこの設計に従う。
実装: `scripts/story/`（エンジン）、`data/story/proto.json`（脚本）、`scenes/proto.tscn`（縦切り）。

## 0. 前提と方針

- 核: 主人公は親友（美咲）を怪異への生贄に捧げた加害者で、初日からその事実を知っている。
  **この核心はプロローグでプレイヤーにも明かす（G-1a）。** 31 日間の性質は「謎解き」ではなく
  「バレるかもしれない恐怖」と「隠し通すか告白するかの道徳的な緊張」である。
- 主人公は隠して調査に加わり、NPC に真実を言う・嘘をつく・黙る、を重ねる。
- 方針は 3 つ。
  1. **「事実」を変数として定義し、知識・発言・信念を「変数への値の割り当て」で表す。**
     嘘は「主人公が知っている値と違う値を言うこと」（世界の真実との差ではない）。
  2. **4 種の状態を別のテーブルに持つ。** 主人公の知識・プレイヤーへの開示・発言記録・NPC ごとの信念。
  3. **状態の変更はすべて Event として記録する。** ただし **正はスナップショット**で、Event 列は監査・デバッグ・検証用（G-1e）。

## 1. 基本語彙

### 1.1 事実（Fact）と階層（G-1f）

事実は 2 階層。

| 階層 | 数の目安 | 持つもの | 用途 |
| --- | --- | --- | --- |
| **core** | 10 前後 | domain（取りうる値）、truth、topic、weight。NPC ごとに信念・確信度・出所・疑いを持つ | 嘘と矛盾の対象。主人公が問われること |
| **flag** | 数十 | Yes/No のみ。NPC ごとに「知っている / 知らない」だけ | 進行フラグ、周辺事実、証拠の発見 |

```
Fact (core) {
  id:      "night_0731_pc_location"          # 7/31 の夜、主人公はどこにいたか
  domain:  ["home", "shrine", "with_misaki"]
  truth:   "shrine"                            # 世界の真実（脚本）
  topic:   "misaki"
  weight:  3                                   # 嘘がばれたときの重さ
  label:   "7/31 の夜の所在"
}
Fact (flag) { id: "ribbon_found", label: "神社でリボンを見つけた" }
```

Yes/No の core 事実も domain ["yes", "no"] で表す。「答えを避けた」は値ではなく発言の種類（silence）。

### 1.2 出来事（Event）

| kind | 内容 | 主な引数 |
| --- | --- | --- |
| `learn` | 主人公がある事実の値を知る | fact, value, source |
| `reveal` | プレイヤーに開示（回想・独白。周辺事実のみ） | fact, scene |
| `flag` | flag 事実を立てる / NPC が flag を知る | fact, npc? |
| `say` | 主人公が NPC に発言する | to, fact, kind（truth / lie / silence）, asserted, witnesses, scene |
| `npc_learn` | NPC が core 事実の値を得る | npc, fact, value, source（observe / pc / heard / script） |
| `confront` | NPC が段階 3 に達し、主人公に問い詰める（結果を含む） | npc, fact, outcome（confess / deny / silence） |
| `tick` | 日付が進む（伝播と保留中の反応を処理） | day |

全 Event は `{seq, day, kind, ...}`。

## 2. 4 種の状態

### 2.1 主人公の知識 `pc_knowledge`

`Dictionary<fact_id, {value, since_day, source}>`。初期値に核心（`misaki_fate = sacrificed` 等）を含む。
参照: 会話で「真実を言う」が指す値。知らないことは言えない（その場合の選択肢は「知らない」= truth で asserted null）。

### 2.2 プレイヤーへの開示 `disclosure`（G-1a）

`Dictionary<fact_id, {revealed, day, scene}>`。**核心には使わない。** 対象は周辺事実だけ:

- 遺体や現場がどうなったか
- 儀式が何を要求したか
- 共犯者や目撃者がいたか
- 主人公自身がまだ思い出せていない部分（記憶の欠落）

開示は回想・独白・現場の調査で `reveal` として記録し、以後の会話の選択肢や地の文が変わる。
選択肢の可否は主人公の知識で決め、開示は文言と演出だけを変える。「開示前の真実を伏せ字で出すか」の分岐点は消えた。

### 2.3 発言記録 `statements`（追記のみ）

```
Statement {
  id, day, to, fact, kind: truth | lie | silence,
  asserted,          # 言った値。silence は null
  is_lie,            # asserted != pc_knowledge[fact].value（記録時に確定）
  witnesses: [npc],  # 同席者（伝播の起点）
  scene
}
```

- 「言ったが嘘」= `is_lie`。「知っているが言っていない」= 知識にあって、その NPC 宛の発言が無い（クエリ）。
- **プレイヤーは「手帳」でこの記録を全件閲覧できる（G-1b）。** 誰に・いつ・何を・真実か嘘か。
  矛盾の検出結果そのものは見せないが、材料はすべて渡す。「嘘を自分で管理している加害者」の人物像に合わせる。

### 2.4 NPC ごとの信念 `npc[id]`

```
npc[id] {
  core: Dictionary<fact_id, {
    belief, confidence,                  # 導出値（derive_belief）
    sources: [ {kind: pc_said, statement, day, value}
             | {kind: observe, day, value}          # 脚本で NPC が自分で知っている
             | {kind: heard, from, day, value} ],   # 他 NPC 経由（伝播）
    doubt: 0..1
  }>
  flags: Set<fact_id>                    # 知っている flag 事実
  suspicion: 0..100                      # 主人公全体への疑念（連続値）
  trust: 0..100
  stage: 0..3                            # suspicion の離散化（G-1c）
  relation: "normal" | "estranged" | "confidant"   # 断絶 / 告白を受けた（G-1d）
  pending: [ {due_day, kind: confront | probe | share, fact, against_statement} ]
}
```

`memory_of_pc` は削除した（G-1g）。主人公から直接聞いた発言は `sources` の `pc_said` に statement id 付きで入っており、
「その NPC に主人公が直接言った発言の一覧」はそこから引ける。二重に持たない。

### 2.5 疑念の段階と挙動（G-1c）

| stage | suspicion | 名称 | 必ず見せる挙動 |
| --- | --- | --- | --- |
| 0 | 0〜19 | 平常 | 通常の会話 |
| 1 | 20〜44 | 違和感 | 目を合わせない・返事が一拍遅れる（地の文で明示）。同じことをもう一度聞く |
| 2 | 45〜69 | 疑念 | 質問が具体的になる（場所・時刻を指定して聞く）。他の NPC に確かめに行く（伝播が強まる） |
| 3 | 70〜100 | 確信 | **問い詰め（confront）**。会話の冒頭で過去の発言を突きつける |

段階が上がった瞬間に、その NPC の次の会話は必ず段階の挙動から始まる（脚本の `stage_lines`）。
段階は下がらない（trust が上がっても stage は据え置き。suspicion の内部値だけ下がる）。
内部値はデバッグ画面で見え、プレイヤーには挙動でだけ見せる。

## 3. 会話の選択肢が参照・更新する状態

脚本は JSON。1 日 × 1 NPC につき質問（node）が 1〜3 個。

```
{"id": "d1_kanae_where", "npc": "kanae", "fact": "night_0731_pc_location",
 "prompt": "あの夜、どこにいたの？",
 "options": [
   {"kind": "truth",   "label": "神社にいた、と話す"},
   {"kind": "lie",     "label": "家にいた、と言う", "asserted": "home"},
   {"kind": "silence", "label": "答えない"}],
 "responses": {"truth": "……神社に？", "lie": "そう。ならいいけど", "silence": "……"}}
```

| 参照 | 用途 |
| --- | --- |
| pc_knowledge | truth が指す値 |
| disclosure | 文言・地の文 |
| statements | 「前に別のことを言った」時の選択肢の出し分け、同じ嘘を繰り返す選択肢 |
| npc.stage / relation / pending | 会話冒頭の挙動、問い詰めの挿入 |

| 更新 | 内容 |
| --- | --- |
| statements | `say` を追記 |
| npc[to].core[fact].sources | `pc_said` を追加 → 矛盾チェック → doubt / suspicion / stage / pending |
| npc[witness] | 同席者にも `pc_said`（confidence 低め） |
| npc[to].trust | truth で +、silence で −（小）、lie は変化なし（ばれるまで） |

## 4. 矛盾の検出・伝播・提示

### 4.1 検出（その場、決定的）

新しい `say`（to = N, fact = F, asserted = V）で、N について:

1. 自己矛盾: N の `pc_said` に同じ F で V と違う値がある（最も重い）
2. 観察との矛盾: N の `observe` の値が V と違う
3. 伝聞との矛盾: N の `heard` の値が V と違う（最も軽い。伝聞は疑える）

`doubt[F] += weight × 係数`、`suspicion += weight × 係数`。silence は矛盾にならないが、同じ質問に 2 度黙ると suspicion 小増。
矛盾は `contradictions[]` に記録し、`pending` に `confront`（due = day + 1〜2）を積む。

### 4.2 伝播（`tick`）

NPC 間の関係値（脚本）が閾値以上なら、`pc_said` を `heard` として隣へ 1 日 1 ホップ流す。乱数なし。
stage 2 以上の NPC は関係値の閾値が下がる（確かめに行く = 挙動）。

### 4.3 提示（G-1b）

矛盾の検出結果はプレイヤーに直接見せない。見せるのは (a) 段階の挙動、(b) 問い詰めの台詞での具体的な突きつけ
（「一日に、家にいたって言ったよね」）、(c) 手帳による発言記録の完全な閲覧。デバッグ画面ではすべて見える。

## 5. 敗北条件と告白ルート（G-1d）

隠し通すことが常に最適解にならないように、3 つの出口を用意する。

### 5.1 stage 3（確信）→ 問い詰め

NPC が stage 3 に達すると、次の会話の冒頭で `confront` が起きる。NPC は矛盾の中身を突きつけ、主人公は 3 択:

| 選択 | 帰結 |
| --- | --- |
| 告白（真実を言う） | 5.2 の告白ルートへ。relation = confidant |
| 否認（嘘を重ねる） | relation = **estranged（断絶）**。以後その NPC とは会話できず、その NPC は翌日から知っている事実と疑いを全員に流す（伝播の閾値ゼロ） |
| 沈黙 | 否認と同じだが 1 日遅れて断絶（もう一度だけ猶予） |

### 5.2 露見（敗北ではなく、結末の一つ）

**estranged の NPC が 2 人以上**になった日の終わり、または **核心事実（misaki_fate）を stage 3 の NPC が観察か伝聞で持った**とき、
次の `tick` で「露見」の結末に入る。町が主人公を知り、調査から外される。
日付によって結末の文面が変わる（早い露見: 何も分からないまま終わる。遅い露見: 怪異の正体は分かったが自分が終わる）。
ゲームオーバー画面で即リトライではなく、**結末として演出し、その日のオートセーブから再開できる**。

### 5.3 告白ルート（「真実を言う」の帰結）

核心事実を NPC に真実で言うと、その NPC の relation は confidant になり、**即座には何も終わらない**。
帰結は相手と trust で分岐する。

- trust が高い相手: 秘密を抱えて協力者になる（自分も背負う）。以後、その NPC への嘘は不要になり、矛盾の対象から外れる。
  ただしその NPC の suspicion は 0 になる代わりに、**その NPC 自身が他の NPC から疑われる**（伝播の対象になる）。
- trust が低い相手: 翌日以降、伝播で広がり露見（5.2）に向かう。ただし主人公が先に自首（下記）すれば別の結末。
- いつでも選べる行動として「自首」（駐在所または美咲の家族へ告白）を置く。**告白の結末は敗北ではなく、贖いの結末**として
  露見とは別の文面・別の演出を持つ。何日目に告白したかで、美咲の家族・町・怪異の側の反応が変わる。

これにより「真実を言う」は一度試して二度と選ばない選択肢ではなく、**相手と時期を選ぶ戦略**になる。
隠し通した場合の結末（31 日目）も一つの結末で、道徳的にはもっとも重いものとして書く。

### 5.4 3 日のプロトタイプでの縮約

- stage 3 と問い詰めは 3 日で到達可能にする（矛盾 2 回で 70 を超える重み）。
- 露見は「estranged 2 人」で 3 日目の終わりに判定。告白は「協力者化」まで実装し、自首は結末文だけ。

## 6. セーブとパッチ（G-1e）

```
Save { version, day, scene, player_pos, snapshot: {全状態}, events: [...] }
```

- **スナップショットが正。** ロードはスナップショットを読む。Event 列は監査・デバッグ・検証用で、
  再生は検証モード（デバッグ画面の「再生して照合」とテストスクリプト）でのみ行う。
- リリース後に脚本 JSON を直しても、既存セーブはスナップショットのまま続く（静かに変わらない）。
  脚本の変更で必要になる移行は `version` と移行表で明示的に行う。
- 1 日ごとのオートセーブ（`tick` の直後）と手動セーブ。

## 7. 規模とデバッグ可能性

- core 10 × NPC 8 = 80 エントリを完全にモデル化、flag は 1 ビット × NPC。Event は 31 日で 1,000 前後、JSON 500 KB 以下。
- 状態を直接書く経路は無く、変更は `apply()` の 7 種の Event だけ。31 日後の不整合は `apply()` / `derive_belief()` / `propagate()`
  の 3 関数か脚本データに原因が限定される。
- 起動時の静的検査: 未定義の fact / npc、domain 外の asserted、到達不能な node。
- デバッグ画面（F1）: 日付、知識と開示の差、発言記録、NPC ごとの core 表（belief / confidence / doubt / sources）、
  suspicion 内部値と stage、trust、relation、pending、矛盾一覧、Event 末尾。「Event 再生 → スナップショット照合」ボタン。
- 総当たりテスト（`tests/story_exhaustive.gd`）: 3 日分の全選択肢の組み合わせを UI なしで再生し、
  クラッシュ・不変条件・到達不能 node・再生照合を検査する。31 日ではサンプリングに切り替える前提で、仕組みだけ先に作る。

## 8. 脚本の作業量（G-1f の所見は PROTO.md に記載）

3 日分を実際に書いた結果と、core / flag の階層化で作業量が耐えられるかの判断は
[lookdev/../PROTO.md](PROTO.md) に記す。

## 9. 要確認事項（残り）

1. 疑念の段階の閾値（20 / 45 / 70）と、矛盾 1 回あたりの上昇量（weight × 10 前後）。3 日で stage 3 に届く設計にしてある。
2. 告白ルートの「協力者化」の条件を trust の閾値だけにするか、NPC ごとの脚本にするか。
3. 自首（いつでも選べる行動）を本編に置くか。プロトタイプでは結末文のみ。
4. 時間の粒度: 日 + 2 slot（昼 / 夕）。プロトタイプは日単位（slot は演出上の区切りのみ）。
