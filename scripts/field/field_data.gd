class_name FieldData
extends RefCounted
## フィールドデータ（形式 2）の読み込み・検証・通行判定（docs/FIELD_FORMAT.md）。
## 唯一の真実は歩行可能マスク（data/fields/<ID>_walkable.png、1 px = 1 タイル）。
## 当たり判定・ミニマップ・建物の配置はすべてここから導く。
## 座標はタイル（左上原点、右 +x、下 +y）。ワールドは x → +X、y → +Z。

const TILE := 1.143
const LOT_KINDS := ["shop_shutter", "shop_wood", "dagashi", "house", "temple_hall", "temple_gate", "fence_wall", "fence_block", "hedge", "bldg_rc", "store", "apartment", "civic", "school", "gym", "shelter"]
const BARRIER_KINDS := ["hedge", "fence_block", "fence_wall", "wire_fence", "guardrail", "overpass", "sound_wall", "stone_fence"]
const GROUND_TEX := ["lot_ground", "gravel", "asphalt", "stone_path", "old_street", "alley", "sidewalk", "grass", "water", "tile", "paddy", "stone_step", "dirt", "concrete_slab", "rock", "earth", "moss", "sand"]
# ---- 高さ（フェーズ 14 T-2、docs/FIELD_FORMAT.md 第 8 節）----
const H_UNIT := 0.15                 # 1 階調 = 0.15 m（石段 1 段の蹴上げ）
const CLIMB_MAX := 1                 # 登れる段差の上限（階調）。2 階調（0.30 m）以上は擁壁・崖
const TERRAIN_KINDS := ["slope", "stairs", "bridge", "wall"]
const WALL_TEX := ["retaining_wall", "stone_wall", "rock", "earth", "concrete_slab"]
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
var heights: PackedByteArray = []    # 階調（0..255）。ファイルが無ければ全面 0
var height_path := ""
var has_height := false
var trects: Array = []               # terrain.rects（kind / rect / wall / tex に axis / dir / steps を足したもの）
var tidx: PackedByteArray = []       # タイル → trects の添字 + 1（0 = 無し）
var corners: PackedFloat32Array = [] # タイルの 4 隅の高さ (m)（NW, NE, SE, SW）。坂・階段の補間用
var terrain_wall := "retaining_wall"
var terrain_stats := {}


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
	if not _load_height(field_path):
		return false
	_index_terrain()
	_validate_static()
	_validate_terrain()
	relayout(flags)
	_validate_connectivity(flags)
	return errors.is_empty()


## フラグに応じて区画と通行判定を作り直す（when 付きの建物・配置物）
func relayout(flags: Dictionary) -> void:
	layout = FieldLayout.new()
	lots = layout.build(size, classes, d.get("buildings", []), d.get("edge_fill", "fence_block"), float(d.get("field_yaw", 0)), flags, float(d.get("cam_pitch_deg", FieldLayout.CAM_PITCH_DEG)))
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
	var bad: Array[String] = []
	for y in size.y:
		for x in size.x:
			var c := class_of(img.get_pixel(x, y))
			if c < 0:
				if bad.size() < 10:
					bad.append("(%d,%d)=%s" % [x, y, img.get_pixel(x, y).to_html(true)])
				c = FieldLayout.CLASS_BLOCKED
			classes[y * size.x + x] = c
	if not bad.is_empty():
		errors.append("歩行可能マスクに 255/192/128/0 以外の画素がある（アンチエイリアスや再保存を疑う）: %s%s" % [", ".join(bad), " …" if bad.size() >= 10 else ""])
		return false
	return true


## 厳密な 4 値（N-2a）。R = G = B かつ A = 255 で、255 = 歩ける、192 = 裏路地、128 = 空き地、0 = 建物の候補地。それ以外は −1（読み込み失敗）
static func class_of(c: Color) -> int:
	var r := int(round(c.r * 255.0))
	var g := int(round(c.g * 255.0))
	var b := int(round(c.b * 255.0))
	var a := int(round(c.a * 255.0))
	if r != g or g != b or a != 255:
		return -1
	match r:
		255: return FieldLayout.CLASS_WALK
		192: return FieldLayout.CLASS_NARROW
		128: return FieldLayout.CLASS_OPEN
		0: return FieldLayout.CLASS_BLOCKED
	return -1


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
	for b in d.get("barriers", []):
		if not (b.get("kind", "hedge") in BARRIER_KINDS):
			errors.append("barrier: 未定義の kind %s" % b.get("kind", ""))
		var r: Array = b.get("rect", [0, 0, 0, 0])
		if b.get("kind", "") == "overpass":
			continue   # 歩道橋は歩けるタイルの上をまたぐ
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				if cls(x, y) != FieldLayout.CLASS_OPEN:
					errors.append("barrier %s: (%d,%d) が空き地（128）ではない" % [b.get("kind", "?"), x, y])
	for e in d.get("exits", []):
		var at: Array = e["at"]
		if not is_walk_class(int(at[0]), int(at[1])):
			errors.append("exit %s (%d,%d) が歩行可能タイルの上に無い" % [e.get("dir", "?"), at[0], at[1]])
	# フェーズ 13 R-3: narrow（裏路地・袋小路）にも調べ物・出入口を置ける（隠れはフェードで解く）
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
func _validate_connectivity(flags: Dictionary = {}) -> void:
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
		if not when_ok(e.get("when"), flags) and e != exits[0]:
			continue   # 条件付きの出入口（落石で封鎖など）は、フラグが無ければ到達を求めない
		if not reach.has(t):
			errors.append("出入口 %s (%d,%d) に到達できない" % [e.get("dir", "?"), t.x, t.y])
	for p in d.get("points", []):
		var t := Vector2i(int(p["at"][0]), int(p["at"][1]))
		if not when_ok(p.get("when"), flags):
			continue   # 状況で出現する調べ物・人物は、フラグが無ければ到達を求めない
		var ok := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := t + Vector2i(dx, dy)
				if reach.has(n):
					ok = true
		if not ok:
			errors.append("調べ物 %s (%d,%d) の周囲 2 タイルに到達できる歩行可能タイルが無い" % [p.get("id", "?"), t.x, t.y])
	if has_height:
		var cut := 0
		var first := ""
		for y in size.y:
			for x in size.x:
				if is_passable(x, y) and not reach.has(Vector2i(x, y)):
					cut += 1
					if first == "":
						first = "(%d,%d)" % [x, y]
		terrain_stats["cut_off"] = cut
		if cut > 0:
			warnings.append("段差で分断: 歩けるのに最初の出入口から届かないタイル %d（最初 %s）。坂か階段を明示する" % [cut, first])


func _flood(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if seen.has(n) or not can_step(c, n):
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
			if prev.has(n) or not can_step(c, n):
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
			img.set_pixel(x, y, c)
	for l in lots:
		var r: Array = l["rect"]
		var col := Color(0.8, 0.2, 0.2, 1) if not (l.get("kind", "") in FieldLayout.FENCE_KINDS) else Color(0.4, 0.3, 0.2, 1)
		if l.get("lowered", false):
			col = Color(0.9, 0.55, 0.2, 1)
		if int(l.get("violates", 0)) > 0:
			col = Color(0.95, 0.3, 0.6, 1)
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				if x >= 0 and y >= 0 and x < size.x and y < size.y:
					img.set_pixel(x, y, col)
	return img


# ---- 高さ（フェーズ 14 T-2）--------------------------------------------------------------
## `<ID>_height.png`（任意）。1 px = 1 タイル、厳密なグレー（R = G = B、A 255）、1 階調 = 0.15 m、0 = 基準面。無ければ全面 0
func _load_height(field_path: String) -> bool:
	heights = PackedByteArray()
	heights.resize(size.x * size.y)
	heights.fill(0)
	height_path = d["height"] if d.has("height") else field_path.get_base_dir() + "/%s_height.png" % d["id"]
	var gp := ProjectSettings.globalize_path(height_path)
	if not FileAccess.file_exists(gp):
		has_height = false
		return true
	var img := Image.load_from_file(gp)
	if img == null:
		errors.append("高さ画像が読めない: %s" % height_path)
		return false
	if img.get_width() != size.x or img.get_height() != size.y:
		errors.append("高さ画像の大きさ %dx%d が size %s と違う" % [img.get_width(), img.get_height(), str(size)])
		return false
	var bad: Array[String] = []
	for y in size.y:
		for x in size.x:
			var c := img.get_pixel(x, y)
			var r := int(round(c.r * 255.0))
			var g := int(round(c.g * 255.0))
			var b := int(round(c.b * 255.0))
			var a := int(round(c.a * 255.0))
			if r != g or g != b or a != 255:
				if bad.size() < 10:
					bad.append("(%d,%d)=%s" % [x, y, c.to_html(true)])
			heights[y * size.x + x] = r
	if not bad.is_empty():
		errors.append("高さ画像に灰色（R = G = B、A 255）以外の画素がある: %s%s" % [", ".join(bad), " …" if bad.size() >= 10 else ""])
		return false
	has_height = true
	return true


## 階調（範囲外は縁のタイルに丸める。外周の帯が縁の高さに続く）
func h_units(x: int, y: int) -> int:
	if heights.is_empty():
		return 0
	return heights[clampi(y, 0, size.y - 1) * size.x + clampi(x, 0, size.x - 1)]


func h_m(x: int, y: int) -> float:
	return float(h_units(x, y)) * H_UNIT


func trect(x: int, y: int) -> Dictionary:
	if tidx.is_empty() or x < 0 or y < 0 or x >= size.x or y >= size.y:
		return {}
	var i := tidx[y * size.x + x]
	return trects[i - 1] if i > 0 else {}


func tkind(x: int, y: int) -> String:
	return String(trect(x, y).get("kind", ""))


## 坂・階段（面が連続し、差に関わらず渡れる）
func is_smooth(x: int, y: int) -> bool:
	var k := tkind(x, y)
	return k == "slope" or k == "stairs"


## 隣のタイル b へ渡れるか（8b）: 通行可で、差が CLIMB_MAX 以下、またはどちらかが坂・階段
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not is_passable(b.x, b.y):
		return false
	if not has_height:
		return true
	if absi(h_units(a.x, a.y) - h_units(b.x, b.y)) <= CLIMB_MAX:
		return true
	return is_smooth(a.x, a.y) or is_smooth(b.x, b.y)


## タイルの 4 隅の高さ (m)。[NW, NE, SE, SW]
func tile_corners(x: int, y: int) -> Array:
	var i := (y * size.x + x) * 4
	return [corners[i], corners[i + 1], corners[i + 2], corners[i + 3]]


## ワールド（フィールドのローカル、m）の地面の高さ。坂・階段は 4 隅を双線形補間、それ以外はタイルの高さ
func ground_y(px: float, pz: float) -> float:
	if not has_height:
		return 0.0
	var tx := clampi(int(floor(px / TILE)), 0, size.x - 1)
	var ty := clampi(int(floor(pz / TILE)), 0, size.y - 1)
	if not is_smooth(tx, ty):
		return h_m(tx, ty)
	var fx := clampf(px / TILE - float(tx), 0.0, 1.0)
	var fz := clampf(pz / TILE - float(ty), 0.0, 1.0)
	var i := (ty * size.x + tx) * 4
	var top := lerpf(corners[i], corners[i + 1], fx)
	var bot := lerpf(corners[i + 3], corners[i + 2], fx)
	return lerpf(top, bot, fz)


## terrain.rects を索引にし、坂・階段の軸と向き、4 隅の高さを求める
func _index_terrain() -> void:
	var t: Dictionary = d.get("terrain", {})
	terrain_wall = String(t.get("wall", "retaining_wall"))
	trects = []
	tidx = PackedByteArray()
	tidx.resize(size.x * size.y)
	tidx.fill(0)
	var n := 0
	# 優先順位: 階段 > 坂 > 橋 > 壁（壁の矩形は面のテクスチャだけなので、坂・階段を覆っても奪わない）
	var ordered: Array = []
	for kind in ["stairs", "slope", "bridge", "wall"]:
		for r0 in t.get("rects", []):
			if String((r0 as Dictionary).get("kind", "")) == kind:
				ordered.append(r0)
	for r0 in t.get("rects", []):
		if not (String((r0 as Dictionary).get("kind", "")) in TERRAIN_KINDS):
			ordered.append(r0)
	for r0 in ordered:
		var r: Dictionary = (r0 as Dictionary).duplicate()
		n += 1
		var rc: Array = r.get("rect", [0, 0, 0, 0])
		var sx := 0
		var sy := 0
		var lo := 255
		var hi := 0
		for y in range(int(rc[1]), int(rc[1]) + int(rc[3])):
			for x in range(int(rc[0]), int(rc[0]) + int(rc[2])):
				if x < 0 or y < 0 or x >= size.x or y >= size.y:
					continue
				if tidx[y * size.x + x] == 0:
					tidx[y * size.x + x] = n
				lo = mini(lo, h_units(x, y))
				hi = maxi(hi, h_units(x, y))
				if x + 1 < int(rc[0]) + int(rc[2]):
					sx += h_units(x + 1, y) - h_units(x, y)
				if y + 1 < int(rc[1]) + int(rc[3]):
					sy += h_units(x, y + 1) - h_units(x, y)
		r["axis"] = "x" if absi(sx) >= absi(sy) else "y"
		r["dir"] = 1 if (sx if r["axis"] == "x" else sy) >= 0 else -1
		r["steps"] = hi - lo
		trects.append(r)
	corners = PackedFloat32Array()
	corners.resize(size.x * size.y * 4)
	for y in size.y:
		for x in size.x:
			var i := (y * size.x + x) * 4
			if not is_smooth(x, y):
				var hh := h_m(x, y)
				corners[i] = hh
				corners[i + 1] = hh
				corners[i + 2] = hh
				corners[i + 3] = hh
				continue
			var my := tidx[y * size.x + x]
			var r := trect(x, y)
			if r.get("kind", "") == "stairs":
				# 階段: 縁の高さは進行方向の隣だけで決める（脇のタイルに引きずられない）。幅方向は一定
				var ax: String = r["axis"]
				var e_lo: float
				var e_hi: float
				if ax == "y":
					e_lo = _inline_edge(x, y, x, y - 1, my)
					e_hi = _inline_edge(x, y, x, y + 1, my)
					corners[i] = e_lo
					corners[i + 1] = e_lo
					corners[i + 2] = e_hi
					corners[i + 3] = e_hi
				else:
					e_lo = _inline_edge(x, y, x - 1, y, my)
					e_hi = _inline_edge(x, y, x + 1, y, my)
					corners[i] = e_lo
					corners[i + 3] = e_lo
					corners[i + 1] = e_hi
					corners[i + 2] = e_hi
				continue
			corners[i] = _corner_h(x, y, my)
			corners[i + 1] = _corner_h(x + 1, y, my)
			corners[i + 2] = _corner_h(x + 1, y + 1, my)
			corners[i + 3] = _corner_h(x, y + 1, my)


## 階段のタイル (x, y) と進行方向の隣 (nx, ny) の間の縁の高さ。隣が同じ階段なら中心の平均、外なら隣（平ら）の高さ、場外なら自分の高さ
func _inline_edge(x: int, y: int, nx: int, ny: int, my_idx: int) -> float:
	if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
		return h_m(x, y)
	if tidx[ny * size.x + nx] == my_idx:
		return (h_m(x, y) + h_m(nx, ny)) * 0.5
	if is_smooth(nx, ny):
		return (h_m(x, y) + h_m(nx, ny)) * 0.5
	return h_m(nx, ny)


## 隅 (cx, cy)（タイル (cx, cy) の左上）の高さ。周りの 4 タイルのうち平らなもの（坂・階段でない、または場外）があればその平均、無ければ 4 つの平均
func _corner_h(cx: int, cy: int, _my_idx: int) -> float:
	var out_sum := 0.0
	var out_n := 0
	var all_sum := 0.0
	for t in [Vector2i(cx - 1, cy - 1), Vector2i(cx, cy - 1), Vector2i(cx - 1, cy), Vector2i(cx, cy)]:
		var tx := clampi(t.x, 0, size.x - 1)
		var ty := clampi(t.y, 0, size.y - 1)
		var hh := h_m(tx, ty)
		var outside: bool = (t.x != tx or t.y != ty) or not is_smooth(tx, ty)   # 坂・階段どうしは続き、平らなタイルが縁を決める
		all_sum += hh
		if outside:
			out_sum += hh
			out_n += 1
	return out_sum / float(out_n) if out_n > 0 else all_sum * 0.25


func _validate_terrain() -> void:
	terrain_stats = {"height": has_height, "rects": trects.size(), "stairs": [], "blocked_edges": 0, "steep_tiles": 0}
	var t: Dictionary = d.get("terrain", {})
	if t.has("wall") and not (t["wall"] in WALL_TEX):
		errors.append("terrain.wall が未定義のテクスチャ %s" % t["wall"])
	if not trects.is_empty() and not has_height:
		warnings.append("terrain があるのに高さ画像が無い")
	var k := 0
	for r in trects:
		k += 1
		var rc: Array = r.get("rect", [0, 0, 0, 0])
		var kind := String(r.get("kind", ""))
		if not (kind in TERRAIN_KINDS):
			errors.append("terrain rect %d: 未定義の kind %s" % [k, kind])
		if rc[0] < 0 or rc[1] < 0 or rc[0] + rc[2] > size.x or rc[1] + rc[3] > size.y:
			errors.append("terrain rect %d %s が範囲外" % [k, str(rc)])
		if r.has("wall") and not (r["wall"] in WALL_TEX):
			errors.append("terrain rect %d: 未定義の wall %s" % [k, r["wall"]])
		if r.has("tex") and not (r["tex"] in GROUND_TEX):
			errors.append("terrain rect %d: 未定義の tex %s" % [k, r["tex"]])
		if r.has("deck") and not (r["deck"] in GROUND_TEX):
			errors.append("terrain rect %d: 未定義の deck %s" % [k, r["deck"]])
		if kind == "stairs":
			# 一方向に単調（各列で差の符号が dir と同じ）
			var mono := true
			var ax: String = r["axis"]
			var dr: int = r["dir"]
			for y in range(int(rc[1]), int(rc[1]) + int(rc[3])):
				for x in range(int(rc[0]), int(rc[0]) + int(rc[2])):
					var nx := x + (1 if ax == "x" else 0)
					var ny := y + (1 if ax == "y" else 0)
					if nx < int(rc[0]) + int(rc[2]) and ny < int(rc[1]) + int(rc[3]):
						if (h_units(nx, ny) - h_units(x, y)) * dr < 0:
							mono = false
			if not mono:
				warnings.append("階段 %d %s が一方向に単調でない" % [k, str(rc)])
			var lo_c := 1e9
			var hi_c := -1e9
			for y in range(int(rc[1]), int(rc[1]) + int(rc[3])):
				for x in range(int(rc[0]), int(rc[0]) + int(rc[2])):
					if x < 0 or y < 0 or x >= size.x or y >= size.y:
						continue
					for cv in tile_corners(x, y):
						lo_c = minf(lo_c, float(cv))
						hi_c = maxf(hi_c, float(cv))
			var steps := int(round((hi_c - lo_c) / H_UNIT)) if hi_c >= lo_c else 0
			terrain_stats["stairs"].append({"rect": rc, "steps": steps, "axis": ax, "dir": dr, "rise_m": float(steps) * H_UNIT})
		if kind == "slope":
			for y in range(int(rc[1]), int(rc[1]) + int(rc[3])):
				for x in range(int(rc[0]), int(rc[0]) + int(rc[2])):
					var sx := x + 1 < int(rc[0]) + int(rc[2]) and absi(h_units(x + 1, y) - h_units(x, y)) > 8
					var sy := y + 1 < int(rc[1]) + int(rc[3]) and absi(h_units(x, y + 1) - h_units(x, y)) > 8
					if sx or sy:
						terrain_stats["steep_tiles"] = int(terrain_stats["steep_tiles"]) + 1
	if int(terrain_stats["steep_tiles"]) > 0:
		warnings.append("坂の傾きが 8 階調 / タイル（46°）を超えるタイル %d（助言）" % int(terrain_stats["steep_tiles"]))
	# 登れない段差の縁（両側とも歩けるタイル）
	var n_edges := 0
	for y in size.y:
		for x in size.x:
			if not is_walk_class(x, y):
				continue
			for o in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if is_walk_class(q.x, q.y) and absi(h_units(x, y) - h_units(q.x, q.y)) > CLIMB_MAX and not is_smooth(x, y) and not is_smooth(q.x, q.y):
					n_edges += 1
	terrain_stats["blocked_edges"] = n_edges


## 始点から（段差の規則で）歩いて最も遠いタイル（自動歩行の終点。出入口が 1 つのフィールド用）
func farthest_from(start: Vector2i) -> Vector2i:
	var dist := {start: 0}
	var q: Array[Vector2i] = [start]
	var qi := 0
	var best := start
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		if dist[c] > dist[best]:
			best = c
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if dist.has(n) or not can_step(c, n):
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	return best
