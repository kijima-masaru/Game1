class_name FieldData
extends RefCounted
## フィールドデータ（data/fields/<id>.json）の読み込み・検証・通行判定（docs/FIELD_FORMAT.md）。
## 座標はタイル（左上原点、右 +x、下 +y）。ワールドは x → +X、y → +Z。

const TILE := 1.143
const LOT_KINDS := ["shop_shutter", "shop_wood", "dagashi", "house", "temple_hall", "temple_gate", "fence_wall", "fence_block", "bldg_rc"]
const ROAD_KINDS := ["old_street", "sidewalk", "alley", "temple_path", "road"]
const GROUND_TEX := ["lot_ground", "gravel", "asphalt", "stone_path"]
const PASSABLE_LOTS := ["temple_gate"]

var d: Dictionary = {}
var assets: Dictionary = {}
var size := Vector2i(1, 1)
var passable: PackedByteArray = []   # size.x * size.y、1 = 通行可
var errors: Array[String] = []
var warnings: Array[String] = []


static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func load(field_path: String, assets_path: String = "res://data/assets/objects.json") -> bool:
	d = load_json(field_path)
	var a := load_json(assets_path)
	assets = a.get("objects", {})
	if d.is_empty():
		errors.append("フィールド JSON が読めない: %s" % field_path)
		return false
	size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	_validate_static()
	_build_passable({})
	_validate_connectivity()
	return errors.is_empty()


# ---- ワールド座標 ------------------------------------------------------------------
static func tile_to_world(tx: float, ty: float) -> Vector3:
	return Vector3(tx * TILE, 0.0, ty * TILE)


static func tile_center(tx: int, ty: int) -> Vector3:
	return Vector3((tx + 0.5) * TILE, 0.0, (ty + 0.5) * TILE)


static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.z / TILE)))


# ---- 検証 ---------------------------------------------------------------------------
func _validate_static() -> void:
	for r in d.get("roads", []):
		if not (r.get("kind", "") in ROAD_KINDS):
			errors.append("road %s: 未定義の kind %s" % [r.get("id", "?"), r.get("kind", "")])
	for patch in d.get("ground", {}).get("patches", []):
		if not (patch.get("tex", "") in GROUND_TEX):
			errors.append("ground patch %s: 未定義の tex %s" % [patch.get("id", "?"), patch.get("tex", "")])
	if not (d.get("ground", {}).get("default", "lot_ground") in GROUND_TEX):
		errors.append("ground.default が未定義")
	var lots: Array = d.get("lots", [])
	for i in lots.size():
		var l: Dictionary = lots[i]
		if not (l.get("kind", "") in LOT_KINDS):
			errors.append("lot %s: 未定義の kind %s" % [l.get("id", "?"), l.get("kind", "")])
		var r: Array = l.get("rect", [0, 0, 0, 0])
		if r[0] < 0 or r[1] < 0 or r[0] + r[2] > size.x or r[1] + r[3] > size.y:
			errors.append("lot %s: 矩形がフィールド外 %s" % [l.get("id", "?"), str(r)])
		for j in range(i + 1, lots.size()):
			var q: Array = lots[j].get("rect", [0, 0, 0, 0])
			if r[0] < q[0] + q[2] and q[0] < r[0] + r[2] and r[1] < q[1] + q[3] and q[1] < r[1] + r[3]:
				errors.append("lot %s と %s が重なる" % [l.get("id", "?"), lots[j].get("id", "?")])
	for p in d.get("props", []):
		if not assets.has(p.get("asset", "")):
			errors.append("prop %s: 未定義の asset %s" % [p.get("id", "?"), p.get("asset", "")])
	for e in d.get("exits", []):
		var at: Array = e["at"]
		if at[0] < 0 or at[1] < 0 or at[0] >= size.x or at[1] >= size.y:
			errors.append("exit %s: フィールド外" % e.get("dir", "?"))


## 通行判定のビット図。flags は when の評価に使う（立っている lots/props だけ塞ぐ）。
func _build_passable(flags: Dictionary) -> void:
	passable = PackedByteArray()
	passable.resize(size.x * size.y)
	passable.fill(1)
	for l in d.get("lots", []):
		if not when_ok(l.get("when"), flags):
			continue
		if l.get("kind", "") in PASSABLE_LOTS:
			continue
		var r: Array = l["rect"]
		_fill(int(r[0]), int(r[1]), int(r[2]), int(r[3]), 0)
	for p in d.get("props", []):
		if not when_ok(p.get("when"), flags):
			continue
		var a: Dictionary = assets.get(p["asset"], {})
		if not p.get("blocking", a.get("blocking", true)):
			continue
		var fp: Array = a.get("footprint", [1, 1])
		var x0 := int(floor(float(p["at"][0]) - float(fp[0]) * 0.5 + 0.5))
		var y0 := int(floor(float(p["at"][1]) - float(fp[1]) * 0.5 + 0.5))
		_fill(x0, y0, int(fp[0]), int(fp[1]), 0)
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


func _fill(x0: int, y0: int, w: int, h: int, v: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_set_tile(x, y, v)


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
				if reach.has(t + Vector2i(dx, dy)):
					ok = true
		if not ok:
			errors.append("調べ物 %s (%d,%d) の周囲 2 タイルに到達できる通行可タイルが無い" % [p.get("id", "?"), t.x, t.y])


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


## 通行判定を PNG（白 = 可）に描く（デバッグ）。
func passable_image() -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			img.set_pixel(x, y, Color(1, 1, 1, 1) if is_passable(x, y) else Color(0.2, 0.05, 0.05, 1))
	return img
