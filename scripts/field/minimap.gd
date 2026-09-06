class_name Minimap
extends Control
## 歩行可能マスクから直接描くミニマップ（フェーズ 9 M-2b）。
## 歩ける範囲の形がそのまま地図の形。建物は描かない。カメラのヨーに合わせて回し（画面の上 = カメラの前方）、
## 現在地・出入口・調べ物・北の矢印を重ねる。

var fd: FieldData
var field_root: Node3D
var cam: Camera3D
var player: Node3D
var flags: Dictionary = {}
var map_px := 120.0            # 描画領域の一辺（px、設計解像度）

const COL_WALK := Color(0.82, 0.80, 0.72, 0.95)
const COL_NARROW := Color(0.45, 0.44, 0.40, 0.95)
const COL_OPEN := Color(0.30, 0.34, 0.28, 0.6)
const COL_BG := Color(0.04, 0.04, 0.07, 0.78)
const COL_EXIT := Color(1.0, 0.35, 0.25)
const COL_POINT := Color(1.0, 0.85, 0.2)
const COL_NPC := Color(0.4, 0.9, 1.0)
const COL_PLAYER := Color(1, 1, 1)


func _ready() -> void:
	custom_minimum_size = Vector2(map_px, map_px)
	size = custom_minimum_size
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


## フィールドのローカル方向（タイル単位）を画面の 2D 方向へ（右 +x、下 +y）
func _to_screen(v: Vector3) -> Vector2:
	var w := field_root.global_transform.basis * v
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	return Vector2(w.dot(right), -w.dot(fwd))


func _draw() -> void:
	if fd == null or cam == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var diag := Vector2(fd.size).length()
	var s := (map_px - 6.0) / diag
	var center := size * 0.5
	var ex := _to_screen(Vector3(1, 0, 0))
	var angle := ex.angle()
	var mc := Vector2(fd.size) * 0.5
	draw_set_transform(center, angle, Vector2(s, s))
	for y in fd.size.y:
		var x := 0
		while x < fd.size.x:
			var c := fd.cls(x, y)
			if c == FieldLayout.CLASS_BLOCKED:
				x += 1
				continue
			var x1 := x
			while x1 < fd.size.x and fd.cls(x1, y) == c:
				x1 += 1
			var col := COL_WALK
			if c == FieldLayout.CLASS_NARROW:
				col = COL_NARROW
			elif c == FieldLayout.CLASS_OPEN:
				col = COL_OPEN
			draw_rect(Rect2(Vector2(x, y) - mc, Vector2(x1 - x, 1)), col)
			x = x1
	# 出入口: 縁の外へ向く三角
	for e in fd.d.get("exits", []):
		var p := Vector2(float(e["at"][0]) + 0.5, float(e["at"][1]) + 0.5) - mc
		var dir := Vector2.ZERO
		match e.get("dir", "N"):
			"N": dir = Vector2(0, -1)
			"S": dir = Vector2(0, 1)
			"E": dir = Vector2(1, 0)
			"W": dir = Vector2(-1, 0)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 2.2, p + side * 1.3 - dir * 0.3, p - side * 1.3 - dir * 0.3]), COL_EXIT)
	# 調べ物
	for pt in fd.d.get("points", []):
		if not FieldData.when_ok(pt.get("when"), flags):
			continue
		var p := Vector2(float(pt["at"][0]) + 0.5, float(pt["at"][1]) + 0.5) - mc
		draw_circle(p, 0.9, COL_NPC if pt.get("kind", "") == "npc" else COL_POINT)
	# 現在地
	if player != null:
		var lp := player.position
		var p := Vector2(lp.x / FieldData.TILE, lp.z / FieldData.TILE) - mc
		draw_circle(p, 1.6, Color(0, 0, 0, 0.8))
		draw_circle(p, 1.1, COL_PLAYER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 北の矢印（右上）
	var n := _to_screen(Vector3(0, 0, -1)).normalized()
	var o := Vector2(size.x - 9.0, 9.0)
	draw_line(o - n * 4.0, o + n * 4.0, Color(1, 1, 1), 1.0)
	var side := Vector2(-n.y, n.x)
	draw_colored_polygon(PackedVector2Array([o + n * 6.0, o + n * 2.0 + side * 2.5, o + n * 2.0 - side * 2.5]), Color(1, 0.3, 0.3))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.0)
