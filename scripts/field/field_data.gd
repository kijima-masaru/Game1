class_name FieldData
extends RefCounted
## フィールドデータ（形式 2）の読み込み・検証・通行判定（docs/FIELD_FORMAT.md）。
## 唯一の真実は歩行可能マスク（data/fields/<ID>_walkable.png、1 px = 1 タイル）。
## 当たり判定・ミニマップ・建物の配置はすべてここから導く。
## 座標はタイル（左上原点、右 +x、下 +y）。ワールドは x → +X、y → +Z。

const TILE := 1.143
const LOT_KINDS := ["shop_shutter", "shop_wood", "dagashi", "house", "temple_hall", "temple_gate", "fence_wall", "fence_block", "hedge", "bldg_rc"]
const GROUND_TEX := ["lot_ground", "gravel", "asphalt", "stone_path", "old_street", "alley", "sidewalk"]
const PASSABLE_LOTS := ["temple_gate"]
const MIN_STREET_WIDTH := 6

var d: Dictionary = {}
var assets: Dictionary = {}
var size := Vector2i(1, 1)
var classes: PackedByteArray = []    # FieldLayout.CLASS_*
var passable: PackedByteArray = []   # 1 = 通行可（フラグ適用後）
var lots: Array = []                 # FieldLayout が生成した区画
var layout: FieldLayout
var mask_path := ""
var errors: Array[String] = []
var warnings: Array[String] = []


static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func load(field_path: String, assets_path: String = "res://data/assets/objects.json", flags: Dictionary = {}) -> bool:
	d = load_json(field_path)
	var a := load_json(assets_path)
	assets = a.get("objects", {})
	if d.is_empty():
		errors.append("フィールド JSON が読めない: %s" % field_path)
		return false
	if int(d.get("format", 1)) != 2:
		errors.append("format 2 のみ対応（歩行可能マスク方式）")
		return false
	size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	if not _load_mask(field_path):
		return false
	_validate_static()
	relayout(flags)
	_validate_connectivity()
	return errors.is_empty()


## フラグに応じて区画と通行判定を作り直す（when 付きの建物・配置物）
func relayout(flags: Dictionary) -> void:
	layout = FieldLayout.new()
	lots = layout.build(size, classes, d.get("buildings", []), d.get("edge_fill", "fence_block"), float(d.get("field_yaw", 0)), flags, float(d.get("near_band_m", FieldLayout.NEAR_BAND_M)))
	for w in layout.warnings:
		if not warnings.has(w):
			warnings.append(w)
	_build_passable(flags)


# ---- マスク ---------------------------------------------------------------------------------
func _load_mask(field_path: String) -> bool:
	mask_path = d["walkable"] if d.has("walkable") else field_path.get_base_dir() + "/%s_walkable.png" % d["id"]
	var img := Image.load_from_file(ProjectSettings.globalize_path(mask_path))
	if img == null:
		errors.append("歩行可能マスクが読めない: %s" % mask_path)
		return false
	if img.get_width() != size.x or img.get_height() != size.y:
		errors.append("歩行可能マスクの大きさ %dx%d が size %s と違う" % [img.get_width(), img.get_height(), str(size)])
		return false
	classes = PackedByteArray()
	classes.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			classes[y * size.x + x] = class_of(img.get_pixel(x, y))
	return true


## 白 = 歩ける、明るい灰 = 歩ける（裏路地）、暗い灰 = 歩けない空き地（建物なし）、黒 = 歩けない（建物の候補地）
static func class_of(c: Color) -> int:
	var v := c.get_luminance() * c.a
	if v >= 0.85:
		return FieldLayout.CLASS_WALK
	if v >= 0.60:
		return FieldLayout.CLASS_NARROW
	if v >= 0.30:
		return FieldLayout.CLASS_OPEN
	return FieldLayout.CLASS_BLOCKED


func cls(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return FieldLayout.CLASS_OPEN
	return classes[y * size.x + x]


func is_walk_class(x: int, y: int) -> bool:
	var c := cls(x, y)
	return c == FieldLayout.CLASS_WALK or c == FieldLayout.CLASS_NARROW


func is_narrow(x: int, y: int) -> bool:
	if cls(x, y) == FieldLayout.CLASS_NARROW:
		return true
	for a in d.get("areas", []):
		if a.get("kind", "") == "narrow":
			var r: Array = a["rect"]
			if x >= r[0] and y >= r[1] and x < r[0] + r[2] and y < r[1] + r[3]:
				return true
	return false


# ---- ワールド座標 ------------------------------------------------------------------
static func tile_to_world(tx: float, ty: float) -> Vector3:
	return Vector3(tx * TILE, 0.0, ty * TILE)


static func tile_center(tx: int, ty: int) -> Vector3:
	return Vector3((tx + 0.5) * TILE, 0.0, (ty + 0.5) * TILE)


static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.z / TILE)))


# ---- 検証 ---------------------------------------------------------------------------
func _validate_static() -> void:
	var g: Dictionary = d.get("ground", {})
	for key in ["walk", "narrow", "open", "default"]:
		if g.has(key) and not (g[key] in GROUND_TEX):
			errors.append("ground.%s が未定義のテクスチャ %s" % [key, g[key]])
	for patch in g.get("patches", []):
		if not (patch.get("tex", "") in GROUND_TEX):
			errors.append("ground patch %s: 未定義の tex %s" % [patch.get("id", "?"), patch.get("tex", "")])
	for b in d.get("buildings", []):
		if not (b.get("kind", "") in LOT_KINDS):
			errors.append("building %s: 未定義の kind %s" % [b.get("id", "?"), b.get("kind", "")])
	for p in d.get("props", []):
		if not assets.has(p.get("asset", "")):
			errors.append("prop %s: 未定義の asset %s" % [p.get("id", "?"), p.get("asset", "")])
	for e in d.get("exits", []):
		var at: Array = e["at"]
		if not is_walk_class(int(at[0]), int(at[1])):
			errors.append("exit %s (%d,%d) が歩行可能タイルの上に無い" % [e.get("dir", "?"), at[0], at[1]])
		elif is_narrow(int(at[0]), int(at[1])):
			errors.append("exit %s (%d,%d) が裏路地（narrow）の上にある" % [e.get("dir", "?"), at[0], at[1]])
	for p in d.get("points", []):
		var at: Array = p["at"]
		if is_narrow(int(at[0]), int(at[1])):
			errors.append("調べ物 %s (%d,%d) が裏路地（narrow）の上にある" % [p.get("id", "?"), at[0], at[1]])
	# 道幅: 主要な歩行可能タイルは、縦横どちらかの連続長が 6 以上
	var thin := 0
	var first := ""
	for y in size.y:
		for x in size.x:
			if cls(x, y) != FieldLayout.CLASS_WALK or is_narrow(x, y):
				continue
			if maxi(_run_len(x, y, 1, 0), _run_len(x, y, 0, 1)) < MIN_STREET_WIDTH:
				thin += 1
				if first == "":
					first = "(%d,%d)" % [x, y]
	if thin > 0:
		errors.append("道幅 %d タイル未満の主要タイルが %d 個（最初 %s）。裏路地なら灰 (narrow) にする" % [MIN_STREET_WIDTH, thin, first])


func _run_len(x: int, y: int, dx: int, dy: int) -> int:
	var n := 1
	var i := 1
	while is_walk_class(x + dx * i, y + dy * i):
		n += 1
		i += 1
	i = 1
	while is_walk_class(x - dx * i, y - dy * i):
		n += 1
		i += 1
	return n


## 通行判定: マスクの歩行可能タイル − 立っている配置物の足元、+ extra_open / − extra_blocked
func _build_passable(flags: Dictionary) -> void:
	passable = PackedByteArray()
	passable.resize(size.x * size.y)
	for i in size.x * size.y:
		passable[i] = 1 if (classes[i] == FieldLayout.CLASS_WALK or classes[i] == FieldLayout.CLASS_NARROW) else 0
	for p in d.get("props", []):
		if not when_ok(p.get("when"), flags):
			continue
		var a: Dictionary = assets.get(p["asset"], {})
		if not p.get("blocking", a.get("blocking", true)):
			continue
		var fp: Array = a.get("footprint", [1, 1])
		var x0 := int(floor(float(p["at"][0]) - float(fp[0]) * 0.5 + 0.5))
		var y0 := int(floor(float(p["at"][1]) - float(fp[1]) * 0.5 + 0.5))
		for y in range(y0, y0 + int(fp[1])):
			for x in range(x0, x0 + int(fp[0])):
				_set_tile(x, y, 0)
	for t in d.get("collision", {}).get("extra_blocked", []):
		_set_tile(int(t[0]), int(t[1]), 0)
	for t in d.get("collision", {}).get("extra_open", []):
		_set_tile(int(t[0]), int(t[1]), 1)


static func when_ok(when, flags: Dictionary) -> bool:
	if when == null or String(when) == "":
		return true
	var s := String(when)
	if s.begins_with("!"):
		return not flags.get(s.substr(1), false)
	return flags.get(s, false)


func _set_tile(x: int, y: int, v: int) -> void:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return
	passable[y * size.x + x] = v


func is_passable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return false
	return passable[y * size.x + x] == 1


func is_passable_world(p: Vector3) -> bool:
	var t := world_to_tile(p)
	return is_passable(t.x, t.y)


## 出入口と調べ物が最初の出入口から歩いて届くか（塗りつぶし）。調べ物は周囲 2 タイル以内の通行可タイルで代用。
func _validate_connectivity() -> void:
	var exits: Array = d.get("exits", [])
	if exits.is_empty():
		warnings.append("出入口が無い")
		return
	var start := Vector2i(int(exits[0]["at"][0]), int(exits[0]["at"][1]))
	if not is_passable(start.x, start.y):
		errors.append("最初の出入口 %s が通行不可タイルの上" % exits[0].get("dir", "?"))
		return
	var reach := _flood(start)
	for e in exits:
		var t := Vector2i(int(e["at"][0]), int(e["at"][1]))
		if not reach.has(t):
			errors.append("出入口 %s (%d,%d) に到達できない" % [e.get("dir", "?"), t.x, t.y])
	for p in d.get("points", []):
		var t := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var ok := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := t + Vector2i(dx, dy)
				if reach.has(n) and not is_narrow(n.x, n.y):
					ok = true
		if not ok:
			errors.append("調べ物 %s (%d,%d) の周囲 2 タイルに到達できる主要タイルが無い" % [p.get("id", "?"), t.x, t.y])


func _flood(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if seen.has(n) or not is_passable(n.x, n.y):
				continue
			seen[n] = true
			q.append(n)
	return seen


## 4 近傍の幅優先探索で最短経路（タイル列、始点を含まず終点を含む）。届かなければ空。
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		if c == to:
			break
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if prev.has(n) or not is_passable(n.x, n.y):
				continue
			prev[n] = c
			q.append(n)
	var path: Array[Vector2i] = []
	if not prev.has(to):
		return path
	var c := to
	while c != from:
		path.push_front(c)
		c = prev[c]
	return path


func reachable_count() -> int:
	var exits: Array = d.get("exits", [])
	if exits.is_empty():
		return 0
	return _flood(Vector2i(int(exits[0]["at"][0]), int(exits[0]["at"][1]))).size()


func walk_count() -> int:
	var n := 0
	for i in size.x * size.y:
		if classes[i] == FieldLayout.CLASS_WALK or classes[i] == FieldLayout.CLASS_NARROW:
			n += 1
	return n


## 通行判定と区画を PNG に描く（デバッグ）。白 = 通行可、灰 = 裏路地、赤 = 建物、橙 = 近景の帯で平屋にした建物、桃 = 近景の帯
func passable_image() -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var c := Color(0.15, 0.1, 0.1, 1)
			if is_passable(x, y):
				c = Color(0.55, 0.55, 0.55, 1) if is_narrow(x, y) else Color(1, 1, 1, 1)
			elif cls(x, y) == FieldLayout.CLASS_OPEN:
				c = Color(0.3, 0.35, 0.25, 1)
			elif layout != null and layout.near_band[y * size.x + x] == 1:
				c = Color(0.6, 0.2, 0.4, 1)
			img.set_pixel(x, y, c)
	for l in lots:
		var r: Array = l["rect"]
		var col := Color(0.8, 0.2, 0.2, 1) if not (l.get("kind", "") in FieldLayout.FENCE_KINDS) else Color(0.4, 0.3, 0.2, 1)
		if l.get("near_band", false):
			col = Color(0.9, 0.5, 0.2, 1)
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				if x >= 0 and y >= 0 and x < size.x and y < size.y:
					img.set_pixel(x, y, col)
	return img
