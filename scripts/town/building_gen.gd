class_name BuildingGen
extends RefCounted
## 建物をスクリプトで生成する（H-1 の案 A）。箱・切妻屋根・板（窓枠・看板）の組み合わせ。
## 面ごとに MeshInstance3D を作り、UV は m 単位（材質の uv1_scale でタイル化）、UV2 は 0..1（AO 用）。
## 生成は 2 段: add_* で面を登録 → finalize(baker) で AO を焼いて Mesh にする。
## 遮蔽物（AABB）は登録した箱と屋根から自動で集める。

## 破風板の見付幅（REFERENCE_VOCAB.md 2-2: 実例180〜240mm幅。写真検証まではこの値で運用する）
const BARGE_WIDTH_M := 0.22

var faces: Array = []          # {origin,u,v,normal,mat,name,ao,skip_ground,tri}
var aabbs: Array[AABB] = []
var root: Node3D
var ao_texel := 2.0
var debug_ao := false


func _init(p_root: Node3D) -> void:
	root = p_root


# ---- 登録 ------------------------------------------------------------------------
func add_face(origin: Vector3, u: Vector3, v: Vector3, normal: Vector3, mat: Material, name_: String, ao := true, skip_ground := false) -> void:
	faces.append({"origin": origin, "u": u, "v": v, "normal": normal, "mat": mat, "name": name_, "ao": ao, "skip_ground": skip_ground, "tri": false})


## 三角形（切妻の妻面）。origin から u 方向に底辺、apex は origin + u/2 + v
func add_tri(origin: Vector3, u: Vector3, v: Vector3, normal: Vector3, mat: Material, name_: String) -> void:
	faces.append({"origin": origin, "u": u, "v": v, "normal": normal, "mat": mat, "name": name_, "ao": true, "skip_ground": false, "tri": true})


## 4 隅の高さが違う四角形（地形の坂）。pts は NW, NE, SE, SW（上から見て時計回り = 法線が上）。AO は平行四辺形で近似
func add_quad4(pts: Array, mat: Material, name_: String, ao := true, normal_override := Vector3.ZERO) -> void:
	var p: Array = pts.duplicate()
	var o: Vector3 = p[0]
	var u: Vector3 = p[1] - p[0]
	var v: Vector3 = p[3] - p[0]
	var n := v.cross(u).normalized()
	if normal_override != Vector3.ZERO:
		if n.dot(normal_override) < 0.0:
			p = [pts[0], pts[3], pts[2], pts[1]]   # 巻き方向を反転
			u = p[1] - p[0]
			v = p[3] - p[0]
		n = normal_override
	faces.append({"origin": o, "u": u, "v": v, "normal": n, "mat": mat, "name": name_, "ao": ao, "skip_ground": true, "tri": false, "pts": p, "flat_normal": normal_override != Vector3.ZERO})


## 直方体（4 壁 + 天面）。center は底面中心。
func add_box(center: Vector3, size: Vector3, wall: Material, top: Material, name_: String, occlude := true, with_top := true) -> void:
	add_box_dir(center, size, wall, wall, wall, top, name_, occlude, with_top)


## add_box の面ごとに壁材を変えられる版（経年の方位差: 北面に苔、南面が退色 等）。
## wall_s/_n は南面（+Z）・北面（-Z）、wall_ew は東西面（省略時は wall_s と同じ）。
func add_box_dir(center: Vector3, size: Vector3, wall_s: Material, wall_n: Material, wall_ew: Material, top: Material, name_: String, occlude := true, with_top := true) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := center.y
	add_face(Vector3(center.x - hx, y0, center.z + hz), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), Vector3.BACK, wall_s, name_ + "_S")
	add_face(Vector3(center.x + hx, y0, center.z - hz), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3.FORWARD, wall_n, name_ + "_N")
	add_face(Vector3(center.x + hx, y0, center.z + hz), Vector3(0, 0, -size.z), Vector3(0, size.y, 0), Vector3.RIGHT, wall_ew, name_ + "_E")
	add_face(Vector3(center.x - hx, y0, center.z - hz), Vector3(0, 0, size.z), Vector3(0, size.y, 0), Vector3.LEFT, wall_ew, name_ + "_W")
	if with_top:
		add_face(Vector3(center.x - hx, y0 + size.y, center.z - hz), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), Vector3.UP, top, name_ + "_top", true, true)
	if occlude:
		aabbs.append(AABB(Vector3(center.x - hx, y0, center.z - hz), size))


## 切妻屋根。棟は X 方向。base_y に軒、rise だけ上がる。overhang は軒の出（Z 方向）。
## keraba はけらばの出（X 方向、妻面を越える屋根の張り出し）。省略時（負値）は overhang と同じ値を使う
## （REFERENCE_VOCAB.md 2-2: けらばの出は文献上の標準値が無いため、軒の出と同程度から始める設計）。
## barge_mat を渡すと妻の破風板（けらば端の見付材）を追加する。省略時は roof 材を使う。
func add_gable_roof(center: Vector3, size_x: float, size_z: float, rise: float, roof: Material, gable_wall: Material, name_: String, overhang := 0.5, thickness := 0.12, keraba := -1.0, barge_mat: Material = null, barge_width := BARGE_WIDTH_M) -> void:
	var kb: float = overhang if keraba < 0.0 else keraba
	var hx := size_x * 0.5 + kb
	var hz := size_z * 0.5 + overhang
	var y0 := center.y
	var ridge := Vector3(center.x, y0 + rise, center.z)
	# 南斜面（+Z 側）: 軒 (z = +hz) から棟へ
	var eave_s := Vector3(center.x - hx, y0, center.z + hz)
	var slope_s := Vector3(0, rise, -hz)
	var n_s := Vector3(0, hz, rise).normalized()
	add_face(eave_s, Vector3(2 * hx, 0, 0), slope_s, n_s, roof, name_ + "_roofS", true, true)
	# 北斜面
	var eave_n := Vector3(center.x + hx, y0, center.z - hz)
	var slope_n := Vector3(0, rise, hz)
	var n_n := Vector3(0, hz, -rise).normalized()
	add_face(eave_n, Vector3(-2 * hx, 0, 0), slope_n, n_n, roof, name_ + "_roofN", true, true)
	# 軒裏（薄い板。下から見える）
	add_face(Vector3(center.x - hx, y0 - thickness, center.z - hz), Vector3(2 * hx, 0, 0), Vector3(0, 0, 2 * hz), Vector3.DOWN, gable_wall, name_ + "_soffit", false, true)
	# 妻面（三角。壁と同じ材質）
	var wz := size_z * 0.5
	add_tri(Vector3(center.x + size_x * 0.5, y0, center.z + wz), Vector3(0, 0, -2 * wz), Vector3(0, rise * (wz / hz), 0), Vector3.RIGHT, gable_wall, name_ + "_gableE")
	add_tri(Vector3(center.x - size_x * 0.5, y0, center.z - wz), Vector3(0, 0, 2 * wz), Vector3(0, rise * (wz / hz), 0), Vector3.LEFT, gable_wall, name_ + "_gableW")
	# 破風板（けらば端の見付材。俯角から見たときの妻面の輪郭を強調する）
	var bmat: Material = barge_mat if barge_mat != null else roof
	add_face(Vector3(center.x + hx, y0, center.z + hz), slope_s, Vector3(0, -barge_width, 0), Vector3.RIGHT, bmat, name_ + "_bargeES", false)
	add_face(Vector3(center.x + hx, y0, center.z - hz), slope_n, Vector3(0, -barge_width, 0), Vector3.RIGHT, bmat, name_ + "_bargeEN", false)
	add_face(Vector3(center.x - hx, y0, center.z + hz), slope_s, Vector3(0, -barge_width, 0), Vector3.LEFT, bmat, name_ + "_bargeWS", false)
	add_face(Vector3(center.x - hx, y0, center.z - hz), slope_n, Vector3(0, -barge_width, 0), Vector3.LEFT, bmat, name_ + "_bargeWN", false)
	aabbs.append(AABB(Vector3(center.x - hx, y0, center.z - hz), Vector3(2 * hx, rise, 2 * hz)))


## 壁面に貼る板（窓・看板・扉）。wall_origin/u/v は壁面の座標系、(ox, oy) は壁面上の位置 (m)、(w, h) は大きさ。
func add_plate(wall_origin: Vector3, wall_u: Vector3, wall_v: Vector3, normal: Vector3, ox: float, oy: float, w: float, h: float, mat: Material, name_: String, lift := 0.02) -> void:
	var ud := wall_u.normalized()
	var vd := wall_v.normalized()
	var o := wall_origin + ud * ox + vd * oy + normal * lift
	add_face(o, ud * w, vd * h, normal, mat, name_, false)


## 窓: 暗いガラス + 白い枠（emission 板、ART_SPEC 第 4 節）
func add_window(wall_origin: Vector3, wall_u: Vector3, wall_v: Vector3, normal: Vector3, ox: float, oy: float, w: float, h: float, glass: Material, frame: Material, name_: String, bar := 0.06) -> void:
	# 暗いガラス面 + 上辺のハイライト 1 本 + 中桟（枠を白い線で囲まない: I-0）
	add_plate(wall_origin, wall_u, wall_v, normal, ox, oy, w, h, glass, name_ + "_glass", 0.02)
	add_plate(wall_origin, wall_u, wall_v, normal, ox, oy + h - bar, w, bar, frame, name_ + "_f1", 0.03)
	add_plate(wall_origin, wall_u, wall_v, normal, ox + w * 0.5 - bar * 0.5, oy, bar, h * 0.9, frame, name_ + "_f4", 0.03)


## 切妻屋根（棟が Z 方向。正面が E/W の建物用）。overhang は軒の出（X 方向）。
## keraba はけらばの出（Z 方向）。省略時（負値）は overhang と同じ値を使う（add_gable_roof 参照）。
func add_gable_roof_z(center: Vector3, size_x: float, size_z: float, rise: float, roof: Material, gable_wall: Material, name_: String, overhang := 0.5, thickness := 0.12, keraba := -1.0, barge_mat: Material = null, barge_width := BARGE_WIDTH_M) -> void:
	var kb: float = overhang if keraba < 0.0 else keraba
	var hx := size_x * 0.5 + overhang
	var hz := size_z * 0.5 + kb
	var y0 := center.y
	# 東斜面（+X 側）: 軒 (x = +hx) から棟へ
	var slope_e := Vector3(-hx, rise, 0)
	var eave_e := Vector3(center.x + hx, y0, center.z - hz)
	add_face(eave_e, Vector3(0, 0, 2 * hz), slope_e, Vector3(rise, hx, 0).normalized(), roof, name_ + "_roofE", true, true)
	var slope_w := Vector3(hx, rise, 0)
	var eave_w := Vector3(center.x - hx, y0, center.z + hz)
	add_face(eave_w, Vector3(0, 0, -2 * hz), slope_w, Vector3(-rise, hx, 0).normalized(), roof, name_ + "_roofW", true, true)
	add_face(Vector3(center.x - hx, y0 - thickness, center.z - hz), Vector3(2 * hx, 0, 0), Vector3(0, 0, 2 * hz), Vector3.DOWN, gable_wall, name_ + "_soffit", false, true)
	var wx := size_x * 0.5
	add_tri(Vector3(center.x - wx, y0, center.z + size_z * 0.5), Vector3(2 * wx, 0, 0), Vector3(0, rise * (wx / hx), 0), Vector3.BACK, gable_wall, name_ + "_gableS")
	add_tri(Vector3(center.x + wx, y0, center.z - size_z * 0.5), Vector3(-2 * wx, 0, 0), Vector3(0, rise * (wx / hx), 0), Vector3.FORWARD, gable_wall, name_ + "_gableN")
	# 破風板（けらば端の見付材）
	var bmat: Material = barge_mat if barge_mat != null else roof
	add_face(Vector3(center.x + hx, y0, center.z + hz), slope_e, Vector3(0, -barge_width, 0), Vector3.BACK, bmat, name_ + "_bargeES", false)
	add_face(Vector3(center.x + hx, y0, center.z - hz), slope_e, Vector3(0, -barge_width, 0), Vector3.FORWARD, bmat, name_ + "_bargeEN", false)
	add_face(Vector3(center.x - hx, y0, center.z + hz), slope_w, Vector3(0, -barge_width, 0), Vector3.BACK, bmat, name_ + "_bargeWS", false)
	add_face(Vector3(center.x - hx, y0, center.z - hz), slope_w, Vector3(0, -barge_width, 0), Vector3.FORWARD, bmat, name_ + "_bargeWN", false)
	aabbs.append(AABB(Vector3(center.x - hx, y0, center.z - hz), Vector3(2 * hx, rise, 2 * hz)))


# ---- 生成 ------------------------------------------------------------------------
## cache: {"dir": "res://cache/fields/F05", "load": true/false}。load なら既存の PNG を読み、無ければ焼いて保存する。
func finalize(baker: AoBaker, cache: Dictionary = {}) -> void:
	if baker != null:
		baker.occluders = aabbs.duplicate()
		baker.texel_per_m = ao_texel
	var cache_dir: String = cache.get("dir", "")
	var use_cache := cache_dir != ""
	if use_cache:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var idx := 0
	for f in faces:
		var mi := MeshInstance3D.new()
		mi.name = f["name"]
		var mat: Material = f["mat"]
		if f["ao"] and baker != null and mat is StandardMaterial3D:
			var img: Image = null
			var cpath := "%s/ao_%04d.png" % [cache_dir, idx]
			if use_cache and cache.get("load", false) and FileAccess.file_exists(cpath):
				img = Image.new()
				img.load_png_from_buffer(FileAccess.get_file_as_bytes(cpath))
				var conv := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RF)
				for y in img.get_height():
					for x in img.get_width():
						var v := img.get_pixel(x, y).r
						conv.set_pixel(x, y, Color(v, v, v))
				img = conv
			if img == null:
				img = baker.bake_face(f["origin"], f["u"], f["v"], f["normal"], f["skip_ground"])
				if use_cache:
					var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
					for y in img.get_height():
						for x in img.get_width():
							var v := img.get_pixel(x, y).r
							out.set_pixel(x, y, Color(v, v, v, 1))
					out.save_png(ProjectSettings.globalize_path(cpath))
			idx += 1
			if debug_ao:
				var acc := 0.0
				for y in img.get_height():
					for x in img.get_width():
						acc += img.get_pixel(x, y).r
				print("AO %-16s mean=%.2f (%dx%d)" % [f["name"], acc / float(img.get_width() * img.get_height()), img.get_width(), img.get_height()])
			mat = AoBaker.apply_to(mat as StandardMaterial3D, baker.to_texture(img))
		mi.mesh = _quad4_mesh(f) if f.has("pts") else (_tri_mesh(f) if f["tri"] else _quad_mesh(f))
		mi.material_override = mat
		root.add_child(mi)


static func _quad_mesh(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o: Vector3 = f["origin"]
	var u: Vector3 = f["u"]
	var v: Vector3 = f["v"]
	var lu := u.length()
	var lv := v.length()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for c in corners:
		st.set_normal(f["normal"])
		st.set_uv(Vector2(c.x * lu, (1.0 - c.y) * lv))   # m 単位。v は上が 0（テクスチャの上端が壁の上端）
		st.set_uv2(c)
		st.add_vertex(o + u * c.x + v * c.y)
	st.add_index(0); st.add_index(1); st.add_index(2)
	st.add_index(0); st.add_index(2); st.add_index(3)
	return st.commit()


static func _tri_mesh(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o: Vector3 = f["origin"]
	var u: Vector3 = f["u"]
	var v: Vector3 = f["v"]
	var lu := u.length()
	var lv := v.length()
	var pts := [o, o + u, o + u * 0.5 + v]
	var uvs := [Vector2(0, lv), Vector2(lu, lv), Vector2(lu * 0.5, 0)]
	var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]
	for i in 3:
		st.set_normal(f["normal"])
		st.set_uv(uvs[i])
		st.set_uv2(uv2[i])
		st.add_vertex(pts[i])
	st.add_index(0); st.add_index(1); st.add_index(2)
	return st.commit()


static func _quad4_mesh(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = f["pts"]
	var o: Vector3 = pts[0]
	var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	# 法線は 2 つの三角形で別々に（坂の折れを滑らかにしすぎない）
	var n0: Vector3 = ((pts[3] - pts[0]) as Vector3).cross(pts[1] - pts[0]).normalized()
	var n1: Vector3 = ((pts[3] - pts[2]) as Vector3).cross(pts[1] - pts[2]).normalized()
	if f.get("flat_normal", false):
		n0 = f["normal"]
		n1 = f["normal"]
	for i in 4:
		var p: Vector3 = pts[i]
		st.set_normal(n0 if i < 2 else n1)
		st.set_uv(Vector2(p.x - o.x, p.z - o.z))   # 地面と同じ m 単位（タイルの境で連続）
		st.set_uv2(uv2[i])
		st.add_vertex(p)
	st.add_index(0); st.add_index(1); st.add_index(2)
	st.add_index(0); st.add_index(2); st.add_index(3)
	return st.commit()
