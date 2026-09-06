class_name FieldLayout
extends RefCounted
## 歩行可能領域（マスク）から建物の区画を自動で決める（フェーズ 9 M-2c / N-1 / N-2b）。
##
## 1. 歩行可能タイルに 4 近傍で接する「塞がれた」タイルを外周とし、向き（歩ける側）ごとに直線の列（run）へまとめる
## 2. `near` 付きの建物を最寄りの外周へ、残りは列の順に隙間なく詰める（contiguous）。奥行きは塞がれたタイルの中へ伸ばす
## 3. 遮蔽の式（N-1）: 歩行可能タイルの主人公の頭（1.7 m）からカメラの方へ上がる視線が建物に当たるなら違反。
##    必要距離 = (高さ − 1.7) / tan(俯角)。軒と棟のそれぞれで判定し、違反する建物は階数を落とす。平屋でも違反なら記録して報告
## 4. 建物の付かなかった外周は塀（edge_fill）で埋める（近景を空白にしない）
##
## 出力は lots の配列（rect / kind / front / floors / h_wall / rise / overhang …）。

const CLASS_BLOCKED := 0
const CLASS_WALK := 1
const CLASS_NARROW := 2
const CLASS_OPEN := 3

const CAM_PITCH_DEG := 30.0        # ART_SPEC 第 2 節。lookdev の既定と合わせる
const HEAD_M := 1.7                # 主人公の頭の高さ
const WALL_1F := 2.3               # 平屋の軒高。棟は +0.7 で 3.0 m
const FLOOR_M := 3.0
const RISE_1F := 0.7
const RISE_2F := 1.4               # 2 階建て: 軒 5.3 + 1.4 = 6.7 m
const OVERHANG_M := 0.5
const DIRS := {"E": Vector2i(1, 0), "W": Vector2i(-1, 0), "S": Vector2i(0, 1), "N": Vector2i(0, -1)}
const FENCE_KINDS := ["fence_block", "fence_wall", "hedge"]
const PASSABLE_KINDS := ["temple_gate"]

var size := Vector2i(1, 1)
var classes: PackedByteArray
var occupied: PackedByteArray
var runs: Array = []              # {dir: String, cells: Array[Vector2i]}
var lots: Array = []
var warnings: Array[String] = []
var violations: Array = []        # {lot: id, tile: Vector2i, part: "eave"|"ridge", dist_m, need_m}
var toward_cam := Vector2(0, 1)   # フィールドのローカル座標でカメラの方へ向く単位ベクトル（タイル）
var pitch_deg := CAM_PITCH_DEG
var _edge_fill_spec = "fence_block"


func _cls(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return CLASS_OPEN            # 場外は「空き地」扱い（建物を置かない）
	return classes[y * size.x + x]


func _walk(x: int, y: int) -> bool:
	var c := _cls(x, y)
	return c == CLASS_WALK or c == CLASS_NARROW


func _free(x: int, y: int) -> bool:
	return _cls(x, y) == CLASS_BLOCKED and occupied[y * size.x + x] == 0


func build(sz: Vector2i, cls: PackedByteArray, buildings: Array, edge_fill, field_yaw_deg: float, flags: Dictionary, pitch: float = CAM_PITCH_DEG) -> Array:
	size = sz
	classes = cls
	pitch_deg = pitch
	occupied = PackedByteArray()
	occupied.resize(size.x * size.y)
	occupied.fill(0)
	lots = []
	warnings = []
	violations = []
	_edge_fill_spec = edge_fill
	toward_cam = Vector2(-sin(deg_to_rad(field_yaw_deg)), cos(deg_to_rad(field_yaw_deg)))
	_trace_runs()
	var pool: Array = []
	for b in buildings:
		if not FieldData.when_ok(b.get("when"), flags):
			continue
		if b.has("at"):
			_place_fixed(b)
		elif b.has("near"):
			_place_near(b)
		else:
			pool.append(b)
	_fill_runs(pool)
	_fill_fences(edge_fill)
	_unify_contiguous()
	return lots


## 必要距離（m） = (高さ − 頭) / tan(俯角)
func need_m(height_m: float) -> float:
	return maxf(height_m - HEAD_M, 0.0) / tan(deg_to_rad(pitch_deg))


# ---- 外周の列 --------------------------------------------------------------------------
func _trace_runs() -> void:
	runs = []
	for dname in ["E", "W", "S", "N"]:
		var d: Vector2i = DIRS[dname]
		var along_y := d.x != 0
		var outer := size.x if along_y else size.y
		var inner := size.y if along_y else size.x
		for o in outer:
			var cur: Array[Vector2i] = []
			for i in inner:
				var c := Vector2i(o, i) if along_y else Vector2i(i, o)
				# 歩けるタイルか空き地（open）に接する塞がれたタイルが外周。空き地にも建物や塀を向ける
				var nx := c.x + d.x
				var ny := c.y + d.y
				var inside := nx >= 0 and ny >= 0 and nx < size.x and ny < size.y   # 場外へ向く正面は作らない
				var nb := _cls(nx, ny)
				var is_b := inside and _cls(c.x, c.y) == CLASS_BLOCKED and (nb == CLASS_WALK or nb == CLASS_NARROW or nb == CLASS_OPEN)
				if is_b:
					cur.append(c)
				elif not cur.is_empty():
					runs.append({"dir": dname, "cells": cur})
					cur = []
			if not cur.is_empty():
				runs.append({"dir": dname, "cells": cur})


func _segment_free(run: Dictionary, start: int, w: int) -> bool:
	var cells: Array[Vector2i] = run["cells"]
	if start < 0 or start + w > cells.size():
		return false
	for i in range(start, start + w):
		if not _free(cells[i].x, cells[i].y):
			return false
	return true


## 正面の列（cells[start..start+w)）から奥へ depth まで伸ばした矩形。伸ばせるだけ伸ばす（最低 1）
func _lot_rect(run: Dictionary, start: int, w: int, depth: int) -> Array:
	var cells: Array[Vector2i] = run["cells"]
	var d: Vector2i = DIRS[run["dir"]]
	var back := -d
	var got := 1
	while got < depth:
		var ok := true
		for i in range(start, start + w):
			var c: Vector2i = cells[i] + back * got
			if not _free(c.x, c.y):
				ok = false
				break
		if not ok:
			break
		got += 1
	var a: Vector2i = cells[start]
	var b: Vector2i = cells[start + w - 1]
	var x0 := mini(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var x1 := maxi(a.x, b.x)
	var y1 := maxi(a.y, b.y)
	if back.x < 0:
		x0 -= got - 1
	elif back.x > 0:
		x1 += got - 1
	if back.y < 0:
		y0 -= got - 1
	elif back.y > 0:
		y1 += got - 1
	return [x0, y0, x1 - x0 + 1, y1 - y0 + 1]


func _occupy(rect: Array) -> void:
	for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
		for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
			if x >= 0 and y >= 0 and x < size.x and y < size.y:
				occupied[y * size.x + x] = 1


# ---- 遮蔽の式（N-1） ------------------------------------------------------------------------
## 区画 rect（タイル）を持つ建物（軒 h_wall、棟 h_ridge、棟は正面と平行な中心線）が、どの歩行可能タイルの主人公を隠すか。
## 視線: タイル中心の頭（1.7 m）からカメラの方へ、水平 1 m につき tan(俯角) 上がる。
func occluded_tiles(rect: Array, front: String, h_wall: float, h_ridge: float, overhang_m: float) -> Array:
	var out: Array = []
	var T := FieldData.TILE
	var need_wall := need_m(h_wall)
	var need_ridge := need_m(h_ridge)
	if need_wall <= 0.0 and need_ridge <= 0.0:
		return out
	var reach := int(ceil(maxf(need_wall, need_ridge) / T)) + 2
	var ridge_along_y := front in ["E", "W"]   # 正面が東西 → 棟は南北（y 方向）に走る
	var ridge_c := float(rect[0]) + float(rect[2]) * 0.5 if ridge_along_y else float(rect[1]) + float(rect[3]) * 0.5
	for ty in range(int(rect[1]) - reach, int(rect[1]) + int(rect[3]) + reach + 1):
		for tx in range(int(rect[0]) - reach, int(rect[0]) + int(rect[2]) + reach + 1):
			if _cls(tx, ty) != CLASS_WALK:
				continue   # 裏路地（narrow）は隠れてよい（ホラー演出）。空き地は立てない
			var c := Vector2(tx + 0.5, ty + 0.5)
			# 軒の判定は壁の矩形まで（式のとおり「建物までの距離」）。張り出しは薄い板なので式では扱わず、実行時の面判定に任せる
			var t_in := _ray_rect_entry(c, toward_cam, float(rect[0]), float(rect[1]), float(rect[0]) + float(rect[2]), float(rect[1]) + float(rect[3]))
			if t_in <= 1e-6:
				continue
			var part := ""
			var dist := t_in * T
			var need := need_wall
			if dist < need_wall:
				part = "eave"
			elif need_ridge > need_wall:
				var t_r := -1.0
				if ridge_along_y:
					if absf(toward_cam.x) > 1e-6:
						t_r = (ridge_c - c.x) / toward_cam.x
						var yy := c.y + toward_cam.y * t_r
						if yy < float(rect[1]) or yy > float(rect[1]) + float(rect[3]):
							t_r = -1.0
				else:
					if absf(toward_cam.y) > 1e-6:
						t_r = (ridge_c - c.y) / toward_cam.y
						var xx := c.x + toward_cam.x * t_r
						if xx < float(rect[0]) or xx > float(rect[0]) + float(rect[2]):
							t_r = -1.0
				if t_r > 0.0 and t_r * T < need_ridge:
					part = "ridge"
					dist = t_r * T
					need = need_ridge
			if part != "":
				out.append({"tile": Vector2i(tx, ty), "part": part, "dist_m": dist, "need_m": need})
	return out


static func _ray_rect_entry(o: Vector2, d: Vector2, x0: float, y0: float, x1: float, y1: float) -> float:
	var tmin := 0.0
	var tmax := 1e9
	for axis in 2:
		var oo := o.x if axis == 0 else o.y
		var dd := d.x if axis == 0 else d.y
		var lo := x0 if axis == 0 else y0
		var hi := x1 if axis == 0 else y1
		if absf(dd) < 1e-9:
			if oo < lo or oo > hi:
				return -1.0
			continue
		var t1 := (lo - oo) / dd
		var t2 := (hi - oo) / dd
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < tmin:
		return -1.0
	return tmin


## 高さ（軒・棟）を決める。データの階数から始め、式に違反するなら 1 階ずつ落とす。平屋でも違反なら記録。
func _fit_height(l: Dictionary) -> void:
	var kind: String = l.get("kind", "")
	var flat: bool = l.get("roof", "gable") == "flat"
	var overhang := OVERHANG_M
	if kind == "temple_hall":
		overhang = 1.4
	var floors := int(l.get("floors", 1))
	var fixed_h := l.has("height_m")
	if kind in PASSABLE_KINDS:
		# 通り抜ける構造物（山門）は主人公が下をくぐるので式の対象外
		l["h_wall"] = float(l.get("height_m", 3.6))
		l["rise"] = 1.0
		l["overhang"] = 0.5
		return
	while true:
		var h_wall: float
		var rise: float
		if fixed_h:
			h_wall = float(l["height_m"])
			rise = 2.4 if kind == "temple_hall" else (0.0 if flat else RISE_2F)
		else:
			h_wall = WALL_1F + FLOOR_M * (floors - 1)
			rise = 0.0 if flat else (RISE_1F if floors == 1 else RISE_2F)
		var bad := occluded_tiles(l["rect"], l["front"], h_wall, h_wall + rise, overhang)
		if bad.is_empty() or floors <= 1 or fixed_h:
			l["h_wall"] = h_wall
			l["rise"] = rise
			l["overhang"] = overhang
			l["floors"] = floors
			for v in bad:
				violations.append({"lot": l["id"], "tile": v["tile"], "part": v["part"], "dist_m": v["dist_m"], "need_m": v["need_m"]})
			if not bad.is_empty():
				l["violates"] = bad.size()
			return
		floors -= 1
		l["lowered"] = true
		if not l.has("lowered_by"):
			l["lowered_by"] = "%s が (%d,%d) を隠す（%.1f m、必要 %.1f m）" % [bad[0]["part"], bad[0]["tile"].x, bad[0]["tile"].y, bad[0]["dist_m"], bad[0]["need_m"]]


func _emit(b: Dictionary, rect: Array, front: String, idx: int) -> void:
	var l := b.duplicate()
	l.erase("near")
	l.erase("at")
	l.erase("width")
	l.erase("depth")
	l["rect"] = rect
	l["front"] = front
	if not l.has("id"):
		l["id"] = "b%02d" % idx
	if not (l.get("kind", "") in FENCE_KINDS):
		_fit_height(l)
	_occupy(rect)
	lots.append(l)


func _place_fixed(b: Dictionary) -> void:
	var w := int(b.get("width", 3))
	var dpt := int(b.get("depth", 1))
	var at: Array = b["at"]
	var rect := [int(at[0]) - w / 2, int(at[1]), w, dpt]
	_emit(b, rect, b.get("front", "S"), lots.size())


func _place_near(b: Dictionary) -> void:
	var near: Array = b["near"]
	var target := Vector2i(int(near[0]), int(near[1]))
	var w := int(b.get("width", 3))
	var best_run: Dictionary = {}
	var best_i := -1
	var best_d := 1 << 30
	for run in runs:
		var cells: Array[Vector2i] = run["cells"]
		for i in cells.size():
			if not _free(cells[i].x, cells[i].y):
				continue
			var dd := maxi(absi(cells[i].x - target.x), absi(cells[i].y - target.y))
			if dd < best_d:
				best_d = dd
				best_run = run
				best_i = i
	if best_i < 0:
		warnings.append("建物 %s: near %s の近くに空いた外周が無い" % [b.get("id", "?"), str(near)])
		return
	var start := best_i - w / 2
	var found := -1
	for k in range(0, w):
		for s in [start + k, start - k]:
			if _segment_free(best_run, s, w) and s <= best_i and best_i < s + w:
				found = s
				break
		if found >= 0:
			break
	if found < 0:
		var ww := w
		while ww > 1 and found < 0:
			ww -= 1
			for s in range(best_i - ww + 1, best_i + 1):
				if _segment_free(best_run, s, ww):
					found = s
					w = ww
					break
		if found < 0:
			warnings.append("建物 %s: near %s の外周に間口 %d が入らない" % [b.get("id", "?"), str(near), w])
			return
		warnings.append("建物 %s: 間口を %d に縮めた" % [b.get("id", "?"), w])
	var rect := _lot_rect(best_run, found, w, int(b.get("depth", 3)))
	_emit(b, rect, best_run["dir"], lots.size())


func _reserved(c: Vector2i) -> bool:
	if not (_edge_fill_spec is Array):
		return false
	for e in _edge_fill_spec:
		if not e.get("reserve", false):
			continue
		var r: Array = e.get("rect", [0, 0, 0, 0])
		if c.x >= r[0] and c.y >= r[1] and c.x < r[0] + r[2] and c.y < r[1] + r[3]:
			return true
	return false


## 順番待ちの建物を列の順に隙間なく詰める。`gap` を持つ建物はその前に空き（路地・駐車場）を残す
func _fill_runs(pool: Array) -> void:
	if pool.is_empty():
		return
	var pi := 0
	for run in runs:
		var cells: Array[Vector2i] = run["cells"]
		var i := 0
		while i < cells.size() and pi < pool.size():
			if not _free(cells[i].x, cells[i].y) or _reserved(cells[i]):
				i += 1
				continue
			var free_len := 0
			while i + free_len < cells.size() and _free(cells[i + free_len].x, cells[i + free_len].y) and not _reserved(cells[i + free_len]):
				free_len += 1
			var b: Dictionary = pool[pi]
			var gap := int(b.get("gap", 0))
			var w := int(b.get("width", 3))
			if gap + w > free_len:
				var alt := -1
				for j in range(pi + 1, pool.size()):
					if int(pool[j].get("gap", 0)) + int(pool[j].get("width", 3)) <= free_len:
						alt = j
						break
				if alt < 0:
					i += free_len
					continue
				b = pool[alt]
				pool.remove_at(alt)
				pool.insert(pi, b)
				gap = int(b.get("gap", 0))
				w = int(b.get("width", 3))
			i += gap
			var rect := _lot_rect(run, i, w, int(b.get("depth", 3)))
			var got: int = rect[2] if run["dir"] in ["E", "W"] else rect[3]
			if got < 2:
				i += 1   # 奥行きが 1 タイルしか取れない（場外や別の道が裏にある）。塀に任せる
				continue
			_emit(b, rect, run["dir"], lots.size())
			pi += 1
			i += w
	for j in range(pi, pool.size()):
		warnings.append("建物 %s（間口 %d）を置く外周が残っていない" % [pool[j].get("id", "?"), int(pool[j].get("width", 3))])


func _edge_kind(edge_fill, c: Vector2i) -> String:
	if edge_fill is String:
		return edge_fill
	if edge_fill is Array:
		for e in edge_fill:
			var r: Array = e.get("rect", [0, 0, 0, 0])
			if c.x >= r[0] and c.y >= r[1] and c.x < r[0] + r[2] and c.y < r[1] + r[3]:
				return e.get("kind", "fence_block")
	return "fence_block"


func _fill_fences(edge_fill) -> void:
	var n := 0
	for run in runs:
		var cells: Array[Vector2i] = run["cells"]
		var i := 0
		while i < cells.size():
			if not _free(cells[i].x, cells[i].y):
				i += 1
				continue
			var kind := _edge_kind(edge_fill, cells[i])
			if kind == "none":
				i += 1
				continue
			var j := i
			while j < cells.size() and _free(cells[j].x, cells[j].y) and _edge_kind(edge_fill, cells[j]) == kind:
				j += 1
			var rect := _lot_rect(run, i, j - i, 1)
			_emit({"kind": kind, "id": "fence%02d" % n}, rect, run["dir"], lots.size())
			n += 1
			i = j


## N-2b 連続性: 同じ正面線上で壁を接して並ぶ建物（contiguous、既定 true）に row を付け、同じ階数なら軒高をそろえる。
## 建物生成器は contiguous の建物で妻側の軒を出さず、隣と一続きの屋根にする。
func _unify_contiguous() -> void:
	var seen := {}
	var row_n := 0
	for a in lots:
		if seen.has(a["id"]) or (a.get("kind", "") in FENCE_KINDS) or not a.get("contiguous", true):
			continue
		var g: Array = [a]
		seen[a["id"]] = true
		var changed := true
		while changed:
			changed = false
			for b in lots:
				if seen.has(b["id"]) or (b.get("kind", "") in FENCE_KINDS) or not b.get("contiguous", true) or b["front"] != a["front"]:
					continue
				for m in g:
					if _adjacent_same_front(m, b):
						g.append(b)
						seen[b["id"]] = true
						changed = true
						break
		if g.size() < 2:
			continue
		for m in g:
			m["row"] = row_n
			m["contiguous"] = true
			# 隣の同じ階数の建物と軒高を合わせる（height_m 指定は除く）
			for o in g:
				if o != m and not o.has("height_m") and not m.has("height_m") and int(o.get("floors", 1)) == int(m.get("floors", 1)):
					m["h_wall"] = float(g[0]["h_wall"]) if int(g[0].get("floors", 1)) == int(m.get("floors", 1)) else m["h_wall"]
		row_n += 1


func _adjacent_same_front(a: Dictionary, b: Dictionary) -> bool:
	var ra: Array = a["rect"]
	var rb: Array = b["rect"]
	if a["front"] in ["E", "W"]:
		var fa: int = ra[0] + ra[2] if a["front"] == "E" else ra[0]
		var fb: int = rb[0] + rb[2] if b["front"] == "E" else rb[0]
		return fa == fb and (ra[1] + ra[3] == rb[1] or rb[1] + rb[3] == ra[1])
	var fa2: int = ra[1] + ra[3] if a["front"] == "S" else ra[1]
	var fb2: int = rb[1] + rb[3] if b["front"] == "S" else rb[1]
	return fa2 == fb2 and (ra[0] + ra[2] == rb[0] or rb[0] + rb[2] == ra[0])


## 隣（同じ列で接する建物）が contiguous か: 妻側の軒を出すかどうかの判定に使う
func has_neighbor(l: Dictionary, side: int) -> bool:
	# side: 正面に向かって -1 = 列の始点側、+1 = 終点側（E/W 正面なら y、N/S 正面なら x）
	var r: Array = l["rect"]
	for o in lots:
		if o == l or (o.get("kind", "") in FENCE_KINDS) or o.get("front") != l["front"]:
			continue
		if not _adjacent_same_front(l, o):
			continue
		var ro: Array = o["rect"]
		if l["front"] in ["E", "W"]:
			if (side < 0 and ro[1] + ro[3] == r[1]) or (side > 0 and r[1] + r[3] == ro[1]):
				return true
		else:
			if (side < 0 and ro[0] + ro[2] == r[0]) or (side > 0 and r[0] + r[2] == ro[0]):
				return true
	return false


## 違反の図。白 = 歩ける、灰 = 裏路地、赤 = 建物、橙 = 式で階数を落とした建物、桃 = 平屋でも隠す建物、黄 = 隠される歩行可能タイル
func occlusion_image() -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var c := Color(0.12, 0.1, 0.1, 1)
			match _cls(x, y):
				CLASS_WALK: c = Color(1, 1, 1, 1)
				CLASS_NARROW: c = Color(0.55, 0.55, 0.55, 1)
				CLASS_OPEN: c = Color(0.3, 0.35, 0.25, 1)
			img.set_pixel(x, y, c)
	for l in lots:
		var r: Array = l["rect"]
		var col := Color(0.8, 0.2, 0.2, 1)
		if l.get("kind", "") in FENCE_KINDS:
			col = Color(0.4, 0.3, 0.2, 1)
		elif int(l.get("violates", 0)) > 0:
			col = Color(0.95, 0.3, 0.6, 1)
		elif l.get("lowered", false):
			col = Color(0.9, 0.55, 0.2, 1)
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				if x >= 0 and y >= 0 and x < size.x and y < size.y:
					img.set_pixel(x, y, col)
	for v in violations:
		var t: Vector2i = v["tile"]
		img.set_pixel(t.x, t.y, Color(1, 0.9, 0.2, 1))
	return img
