class_name FieldLayout
extends RefCounted
## 歩行可能領域（マスク）から建物の区画を自動で決める（フェーズ 9 M-2c / M-3）。
##
## 1. 歩行可能タイルに 4 近傍で接する「塞がれた」タイルを外周とし、向き（歩ける側）ごとに直線の列（run）へまとめる
## 2. `near` 付きの建物を最寄りの外周へ、残りは列の順に間口ぶんずつ詰める。奥行きは塞がれたタイルの中へ伸ばす
## 3. カメラ手前の帯（歩行可能タイルからカメラ方向 5.2 m 以内）に掛かる建物は平屋に落とす
## 4. 建物の付かなかった外周は塀（edge_fill）で埋める
##
## 出力は旧形式と同じ lots の配列（rect / kind / front / floors …）なので FieldBuilder はそのまま使える。

const CLASS_BLOCKED := 0
const CLASS_WALK := 1
const CLASS_NARROW := 2
const CLASS_OPEN := 3

const NEAR_BAND_M := 5.2          # 既定（M-3）。JSON の near_band_m で上書き可
var near_band_m := NEAR_BAND_M
const NEAR_BAND_HALF_WIDTH := 0.75  # 視線の帯の半幅（タイル）
const DIRS := {"E": Vector2i(1, 0), "W": Vector2i(-1, 0), "S": Vector2i(0, 1), "N": Vector2i(0, -1)}
const FENCE_KINDS := ["fence_block", "fence_wall", "hedge"]
const PASSABLE_KINDS := ["temple_gate"]

var size := Vector2i(1, 1)
var classes: PackedByteArray
var occupied: PackedByteArray
var near_band: PackedByteArray
var runs: Array = []              # {dir: String, cells: Array[Vector2i]}
var lots: Array = []
var warnings: Array[String] = []
var toward_cam := Vector2(0, 1)   # フィールドのローカル座標でカメラの方へ向く単位ベクトル（タイル）


func _cls(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return CLASS_OPEN            # 場外は「空き地」扱い（建物を置かない）
	return classes[y * size.x + x]


func _walk(x: int, y: int) -> bool:
	var c := _cls(x, y)
	return c == CLASS_WALK or c == CLASS_NARROW


func _free(x: int, y: int) -> bool:
	return _cls(x, y) == CLASS_BLOCKED and occupied[y * size.x + x] == 0


func build(sz: Vector2i, cls: PackedByteArray, buildings: Array, edge_fill, field_yaw_deg: float, flags: Dictionary, band_m: float = NEAR_BAND_M) -> Array:
	size = sz
	near_band_m = band_m
	classes = cls
	occupied = PackedByteArray()
	occupied.resize(size.x * size.y)
	occupied.fill(0)
	lots = []
	warnings = []
	toward_cam = Vector2(-sin(deg_to_rad(field_yaw_deg)), cos(deg_to_rad(field_yaw_deg)))
	_edge_fill_spec = edge_fill
	_compute_near_band()
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
	return lots


# ---- 近景の帯 ------------------------------------------------------------------------
func _compute_near_band() -> void:
	# 歩行可能タイルからカメラの方へ伸ばした視線の帯（幅 ±0.75 タイル、長さ 5.2 m）に入る塞がれたタイル。
	# ここに 2 階建てを置くと、その視線上の歩行可能タイルが隠れる（死角 = 高さ × 1.73、俯角 30°）。
	near_band = PackedByteArray()
	near_band.resize(size.x * size.y)
	near_band.fill(0)
	var reach := near_band_m / FieldData.TILE
	var r := int(ceil(reach))
	for y in size.y:
		for x in size.x:
			if not _walk(x, y):
				continue
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx == 0 and dy == 0:
						continue
					var d := Vector2(dx, dy)
					var along := d.dot(toward_cam)
					if along <= 0.0 or along > reach:
						continue
					var perp := (d - toward_cam * along).length()
					if perp > NEAR_BAND_HALF_WIDTH:
						continue
					var cx := x + dx
					var cy := y + dy
					if _cls(cx, cy) == CLASS_BLOCKED:
						near_band[cy * size.x + cx] = 1


func in_near_band(rect: Array) -> bool:
	for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
		for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
			if x >= 0 and y >= 0 and x < size.x and y < size.y and near_band[y * size.x + x] == 1:
				return true
	return false


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
				var is_b := _cls(c.x, c.y) == CLASS_BLOCKED and _walk(c.x + d.x, c.y + d.y)
				if is_b:
					cur.append(c)
				elif not cur.is_empty():
					runs.append({"dir": dname, "cells": cur})
					cur = []
			if not cur.is_empty():
				runs.append({"dir": dname, "cells": cur})


## 列の中で index から幅 w のタイルが空いているか
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
	if in_near_band(rect) and not (l.get("kind", "") in FENCE_KINDS):
		l["near_band"] = true
		if int(l.get("floors", 1)) > 1:
			l["floors"] = 1
		if l.has("height_m") and float(l["height_m"]) > 3.0:
			l["height_m"] = 3.0
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
	var cells: Array[Vector2i] = best_run["cells"]
	# 最寄りのタイルを含むように間口をずらして、空いている位置を探す
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
		# 間口を縮める
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


## edge_fill の領域に reserve: true が付いていれば、順番待ちの建物はそこへ置かない（near 指定は置ける）
var _edge_fill_spec = "fence_block"


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


func _fill_runs(pool: Array) -> void:
	if pool.is_empty():
		return
	var pi := 0
	for run in runs:
		var cells: Array[Vector2i] = run["cells"]
		var i := 0
		while i < cells.size() and pi < pool.size():
			if not _free(cells[i].x, cells[i].y):
				i += 1
				continue
			# ここから空いている長さ
			var free_len := 0
			while i + free_len < cells.size() and _free(cells[i + free_len].x, cells[i + free_len].y):
				free_len += 1
			var b: Dictionary = pool[pi]
			var w := int(b.get("width", 3))
			if w > free_len:
				# 次の建物で入るものを探す。無ければこの区間は塀に任せる
				var alt := -1
				for j in range(pi + 1, pool.size()):
					if int(pool[j].get("width", 3)) <= free_len:
						alt = j
						break
				if alt < 0:
					i += free_len
					continue
				b = pool[alt]
				pool.remove_at(alt)
				pool.insert(pi, b)
				w = int(b.get("width", 3))
			var rect := _lot_rect(run, i, w, int(b.get("depth", 3)))
			var got: int = rect[2] if run["dir"] in ["E", "W"] else rect[3]
			if got < 2 or _reserved(cells[i]):
				# 奥行きが 1 タイルしか取れない（場外や別の道が裏にある）か、塀に予約された外周。建物は置かず塀に任せる
				i += 1
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
