extends SceneTree
## 総当たりテスト（G-3）。3 日分の全選択肢の組み合わせを UI なしで再生し、
## クラッシュ・状態の不変条件・到達不能な node / 選択肢・Event 再生の一致を検査する。
##
##   godot --headless --path . --script res://tests/story_exhaustive.gd
##
## 1 日の行動は「神社を調べる / 調べない」× 各 NPC の全 node の全選択肢（問い詰めが出れば 3 択）。
## 31 日規模では全数は無理なので、その時は `--` の後に max_leaves=N を付けてサンプリングに切り替える前提。

var data: Dictionary
var leaves := 0
var steps := 0
var failures: Array[String] = []
var seen_nodes := {}
var seen_options := {}
var seen_endings := {}
var seen_confront := {}
var max_stage_seen := 0
var max_leaves := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("max_leaves="):
			max_leaves = int(a.substr(11))
	data = StoryRunner.load_script()
	var errs := StoryState.validate(data)
	if not errs.is_empty():
		for e in errs:
			printerr("validate: " + e)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var runner := StoryRunner.new()
	runner.setup(data)
	_explore(runner)
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	# 到達性
	var all_nodes := {}
	var all_options := {}
	for day in data["days"]:
		for nid in data["days"][day]:
			if nid == "intro":
				continue
			for node in data["days"][day][nid]:
				all_nodes[node["id"]] = true
				for i in node["options"].size():
					all_options["%s#%d" % [node["id"], i]] = true
	for n in all_nodes:
		if not seen_nodes.has(n):
			failures.append("到達不能な node: %s" % n)
	for o in all_options:
		if not seen_options.has(o):
			failures.append("選ばれなかった選択肢: %s" % o)
	for e in data.get("endings", {}):
		if not seen_endings.has(e):
			failures.append("到達しなかった結末: %s" % e)
	print("story_exhaustive: leaves=%d steps=%d time=%.1fs" % [leaves, steps, dt])
	print("  endings: %s" % JSON.stringify(seen_endings))
	print("  confront outcomes: %s   max stage seen: %d" % [JSON.stringify(seen_confront), max_stage_seen])
	print("  nodes reached: %d/%d   options taken: %d/%d" % [seen_nodes.size(), all_nodes.size(), seen_options.size(), all_options.size()])
	if failures.is_empty():
		print("story_exhaustive: OK")
		quit(0)
	else:
		for f in failures.slice(0, 30):
			printerr("story_exhaustive: FAIL - " + f)
		if failures.size() > 30:
			printerr("... 他 %d 件" % (failures.size() - 30))
		quit(1)


## 深さ優先で全分岐を辿る。分岐点ごとにスナップショットを保存して戻す。
func _explore(r: StoryRunner) -> void:
	if max_leaves > 0 and leaves >= max_leaves:
		return
	if r.is_over():
		_leaf(r)
		return
	# その日の行動列: 神社 → NPC 順（順序は固定。順序の違いは今回の脚本では状態に影響しない）
	var snap := r.state.snapshot()
	var evs := r.state.events.duplicate(true)
	var logn := r.state.log.size()
	for visit_shrine in [false, true]:
		_restore(r, snap, evs, logn)
		if visit_shrine:
			r.visit("shrine")
			steps += 1
		_explore_npcs(r, data["npcs"].keys(), 0)


func _explore_npcs(r: StoryRunner, npcs: Array, idx: int) -> void:
	if max_leaves > 0 and leaves >= max_leaves:
		return
	if idx >= npcs.size():
		# 日を終える
		var snap := r.state.snapshot()
		var evs := r.state.events.duplicate(true)
		var logn := r.state.log.size()
		var out := r.end_day()
		steps += 1
		_check(r)
		if out["ending"] != "":
			seen_endings[out["ending"]] = seen_endings.get(out["ending"], 0) + 1
		_explore(r)
		_restore(r, snap, evs, logn)
		return
	var nid: String = npcs[idx]
	_explore_talk(r, npcs, idx, nid)


func _explore_talk(r: StoryRunner, npcs: Array, idx: int, nid: String) -> void:
	if max_leaves > 0 and leaves >= max_leaves:
		return
	var step := r.next_step(nid)
	steps += 1
	match step["type"]:
		"line":
			if step.get("final", false):
				_explore_npcs(r, npcs, idx + 1)
			else:
				max_stage_seen = maxi(max_stage_seen, int(step.get("stage", 0)))
				_explore_talk(r, npcs, idx, nid)
		"end":
			_explore_npcs(r, npcs, idx + 1)
		"node":
			seen_nodes[step["node"]["id"]] = true
			var snap := r.state.snapshot()
			var evs := r.state.events.duplicate(true)
			var logn := r.state.log.size()
			for i in step["options"].size():
				_restore(r, snap, evs, logn)
				var step2 := r.next_step(nid)   # 復元後に同じ step を取り直す
				if step2["type"] != "node" or step2["node"]["id"] != step["node"]["id"]:
					failures.append("復元後の step が一致しない: %s" % step["node"]["id"])
					continue
				seen_options["%s#%d" % [step["node"]["id"], i]] = true
				r.choose(step2, i)
				steps += 1
				_check(r)
				_explore_talk(r, npcs, idx, nid)
			_restore(r, snap, evs, logn)
		"confront":
			var snap := r.state.snapshot()
			var evs := r.state.events.duplicate(true)
			var logn := r.state.log.size()
			for o in step["options"]:
				_restore(r, snap, evs, logn)
				var step2 := r.next_step(nid)
				if step2["type"] != "confront":
					failures.append("復元後に confront が再現しない: %s" % nid)
					continue
				seen_confront[o["outcome"]] = seen_confront.get(o["outcome"], 0) + 1
				r.choose_confront(step2, o["outcome"])
				steps += 1
				_check(r)
				_explore_talk(r, npcs, idx, nid)
			_restore(r, snap, evs, logn)


func _restore(r: StoryRunner, snap: Dictionary, evs: Array, logn: int) -> void:
	r.state.load_snapshot(snap)
	r.state.events = evs.duplicate(true)
	r.state.log = r.state.log.slice(0, logn)


func _check(r: StoryRunner) -> void:
	for e in r.state.check_invariants():
		failures.append("不変条件: %s" % e)


func _leaf(r: StoryRunner) -> void:
	leaves += 1
	# Event 再生とスナップショットの照合（検証モード。葉の 1/16 だけ実行して時間を抑える）
	if leaves % 16 == 1:
		var rep := StoryState.replay(data, r.state.events)
		var a := JSON.stringify(_strip(rep.s))
		var b := JSON.stringify(_strip(r.state.s))
		if a != b:
			failures.append("再生結果がスナップショットと一致しない (leaf %d)" % leaves)
			if failures.size() < 3:
				printerr("replay: " + a.substr(0, 400))
				printerr("snap  : " + b.substr(0, 400))


func _strip(d: Dictionary) -> Dictionary:
	return d   # 全項目を照合する（stage_seen / talked / ending も Event 化済み）
