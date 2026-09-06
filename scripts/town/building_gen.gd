class_name BuildingGen
extends RefCounted
## 建物をスクリプトで生成する（H-1 の案 A）。箱・切妻屋根・板（窓枠・看板）の組み合わせ。
## 面ごとに MeshInstance3D を作り、UV は m 単位（材質の uv1_scale でタイル化）、UV2 は 0..1（AO 用）。
## 生成は 2 段: add_* で面を登録 → finalize(baker) で AO を焼いて Mesh にする。
## 遮蔽物（AABB）は登録した箱と屋根から自動で集める。

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


## 直方体（4 壁 + 天面）。center は底面中心。
func add_box(center: Vector3, size: Vector3, wall: Material, top: Material, name_: String, occlude := true, with_top := true) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := center.y
	add_face(Vector3(center.x - hx, y0, center.z + hz), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), Vector3.BACK, wall, name_ + "_S")
	add_face(Vector3(center.x + hx, y0, center.z - hz), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3.FORWARD, wall, name_ + "_N")
	add_face(Vector3(center.x + hx, y0, center.z + hz), Vector3(0, 0, -size.z), Vector3(0, size.y, 0), Vector3.RIGHT, wall, name_ + "_E")
	add_face(Vector3(center.x - hx, y0, center.z - hz), Vector3(0, 0, size.z), Vector3(0, size.y, 0), Vector3.LEFT, wall, name_ + "_W")
	if with_top:
		add_face(Vector3(center.x - hx, y0 + size.y, center.z - hz), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), Vector3.UP, top, name_ + "_top", true, true)
	if occlude:
		aabbs.append(AABB(Vector3(center.x - hx, y0, center.z - hz), size))


## 切妻屋根。棟は X 方向。base_y に軒、rise だけ上がる。overhang は軒の出。
func add_gable_roof(center: Vector3, size_x: float, size_z: float, rise: float, roof: Material, gable_wall: Material, name_: String, overhang := 0.5, thickness := 0.12) -> void:
	var hx := size_x * 0.5 + overhang
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
	aabbs.append(AABB(Vector3(center.x - hx, y0, center.z - hz), Vector3(2 * hx, rise, 2 * hz)))


## 壁面に貼る板（窓・看板・扉）。wall_origin/u/v は壁面の座標系、(ox, oy) は壁面上の位置 (m)、(w, h) は大きさ。
func add_plate(wall_origin: Vector3, wall_u: Vector3, wall_v: Vector3, normal: Vector3, ox: float, oy: float, w: float, h: float, mat: Material, name_: String, lift := 0.02) -> void:
	var ud := wall_u.normalized()
	var vd := wall_v.normalized()
	var o := wall_origin + ud * ox + vd * oy + normal * lift
	add_face(o, ud * w, vd * h, normal, mat, name_, false)


## 窓: 暗いガラス + 白い枠（emission 板、ART_SPEC 第 4 節）
func add_window(wall_origin: Vector3, wall_u: Vector3, wall_v: Vector3, normal: Vector3, ox: float, oy: float, w: float, h: float, glass: Material, frame: Material, name_: String, bar := 0.06) -> void:
	add_plate(wall_origin, wall_u, wall_v, normal, ox, oy, w, h, glass, name_ + "_glass", 0.02)
	add_plate(wall_origin, wall_u, wall_v, normal, ox, oy, w, bar, frame, name_ + "_f0", 0.03)
	add_plate(wall_origin, wall_u, wall_v, normal, ox, oy + h - bar, w, bar, frame, name_ + "_f1", 0.03)
	add_plate(wall_origin, wall_u, wall_v, normal, ox, oy, bar, h, frame, name_ + "_f2", 0.03)
	add_plate(wall_origin, wall_u, wall_v, normal, ox + w - bar, oy, bar, h, frame, name_ + "_f3", 0.03)
	add_plate(wall_origin, wall_u, wall_v, normal, ox + w * 0.5 - bar * 0.5, oy, bar, h, frame, name_ + "_f4", 0.03)


# ---- 生成 ------------------------------------------------------------------------
func finalize(baker: AoBaker) -> void:
	if baker != null:
		baker.occluders = aabbs.duplicate()
		baker.texel_per_m = ao_texel
	for f in faces:
		var mi := MeshInstance3D.new()
		mi.name = f["name"]
		var mat: Material = f["mat"]
		if f["ao"] and baker != null and mat is StandardMaterial3D:
			var img := baker.bake_face(f["origin"], f["u"], f["v"], f["normal"], f["skip_ground"])
			if debug_ao:
				var acc := 0.0
				for y in img.get_height():
					for x in img.get_width():
						acc += img.get_pixel(x, y).r
				print("AO %-16s mean=%.2f (%dx%d)" % [f["name"], acc / float(img.get_width() * img.get_height()), img.get_width(), img.get_height()])
			mat = AoBaker.apply_to(mat as StandardMaterial3D, baker.to_texture(img))
		mi.mesh = _tri_mesh(f) if f["tri"] else _quad_mesh(f)
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
