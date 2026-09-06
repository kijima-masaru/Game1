# 状態管理の設計案（F-1）— 『磐戸町奇譚』の「知っている / 開示した / 言った / 疑われている」

2026-09-06。設計案。**実装はまだ無い。** 依頼者の確認を経てから F-2（3 日・NPC 2 人の縦切り）に入る。

## 0. 前提と方針

- 核: 主人公は親友を怪異への生贄に捧げた加害者で、初日からその事実を知っている。プレイヤーには回想で少しずつ開示される。
  主人公はそれを隠して調査に加わり、NPC に真実を言う・嘘をつく・黙る、を重ねる。
- 31 日 × 複数 NPC に耐えること。数日後に効いてくる嘘、矛盾の検出、デバッグ可能性、セーブの互換性が要件。
- 方針は 3 つ。
  1. **「事実」を変数として定義し、あらゆる知識・発言・信念を「変数への値の割り当て」で表す。**
     真偽は文字列の一致ではなく、変数の値どうしの比較で決まる。嘘は「主人公が知っている値と違う値を言うこと」。
  2. **4 種の状態を別のテーブルに持ち、互いに参照はしても共有はしない。** 主人公の知識・プレイヤーへの開示・発言記録・NPC ごとの信念。
  3. **状態を直接書き換えない。すべて「出来事（Event）」として追記し、状態は出来事の畳み込みで求める。**
     セーブは出来事の列で、ロードは再生。デバッグは出来事を並べれば全部見える。

## 1. 基本語彙

### 1.1 事実変数（Fact）

世界の「問い」を変数として列挙する。各変数は取りうる値（domain）と、世界の真の値（truth）を持つ。
真の値は脚本で固定（authored）。プロトタイプでは 10〜15 個、本編で 40〜60 個を想定。

```
Fact {
  id:      "night_0731_pc_location"          # 7/31 の夜、主人公はどこにいたか
  domain:  ["home", "shrine", "with_misaki"]  # 取りうる答え
  truth:   "shrine"                            # 世界の真実（脚本）
  topic:   "misaki_disappearance"              # 会話や噂の束ね単位
  weight:  3                                   # 嘘がばれたときの重さ（疑念値の係数）
}
```

Yes/No の事実も domain ["yes", "no"] の変数として扱い、特別扱いしない。
「答えを避けた」は値ではなく発言の種類（後述の Statement.kind = silence）で表す。

### 1.2 出来事（Event）

状態を変えるものはすべて Event として記録する。種類は 5 つだけに絞る。

| kind | 内容 | 主な引数 |
| --- | --- | --- |
| `learn` | 主人公がある事実の値を知る | fact, value, source（"initial" / "npc:x" / "scene:y"） |
| `reveal` | プレイヤーにある事実が開示される（回想・独白） | fact, scene |
| `say` | 主人公が NPC に発言する | to, fact, kind（truth / lie / silence）, asserted, witnesses |
| `npc_learn` | NPC がある事実の値をどこかから得る | npc, fact, value, source（"observe" / "pc" / "npc:x" / "script"） |
| `tick` | 日付が進む（この時に噂の伝播と保留中の反応を処理） | day |

全 Event は `{seq, day, slot, kind, ...}` で、`seq` は通し番号。

## 2. 4 種の状態とデータ構造

### 2.1 主人公の知識 `PCKnowledge`

```
PCKnowledge: Dictionary<fact_id, {value, since_day, source}>
```

- 初期値に「生贄の真実」を含む（`source: "initial"`、`since_day: 0`）。プレイヤーがまだ知らなくても主人公は知っている。
- `learn` Event で追加・更新。同じ変数に別の値を学ぶこともある（誤情報）。その場合は履歴を残し、最新を採用。
- 参照される場面: 会話で「真実を言う」の選択肢を出せるかどうか（知らないことは言えない。「知らない」と答えるのは silence 扱いではなく `say kind=truth asserted=null`）。

### 2.2 プレイヤーへの開示 `Disclosure`

```
Disclosure: Dictionary<fact_id, {revealed: bool, day, scene}>
FlashbackQueue: Array<{scene, trigger}>    # 回想の挿入予定
```

- 主人公の知識の**部分集合**。「主人公は知っているがプレイヤーはまだ知らない」= PCKnowledge にあって Disclosure に無い。
- 会話の選択肢の**文言**だけを変える。開示前は「本当のことを言う」の中身が伏せ字（「……あの夜のことを、話す」）。
  **選択肢の可否は主人公の知識で決め、開示状態では制限しない。** プレイヤーが伏せ字のまま「話す」を選ぶと、
  その発言が回想の引き金になる（`say` の直後に `reveal`）。隠している当人は真実を知っているので、
  プレイヤーの無知を選択肢の欠落で表さない、という判断。（要確認: 依頼者の意図と違えば、開示前は truth を出さない設定に切り替え可能。フラグ 1 つ。）

### 2.3 発言記録 `Statements`

```
Statement {
  id:        "s0042"
  day, slot
  to:        "npc:kanae"
  fact:      "night_0731_pc_location"
  kind:      "truth" | "lie" | "silence"
  asserted:  "home"            # 言った値。silence なら null
  is_lie:    true              # asserted != PCKnowledge[fact].value （記録時に確定）
  witnesses: ["npc:father"]    # その場にいた他の NPC（伝播の起点）
  scene:     "d02_shrine_talk"
}
Statements: Array<Statement>   # 追記のみ
```

- 「言ったが嘘」= `is_lie`。嘘かどうかは**主人公の知識との差**で判定する（世界の真実との差ではない）。
  主人公が誤情報を信じて言った場合は嘘ではない（後で矛盾にはなり得る）。
- 「知っているが言っていない」= PCKnowledge にあって、その NPC 宛の Statement が無い。クエリで求め、状態には持たない。
- 同じ NPC に同じ事実を複数回言える。矛盾検出はこの記録を見る（第 4 節）。

### 2.4 NPC ごとの信念 `NPCBelief`

```
NPCBelief[npc_id] {
  facts: Dictionary<fact_id, {
    belief:     "home" | null           # その NPC が今そう思っている値
    confidence: 0.0..1.0                # 確信度
    sources: [                          # どこから得たか（同じ変数に複数）
      {kind: "pc_said", statement: "s0042", day: 2, value: "home"},
      {kind: "observe", day: 1, value: "shrine"},        # 自分で見た（脚本で付与）
      {kind: "heard", from: "npc:father", day: 3, value: "home"}
    ]
    doubt:      0.0..1.0                # 主人公の発言に対する疑い（矛盾で上がる）
  }>
  suspicion: 0..100                     # 主人公全体への疑念（事実横断の合計値）
  trust:     0..100                     # 主人公への信頼（黙る・正直が上げる）
  pending:   Array<{due_day, reaction, payload}>   # 数日後に発火する反応
  memory_of_pc: Array<statement_id>     # 主人公から直接聞いた発言（伝聞は sources 側）
}
```

- 「相手に疑われている」= その事実の `doubt` が閾値超え、または `suspicion` が段階閾値超え。
  事実ごとの疑い（doubt）と人物への疑念（suspicion）を分けるのは、「あの件は怪しいが、こいつは信じている」を表せるようにするため。
- `belief` は sources から**規則で導出**する（最新の観察 > 信頼する相手の伝聞 > 主人公の発言、など）。
  規則は 1 か所（`derive_belief()`）に置き、デバッグ画面で「なぜそう信じているか」を sources ごとに表示できるようにする。

## 3. 会話の選択肢が参照・更新する状態

選択肢は脚本データ（JSON）で、条件と効果を宣言的に持つ。

```
{
  "id": "d02_kanae_q_where",
  "npc": "npc:kanae",
  "fact": "night_0731_pc_location",
  "prompt": "あの夜、どこにいたの？",
  "options": [
    {"kind": "truth",   "label": "神社にいた、と話す", "requires": {"pc_knows": "night_0731_pc_location"}},
    {"kind": "lie",     "label": "家にいた、と言う",   "asserted": "home"},
    {"kind": "lie",     "label": "美咲と一緒だった、と言う", "asserted": "with_misaki",
                        "requires": {"not_said_before": ["npc:kanae", "night_0731_pc_location", "home"]}},
    {"kind": "silence", "label": "答えない"}
  ]
}
```

| 参照する状態 | 用途 |
| --- | --- |
| PCKnowledge | truth の可否と、truth が指す値 |
| Disclosure | truth の**文言**（伏せ字かどうか） |
| Statements | 「前に別のことを言った」選択肢の出し分け、同じ嘘を繰り返す選択肢 |
| NPCBelief | NPC の反応台詞の分岐（既に疑っている・別ルートで知っている） |

| 書き換える状態 | 内容 |
| --- | --- |
| Statements | `say` を追記 |
| NPCBelief[to] | sources に `pc_said` を追加、`memory_of_pc` に追加。矛盾チェック（第 4 節）→ doubt / suspicion / pending |
| NPCBelief[witness] | 同席者にも `pc_said`（信頼度低め）として入る |
| Disclosure | truth を選んで未開示なら `reveal` を追記（回想へ） |

選択肢自体は状態を直接触らず、Event を発行するだけ。効果はすべて Event の適用規則側にある。

## 4. 矛盾の検出と扱い

### 4.1 検出（決定的・その場で実行）

新しい `say`（to = N, fact = F, asserted = V）を適用するとき、NPC N について次を調べる。

1. **自己矛盾**: N の `memory_of_pc` にある同じ F の発言で、asserted が V と異なるものがある。
2. **伝聞との矛盾**: N の sources に `heard`（他の NPC 経由で伝わった主人公の発言）があり、値が V と異なる。
3. **観察との矛盾**: N の sources に `observe`（脚本で N が直接知っている）があり、値が V と異なる。

該当すれば `Contradiction {day, npc, fact, new: statement_id, against: source, severity}` を記録し、
- `doubt[F] += weight × 係数`（自己矛盾 > 観察 > 伝聞 の順に重い）
- `suspicion += weight × 係数`
- `pending` に反応を積む（`due_day = day + 1〜3`、内容は「問い詰める」「第三者に確かめる」「態度が変わる」）

silence は矛盾にならないが、同じ質問に 2 度黙ると doubt が少し上がる（「隠している」のシグナル）。

### 4.2 伝播（`tick` 時に実行）

NPC 間の関係グラフ（誰が誰と話すか、topic ごとの共有しやすさ）を脚本で持ち、日が変わるたびに
`pc_said` を `heard` として隣へ流す（1 日 1 ホップ、確率ではなく規則で決める: 関係 ≥ 閾値なら流す）。
これで「A に言った嘘が 2 日後に B の耳に入り、B との会話で矛盾になる」が作れる。
**乱数は使わない。** 使うなら seed をセーブに入れるが、まずは決定的な規則だけで作る。

### 4.3 プレイヤーへの提示

推奨は **原則として見せない**（NPC の疑念値が上がる・保留中の反応が後日発火する）。
理由: 「隠している緊張」は、ばれているかどうか分からないことから生まれる。矛盾を UI で明示すると管理ゲームになる。
ただし例外を 2 つ用意する。
- 反応が発火した会話では、NPC の台詞で矛盾の中身を突きつける（「この前は家にいたって言ったよね」）。
- デバッグ画面ではすべて表示する（第 6 節）。

**要確認**: 「主人公自身は自分が何を言ったか覚えている」を UI に出すか（手帳のような発言記録の閲覧）。
出すなら Statements の閲覧 UI をプレイヤー向けに用意する。プロトタイプではデバッグ画面で代用。

## 5. 31 日 × 複数 NPC への耐性

### 5.1 データ量

| 項目 | 本編の見積もり | 容量 |
| --- | --- | --- |
| Fact | 60 | 静的、脚本 |
| Event | 1 日 20〜40 × 31 日 ≒ 1,000 | 1 件 200 バイトで 200 KB |
| Statements | Event の一部、300 前後 | 上に含む |
| NPCBelief | NPC 8 × Fact 60 = 480 エントリ、sources は 1 エントリ数個 | 100 KB 以下 |
| セーブ | Event 列 + 派生状態のスナップショット | 500 KB 以下、JSON |

Godot の JSON 読み書きで問題ない規模。1 日 40 Event でも 31 日で 1,240 件。

### 5.2 デバッグ可能性

- **Event が単一の真実**。派生状態（NPCBelief 等）は Event の畳み込みで再計算できるので、
  「この状態はどうしてこうなった」を必ず Event 列に遡れる。
- 状態を直接書く経路を作らない（脚本の効果も Event を発行するだけ）。これを守れば、31 日後の不整合の原因は
  規則（`apply()` / `derive_belief()` / `propagate()`）の 3 関数か脚本データのどちらかに限定される。
- デバッグ画面（第 6 節）で NPC ごとの信念表・sources・矛盾・保留中の反応を一覧できる。
- 脚本データの静的検査（起動時）: 未定義の fact / npc 参照、domain 外の asserted、到達不能な選択肢。

### 5.3 セーブとロード

```
Save {
  version: 1,
  day, slot, scene, position,
  events: [...],                 # 通し番号付き。これが本体
  snapshot: { pc_knowledge, disclosure, statements, npc_belief }   # 高速ロード用の派生状態
}
```

- ロードは snapshot を読み、**検証モードでは events を再生して snapshot と一致するか照合**する。
  規則を変えた後の古いセーブは、一致しなければ再生結果を採用して上書き（バランス変更に追従できる）。
- `version` を持ち、Fact の追加は後方互換（未知の fact は未知のまま）、Fact の削除・改名は移行表で対応。
- 31 日を通すために、1 日ごとの自動セーブ（`tick` の直後）と手動セーブ 3 枠。

## 6. デバッグ画面（F-3 の要件）

1 画面に次を出す（`F1` で切替）。

- 日付・slot・現在シーン
- PCKnowledge と Disclosure の差分（主人公が知っていてプレイヤーが知らないもの）
- Statements の一覧（日、相手、事実、種類、値、嘘か、目撃者）
- NPC ごとの表: fact × {belief, confidence, doubt} と、選択した fact の sources
- suspicion / trust と pending（due_day と内容）
- Contradictions の一覧
- Event の末尾 N 件

## 7. プロトタイプ（F-2）での範囲

- Fact 10 前後（7/31 の夜の所在、美咲と最後に会った場所、誰が誘ったか、神社で何を見たか、など）
- NPC 2 人（例: 幼なじみ・美咲の家族。関係グラフは 1 辺）
- 3 日（8/1〜8/3）: 1 日目に嘘をつき、2 日目に伝播、3 日目に矛盾の反応が来る、が最短で成立する構成
- Disclosure は回想 2 本（初日の導入と、truth を選んだときの引き金）
- 実装順: Fact / Event / apply() → Statements と矛盾検出 → NPCBelief と伝播 → 会話 UI と選択肢 → セーブ → デバッグ画面

## 8. 要確認事項（設計を確定する前に決めたいこと）

1. 開示前の「真実を言う」選択肢を **出す**（伏せ字、選ぶと回想）か **出さない** か。案は「出す」。
2. 矛盾をプレイヤーに **見せない**（疑念値と後日の反応だけ）で良いか。案は「見せない」。
3. 主人公自身の発言記録をプレイヤーに閲覧させるか（手帳 UI）。プロトタイプではデバッグ画面で代用。
4. NPC の疑念を **事実ごと（doubt）と人物全体（suspicion）の 2 層**にする案で良いか。
5. 伝播は乱数なしの規則（関係値の閾値）で良いか。
6. 時間の粒度: 日 + slot（朝 / 昼 / 夕 / 夜）で良いか。プロトタイプは日 + 2 slot を想定。
