class_name StoryState
extends RefCounted
## 『磐戸町奇譚』の状態管理エンジン（docs/DESIGN_STATE.md）。
##
## 4 種の状態（主人公の知識 / プレイヤーへの開示 / 発言記録 / NPC ごとの信念）を
## 1 つのスナップショット辞書 `s` に持ち、変更はすべて `apply(event)` を通す。
## 正はスナップショット。Event 列は監査・デバッグ・検証（replay）用。
## UI に依存しない。ヘッドレスのテストからそのまま使う。

const SEVERITY := {"self": 1.0, "observe": 0.8, "heard": 0.5}
const SILENCE_REPEAT_SUSPICION := 5.0
const INCRIMINATING_SUSPICION_PER_WEIGHT := 5.0

var data: Dictionary          # 脚本（data/story/*.json）
var s: Dictionary             # スナップショット（正）
var events: Array = []        # 監査用 Event 列
var log: Array[String] = []   # 人間向けの短い記録（デバッグ画面用）


# ============================================================================
# 初期化
# ============================================================================
func setup(script_data: Dictionary) -> void:
	data = script_data
	s = {
		"day": 1,
		"seq": 0,
		"pc_knowledge": {},
		"disclosure": {},
		"flags": {},                 # flag 事実（主人公が知っている）: id -> true
		"statements": [],
		"npc": {},
		"contradictions": [],
		"ending": "",
		"talked": {},                # "day:npc" -> 済んだ node id の配列
	}
	for fid in data["pc_knowledge"]:
		s["pc_knowledge"][fid] = {"value": data["pc_knowledge"][fid], "since_day": 0, "source": "initial"}
	for nid in data["npcs"]:
		var n: Dictionary = data["npcs"][nid]
		s["npc"][nid] = {
			"core": {},
			"flags": {},
			"suspicion": 0.0,
			"trust": float(n.get("trust", 50)),
			"stage": 0,
			"stage_seen": 0,           # 会話で挙動を見せた段階（未提示の段階変化を検出する）
			"relation": "normal",
			"pending": [],
			"silences": {},            # fact -> 黙った回数
		}
		for fid in n.get("observe", {}):
			_add_source(nid, fid, {"kind": "observe", "day": 0, "value": n["observe"][fid]})


## 脚本の静的検査。問題があれば文字列で返す（空なら OK）。
static func validate(d: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var facts: Dictionary = d.get("facts", {})
	for fid in d.get("pc_knowledge", {}):
		if not facts.has(fid):
			errs.append("pc_knowledge: 未定義の fact %s" % fid)
		elif not (d["pc_knowledge"][fid] in facts[fid].get("domain", [])):
			errs.append("pc_knowledge: %s の値 %s が domain 外" % [fid, d["pc_knowledge"][fid]])
	for nid in d.get("npcs", {}):
		for fid in d["npcs"][nid].get("observe", {}):
			if not facts.has(fid):
				errs.append("npc %s observe: 未定義の fact %s" % [nid, fid])
			elif not (d["npcs"][nid]["observe"][fid] in facts[fid].get("domain", [])):
				errs.append("npc %s observe: %s の値が domain 外" % [nid, fid])
		for other in d["npcs"][nid].get("relations", {}):
			if not d["npcs"].has(other):
				errs.append("npc %s relations: 未定義の npc %s" % [nid, other])
	for day in d.get("days", {}):
		for nid in d["days"][day]:
			if nid == "intro":
				continue
			if not d["npcs"].has(nid):
				errs.append("day %s: 未定義の npc %s" % [day, nid])
				continue
			for node in d["days"][day][nid]:
				var fid: String = node.get("fact", "")
				if not facts.has(fid):
					errs.append("node %s: 未定義の fact %s" % [node.get("id", "?"), fid])
					continue
				for o in node.get("options", []):
					if o["kind"] == "lie" and not (o.get("asserted") in facts[fid]["domain"]):
						errs.append("node %s: lie の asserted %s が domain 外" % [node.get("id", "?"), o.get("asserted")])
				for k in ["truth", "lie", "silence"]:
					if not node.get("responses", {}).has(k):
						errs.append("node %s: responses.%s が無い" % [node.get("id", "?"), k])
	return errs


# ============================================================================
# Event の適用（状態を変える唯一の入口）
# ============================================================================
func apply(ev: Dictionary) -> Dictionary:
	s["seq"] += 1
	ev["seq"] = s["seq"]
	ev["day"] = s["day"]
	events.append(ev)
	var result := {}
	match ev["kind"]:
		"learn":
			s["pc_knowledge"][ev["fact"]] = {"value": ev["value"], "since_day": s["day"], "source": ev.get("source", "")}
			log.append("D%d 知る %s=%s" % [s["day"], ev["fact"], ev["value"]])
		"reveal":
			s["disclosure"][ev["fact"]] = {"revealed": true, "day": s["day"], "scene": ev.get("scene", "")}
			log.append("D%d 開示 %s" % [s["day"], ev["fact"]])
		"flag":
			if ev.has("npc") and ev["npc"] != null:
				s["npc"][ev["npc"]]["flags"][ev["fact"]] = true
			else:
				s["flags"][ev["fact"]] = true
			log.append("D%d flag %s%s" % [s["day"], ev["fact"], (" (%s)" % ev["npc"]) if ev.get("npc") else ""])
		"say":
			result = _apply_say(ev)
		"npc_learn":
			_add_source(ev["npc"], ev["fact"], {"kind": ev.get("source", "script"), "day": s["day"], "value": ev["value"], "from": ev.get("from", "")})
			result = _check_incriminating(ev["npc"], ev["fact"])
			log.append("D%d %s が知る %s=%s (%s)" % [s["day"], ev["npc"], ev["fact"], ev["value"], ev.get("source", "script")])
		"confront":
			result = _apply_confront(ev)
		"tick":
			result = _apply_tick()
		"mark":
			# 進行の帳簿（済んだ node、調べた対象）。再生で復元できるよう Event にする
			if not s["talked"].has(ev["key"]):
				s["talked"][ev["key"]] = []
			s["talked"][ev["key"]].append(ev["value"])
		"stage_seen":
			s["npc"][ev["npc"]]["stage_seen"] = int(ev["stage"])
		"ending":
			s["ending"] = ev["value"]
			log.append("D%d 結末 %s" % [s["day"], ev["value"]])
		_:
			push_error("未知の Event: %s" % ev["kind"])
	return result


# ---- 発言 ----------------------------------------------------------------------
func say(npc: String, fact: String, kind: String, asserted, scene: String, witnesses: Array = []) -> Dictionary:
	return apply({"kind": "say", "to": npc, "fact": fact, "say_kind": kind, "asserted": asserted, "scene": scene, "witnesses": witnesses})


func _apply_say(ev: Dictionary) -> Dictionary:
	var fact: String = ev["fact"]
	var kind: String = ev["say_kind"]
	var known = s["pc_knowledge"].get(fact, {}).get("value", null)
	var asserted = ev["asserted"]
	if kind == "truth":
		asserted = known
	elif kind == "silence":
		asserted = null
	var st := {
		"id": "s%04d" % s["seq"], "day": s["day"], "to": ev["to"], "fact": fact, "kind": kind,
		"asserted": asserted, "is_lie": (kind == "lie" and asserted != known), "witnesses": ev.get("witnesses", []),
		"scene": ev.get("scene", ""),
	}
	s["statements"].append(st)
	var result := {"statement": st["id"], "contradictions": [], "stage_up": false, "confidant": false}
	var npc: Dictionary = s["npc"][ev["to"]]
	if kind == "silence":
		var count: int = npc["silences"].get(fact, 0) + 1
		npc["silences"][fact] = count
		if count >= 2:
			_add_suspicion(ev["to"], SILENCE_REPEAT_SUSPICION, result)
		npc["trust"] = maxf(npc["trust"] - 2.0, 0.0)
		log.append("D%d %s に黙る %s" % [s["day"], ev["to"], fact])
		return result
	# 矛盾チェック（新しい発言を入れる前に、既存の出所と比べる）
	var weight: float = float(data["facts"][fact].get("weight", 1))
	for src in npc["core"].get(fact, {}).get("sources", []):
		var sev := 0.0
		if src["kind"] == "pc_said" and src["value"] != asserted:
			sev = SEVERITY["self"]
		elif src["kind"] == "observe" and src["value"] != asserted:
			sev = SEVERITY["observe"]
		elif src["kind"] == "heard" and src["value"] != asserted:
			sev = SEVERITY["heard"]
		if sev > 0.0:
			var c := {"day": s["day"], "npc": ev["to"], "fact": fact, "statement": st["id"], "against": src.duplicate(), "severity": sev}
			s["contradictions"].append(c)
			result["contradictions"].append(c)
			var f: Dictionary = npc["core"][fact]
			f["doubt"] = minf(f["doubt"] + 0.25 * sev * weight / 3.0, 1.0)
			_add_suspicion(ev["to"], weight * 10.0 * sev, result)
			npc["pending"].append({"due_day": s["day"], "kind": "confront", "fact": fact, "against": c["against"], "statement": st["id"]})
	# 出所として登録（本人と同席者）
	_add_source(ev["to"], fact, {"kind": "pc_said", "statement": st["id"], "day": s["day"], "value": asserted})
	for w in ev.get("witnesses", []):
		_add_source(w, fact, {"kind": "pc_said", "statement": st["id"], "day": s["day"], "value": asserted, "witness": true})
	if kind == "truth":
		npc["trust"] = minf(npc["trust"] + 3.0, 100.0)
		# 核心を真実で告げた → 告白ルート（DESIGN 5.3）
		if data["facts"][fact].get("core_secret", false) and asserted == data["facts"][fact]["truth"]:
			npc["relation"] = "confidant"
			result["confidant"] = true
			if npc["trust"] >= float(data.get("confidant_trust", 50)):
				npc["suspicion"] = 0.0
				log.append("D%d %s に告白 → 協力者" % [s["day"], ev["to"]])
			else:
				log.append("D%d %s に告白 → 信頼不足、広まる恐れ" % [s["day"], ev["to"]])
			return result
	var inc := _check_incriminating(ev["to"], fact)
	if inc.get("stage_up", false):
		result["stage_up"] = true
	log.append("D%d %s に%s %s=%s" % [s["day"], ev["to"], "嘘" if st["is_lie"] else "本当", fact, str(asserted)])
	return result


## NPC がその事実について「主人公に不利な値」を信じるようになったら疑念が上がる。
func _check_incriminating(nid: String, fact: String) -> Dictionary:
	var result := {"stage_up": false}
	var fd: Dictionary = data["facts"][fact]
	if not fd.has("incriminating"):
		return result
	var f: Dictionary = s["npc"][nid]["core"].get(fact, {})
	if f.is_empty():
		return result
	if f["belief"] == fd["incriminating"] and f["confidence"] >= 0.6 and not f.get("incriminated", false):
		f["incriminated"] = true
		if s["npc"][nid]["relation"] != "confidant":
			_add_suspicion(nid, float(fd.get("weight", 1)) * INCRIMINATING_SUSPICION_PER_WEIGHT, result)
	return result


func _add_suspicion(nid: String, amount: float, result: Dictionary) -> void:
	var npc: Dictionary = s["npc"][nid]
	npc["suspicion"] = clampf(npc["suspicion"] + amount, 0.0, 100.0)
	var new_stage := _stage_of(npc["suspicion"])
	if new_stage > npc["stage"]:
		npc["stage"] = new_stage
		result["stage_up"] = true
		log.append("D%d %s の段階 → %d (%.0f)" % [s["day"], nid, new_stage, npc["suspicion"]])


func _stage_of(v: float) -> int:
	var th: Array = data.get("stage_thresholds", [20, 45, 70])
	var st := 0
	for t in th:
		if v >= float(t):
			st += 1
	return st


# ---- 信念 ------------------------------------------------------------------------
func _add_source(nid: String, fact: String, src: Dictionary) -> void:
	var core: Dictionary = s["npc"][nid]["core"]
	if not core.has(fact):
		core[fact] = {"belief": null, "confidence": 0.0, "sources": [], "doubt": 0.0}
	core[fact]["sources"].append(src)
	_derive_belief(nid, fact)


## 出所から信念を導く。観察 > 信頼する相手の伝聞 > 主人公の発言（嘘が疑われるほど弱い）。
func _derive_belief(nid: String, fact: String) -> void:
	var f: Dictionary = s["npc"][nid]["core"][fact]
	var best_value = null
	var best_score := 0.0
	var scores := {}
	for src in f["sources"]:
		var w := 0.0
		match src["kind"]:
			"observe":
				w = 1.0
			"heard":
				w = 0.6
			"pc_said":
				w = 0.5 * (1.0 - f["doubt"]) * (0.7 if src.get("witness", false) else 1.0)
			_:
				w = 0.8
		if src["value"] == null:
			continue
		scores[src["value"]] = scores.get(src["value"], 0.0) + w
	for v in scores:
		if scores[v] > best_score:
			best_score = scores[v]
			best_value = v
	f["belief"] = best_value
	f["confidence"] = clampf(best_score, 0.0, 1.0)


# ---- 問い詰め ---------------------------------------------------------------------
func confront(npc: String, fact: String, outcome: String) -> Dictionary:
	return apply({"kind": "confront", "npc": npc, "fact": fact, "outcome": outcome})


func _apply_confront(ev: Dictionary) -> Dictionary:
	var npc: Dictionary = s["npc"][ev["npc"]]
	var result := {"relation": npc["relation"]}
	# 保留中の confront を消化
	var rest: Array = []
	for p in npc["pending"]:
		if not (p["kind"] == "confront"):
			rest.append(p)
	npc["pending"] = rest
	match ev["outcome"]:
		"confess":
			npc["relation"] = "confidant"
			for fid in data["facts"]:
				if data["facts"][fid].get("core_secret", false):
					_add_source(ev["npc"], fid, {"kind": "pc_said", "statement": "", "day": s["day"], "value": data["facts"][fid]["truth"]})
			if npc["trust"] >= float(data.get("confidant_trust", 50)):
				npc["suspicion"] = 0.0
			log.append("D%d %s の問い詰めに告白" % [s["day"], ev["npc"]])
		"deny":
			npc["relation"] = "estranged"
			npc["suspicion"] = 100.0
			npc["stage"] = 3
			log.append("D%d %s の問い詰めを否認 → 断絶" % [s["day"], ev["npc"]])
		"silence":
			npc["pending"].append({"due_day": s["day"] + 1, "kind": "estrange", "fact": ev["fact"]})
			npc["suspicion"] = 100.0
			npc["stage"] = 3
			log.append("D%d %s の問い詰めに沈黙 → 翌日に断絶" % [s["day"], ev["npc"]])
	result["relation"] = npc["relation"]
	return result


# ---- 日替わり ---------------------------------------------------------------------
func tick() -> Dictionary:
	return apply({"kind": "tick"})


func _apply_tick() -> Dictionary:
	var result := {"propagated": [], "estranged": [], "ending": ""}
	# 1. 伝播: pc_said を関係のある NPC へ heard として流す（1 日 1 ホップ、乱数なし）
	var new_sources: Array = []
	for a in s["npc"]:
		var na: Dictionary = s["npc"][a]
		var rels: Dictionary = data["npcs"][a].get("relations", {})
		for b in rels:
			var threshold := 0.5
			if na["stage"] >= 2 or na["relation"] == "estranged":
				threshold = 0.0    # 疑っている / 断絶した NPC は誰にでも話す
			if float(rels[b]) < threshold:
				continue
			for fid in na["core"]:
				for src in na["core"][fid]["sources"]:
					if src["kind"] != "pc_said" or src["day"] != s["day"] or src["value"] == null:
						continue
					# 協力者は核心を漏らさない（trust が足りなければ漏らす）
					if na["relation"] == "confidant" and data["facts"][fid].get("core_secret", false) and na["trust"] >= float(data.get("confidant_trust", 50)):
						continue
					new_sources.append([b, fid, {"kind": "heard", "from": a, "day": s["day"] + 1, "value": src["value"], "statement": src.get("statement", "")}])
	for ns in new_sources:
		_add_source(ns[0], ns[1], ns[2])
		result["propagated"].append(ns)
		var inc := _check_incriminating(ns[0], ns[1])
		log.append("D%d 伝播 %s→%s %s=%s" % [s["day"], ns[2]["from"], ns[0], ns[1], ns[2]["value"]])
	# 2. 保留中の反応
	for nid in s["npc"]:
		var npc: Dictionary = s["npc"][nid]
		var rest: Array = []
		for p in npc["pending"]:
			if p["kind"] == "estrange" and p["due_day"] <= s["day"] + 1:
				npc["relation"] = "estranged"
				result["estranged"].append(nid)
				log.append("D%d %s 断絶" % [s["day"] + 1, nid])
			else:
				rest.append(p)
		npc["pending"] = rest
	# 3. 露見の判定（DESIGN 5.2）
	var estranged := 0
	var exposed := false
	for nid in s["npc"]:
		var npc: Dictionary = s["npc"][nid]
		if npc["relation"] == "estranged":
			estranged += 1
		for fid in data["facts"]:
			if not data["facts"][fid].get("core_secret", false):
				continue
			var f: Dictionary = npc["core"].get(fid, {})
			if f.is_empty() or npc["relation"] == "confidant":
				continue
			if f["belief"] == data["facts"][fid]["truth"] and f["confidence"] >= 0.6 and npc["stage"] >= 3:
				exposed = true
	if estranged >= 2 or exposed:
		s["ending"] = "exposed"
		result["ending"] = "exposed"
	s["day"] += 1
	log.append("== %d 日目 ==" % s["day"])
	return result


# ============================================================================
# クエリ
# ============================================================================
func knows(fact: String) -> bool:
	return s["pc_knowledge"].has(fact)


func known_value(fact: String):
	return s["pc_knowledge"].get(fact, {}).get("value", null)


func statements_to(npc: String, fact: String = "") -> Array:
	var out := []
	for st in s["statements"]:
		if st["to"] == npc and (fact == "" or st["fact"] == fact):
			out.append(st)
	return out


func stage(npc: String) -> int:
	return int(s["npc"][npc]["stage"])


func pending_confront(npc: String) -> Dictionary:
	for p in s["npc"][npc]["pending"]:
		if p["kind"] == "confront" and p["due_day"] <= s["day"]:
			return p
	return {}


func has_flag(fact: String) -> bool:
	return s["flags"].has(fact)


# ============================================================================
# スナップショットと再生（DESIGN 6）
# ============================================================================
func snapshot() -> Dictionary:
	return s.duplicate(true)


func load_snapshot(d: Dictionary) -> void:
	s = d.duplicate(true)


## Event 列だけから状態を作り直す（検証モード）。
static func replay(script_data: Dictionary, evs: Array) -> StoryState:
	var st := StoryState.new()
	st.setup(script_data)
	for ev in evs:
		var e: Dictionary = ev.duplicate(true)
		e.erase("seq")
		e.erase("day")
		st.apply(e)
	return st


## スナップショットの整合性検査。問題があれば文字列で返す。
func check_invariants() -> Array[String]:
	var errs: Array[String] = []
	var ids := {}
	for st in s["statements"]:
		ids[st["id"]] = true
		if st["kind"] == "lie" and not (st["asserted"] in data["facts"][st["fact"]]["domain"]):
			errs.append("statement %s: asserted が domain 外" % st["id"])
	for nid in s["npc"]:
		var npc: Dictionary = s["npc"][nid]
		if npc["suspicion"] < 0.0 or npc["suspicion"] > 100.0:
			errs.append("%s suspicion 範囲外 %.1f" % [nid, npc["suspicion"]])
		if npc["stage"] < _stage_of(npc["suspicion"]) and npc["relation"] != "confidant":
			errs.append("%s stage %d < 内部値の段階 %d" % [nid, npc["stage"], _stage_of(npc["suspicion"])])
		for fid in npc["core"]:
			var f: Dictionary = npc["core"][fid]
			if f["belief"] != null and not (f["belief"] in data["facts"][fid]["domain"]):
				errs.append("%s belief %s=%s が domain 外" % [nid, fid, f["belief"]])
			for src in f["sources"]:
				if src["kind"] == "pc_said" and src.get("statement", "") != "" and not ids.has(src["statement"]):
					errs.append("%s source が存在しない statement %s を参照" % [nid, src["statement"]])
	return errs
