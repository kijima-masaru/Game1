class_name FieldBuilder
extends RefCounted
## data/fields/<id>.json から 3D の街を組む（docs/FIELD_FORMAT.md 第 9 節）。
## 地面 → 道 → 区画（建物生成器）→ 塀 → 配置物と光源 → field_yaw で全体を回す。AO は res://cache/fields/<id>/ にキャッシュ。

const TEX_VERSION := 5            # テクスチャ生成の版。上げるとキャッシュを焼き直す（5: 地形、フェーズ 14 T-2b）
const T := FieldData.TILE

var fd: FieldData
var root: Node3D                   # 回転する親（フィールドのローカル座標 = タイル × T）
var gen: BuildingGen
var baker: AoBaker
var mats := {}
var pixel_size := 1.0 / 28.0
var billboards: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
var lot_faces := {}                # lot id -> Array[MeshInstance3D]
var lot_aabbs := {}                # lot id -> AABB（ローカル）
var lot_quads := {}                # lot id -> Array[{o,u,v,tri}]（隠れ判定に使う実際の面）
var terrain_quads: Array = []      # 地形の垂直面（3 階調以上）。隠れの診断に使い、建物と同じフェードの対象（名前 tstepNN）
var _riser_n := 0
var bake_seconds := 0.0
var cache_hit := false


func build(field: FieldData, parent: Node3D, flags: Dictionary, cam_yaw_deg: float, regen: bool = false, tex_mode: String = "proc") -> Node3D:
	fd = field
	root = Node3D.new()
	root.name = "Field_" + fd.d["id"]
	parent.add_child(root)
	gen = BuildingGen.new(root)
	gen.ao_texel = 2.0
	baker = AoBaker.new([], 18.0, 24)
	_build_materials(tex_mode)
	_build_ground()
	for l in fd.lots:          # FieldLayout が歩行可能マスクから決めた区画（when は適用済み）
		_build_lot(l)
	_build_barriers()
	var t0 := Time.get_ticks_msec()
	var cache_dir := "res://cache/fields/%s" % fd.d["id"]
	var key := _cache_key()
	var manifest := "%s/manifest.json" % cache_dir
	var can_load := false
	if not regen and FileAccess.file_exists(manifest):
		var m = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		can_load = typeof(m) == TYPE_DICTIONARY and m.get("key", "") == key
	gen.finalize(baker, {"dir": cache_dir, "load": can_load})
	cache_hit = can_load
	if not can_load:
		var f := FileAccess.open(manifest, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"key": key, "faces": gen.faces.size(), "generated": Time.get_datetime_string_from_system()}))
	bake_seconds = (Time.get_ticks_msec() - t0) / 1000.0
	_collect_lot_faces()
	for p in fd.d.get("props", []):
		if FieldData.when_ok(p.get("when"), flags):
			_build_prop(p)
	# 全体の回転（K-1）: 地図の北（ローカル -Z）がカメラ前方から field_yaw だけ回った向きになる
	root.rotation.y = deg_to_rad(cam_yaw_deg + float(fd.d.get("field_yaw", 0)))
	return root


func _cache_key() -> String:
	var txt := FileAccess.get_file_as_string("res://data/fields/%s.json" % fd.d["id"].to_lower())
	var mask := FileAccess.get_md5(ProjectSettings.globalize_path(fd.mask_path))
	var hgt := FileAccess.get_md5(ProjectSettings.globalize_path(fd.height_path)) if fd.has_height else "flat"
	return "%s:%s:%s:%d:%s:%d" % [str(txt.hash()), mask, hgt, TEX_VERSION, str(FileAccess.get_file_as_string("res://data/assets/objects.json").hash()), int(fd.d.get("field_yaw", 0))]


# ============================================================================
# 材質
# ============================================================================
func _build_materials(tex_mode: String) -> void:
	var PT := PixelTextures
	mats["lot_ground"] = PT.material(PT.lot_ground())
	mats["gravel"] = PT.material(PT.gravel())
	mats["grass"] = PT.material(PT.grass())
	mats["water"] = PT.material(PT.noise(32, Color(0.16, 0.22, 0.34), 0.03))
	mats["tile"] = PT.material(PT.stone_path(32, 61))
	mats["paddy"] = PT.material(PT.paddy())
	mats["stone_step"] = PT.material(PT.stone_step())
	mats["dirt"] = PT.material(PT.earth(32, 93))   # 農道・畦道（土の色。lot_ground は緑がかって草と区別がつかない）
	mats["concrete_slab"] = PT.material(PT.concrete())
	mats["retaining_wall"] = PT.material(PT.retaining_wall())
	mats["stone_wall"] = PT.material(PT.stone_wall())
	mats["rock"] = PT.material(PT.rock())
	mats["earth"] = PT.material(PT.earth())
	mats["moss"] = PT.material(PT.grass(32, 75))
	mats["sand"] = PT.material(PT.gravel(32, 77))
	mats["asphalt"] = PT.material(PT.asphalt_gravel())
	mats["stone_path"] = PT.material(PT.stone_path())
	mats["old_street"] = PT.material(PT.old_street())
	mats["sidewalk"] = PT.material(PT.gutter())
	mats["alley"] = PT.material(PT.lot_ground(32, 71))
	mats["temple_path"] = mats["stone_path"]
	mats["road"] = mats["asphalt"]
	mats["weatherboard"] = [PT.material(PT.weatherboard(32, Color(0.55, 0.58, 0.72))), PT.material(PT.weatherboard(32, Color(0.62, 0.55, 0.50), 0.50, 14)),
		PT.material(PT.weatherboard(32, Color(0.50, 0.60, 0.62), 0.50, 15)), PT.material(PT.weatherboard(32, Color(0.66, 0.60, 0.58), 0.48, 16))]
	mats["mortar"] = [PT.material(PT.mortar()), PT.material(PT.mortar(32, Color(0.78, 0.74, 0.66), 0.50, 12)), PT.material(PT.mortar(32, Color(0.72, 0.76, 0.78), 0.52, 13))]
	mats["concrete"] = [PT.material(PT.concrete())]
	mats["namako"] = [PT.material(PT.namako())]
	mats["plaster"] = [PT.material(PT.plaster())]
	mats["kawara"] = [PT.material(PT.kawara()), PT.material(PT.kawara(32, Color(0.40, 0.36, 0.42), 0.22, 30)), PT.material(PT.kawara(32, Color(0.34, 0.40, 0.44), 0.24, 31))]
	mats["corrugated"] = PT.material(PT.corrugated())
	mats["shutter"] = [PT.material(PT.shutter()), PT.material(PT.shutter(32, 0.36, 24)), PT.material(PT.shutter(32, 0.44, 25))]
	mats["block_fence"] = PT.material(PT.block_fence())
	mats["hedge"] = PT.material(PT.hedge())
	mats["wire"] = PT.material(PT.noise(8, Color(0.42, 0.44, 0.46), 0.08))
	mats["sign_red"] = PT.emissive_material(Color(0.85, 0.15, 0.12), 0.25)
	mats["sign_blue"] = PT.emissive_material(Color(0.15, 0.35, 0.8), 0.25)
	mats["sign_yellow"] = PT.emissive_material(Color(0.95, 0.75, 0.15), 0.25)
	mats["sign_white"] = PT.emissive_material(Color(0.95, 0.95, 0.9), 0.2)
	mats["glass_bright"] = PT.material(PT.noise(8, Color(0.30, 0.40, 0.50), 0.03))
	mats["glass"] = PT.material(PT.noise(8, Color(0.10, 0.12, 0.18), 0.02))
	mats["frame"] = PT.material(PT.noise(8, Color(0.62, 0.62, 0.60), 0.02))
	mats["wood"] = PT.material(PT.weatherboard(32, Color(0.48, 0.36, 0.26), 0.30, 17))
	mats["dark"] = PT.material(PT.noise(8, Color(0.08, 0.08, 0.10), 0.01))
	mats["sign_dark"] = PT.material(PT.noise(8, Color(0.30, 0.30, 0.32), 0.02))
	mats["warm_window"] = PT.emissive_material(Color(1.0, 0.82, 0.45), 2.5)
	var wt := StandardMaterial3D.new()
	wt.albedo_color = Color(0, 0, 0, 1)
	wt.emission_enabled = true
	wt.emission = Color(1, 1, 1)
	wt.emission_texture = ImageTexture.create_from_image(PT.warm_window())
	wt.emission_energy_multiplier = 0.35   # 2.5 / 1.0 は Filmic white 1.0 で白飛びした。Glow を切っている以上、発光は 0.3〜0.5 が上限（フェーズ8 J-3）
	PT.register(wt)   # 世界テクスチャのフィルタに揃える（F-0a の漏れの再発防止）
	wt.uv1_scale = Vector3(28.0 / 16.0, 28.0 / 16.0, 1)
	wt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["warm_window"] = wt


func _wall_mat(kind: String, variant: int) -> StandardMaterial3D:
	var arr = mats.get(kind, mats["mortar"])
	if arr is Array:
		return arr[variant % arr.size()]
	return arr


# ============================================================================
# 地面・道
# ============================================================================
func _rect_face(r: Array, mat: Material, name_: String, lift: float, ao := true) -> void:
	var o := Vector3(float(r[0]) * T, lift, float(r[1]) * T)
	gen.add_face(o, Vector3(float(r[2]) * T, 0, 0), Vector3(0, 0, float(r[3]) * T), Vector3.UP, mat, name_, ao, true)


func _build_ground() -> void:
	if fd.has_height:
		_build_terrain()
		return
	var g: Dictionary = fd.d.get("ground", {})
	var margin := 16   # 画面端に虚無が出ないよう広め（面は 5 枚、描画コストは無視できる）
	var gm: Material = mats[g.get("default", "lot_ground")]
	_rect_face([0, 0, fd.size.x, fd.size.y], gm, "ground", 0.0)
	# 外周（フィールド外）。areamask=1 で別色にして「画面のうちフィールド外の割合」を測る
	_rect_face([-margin, -margin, fd.size.x + 2 * margin, margin], gm, "margin_n", 0.0, false)
	_rect_face([-margin, fd.size.y, fd.size.x + 2 * margin, margin], gm, "margin_s", 0.0, false)
	_rect_face([-margin, 0, margin, fd.size.y], gm, "margin_w", 0.0, false)
	_rect_face([fd.size.x, 0, margin, fd.size.y], gm, "margin_e", 0.0, false)
	# 歩行可能マスクの種別ごとに、行の連続区間を 1 面にまとめて敷く
	var tex := {FieldLayout.CLASS_WALK: mats[g.get("walk", "old_street")], FieldLayout.CLASS_NARROW: mats[g.get("narrow", "alley")], FieldLayout.CLASS_OPEN: mats[g.get("open", "gravel")]}
	var names := {FieldLayout.CLASS_WALK: "walk", FieldLayout.CLASS_NARROW: "narrow", FieldLayout.CLASS_OPEN: "open"}
	var n := 0
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
			_rect_face([x, y, x1 - x, 1], tex[c], "%s_%03d" % [names[c], n], 0.01, true)
			n += 1
			x = x1
	for p in g.get("patches", []):
		_rect_face(p["rect"], mats[p["tex"]], "patch_" + p["id"], 0.02)


# ============================================================================
# 区画（建物）
# ============================================================================
func _lot_box(l: Dictionary) -> Dictionary:
	var r: Array = l["rect"]
	var w := float(r[2]) * T
	var d := float(r[3]) * T
	var cx := (float(r[0]) + float(r[2]) * 0.5) * T
	var cz := (float(r[1]) + float(r[3]) * 0.5) * T
	var hb := _rect_heights(r)
	return {"center": Vector3(cx, hb["max"], cz), "w": w, "d": d, "min": hb["min"], "max": hb["max"]}


## 矩形の中の地面の高さの最小・最大 (m)。区画は最大に合わせ、下は基礎で埋める（8d）
func _rect_heights(r: Array) -> Dictionary:
	var lo := 1e9
	var hi := -1e9
	for y in range(int(r[1]), int(r[1]) + int(r[3])):
		for x in range(int(r[0]), int(r[0]) + int(r[2])):
			var h := fd.h_m(x, y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if lo > hi:
		return {"min": 0.0, "max": 0.0}
	return {"min": lo, "max": hi}


func _terrain_wall_mat(x: int, y: int) -> Material:
	var r := fd.trect(x, y)
	return mats[r.get("wall", fd.terrain_wall)]


## 正面の壁の座標系（origin = 正面の左下、u = 幅方向、v = 上、normal = 外向き）
func _front_frame(l: Dictionary, box: Dictionary, h: float) -> Dictionary:
	var c: Vector3 = box["center"]
	var hw: float = box["w"] * 0.5
	var hd: float = box["d"] * 0.5
	match l.get("front", "S"):
		"S":
			return {"o": Vector3(c.x - hw, c.y, c.z + hd), "u": Vector3(box["w"], 0, 0), "v": Vector3(0, h, 0), "n": Vector3.BACK, "len": box["w"]}
		"N":
			return {"o": Vector3(c.x + hw, c.y, c.z - hd), "u": Vector3(-box["w"], 0, 0), "v": Vector3(0, h, 0), "n": Vector3.FORWARD, "len": box["w"]}
		"E":
			return {"o": Vector3(c.x + hw, c.y, c.z + hd), "u": Vector3(0, 0, -box["d"]), "v": Vector3(0, h, 0), "n": Vector3.RIGHT, "len": box["d"]}
		_:
			return {"o": Vector3(c.x - hw, c.y, c.z - hd), "u": Vector3(0, 0, box["d"]), "v": Vector3(0, h, 0), "n": Vector3.LEFT, "len": box["d"]}


func _roof(l: Dictionary, box: Dictionary, h: float, roof_mat: Material, wall_mat: Material, overhang: float, rise: float) -> void:
	var c: Vector3 = box["center"]
	var along_z: bool = l.get("front", "S") in ["E", "W"]
	# 連続する建物（N-2b）: 妻側（隣と接する側）には軒を出さず、屋根を一続きにする
	var end_overhang := overhang
	if l.get("contiguous", false) and (fd.layout.has_neighbor(l, -1) or fd.layout.has_neighbor(l, 1)):
		end_overhang = 0.0
	if l.get("roof", "gable") == "flat" or l.get("kind", "") in ["store", "apartment", "civic", "school", "gym", "shelter"]:
		gen.add_face(Vector3(c.x - box["w"] * 0.5, c.y + h, c.z - box["d"] * 0.5), Vector3(box["w"], 0, 0), Vector3(0, 0, box["d"]), Vector3.UP, roof_mat, l["id"] + "_top", true, true)
		return
	if l.get("roof", "gable") == "none":
		return
	if along_z:
		gen.add_gable_roof_z(Vector3(c.x, c.y + h, c.z), box["w"], box["d"] + 2.0 * end_overhang, rise, roof_mat, wall_mat, l["id"], overhang)
	else:
		gen.add_gable_roof(Vector3(c.x, c.y + h, c.z), box["w"] + 2.0 * end_overhang, box["d"], rise, roof_mat, wall_mat, l["id"], overhang)


func _build_lot(l: Dictionary) -> void:
	var kind: String = l["kind"]
	var box := _lot_box(l)
	var variant := int(l.get("variant", absi(hash(str(l.get("id", "")))) % 8))
	var floors := int(l.get("floors", 1))
	# 高さは FieldLayout が遮蔽の式（N-1）で決めたもの（軒 h_wall、棟の立ち上がり rise、軒の出 overhang）
	var h: float = float(l.get("h_wall", 2.3))
	var rise: float = float(l.get("rise", 0.7))
	var overhang: float = float(l.get("overhang", 0.5))
	var contiguous: bool = l.get("contiguous", false)
	var wall := _wall_mat(l.get("wall", "mortar"), variant)
	var roof: StandardMaterial3D = mats["kawara"][variant % 3]
	# 地形: 区画の中で高さが揃わなければ最大に合わせ、下を基礎で埋める（8d）
	if float(box["max"]) - float(box["min"]) > 0.01:
		var fc: Vector3 = box["center"]
		gen.add_box(Vector3(fc.x, box["min"], fc.z), Vector3(box["w"], float(box["max"]) - float(box["min"]), box["d"]), mats[fd.terrain_wall], mats[fd.terrain_wall], l["id"] + "_found", true, false)
	if kind in ["shop_shutter", "shop_wood", "house"] and variant % 4 == 3 and mats.has("corrugated"):
		roof = mats["corrugated"] if not (mats["corrugated"] is Array) else mats["corrugated"][0]
	if kind in FieldLayout.FENCE_KINDS:
		# 塀・生垣は正面の縁に薄く立てる（区画の奥行きは 1 タイルだが厚みは 0.3 m）
		var thick := 0.3
		var c: Vector3 = box["center"]
		var sz := Vector3(box["w"], 1.2, box["d"])
		match l.get("front", "S"):
			"S":
				sz.z = thick
				c.z = c.z + box["d"] * 0.5 - thick * 0.5
			"N":
				sz.z = thick
				c.z = c.z - box["d"] * 0.5 + thick * 0.5
			"E":
				sz.x = thick
				c.x = c.x + box["w"] * 0.5 - thick * 0.5
			"W":
				sz.x = thick
				c.x = c.x - box["w"] * 0.5 + thick * 0.5
		match kind:
			"fence_block":
				gen.add_box(c, sz, mats["block_fence"], mats["block_fence"], l["id"], true)
			"hedge":
				sz.y = 1.0
				gen.add_box(c, Vector3(sz.x + 0.3, sz.y, sz.z + 0.3), mats["hedge"], mats["hedge"], l["id"], true)
			"fence_wall":
				sz.y = 1.8
				gen.add_box(c, sz, mats["plaster"][0], mats["plaster"][0], l["id"], true, false)
				gen.add_box(Vector3(c.x, c.y + 1.8, c.z), Vector3(sz.x + 0.2, 0.25, sz.z + 0.2), roof, roof, l["id"] + "_cap", false)
		return
	match kind:
		"temple_gate":
			var fr := _front_frame(l, box, 3.6)
			var along: Vector3 = (fr["u"] as Vector3).normalized()
			var c: Vector3 = box["center"]
			for s in [-1.0, 1.0]:
				var pc: Vector3 = c + along * (float(s) * (float(fr["len"]) * 0.5 - 0.35))
				gen.add_box(Vector3(pc.x, c.y, pc.z), Vector3(0.4, 3.6, 0.4), mats["wood"], mats["wood"], "%s_p%d" % [l["id"], 0 if s < 0 else 1], false)
			# 屋根は柱の上。棟は正面と平行（= 通り抜け方向と直交）
			if l.get("front", "S") in ["E", "W"]:
				gen.add_gable_roof_z(Vector3(c.x, c.y + 3.6, c.z), maxf(box["w"], 1.0), box["d"], 1.0, roof, mats["wood"], l["id"], 0.5)
			else:
				gen.add_gable_roof(Vector3(c.x, c.y + 3.6, c.z), box["w"], maxf(box["d"], 1.0), 1.0, roof, mats["wood"], l["id"], 0.5)
			return
		"shelter":
			# バス停の待合（F03）: 背面の壁 1 枚 + 柱 + 平らな屋根。正面は開いている
			var fr := _front_frame(l, box, 2.6)
			var c: Vector3 = box["center"]
			var along: Vector3 = (fr["u"] as Vector3).normalized()
			var nrm: Vector3 = fr["n"]
			var back: Vector3 = c - nrm * (box["d"] * 0.5 - 0.15) if l.get("front", "S") in ["S", "N"] else c - nrm * (box["w"] * 0.5 - 0.15)
			var bw: float = fr["len"]
			gen.add_box(Vector3(back.x, c.y, back.z), Vector3(bw, 2.6, 0.2) if l.get("front", "S") in ["S", "N"] else Vector3(0.2, 2.6, bw), mats["concrete"][0], mats["concrete"][0], l["id"] + "_back", true, false)
			for s in [-1.0, 1.0]:
				var pc: Vector3 = c + along * (float(s) * (bw * 0.5 - 0.2)) + nrm * ((box["d"] if l.get("front", "S") in ["S", "N"] else box["w"]) * 0.5 - 0.2)
				gen.add_box(Vector3(pc.x, c.y, pc.z), Vector3(0.2, 2.6, 0.2), mats["frame"], mats["frame"], "%s_p%d" % [l["id"], 0 if s < 0 else 1], false)
			gen.add_face(Vector3(c.x - box["w"] * 0.5, c.y + 2.6, c.z - box["d"] * 0.5), Vector3(box["w"], 0, 0), Vector3(0, 0, box["d"]), Vector3.UP, mats["concrete"][0], l["id"] + "_top", true, true)
			gen.add_face(Vector3(c.x - box["w"] * 0.5, c.y + 2.55, c.z + box["d"] * 0.5), Vector3(box["w"], 0, 0), Vector3(0, 0, -box["d"]), Vector3.DOWN, mats["dark"], l["id"] + "_soffit", false, true)
			gen.add_plate(fr["o"], fr["u"], fr["v"], fr["n"], 0.2, 0.9, 1.4, 0.9, mats["sign_white"], l["id"] + "_timetable")
			return
	# --- 壁のある建物 ---
	var with_top: bool = l.get("roof", "gable") == "flat" or kind in ["store", "apartment", "civic", "school", "gym"]
	gen.add_box(box["center"], Vector3(box["w"], h, box["d"]), wall, wall, l["id"], true, with_top)
	_roof(l, box, h, roof, wall, overhang, rise)
	var fr := _front_frame(l, box, h)
	var o: Vector3 = fr["o"]
	var u: Vector3 = fr["u"]
	var v: Vector3 = fr["v"]
	var n: Vector3 = fr["n"]
	var L: float = fr["len"]
	match kind:
		"shop_shutter":
			var sw := minf(L - 0.6, 3.4)
			var sh := minf(2.5, h - 0.5)
			gen.add_plate(o, u, v, n, (L - sw) * 0.5, 0.05, sw, sh, mats["shutter"][variant % 3], l["id"] + "_shutter")
			gen.add_plate(o, u, v, n, 0.2, sh + 0.1, L - 0.4, minf(0.5, h - sh - 0.15), mats["sign_dark"], l["id"] + "_sign")
			if floors >= 2:
				gen.add_window(o, u, v, n, 0.4, 3.6, minf(1.6, L * 0.4), 1.1, mats["glass"], mats["frame"], l["id"] + "_w1")
				gen.add_window(o, u, v, n, L - 0.4 - minf(1.6, L * 0.4), 3.6, minf(1.6, L * 0.4), 1.1, mats["glass"], mats["frame"], l["id"] + "_w2")
		"shop_wood":
			var dw := minf(L - 0.8, 2.4)
			gen.add_plate(o, u, v, n, (L - dw) * 0.5, 0.05, dw, 2.2, mats["dark"], l["id"] + "_dooropen")
			gen.add_plate(o, u, v, n, (L - dw) * 0.5, 0.05, 0.08, 2.2, mats["wood"], l["id"] + "_dj0")
			gen.add_plate(o, u, v, n, (L - dw) * 0.5 + dw * 0.5, 0.05, 0.08, 2.2, mats["wood"], l["id"] + "_dj1")
			gen.add_plate(o, u, v, n, (L - dw) * 0.5 + dw - 0.08, 0.05, 0.08, 2.2, mats["wood"], l["id"] + "_dj2")
			gen.add_plate(o, u, v, n, 0.2, 2.35, L - 0.4, 0.35, mats["wood"], l["id"] + "_noren")
			if floors >= 2:
				gen.add_window(o, u, v, n, 0.5, 3.6, L - 1.0, 1.1, mats["glass"], mats["frame"], l["id"] + "_w1")
		"dagashi":
			var ww := minf(L - 0.8, 2.2)
			gen.add_plate(o, u, v, n, 0.3, 0.7, ww, 1.4, mats["warm_window"], l["id"] + "_warm")
			gen.add_plate(o, u, v, n, 0.3 + ww + 0.1, 0.05, minf(1.0, L - ww - 0.7), 2.1, mats["dark"], l["id"] + "_door")
			gen.add_plate(o, u, v, n, 0.2, 2.4, L - 0.4, 0.5, mats["sign_dark"], l["id"] + "_sign")
			gen.add_plate(o, u, v, n, 0.1, 2.35, L - 0.2, 0.08, mats["wood"], l["id"] + "_eave")
			# 窓の灯り（夕方・夜）。通りから「一軒だけ明るい」と読めるよう、正面の前 1 m に暖色の点光源
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.78, 0.45)
			light.light_energy = 2.2
			light.omni_range = 7.0
			light.omni_attenuation = 1.4
			light.shadow_enabled = false
			var lp: Vector3 = o + u * 0.5 + n * 1.0 + Vector3(0, 1.6, 0)
			light.position = lp
			light.set_meta("dusk", true)
			root.add_child(light)
			lights.append(light)
			if floors >= 2:
				gen.add_window(o, u, v, n, 0.5, 3.6, L - 1.0, 1.1, mats["glass"], mats["frame"], l["id"] + "_w1")
		"house":
			gen.add_window(o, u, v, n, 0.4, 0.9, minf(1.6, L * 0.4), 1.0, mats["glass"], mats["frame"], l["id"] + "_w1")
			gen.add_plate(o, u, v, n, L - 0.4 - 1.0, 0.05, 1.0, 2.0, mats["dark"], l["id"] + "_door")
		"temple_hall":
			gen.add_plate(o, u, v, n, L * 0.35, 0.05, L * 0.3, 2.6, mats["dark"], l["id"] + "_entrance")
			gen.add_plate(o, u, v, n, 0.2, 2.8, L - 0.4, 0.3, mats["wood"], l["id"] + "_beam")
			for i in range(3):
				var px := 0.4 + i * (L - 0.8) / 2.0
				gen.add_plate(o, u, v, n, px, 0.05, 0.3, h - 0.2, mats["wood"], "%s_pillar%d" % [l["id"], i], 0.04)
		"bldg_rc":
			for fl in floors:
				gen.add_window(o, u, v, n, 0.5, 0.9 + fl * 3.0, L - 1.0, 1.2, mats["glass"], mats["frame"], "%s_w%d" % [l["id"], fl])
		"store":
			# 大型店の記号（F01）: 看板の帯（色）、自動ドア（明るいガラス 2 枚）、庇。建物は大きくしない
			var sign_mat: Material = mats.get("sign_" + String(l.get("sign", "red")), mats["sign_red"])
			gen.add_plate(o, u, v, n, 0.2, h - 1.1, L - 0.4, 0.9, sign_mat, l["id"] + "_sign", 0.04)
			var dw := minf(L * 0.4, 3.0)
			gen.add_plate(o, u, v, n, (L - dw) * 0.5, 0.05, dw, 2.4, mats["glass_bright"], l["id"] + "_door")
			gen.add_plate(o, u, v, n, (L - dw) * 0.5 + dw * 0.5 - 0.04, 0.05, 0.08, 2.4, mats["frame"], l["id"] + "_doorframe")
			gen.add_plate(o, u, v, n, 0.1, 2.5, L - 0.2, 0.15, mats["frame"], l["id"] + "_canopy", 0.3)
			var ww := (L - dw) * 0.5 - 0.6
			if ww > 0.8:
				gen.add_window(o, u, v, n, 0.3, 0.6, ww, 1.8, mats["glass_bright"], mats["frame"], l["id"] + "_w1")
				gen.add_window(o, u, v, n, L - 0.3 - ww, 0.6, ww, 1.8, mats["glass_bright"], mats["frame"], l["id"] + "_w2")
		"apartment":
			# 団地（F12）: 各階に窓の列とベランダの手すり
			for fl in floors:
				var y0 := 0.9 + fl * 3.0
				var k := 0
				var x := 0.4
				while x + 1.2 <= L - 0.4:
					gen.add_window(o, u, v, n, x, y0, 1.2, 1.1, mats["glass"], mats["frame"], "%s_w%d_%d" % [l["id"], fl, k])
					x += 1.8
					k += 1
				if fl > 0:
					gen.add_plate(o, u, v, n, 0.2, y0 - 0.9, L - 0.4, 0.9, mats["concrete"][0], "%s_balc%d" % [l["id"], fl], 0.35)
		"school":
			# 校舎（F11）: RC 3 階、各階に連続窓、1 階に昇降口
			gen.add_plate(o, u, v, n, L * 0.5 - 1.5, 0.05, 3.0, 2.4, mats["glass_bright"], l["id"] + "_entrance")
			for fl in floors:
				var y0 := 1.0 + fl * 3.0
				var x := 0.5
				var k := 0
				while x + 2.0 <= L - 0.5:
					gen.add_window(o, u, v, n, x, y0, 2.0, 1.3, mats["glass"], mats["frame"], "%s_w%d_%d" % [l["id"], fl, k])
					x += 2.6
					k += 1
		"gym":
			# 体育館（F11）: 高い壁に横長の高窓、正面に扉
			gen.add_plate(o, u, v, n, L * 0.5 - 1.0, 0.05, 2.0, 2.4, mats["dark"], l["id"] + "_door")
			gen.add_window(o, u, v, n, 0.6, h - 2.2, L - 1.2, 1.2, mats["glass"], mats["frame"], l["id"] + "_hiwin")
		"civic":
			# 市民センター・交番（F06）: RC 2 階、正面に庇付きの入口と横長の窓
			gen.add_plate(o, u, v, n, L * 0.5 - 1.2, 0.05, 2.4, 2.4, mats["glass_bright"], l["id"] + "_entrance")
			gen.add_plate(o, u, v, n, L * 0.5 - 1.6, 2.5, 3.2, 0.2, mats["frame"], l["id"] + "_canopy", 0.5)
			for fl in floors:
				gen.add_window(o, u, v, n, 0.5, 0.9 + fl * 3.0, L - 1.0, 1.2, mats["glass"], mats["frame"], "%s_w%d" % [l["id"], fl])


func _collect_lot_faces() -> void:
	for f in gen.faces:
		var n: String = f["name"]
		var id := ""
		if n.begins_with("barrier") or n.begins_with("tstep") or _terrain_top(n):
			id = n.split("_")[0]   # barrierNN（塀・生垣・金網）、tstepNNN（地形の段差）、0.45 m より高い地形の面もフェードの対象
		else:
			for l in fd.lots:
				var lid: String = l["id"]
				if n == lid or n.begins_with(lid + "_"):
					id = lid
					break
		if id == "":
			continue
		if _terrain_top(n):
			var top_y: float = maxf(maxf((f["origin"] as Vector3).y, ((f["origin"] as Vector3) + (f["u"] as Vector3)).y), ((f["origin"] as Vector3) + (f["v"] as Vector3)).y)
			if f.has("pts"):
				for pp in f["pts"]:
					top_y = maxf(top_y, (pp as Vector3).y)
			if top_y < 0.45:
				continue
		if not lot_quads.has(id):
			lot_quads[id] = []
		lot_quads[id].append({"o": f["origin"], "u": f["u"], "v": f["v"], "tri": f["tri"]})
	for mi in root.get_children():
		if not (mi is MeshInstance3D):
			continue
		var n: String = mi.name
		if n.begins_with("barrier") or n.begins_with("tstep") or _terrain_top(n):
			var bb0: AABB = mi.transform * mi.get_aabb()
			if not n.begins_with("barrier") and not n.begins_with("tstep") and bb0.end.y < 0.45:
				continue   # 低い地形の面は主人公を隠せない
			var bid: String = n.split("_")[0]
			var bb: AABB = mi.transform * mi.get_aabb()
			if not lot_faces.has(bid):
				lot_faces[bid] = []
				lot_aabbs[bid] = bb
			else:
				lot_aabbs[bid] = (lot_aabbs[bid] as AABB).merge(bb)
			lot_faces[bid].append(mi)
			continue
		for l in fd.lots:
			var id: String = l["id"]
			if n == id or n.begins_with(id + "_"):
				_tag_front(mi, l)
				# 区画の AABB は実際のメッシュから（平屋・塀は低いので、隠れ判定で 2 階建てと区別できる）
				var bb: AABB = mi.transform * mi.get_aabb()
				if not lot_faces.has(id):
					lot_faces[id] = []
					lot_aabbs[id] = bb
				else:
					lot_aabbs[id] = (lot_aabbs[id] as AABB).merge(bb)
				lot_faces[id].append(mi)
				break


## 地形の上面・坂・裾・踏面（タイルごとに独立した名前）。F16 の岩壁の上面のように、高い地形の面が主人公を隠すのでフェードの対象にする
static func _terrain_top(n: String) -> bool:
	return n.begins_with("tflat") or n.begins_with("tslope") or n.begins_with("tskirt") or n.begins_with("ttread")


## barriers: 空き地（open）の上に明示した塀・生垣・金網（P-2a の近景）。矩形の細い方の軸に沿って薄い箱を立てる
func _build_barriers() -> void:
	var n := 0
	for b in fd.d.get("barriers", []):
		var r: Array = b["rect"]
		var kind: String = b.get("kind", "hedge")
		var cx := (float(r[0]) + float(r[2]) * 0.5) * T
		var cz := (float(r[1]) + float(r[3]) * 0.5) * T
		var along_x := int(r[2]) >= int(r[3])
		var length := float(r[2] if along_x else r[3]) * T
		var thick := 0.3
		var by: float = _rect_heights(r)["max"]   # 地形の上に立てる
		if kind == "overpass":
			# 歩道橋・高架: height_m（既定 4.5 m）の床板と両端の柱。下は通れる
			var oh := float(b.get("height_m", 4.5))
			var ow := float(b.get("width_m", 2.0))
			gen.add_box(Vector3(cx, by + oh, cz), Vector3(length, 0.3, ow) if along_x else Vector3(ow, 0.3, length), mats["concrete"][0], mats["concrete"][0], "barrier%02d" % n, false)
			gen.add_box(Vector3(cx, by + oh + 0.6, cz), Vector3(length, 1.0, 0.1) if along_x else Vector3(0.1, 1.0, length), mats["frame"], mats["frame"], "barrier%02d_rail" % n, false)
			var ends := [Vector3(cx - length * 0.5 + 0.4, by, cz), Vector3(cx + length * 0.5 - 0.4, by, cz)] if along_x else [Vector3(cx, by, cz - length * 0.5 + 0.4), Vector3(cx, by, cz + length * 0.5 - 0.4)]
			for e in ends:
				gen.add_box(e, Vector3(0.6, oh, 0.6), mats["concrete"][0], mats["concrete"][0], "barrier%02d_pier" % n, false)
			n += 1
			continue
		var h: float = {"hedge": 1.0, "fence_block": 1.2, "fence_wall": 1.8, "wire_fence": 1.5, "guardrail": 0.8, "sound_wall": 3.5, "stone_fence": 1.0}.get(kind, 1.0)
		var mat: Material = {"hedge": mats["hedge"], "fence_block": mats["block_fence"], "fence_wall": mats["plaster"][0], "wire_fence": mats["wire"], "guardrail": mats["frame"], "sound_wall": mats["concrete_slab"], "stone_fence": mats["stone_wall"]}.get(kind, mats["hedge"])
		var sz := Vector3(length, h, thick) if along_x else Vector3(thick, h, length)
		if kind == "hedge":
			sz = Vector3(length, h, 0.6) if along_x else Vector3(0.6, h, length)
		gen.add_box(Vector3(cx, by, cz), sz, mat, mat, "barrier%02d" % n, true)
		n += 1


## 正面（歩ける側）にある面に meta front=true を付ける（N-2c の計測用）。壁の面は正面の縁に接するもの、板類は名前で判定
func _tag_front(mi: MeshInstance3D, l: Dictionary) -> void:
	var r: Array = l["rect"]
	var bb: AABB = mi.transform * mi.get_aabb()
	var front_x := -1.0
	var front_z := -1.0
	match l.get("front", "S"):
		"E": front_x = float(r[0] + r[2]) * T
		"W": front_x = float(r[0]) * T
		"S": front_z = float(r[1] + r[3]) * T
		"N": front_z = float(r[1]) * T
	var n: String = mi.name
	var is_roof := "_roof" in n or n.ends_with("_top") or "_soffit" in n or "_gable" in n or n.ends_with("_cap")
	if is_roof:
		return
	if front_x >= 0.0 and bb.size.x < 0.2 and absf(bb.position.x + bb.size.x * 0.5 - front_x) < 0.15:
		mi.set_meta("front", true)
	elif front_z >= 0.0 and bb.size.z < 0.2 and absf(bb.position.z + bb.size.z * 0.5 - front_z) < 0.15:
		mi.set_meta("front", true)


# ============================================================================
# 配置物
# ============================================================================
func _build_prop(p: Dictionary) -> void:
	var a: Dictionary = fd.assets.get(p["asset"], {})
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://" + a["file"]))
	if img == null:
		push_warning("prop %s: 画像が無い %s" % [p["id"], a["file"]])
		return
	var pivot := Node3D.new()
	pivot.name = "Prop_" + p["id"]
	pivot.position = Vector3(float(p["at"][0]) * T, fd.ground_y(float(p["at"][0]) * T, float(p["at"][1]) * T) + 0.02, float(p["at"][1]) * T)
	root.add_child(pivot)
	var sp := Sprite3D.new()
	sp.texture = ImageTexture.create_from_image(img)
	sp.pixel_size = pixel_size
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.alpha_scissor_threshold = 0.5
	sp.shaded = true
	sp.double_sided = true
	sp.flip_h = p.get("facing", "E") == "W"
	sp.set_meta("h", img.get_height())
	sp.position = Vector3(0, img.get_height() * pixel_size * 0.5, 0)
	pivot.add_child(sp)
	billboards.append(pivot)
	if a.has("emissive"):
		var e: Dictionary = a["emissive"]
		var light := OmniLight3D.new()
		light.light_color = Color(e["color"][0], e["color"][1], e["color"][2])
		light.light_energy = float(e.get("energy", 1.0))
		light.omni_range = float(e.get("range_m", 5.0))
		light.omni_attenuation = 1.6
		light.shadow_enabled = false
		var off: Array = e.get("offset_m", [0, 1, 0])
		light.position = Vector3(off[0], off[1], off[2])
		pivot.add_child(light)
		lights.append(light)


## 毎フレーム: ビルボードをカメラに正対させ、等倍スナップ（ART_SPEC 第 5 節）
func update_billboards(cam: Camera3D, texel_per_m: float) -> void:
	var basis := cam.global_transform.basis
	for pv in billboards:
		pv.global_transform.basis = basis
		for sp in pv.get_children():
			if not (sp is Sprite3D):
				continue
			var base := pv.global_position
			var h_px := absf(cam.unproject_position(base).y - cam.unproject_position(base + basis.y).y)
			var ratio: float = h_px / texel_per_m
			var sc := maxf(round(ratio), 1.0) / maxf(ratio, 0.001)
			sp.scale = Vector3(sc, sc, sc)
			sp.position = Vector3(0, int(sp.get_meta("h")) * pixel_size * 0.5 * sc, 0)


## 街灯・自販機は lamps（夜）のとき。dusk 付き（駄菓子屋の窓）は夕方から点ける
func set_lights(on: bool, dusk: bool = false) -> void:
	for l in lights:
		l.visible = (dusk if l.has_meta("dusk") else on)


# ============================================================================
# 地形（フェーズ 14 T-2b、docs/FIELD_FORMAT.md 第 8 節）
# ============================================================================
## 高さ画像があるときの地面。平らなタイルは (材質, 高さ) の行の連続区間を 1 面に、坂・階段はタイルごと、段差の境に垂直の面
func _build_terrain() -> void:
	var g: Dictionary = fd.d.get("ground", {})
	var gm: Material = mats[g.get("default", "lot_ground")]
	var tex := {FieldLayout.CLASS_WALK: mats[g.get("walk", "old_street")], FieldLayout.CLASS_NARROW: mats[g.get("narrow", "alley")], FieldLayout.CLASS_OPEN: mats[g.get("open", "gravel")], FieldLayout.CLASS_BLOCKED: gm}
	var w := fd.size.x
	var h := fd.size.y
	var tm: Array = []
	tm.resize(w * h)
	for y in h:
		for x in w:
			tm[y * w + x] = tex[fd.cls(x, y)]
	for p in g.get("patches", []):
		var r: Array = p["rect"]
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				if x >= 0 and y >= 0 and x < w and y < h:
					tm[y * w + x] = mats[p["tex"]]
	for r in fd.trects:
		if r.has("tex") and r.get("kind", "") != "stairs":
			var rc: Array = r["rect"]
			for y in range(int(rc[1]), int(rc[1]) + int(rc[3])):
				for x in range(int(rc[0]), int(rc[0]) + int(rc[2])):
					if x >= 0 and y >= 0 and x < w and y < h:
						tm[y * w + x] = mats[r["tex"]]
	# 平らなタイル
	var n := 0
	for y in h:
		var x := 0
		while x < w:
			if fd.is_smooth(x, y):
				x += 1
				continue
			var hh := fd.h_m(x, y)
			var m: Material = tm[y * w + x]
			var x1 := x
			while x1 < w and not fd.is_smooth(x1, y) and fd.h_m(x1, y) == hh and tm[y * w + x1] == m:
				x1 += 1
			_rect_face([x, y, x1 - x, 1], m, "tflat%04d" % n, hh + 0.01, true)
			n += 1
			x = x1
	# 坂・階段
	for y in h:
		for x in w:
			if not fd.is_smooth(x, y):
				continue
			var r := fd.trect(x, y)
			if r.get("kind", "") == "stairs":
				_build_stairs_tile(x, y, r)
			else:
				_build_slope_tile(x, y, tm[y * w + x])
	_build_risers()
	var bi := 0
	for r in fd.trects:
		if r.get("kind", "") == "bridge":
			_build_bridge(r, bi)
			bi += 1
	# 外周: 縁のタイルの高さで帯を延ばし、帯どうしの段差は面で塞ぐ
	var margin := 16
	for x in w:
		_rect_face([x, -margin, 1, margin], gm, "margin_n_%d" % x, fd.h_m(x, 0), false)
		_rect_face([x, h, 1, margin], gm, "margin_s_%d" % x, fd.h_m(x, h - 1), false)
		if x + 1 < w:
			_margin_step(Vector3(float(x + 1) * T, 0, -margin * T), Vector3(0, 0, margin * T), fd.h_m(x, 0), fd.h_m(x + 1, 0), gm, "margin_ns_%d" % x)
			_margin_step(Vector3(float(x + 1) * T, 0, h * T), Vector3(0, 0, margin * T), fd.h_m(x, h - 1), fd.h_m(x + 1, h - 1), gm, "margin_ss_%d" % x)
	for y in h:
		_rect_face([-margin, y, margin, 1], gm, "margin_w_%d" % y, fd.h_m(0, y), false)
		_rect_face([w, y, margin, 1], gm, "margin_e_%d" % y, fd.h_m(w - 1, y), false)
		if y + 1 < h:
			_margin_step(Vector3(-margin * T, 0, float(y + 1) * T), Vector3(margin * T, 0, 0), fd.h_m(0, y), fd.h_m(0, y + 1), gm, "margin_ws_%d" % y)
			_margin_step(Vector3(w * T, 0, float(y + 1) * T), Vector3(margin * T, 0, 0), fd.h_m(w - 1, y), fd.h_m(w - 1, y + 1), gm, "margin_es_%d" % y)
	_rect_face([-margin, -margin, margin, margin], gm, "margin_nw", fd.h_m(0, 0), false)
	_rect_face([w, -margin, margin, margin], gm, "margin_ne", fd.h_m(w - 1, 0), false)
	_rect_face([-margin, h, margin, margin], gm, "margin_sw", fd.h_m(0, h - 1), false)
	_rect_face([w, h, margin, margin], gm, "margin_se", fd.h_m(w - 1, h - 1), false)


## 外周の帯どうしの段差（両面）
func _margin_step(o: Vector3, along: Vector3, ha: float, hb: float, mat: Material, name_: String) -> void:
	if absf(ha - hb) < 0.01:
		return
	var lo := minf(ha, hb)
	var hi := maxf(ha, hb)
	var base := Vector3(o.x, lo, o.z)
	gen.add_face(base, along, Vector3(0, hi - lo, 0), Vector3.UP, mat, name_, false, true)
	gen.add_face(base + along, -along, Vector3(0, hi - lo, 0), Vector3.UP, mat, name_ + "b", false, true)


func _build_slope_tile(x: int, y: int, mat: Material) -> void:
	var c: Array = fd.tile_corners(x, y)
	var x0 := float(x) * T
	var z0 := float(y) * T
	var pts := [Vector3(x0, float(c[0]) + 0.01, z0), Vector3(x0 + T, float(c[1]) + 0.01, z0), Vector3(x0 + T, float(c[2]) + 0.01, z0 + T), Vector3(x0, float(c[3]) + 0.01, z0 + T)]
	gen.add_quad4(pts, mat, "tslope%03d%03d" % [x, y], true)
	_skirts(x, y, c)


## 坂・階段の縁が隣の平らなタイルと合わないとき、その縁に垂直の面（裾）を立てる。c は 4 隅 [NW, NE, SE, SW]
func _skirts(x: int, y: int, c: Array) -> void:
	var x0 := float(x) * T
	var z0 := float(y) * T
	# [隣のタイル, 縁の 2 点 (A, B), 隣の側へ向く法線]
	var edges := [
		[Vector2i(x, y - 1), Vector3(x0, c[0], z0), Vector3(x0 + T, c[1], z0), Vector3.FORWARD],
		[Vector2i(x, y + 1), Vector3(x0, c[3], z0 + T), Vector3(x0 + T, c[2], z0 + T), Vector3.BACK],
		[Vector2i(x - 1, y), Vector3(x0, c[0], z0), Vector3(x0, c[3], z0 + T), Vector3.LEFT],
		[Vector2i(x + 1, y), Vector3(x0 + T, c[1], z0), Vector3(x0 + T, c[2], z0 + T), Vector3.RIGHT],
	]
	var k := 0
	for e in edges:
		var nb: Vector2i = e[0]
		if nb.x < 0 or nb.y < 0 or nb.x >= fd.size.x or nb.y >= fd.size.y:
			continue
		if fd.is_smooth(nb.x, nb.y) or fd.tkind(nb.x, nb.y) == "bridge":
			continue
		var hn := fd.h_m(nb.x, nb.y)
		var a: Vector3 = e[1]
		var b: Vector3 = e[2]
		if absf(a.y - hn) < 0.02 and absf(b.y - hn) < 0.02:
			continue
		var nrm: Vector3 = e[3]
		var lower := hn < minf(a.y, b.y)   # 隣が低ければ面は隣の側を向く、高ければ自分の側を向く
		var pts := [a, b, Vector3(b.x, hn, b.z), Vector3(a.x, hn, a.z)]
		var mat := _terrain_wall_mat(x, y) if lower else _terrain_wall_mat(nb.x, nb.y)
		gen.add_quad4(pts, mat, "tskirt%03d%03d%d" % [x, y, k], true, nrm if lower else -nrm)
		k += 1


## 階段のタイル: 入口側の縁 e0 から出口側の縁 e1 まで、蹴上げ 0.15 m の段を (e1 − e0) / 0.15 段刻む。踏面は 1.143 / 段数
func _build_stairs_tile(x: int, y: int, r: Dictionary) -> void:
	var c: Array = fd.tile_corners(x, y)
	var axis: String = r["axis"]
	var dir: int = r["dir"]
	var x0 := float(x) * T
	var z0 := float(y) * T
	var e0: float
	var e1: float
	if axis == "x":
		var ew := (float(c[0]) + float(c[3])) * 0.5
		var ee := (float(c[1]) + float(c[2])) * 0.5
		e0 = ew if dir > 0 else ee
		e1 = ee if dir > 0 else ew
	else:
		var en := (float(c[0]) + float(c[1])) * 0.5
		var es := (float(c[3]) + float(c[2])) * 0.5
		e0 = en if dir > 0 else es
		e1 = es if dir > 0 else en
	var tread: Material = mats[r.get("tex", "stone_step")]
	var riser: Material = mats[r.get("wall", "stone_wall")]
	_skirts(x, y, c)
	var n := int(round((e1 - e0) / FieldData.H_UNIT))
	if n <= 0:
		_rect_face([x, y, 1, 1], tread, "ttread%03d%03d99" % [x, y], (e0 + e1) * 0.5 + 0.01, true)
		return
	var tl := T / float(n)
	for k in n:
		var hk := e0 + (float(k) + 0.5) * FieldData.H_UNIT
		var s0 := float(k) * tl
		var lo := hk - FieldData.H_UNIT
		if axis == "x":
			var ax := x0 + (s0 if dir > 0 else T - s0 - tl)
			gen.add_face(Vector3(ax, hk + 0.01, z0), Vector3(tl, 0, 0), Vector3(0, 0, T), Vector3.UP, tread, "ttread%03d%03d%02d" % [x, y, k], true, true)
			var rx := x0 + (s0 if dir > 0 else T - s0)
			if dir > 0:
				gen.add_face(Vector3(rx, lo, z0), Vector3(0, 0, T), Vector3(0, FieldData.H_UNIT, 0), Vector3.LEFT, riser, "triser_%d_%d_%d" % [x, y, k], false, true)
			else:
				gen.add_face(Vector3(rx, lo, z0 + T), Vector3(0, 0, -T), Vector3(0, FieldData.H_UNIT, 0), Vector3.RIGHT, riser, "triser_%d_%d_%d" % [x, y, k], false, true)
		else:
			var az := z0 + (s0 if dir > 0 else T - s0 - tl)
			gen.add_face(Vector3(x0, hk + 0.01, az), Vector3(T, 0, 0), Vector3(0, 0, tl), Vector3.UP, tread, "ttread%03d%03d%02d" % [x, y, k], true, true)
			var rz := z0 + (s0 if dir > 0 else T - s0)
			if dir > 0:
				gen.add_face(Vector3(x0 + T, lo, rz), Vector3(-T, 0, 0), Vector3(0, FieldData.H_UNIT, 0), Vector3.FORWARD, riser, "triser_%d_%d_%d" % [x, y, k], false, true)
			else:
				gen.add_face(Vector3(x0, lo, rz), Vector3(T, 0, 0), Vector3(0, FieldData.H_UNIT, 0), Vector3.BACK, riser, "triser_%d_%d_%d" % [x, y, k], false, true)


## 平らなタイルどうしの段差に垂直の面（擁壁・石垣・縁石）。同じ高さの差・材質の連続区間を 1 面にまとめる
func _build_risers() -> void:
	var w := fd.size.x
	var h := fd.size.y
	var done := {}
	# 東西に隣り合う (x, y)-(x+1, y)。y 方向にまとめる
	for x in w - 1:
		for y in h:
			if done.has(Vector2i(x, y)):
				continue
			var a := fd.h_units(x, y)
			var b := fd.h_units(x + 1, y)
			if a == b or fd.is_smooth(x, y) or fd.is_smooth(x + 1, y) or fd.tkind(x, y) == "bridge" or fd.tkind(x + 1, y) == "bridge":
				continue
			var hx := x if a > b else x + 1
			var mat := _terrain_wall_mat(hx, y)
			var y1 := y
			while y1 + 1 < h and fd.h_units(x, y1 + 1) == a and fd.h_units(x + 1, y1 + 1) == b and not fd.is_smooth(x, y1 + 1) and not fd.is_smooth(x + 1, y1 + 1) and _terrain_wall_mat(hx, y1 + 1) == mat:
				y1 += 1
			for yy in range(y, y1 + 1):
				done[Vector2i(x, yy)] = true
			var lo := float(mini(a, b)) * FieldData.H_UNIT
			var hi := float(maxi(a, b)) * FieldData.H_UNIT
			var bx := float(x + 1) * T
			var z0 := float(y) * T
			var len := float(y1 - y + 1) * T
			var o: Vector3
			var u: Vector3
			var nrm: Vector3
			if a > b:
				o = Vector3(bx, lo, z0 + len)
				u = Vector3(0, 0, -len)
				nrm = Vector3.RIGHT
			else:
				o = Vector3(bx, lo, z0)
				u = Vector3(0, 0, len)
				nrm = Vector3.LEFT
			_riser(o, u, Vector3(0, hi - lo, 0), nrm, mat, "tstep_x_%d_%d" % [x, y], maxi(a, b) - mini(a, b))
	done = {}
	for y in h - 1:
		for x in w:
			if done.has(Vector2i(x, y)):
				continue
			var a := fd.h_units(x, y)
			var b := fd.h_units(x, y + 1)
			if a == b or fd.is_smooth(x, y) or fd.is_smooth(x, y + 1) or fd.tkind(x, y) == "bridge" or fd.tkind(x, y + 1) == "bridge":
				continue
			var hy := y if a > b else y + 1
			var mat := _terrain_wall_mat(x, hy)
			var x1 := x
			while x1 + 1 < w and fd.h_units(x1 + 1, y) == a and fd.h_units(x1 + 1, y + 1) == b and not fd.is_smooth(x1 + 1, y) and not fd.is_smooth(x1 + 1, y + 1) and _terrain_wall_mat(x1 + 1, hy) == mat:
				x1 += 1
			for xx in range(x, x1 + 1):
				done[Vector2i(xx, y)] = true
			var lo := float(mini(a, b)) * FieldData.H_UNIT
			var hi := float(maxi(a, b)) * FieldData.H_UNIT
			var bz := float(y + 1) * T
			var x0 := float(x) * T
			var len := float(x1 - x + 1) * T
			var o: Vector3
			var u: Vector3
			var nrm: Vector3
			if a > b:
				o = Vector3(x0, lo, bz)
				u = Vector3(len, 0, 0)
				nrm = Vector3.BACK
			else:
				o = Vector3(x0 + len, lo, bz)
				u = Vector3(-len, 0, 0)
				nrm = Vector3.FORWARD
			_riser(o, u, Vector3(0, hi - lo, 0), nrm, mat, "tstep_y_%d_%d" % [x, y], maxi(a, b) - mini(a, b))


func _riser(o: Vector3, u: Vector3, v: Vector3, nrm: Vector3, mat: Material, name_: String, units: int) -> void:
	if units >= 3:
		name_ = "tstep%03d" % _riser_n   # フェードの対象（_collect_lot_faces が tstep で始まる名前を拾う）
		_riser_n += 1
	gen.add_face(o, u, v, nrm, mat, name_, true, true)
	if units >= 3:
		# 3 階調以上は AO の遮蔽物と隠れの診断に入れる
		var p0 := o
		var p1 := o + u + v
		var lo := Vector3(minf(p0.x, p1.x) - 0.05, minf(p0.y, p1.y), minf(p0.z, p1.z) - 0.05)
		var hi := Vector3(maxf(p0.x, p1.x) + 0.05, maxf(p0.y, p1.y), maxf(p0.z, p1.z) + 0.05)
		gen.aabbs.append(AABB(lo, hi - lo))
		terrain_quads.append({"o": o, "u": u, "v": v, "tri": false})


## 橋: 床板の厚み（側面）と欄干、橋脚。床板の上面は平らなタイルとして敷いてある。下の地面（川）まで壁で埋めない
func _build_bridge(r: Dictionary, i: int) -> void:
	var rc: Array = r["rect"]
	var along_x := int(rc[2]) >= int(rc[3])
	var deck: float = _rect_heights(rc)["max"]
	var dm: Material = mats[r.get("deck", "concrete_slab")]
	var x0 := float(rc[0]) * T
	var z0 := float(rc[1]) * T
	var bw := float(rc[2]) * T
	var bd := float(rc[3]) * T
	var cx := x0 + bw * 0.5
	var cz := z0 + bd * 0.5
	gen.add_box(Vector3(cx, deck - 0.4, cz), Vector3(bw, 0.4, bd), dm, dm, "tbridge%d_slab" % i, false, false)
	var rail_h := 1.0
	if along_x:
		gen.add_box(Vector3(cx, deck, z0 + 0.08), Vector3(bw, rail_h, 0.12), mats["frame"], mats["frame"], "tbridge%d_rail0" % i, false)
		gen.add_box(Vector3(cx, deck, z0 + bd - 0.08), Vector3(bw, rail_h, 0.12), mats["frame"], mats["frame"], "tbridge%d_rail1" % i, false)
	else:
		gen.add_box(Vector3(x0 + 0.08, deck, cz), Vector3(0.12, rail_h, bd), mats["frame"], mats["frame"], "tbridge%d_rail0" % i, false)
		gen.add_box(Vector3(x0 + bw - 0.08, deck, cz), Vector3(0.12, rail_h, bd), mats["frame"], mats["frame"], "tbridge%d_rail1" % i, false)
	# 橋脚: 長辺に沿って 6 タイルごと。下端は長辺の外側のタイルの最低の高さ
	var bottom := 1e9
	for y in range(int(rc[1]) - 1, int(rc[1]) + int(rc[3]) + 1):
		for x in range(int(rc[0]) - 1, int(rc[0]) + int(rc[2]) + 1):
			bottom = minf(bottom, fd.h_m(x, y))
	bottom = float(r.get("bottom", bottom / FieldData.H_UNIT)) * FieldData.H_UNIT
	var span := int(rc[2] if along_x else rc[3])
	var k := 0
	var s := 3
	while s < span:
		var px := x0 + (float(s) * T if along_x else bw * 0.5)
		var pz := z0 + (bd * 0.5 if along_x else float(s) * T)
		gen.add_box(Vector3(px, bottom, pz), Vector3(0.8, maxf(deck - 0.4 - bottom, 0.1), bd * 0.8) if along_x else Vector3(bw * 0.8, maxf(deck - 0.4 - bottom, 0.1), 0.8), mats["concrete_slab"], mats["concrete_slab"], "tbridge%d_pier%d" % [i, k], false, false)
		k += 1
		s += 6
