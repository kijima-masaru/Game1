class_name StoryRunner
extends RefCounted
## 脚本（days / targets）を StoryState の上で進める。UI を持たない。
## 会話は「step」の列として返す: {"type": "line"|"node"|"confront"|"end", ...}。
## UI もテストも同じ API を使う。

var data: Dictionary
var state: StoryState


static func load_script(path: String = "res://data/story/proto.json") -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("脚本が開けない: %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("脚本の JSON が不正: %s" % path)
		return {}
	return parsed


func setup(script_data: Dictionary) -> void:
	data = script_data
	state = StoryState.new()
	state.setup(data)


func day() -> int:
	return int(state.s["day"])


func day_data() -> Dictionary:
	return data["days"].get(str(day()), {})


func intro_text() -> String:
	return day_data().get("intro", "")


func is_over() -> bool:
	return state.s["ending"] != "" or day() > int(data.get("last_day", 3))


func npc_name(nid: String) -> String:
	return data["npcs"][nid].get("name", nid)


# ---- 会話 ---------------------------------------------------------------------
## その NPC との会話で今出せる step。何も無ければ end。
func next_step(nid: String) -> Dictionary:
	var npc: Dictionary = state.s["npc"][nid]
	if npc["relation"] == "estranged":
		return {"type": "line", "text": data["npcs"][nid].get("estranged_line", "……（話しかけても、返事がない）"), "final": true}
	# 1. 未提示の段階変化 → 挙動の台詞（必ず見せる。DESIGN 2.5）
	if npc["stage"] > npc["stage_seen"]:
		var lines: Dictionary = data["npcs"][nid].get("stage_lines", {})
		var text: String = lines.get(str(npc["stage"]), "")
		state.apply({"kind": "stage_seen", "npc": nid, "stage": npc["stage"]})
		if text != "":
			return {"type": "line", "text": text, "stage": npc["stage"]}
	# 2. 問い詰め（段階 3 で保留中の矛盾がある）
	if npc["stage"] >= 3 and npc["relation"] == "normal":
		var p := state.pending_confront(nid)
		if not p.is_empty():
			return {"type": "confront", "npc": nid, "fact": p["fact"], "against": p["against"],
				"text": _confront_text(nid, p), "options": data.get("confront_options", [])}
	# 3. 今日の未消化 node
	var key := "%d:%s" % [day(), nid]
	var done: Array = state.s["talked"].get(key, [])
	for node in day_data().get(nid, []):
		if node["id"] in done:
			continue
		if not _requires_ok(node.get("requires", {}), nid):
			continue
		return {"type": "node", "npc": nid, "node": node, "options": _options_for(node, nid)}
	return {"type": "end", "text": data["npcs"][nid].get("idle_line", "……")}


func _requires_ok(req: Dictionary, nid: String) -> bool:
	for fid in req.get("flag", []):
		if not state.has_flag(fid):
			return false
	for fid in req.get("not_flag", []):
		if state.has_flag(fid):
			return false
	if req.has("min_stage") and state.stage(nid) < int(req["min_stage"]):
		return false
	if req.has("max_stage") and state.stage(nid) > int(req["max_stage"]):
		return false
	return true


## 選択肢に、主人公の知識・過去の発言に応じた文言を付ける。
func _options_for(node: Dictionary, nid: String) -> Array:
	var out := []
	var fact: String = node["fact"]
	var prev := state.statements_to(nid, fact)
	for i in node["options"].size():
		var o: Dictionary = node["options"][i].duplicate()
		o["index"] = i
		if o["kind"] == "truth" and not state.knows(fact):
			o["label"] = o.get("label_unknown", "知らない、と言う")
		if prev.size() > 0:
			var last: Dictionary = prev[-1]
			var same: bool = (o["kind"] == "truth" and last["kind"] == "truth") or (o["kind"] == "lie" and last["asserted"] == o.get("asserted"))
			o["note"] = "（前と同じ）" if same else ("（前と違う）" if last["kind"] != "silence" else "")
		out.append(o)
	return out


func _confront_text(nid: String, p: Dictionary) -> String:
	var against: Dictionary = p["against"]
	var fact_label: String = data["facts"][p["fact"]].get("label", p["fact"])
	var vlabel := _value_label(p["fact"], against.get("value"))
	var tmpl: String = data["npcs"][nid].get("confront_line", "%s。前に「%s」って言ったよね。")
	return tmpl % [fact_label, vlabel]


func _value_label(fact: String, value) -> String:
	if value == null:
		return "……"
	return data["facts"][fact].get("value_labels", {}).get(str(value), str(value))


## node の選択肢を選ぶ。結果 {response, result, stage_up}
func choose(step: Dictionary, option_index: int) -> Dictionary:
	var node: Dictionary = step["node"]
	var nid: String = step["npc"]
	var o: Dictionary = node["options"][option_index]
	var r := state.say(nid, node["fact"], o["kind"], o.get("asserted"), node["id"], node.get("witnesses", []))
	state.apply({"kind": "mark", "key": "%d:%s" % [day(), nid], "value": node["id"]})
	var resp: String = node["responses"].get(o["kind"], "")
	if o["kind"] == "lie" and node["responses"].has("lie_" + str(o.get("asserted"))):
		resp = node["responses"]["lie_" + str(o.get("asserted"))]
	if r.get("confidant", false):
		resp += "\n" + data["npcs"][nid].get("confidant_line", "……そうか。")
	return {"response": resp, "result": r}


## 問い詰めの選択（confess / deny / silence）
func choose_confront(step: Dictionary, outcome: String) -> Dictionary:
	var r := state.confront(step["npc"], step["fact"], outcome)
	var lines: Dictionary = data["npcs"][step["npc"]].get("confront_outcome", {})
	return {"response": lines.get(outcome, ""), "result": r}


# ---- 調査対象 -------------------------------------------------------------------
func visit(target: String) -> Dictionary:
	var t: Dictionary = data["targets"][target]
	var ev: Dictionary = t.get("day_events", {}).get(str(day()), {})
	if ev.is_empty():
		return {"text": t.get("nothing", "……特に何もない。")}
	var key := "%d:target:%s" % [day(), target]
	if state.s["talked"].has(key):
		return {"text": t.get("nothing", "……もう調べた。")}
	state.apply({"kind": "mark", "key": key, "value": "visited"})
	for fid in ev.get("flags", []):
		state.apply({"kind": "flag", "fact": fid})
	if ev.has("reveal"):
		state.apply({"kind": "reveal", "fact": ev["reveal"], "scene": "%s_d%d" % [target, day()]})
	if ev.has("learn"):
		state.apply({"kind": "learn", "fact": ev["learn"]["fact"], "value": ev["learn"]["value"], "source": target})
	return {"text": ev.get("text", "")}


# ---- 日替わり -------------------------------------------------------------------
func end_day() -> Dictionary:
	var r := state.tick()
	var out := {"tick": r, "ending": "", "text": ""}
	if state.s["ending"] != "":
		out["ending"] = state.s["ending"]
	elif day() > int(data.get("last_day", 3)):
		out["ending"] = _final_ending()
		state.apply({"kind": "ending", "value": out["ending"]})
	if out["ending"] != "":
		out["text"] = data.get("endings", {}).get(out["ending"], out["ending"])
	return out


func _final_ending() -> String:
	for nid in state.s["npc"]:
		if state.s["npc"][nid]["relation"] == "confidant":
			return "confidant"
	return "concealed"


# ---- 手帳・デバッグ用の整形 ------------------------------------------------------------
func notebook_lines() -> Array[String]:
	var out: Array[String] = []
	for st in state.s["statements"]:
		var kind_s: String = {"truth": "本当", "lie": "嘘", "silence": "黙った"}[st["kind"]]
		var v := _value_label(st["fact"], st["asserted"]) if st["kind"] != "silence" else "—"
		out.append("8/%d  %s に  %s → %s  [%s]" % [st["day"], npc_name(st["to"]), data["facts"][st["fact"]].get("label", st["fact"]), v, kind_s])
	if out.is_empty():
		out.append("（まだ何も書いていない）")
	return out


func debug_text() -> String:
	var lines: Array[String] = []
	var s: Dictionary = state.s
	lines.append("DAY %d   seq %d   ending=%s" % [s["day"], s["seq"], s["ending"]])
	lines.append("-- 主人公の知識 / 開示 --")
	for fid in s["pc_knowledge"]:
		var rev := "開示済" if s["disclosure"].has(fid) else ("核心" if data["facts"][fid].get("core_secret", false) else "未開示")
		lines.append("  %s = %s  (%s)" % [fid, s["pc_knowledge"][fid]["value"], rev])
	lines.append("  flags: %s" % ", ".join(s["flags"].keys()))
	lines.append("-- 発言記録 (%d) --" % s["statements"].size())
	for st in s["statements"]:
		lines.append("  %s D%d %s %s %s=%s%s" % [st["id"], st["day"], st["to"], st["kind"], st["fact"], str(st["asserted"]), " LIE" if st["is_lie"] else ""])
	for nid in s["npc"]:
		var n: Dictionary = s["npc"][nid]
		lines.append("-- %s  suspicion %.1f  stage %d (seen %d)  trust %.0f  relation %s  pending %d --" % [nid, n["suspicion"], n["stage"], n["stage_seen"], n["trust"], n["relation"], n["pending"].size()])
		for fid in n["core"]:
			var f: Dictionary = n["core"][fid]
			var srcs := []
			for src in f["sources"]:
				srcs.append("%s:%s%s" % [src["kind"], str(src["value"]), ("@" + str(src.get("from", ""))) if src["kind"] == "heard" else ""])
			lines.append("    %s belief=%s conf=%.2f doubt=%.2f  [%s]" % [fid, str(f["belief"]), f["confidence"], f["doubt"], ", ".join(srcs)])
		for p in n["pending"]:
			lines.append("    pending %s due D%d %s" % [p["kind"], p["due_day"], p.get("fact", "")])
	lines.append("-- 矛盾 (%d) --" % s["contradictions"].size())
	for c in s["contradictions"]:
		lines.append("  D%d %s %s: %s vs %s:%s (sev %.1f)" % [c["day"], c["npc"], c["fact"], c["statement"], c["against"]["kind"], str(c["against"]["value"]), c["severity"]])
	lines.append("-- log (末尾) --")
	for l in state.log.slice(maxi(state.log.size() - 12, 0)):
		lines.append("  " + l)
	return "\n".join(lines)
