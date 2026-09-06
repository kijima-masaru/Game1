extends Node3D
## 街路 1 ブロックの縦切り（フェーズ 6）。lookdev（layout=empty）を土台に、本番用の作りで建物 3 棟と路面を置く。
##
##   godot --path . res://scenes/block.tscn -- time=evening
##   引数（lookdev の引数もそのまま使える: time / shot / target / fov / hud など）
##     tex=proc|pixellab|noise   テクスチャ（構造化手続き / PixelLab タイル / 従来ノイズ）
##     street_angle=<deg>        街路の軸とカメラ前方のなす角（0 = 真っ直ぐ奥、90 = 横切る）。既定 30（lookdev v2 と同じ）
##     objects=0|1               PixelLab のオブジェクトをビルボードで置く
##     player=x,z                主人公の板を置く
##     occl=none|fade|noroof|silhouette   手前の建物による遮蔽への対処（H-6b）
##     footprint=1               1 画面に写る地面の範囲を出力（H-6c）

const CURB_Z := 3.5          # 車道の端
const WALK_W := 1.8          # 歩道幅
const LOT_Z := CURB_Z + WALK_W + 0.8   # 建物の前面（歩道の 0.8 m 奥）

var lookdev: Node3D
var block: Node3D
var gen: BuildingGen
var baker: AoBaker
var tex_mode := "proc"
var street_angle := 30.0
var with_objects := true
var player_pos := Vector3.INF
var occl := "none"
var want_footprint := false
var no_ao := false
var player_pivot: Node3D
var player_sprite: Sprite3D
var silhouette: Sprite3D
var billboards: Array[Node3D] = []
var buildings := {}          # name -> {aabb, faces: [MeshInstance3D], mats: [StandardMaterial3D]}
var mats := {}
var _footprint_done := false
var _playerpx_done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"tex":
				tex_mode = kv[1]
			"street_angle":
				street_angle = float(kv[1])
			"objects":
				with_objects = kv[1] == "1"
			"player":
				var xz := kv[1].split(",")
				player_pos = Vector3(float(xz[0]), 0.12, float(xz[1]))
			"occl":
				occl = kv[1]
			"footprint":
				want_footprint = kv[1] == "1"
			"noao":
				no_ao = kv[1] == "1"
	lookdev = load("res://scenes/lookdev.tscn").instantiate()
	# layout=empty を lookdev の引数に頼らず直接指定
	lookdev.layout = "empty"
	add_child(lookdev)
	var has_target := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("target="):
			has_target = true
	if not has_target:
		lookdev.cam_target = Vector3(-3.0, 0.0, -1.0)
		lookdev._apply_camera()
	_build_materials()
	_build_block()
	if with_objects:
		_place_objects()
	if player_pos != Vector3.INF:
		_place_player()


# ============================================================================
# 材質
# ============================================================================
func _tex_from_file(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return img


func _build_materials() -> void:
	var PT := PixelTextures
	match tex_mode:
		"noise":
			mats["asphalt"] = PT.material(PT.noise(64, Color(0.42, 0.39, 0.47), 0.06))
			mats["sidewalk"] = PT.material(PT.noise(32, Color(0.50, 0.47, 0.52), 0.04))
			mats["wall_shop"] = PT.material(PT.noise(32, Color(0.44, 0.47, 0.58), 0.03))
			mats["wall_house"] = PT.material(PT.noise(32, Color(0.62, 0.60, 0.57), 0.03))
			mats["wall_concrete"] = PT.material(PT.noise(32, Color(0.60, 0.60, 0.62), 0.03))
			mats["roof_kawara"] = PT.material(PT.noise(32, Color(0.22, 0.23, 0.29), 0.03))
			mats["roof_flat"] = PT.material(PT.noise(32, Color(0.38, 0.38, 0.40), 0.03))
			mats["roof_corrugated"] = PT.material(PT.noise(32, Color(0.40, 0.36, 0.30), 0.03))
			mats["fence"] = PT.material(PT.noise(32, Color(0.55, 0.54, 0.52), 0.03))
			mats["shutter"] = PT.material(PT.noise(32, Color(0.45, 0.48, 0.52), 0.03))
		"pixellab":
			mats["asphalt"] = PT.material(_tex_from_file("res://assets/pixellab/tiles/tile_asphalt_curb.png"))
			mats["sidewalk"] = PT.material(_tex_from_file("res://assets/pixellab/tiles/tile_concrete_grass.png"))
			mats["wall_shop"] = PT.material(PT.weatherboard())
			mats["wall_house"] = PT.material(PT.mortar())
			mats["wall_concrete"] = PT.material(PT.concrete())
			mats["roof_kawara"] = PT.material(_tex_from_file("res://assets/pixellab/tiles/roof_kawara.png"))
			mats["roof_flat"] = PT.material(_tex_from_file("res://assets/pixellab/tiles/roof_flat_concrete.png"))
			mats["roof_corrugated"] = PT.material(_tex_from_file("res://assets/pixellab/tiles/roof_corrugated.png"))
			mats["fence"] = PT.material(PT.block_fence())
			mats["shutter"] = PT.material(PT.shutter())
		_:
			mats["asphalt"] = PT.material(PT.asphalt_gravel())
			mats["sidewalk"] = PT.material(PT.sidewalk())
			mats["wall_shop"] = PT.material(PT.weatherboard())
			mats["wall_house"] = PT.material(PT.mortar())
			mats["wall_concrete"] = PT.material(PT.concrete())
			mats["roof_kawara"] = PT.material(PT.kawara())
			mats["roof_flat"] = PT.material(PT.concrete(32, 0.35, 41))
			mats["roof_corrugated"] = PT.material(PT.corrugated())
			mats["fence"] = PT.material(PT.block_fence())
			mats["shutter"] = PT.material(PT.shutter())
	mats["glass"] = PT.material(PT.noise(8, Color(0.10, 0.12, 0.18), 0.02))
	mats["frame"] = PT.emissive_material(Color(0.92, 0.92, 0.90), 1.0)     # 白い窓枠（unshaded 相当）
	mats["sign"] = PT.emissive_material(Color(0.95, 0.94, 0.90), 1.1)
	mats["lane"] = PT.emissive_material(Color(0.88, 0.88, 0.85), 0.9)      # 白線
	mats["soffit"] = PT.material(PT.noise(16, Color(0.30, 0.29, 0.30), 0.02))
	var mh := StandardMaterial3D.new()
	if tex_mode == "pixellab":
		var mimg := _tex_from_file("res://assets/pixellab/deco/deco_manhole.png")
		mh.albedo_texture = ImageTexture.create_from_image(mimg)
	else:
		mh.albedo_texture = ImageTexture.create_from_image(PT.manhole())
	mh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mh.alpha_scissor_threshold = 0.5
	mh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mh.roughness = 1.0
	mh.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mats["manhole"] = mh


# ============================================================================
# 街区
# ============================================================================
func _build_block() -> void:
	block = Node3D.new()
	block.name = "Block"
	add_child(block)
	gen = BuildingGen.new(block)
	gen.debug_ao = OS.get_cmdline_user_args().has("debug_ao=1")
	baker = AoBaker.new([], 18.0, 24)

	# --- 向こう側（-Z）: 商店・民家・ビル ---
	_shop(Vector3(-3.0, 0.0, -LOT_Z - 3.5))
	_house(Vector3(7.5, 0.0, -LOT_Z - 3.5 - 2.5))
	_concrete(Vector3(-12.5, 0.0, -LOT_Z - 4.0))
	# --- 手前側（+Z）: 枠にする 2 棟（同じ作りの簡素な民家・作業場） ---
	_simple(Vector3(-9.0, 0.0, LOT_Z + 3.0), Vector3(7.0, 3.6, 6.0), mats["wall_house"], "roof_kawara", 1.4, "near_house")
	_simple(Vector3(3.0, 0.0, LOT_Z + 3.5), Vector3(7.0, 4.8, 7.0), mats["wall_shop"], "roof_corrugated", 0.9, "near_work")

	# --- 路面・歩道・白線・マンホール ---
	var half_x := 30.0
	var half_z := 20.0
	gen.add_face(Vector3(-half_x, 0, -half_z), Vector3(2 * half_x, 0, 0), Vector3(0, 0, 2 * half_z), Vector3.UP, mats["asphalt"], "ground", true, true)
	for side in [-1.0, 1.0]:
		var zc: float = float(side) * (CURB_Z + WALK_W * 0.5)
		gen.add_box(Vector3(0, 0, zc), Vector3(2 * half_x, 0.12, WALK_W), mats["sidewalk"], mats["sidewalk"], "sidewalk%s" % ("N" if side < 0 else "S"), false)
	for i in range(-6, 7):
		gen.add_plate(Vector3(-half_x, 0, -half_z), Vector3(2 * half_x, 0, 0), Vector3(0, 0, 2 * half_z), Vector3.UP, half_x + i * 5.0 - 1.0, half_z - 0.08, 2.0, 0.16, mats["lane"], "lane%d" % (i + 6), 0.012)
	gen.add_plate(Vector3(-half_x, 0, -half_z), Vector3(2 * half_x, 0, 0), Vector3(0, 0, 2 * half_z), Vector3.UP, half_x - 6.5, half_z - 2.0 - 0.43, 0.86, 0.86, mats["manhole"], "manhole", 0.01)

	gen.finalize(null if no_ao else baker)
	_collect_buildings()
	# 街路の向き（H-6a）: カメラ前方に対して street_angle。lookdev v2 の配置は 30° 相当
	var yaw: float = lookdev.cam_yaw_deg
	var fwd := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
	var dir := fwd.rotated(Vector3.UP, deg_to_rad(street_angle))
	block.rotation.y = atan2(-dir.z, dir.x) - PI   # ローカル -X（奥）を dir に向ける


func _collect_buildings() -> void:
	for mi in block.get_children():
		if not (mi is MeshInstance3D):
			continue
		var n: String = mi.name
		var key := n.get_slice("_", 0)
		if key in ["ground", "lane", "manhole", "sidewalkN", "sidewalkS"] or n.begins_with("lane") or n.begins_with("sidewalk"):
			continue
		if not buildings.has(key):
			buildings[key] = {"faces": [], "aabb": AABB()}
		buildings[key]["faces"].append(mi)
	# AABB は gen.aabbs から名前順に対応できないので、面の頂点から作る
	for key in buildings:
		var bb := AABB()
		var first := true
		for mi in buildings[key]["faces"]:
			var m: ArrayMesh = mi.mesh
			var arr := m.surface_get_arrays(0)
			for v in arr[Mesh.ARRAY_VERTEX]:
				if first:
					bb = AABB(v, Vector3.ZERO)
					first = false
				else:
					bb = bb.expand(v)
		buildings[key]["aabb"] = bb


## 2 階建ての商店。1 階正面にシャッターと引き戸、2 階に窓、看板。
func _shop(pos: Vector3) -> void:
	var size := Vector3(7.0, 6.0, 7.0)
	gen.add_box(pos, size, mats["wall_shop"], mats["wall_shop"], "shop", true, false)
	gen.add_gable_roof(Vector3(pos.x, pos.y + size.y, pos.z), size.x, size.z, 1.6, mats["roof_kawara"], mats["wall_shop"], "shop", 0.6)
	# 正面（+Z 面）: origin = 左下 (x - hx, y0, z + hz)、u = +X
	var o := Vector3(pos.x - size.x * 0.5, pos.y, pos.z + size.z * 0.5)
	var u := Vector3(size.x, 0, 0)
	var v := Vector3(0, size.y, 0)
	gen.add_plate(o, u, v, Vector3.BACK, 0.4, 0.05, 3.6, 2.7, mats["shutter"], "shop_shutter")
	gen.add_window(o, u, v, Vector3.BACK, 4.4, 0.05, 1.6, 2.2, mats["glass"], mats["frame"], "shop_door")
	gen.add_plate(o, u, v, Vector3.BACK, 0.5, 3.0, 6.0, 0.55, mats["sign"], "shop_sign")
	gen.add_window(o, u, v, Vector3.BACK, 0.8, 3.9, 1.8, 1.2, mats["glass"], mats["frame"], "shop_w1")
	gen.add_window(o, u, v, Vector3.BACK, 4.3, 3.9, 1.8, 1.2, mats["glass"], mats["frame"], "shop_w2")
	# 側面（+X 面）にも窓
	var oe := Vector3(pos.x + size.x * 0.5, pos.y, pos.z + size.z * 0.5)
	gen.add_window(oe, Vector3(0, 0, -size.z), v, Vector3.RIGHT, 1.5, 3.9, 1.6, 1.2, mats["glass"], mats["frame"], "shop_w3")


## 平屋の民家。瓦屋根、正面に窓と引き戸、前庭とブロック塀。
func _house(pos: Vector3) -> void:
	var size := Vector3(8.0, 3.0, 7.0)
	gen.add_box(pos, size, mats["wall_house"], mats["wall_house"], "house", true, false)
	gen.add_gable_roof(Vector3(pos.x, pos.y + size.y, pos.z), size.x, size.z, 1.7, mats["roof_kawara"], mats["wall_house"], "house", 0.8)
	var o := Vector3(pos.x - size.x * 0.5, pos.y, pos.z + size.z * 0.5)
	var u := Vector3(size.x, 0, 0)
	var v := Vector3(0, size.y, 0)
	gen.add_window(o, u, v, Vector3.BACK, 0.7, 0.9, 2.0, 1.1, mats["glass"], mats["frame"], "house_w1")
	gen.add_window(o, u, v, Vector3.BACK, 3.2, 0.05, 1.7, 2.0, mats["glass"], mats["frame"], "house_door")
	gen.add_window(o, u, v, Vector3.BACK, 5.6, 0.9, 1.8, 1.1, mats["glass"], mats["frame"], "house_w2")
	# ブロック塀（正面から 2.5 m 手前、門の隙間 1.4 m）。細い箱。
	var fz := pos.z + size.z * 0.5 + 2.5
	var fh := 1.2
	var gate_x := pos.x + 0.5
	gen.add_box(Vector3((pos.x - size.x * 0.5 - 0.5 + gate_x - 0.7) * 0.5, pos.y, fz), Vector3((gate_x - 0.7) - (pos.x - size.x * 0.5 - 0.5), fh, 0.15), mats["fence"], mats["fence"], "fence_a", true)
	gen.add_box(Vector3((gate_x + 0.7 + pos.x + size.x * 0.5 + 0.5) * 0.5, pos.y, fz), Vector3((pos.x + size.x * 0.5 + 0.5) - (gate_x + 0.7), fh, 0.15), mats["fence"], mats["fence"], "fence_b", true)
	gen.add_box(Vector3(pos.x - size.x * 0.5 - 0.5, pos.y, fz - 1.25), Vector3(0.15, fh, 2.5), mats["fence"], mats["fence"], "fence_c", true)
	gen.add_box(Vector3(pos.x + size.x * 0.5 + 0.5, pos.y, fz - 1.25), Vector3(0.15, fh, 2.5), mats["fence"], mats["fence"], "fence_d", true)


## 3 階建てのコンクリートのビル。陸屋根とパラペット、屋上の水槽、窓の格子、入口。
func _concrete(pos: Vector3) -> void:
	var size := Vector3(6.0, 9.6, 8.0)
	gen.add_box(pos, size, mats["wall_concrete"], mats["roof_flat"], "bldg", true, true)
	var top_y := pos.y + size.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	gen.add_box(Vector3(pos.x, top_y, pos.z + hz - 0.15), Vector3(size.x, 0.6, 0.3), mats["wall_concrete"], mats["wall_concrete"], "bldg_ppS", false)
	gen.add_box(Vector3(pos.x, top_y, pos.z - hz + 0.15), Vector3(size.x, 0.6, 0.3), mats["wall_concrete"], mats["wall_concrete"], "bldg_ppN", false)
	gen.add_box(Vector3(pos.x + hx - 0.15, top_y, pos.z), Vector3(0.3, 0.6, size.z), mats["wall_concrete"], mats["wall_concrete"], "bldg_ppE", false)
	gen.add_box(Vector3(pos.x - hx + 0.15, top_y, pos.z), Vector3(0.3, 0.6, size.z), mats["wall_concrete"], mats["wall_concrete"], "bldg_ppW", false)
	gen.add_box(Vector3(pos.x + 1.2, top_y, pos.z - 1.5), Vector3(1.6, 1.4, 1.6), mats["wall_concrete"], mats["roof_flat"], "bldg_tank", false)
	var o := Vector3(pos.x - hx, pos.y, pos.z + hz)
	var u := Vector3(size.x, 0, 0)
	var v := Vector3(0, size.y, 0)
	for fl in 3:
		var y := 0.9 + fl * 3.2
		if fl == 0:
			gen.add_window(o, u, v, Vector3.BACK, 0.6, 0.05, 1.2, 2.3, mats["glass"], mats["frame"], "bldg_door")
			gen.add_window(o, u, v, Vector3.BACK, 3.4, y, 1.8, 1.3, mats["glass"], mats["frame"], "bldg_w0b")
		else:
			gen.add_window(o, u, v, Vector3.BACK, 0.7, y, 1.8, 1.3, mats["glass"], mats["frame"], "bldg_w%da" % fl)
			gen.add_window(o, u, v, Vector3.BACK, 3.4, y, 1.8, 1.3, mats["glass"], mats["frame"], "bldg_w%db" % fl)
	var oe := Vector3(pos.x + hx, pos.y, pos.z + hz)
	for fl in 3:
		gen.add_window(oe, Vector3(0, 0, -size.z), v, Vector3.RIGHT, 1.0 + 3.0 * (fl % 2), 0.9 + fl * 3.2, 1.6, 1.3, mats["glass"], mats["frame"], "bldg_e%d" % fl)


## 簡素な建物（手前の枠用）。
func _simple(pos: Vector3, size: Vector3, wall: Material, roof_key: String, rise: float, name_: String) -> void:
	gen.add_box(pos, size, wall, wall, name_, true, false)
	gen.add_gable_roof(Vector3(pos.x, pos.y + size.y, pos.z), size.x, size.z, rise, mats[roof_key], wall, name_, 0.6)
	var o := Vector3(pos.x - size.x * 0.5, pos.y, pos.z - size.z * 0.5)   # 街路側は -Z 面（手前側の建物）
	gen.add_window(Vector3(pos.x + size.x * 0.5, pos.y, pos.z - size.z * 0.5), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3.FORWARD, 1.0, 0.9, 1.8, 1.1, mats["glass"], mats["frame"], name_ + "_w1")
	gen.add_window(Vector3(pos.x + size.x * 0.5, pos.y, pos.z - size.z * 0.5), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3.FORWARD, 4.2, 0.05, 1.5, 2.0, mats["glass"], mats["frame"], name_ + "_door")


# ============================================================================
# PixelLab オブジェクト（H-4）と主人公（H-5）
# ============================================================================
func _billboard(img: Image, pos: Vector3, name_: String, shaded := true) -> Sprite3D:
	var pivot := Node3D.new()
	pivot.name = "BB_" + name_
	pivot.position = pos
	block.add_child(pivot)
	var sp := Sprite3D.new()
	var tex := ImageTexture.create_from_image(img)
	sp.texture = tex
	sp.pixel_size = lookdev.pixel_size
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.alpha_scissor_threshold = 0.5
	sp.shaded = shaded
	sp.double_sided = true
	sp.set_meta("h", img.get_height())
	pivot.add_child(sp)
	billboards.append(pivot)
	return sp


func _place_objects() -> void:
	var O := "res://assets/pixellab/objects/"
	# 向こう側の歩道（z = -CURB_Z - WALK_W/2 付近）
	var zf := -(CURB_Z + WALK_W * 0.5)
	var zn := CURB_Z + WALK_W * 0.5
	_billboard(_tex_from_file(O + "obj_vending_machine.png"), Vector3(1.4, 0.12, zf), "vending")
	_billboard(_tex_from_file(O + "obj_street_light_led.png"), Vector3(-8.0, 0.12, zn), "light1")
	_billboard(_tex_from_file(O + "obj_utility_pole.png"), Vector3(4.5, 0.12, zf), "pole")
	_billboard(_tex_from_file(O + "obj_kei_car.png"), Vector3(-6.0, 0.05, 1.6), "car")
	_billboard(_tex_from_file(O + "obj_bench.png"), Vector3(10.0, 0.12, zf), "bench")
	_billboard(_tex_from_file(O + "obj_mailbox.png"), Vector3(-1.5, 0.12, zf), "mailbox")
	_billboard(_tex_from_file(O + "obj_road_mirror.png"), Vector3(-15.0, 0.12, zf), "mirror")
	_billboard(_tex_from_file(O + "obj_traffic_cone.png"), Vector3(-11.0, 0.05, 2.8), "cone")
	_billboard(_tex_from_file(O + "obj_planter_box.png"), Vector3(13.0, 0.12, zf), "planter")
	_billboard(_tex_from_file(O + "obj_street_light_mercury.png"), Vector3(6.0, 0.12, zn), "light2")


func _figure_image(body: Color, head: Color, w: int = 16, h: int = 48) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(4, 0, 8, 8), head)
	img.fill_rect(Rect2i(3, 8, 10, 22), body)
	img.fill_rect(Rect2i(3, 30, 4, 18), body.darkened(0.3))
	img.fill_rect(Rect2i(9, 30, 4, 18), body.darkened(0.3))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and (x == 3 or x == 12 or y == 0 or y == h - 1 or (y == 8 and x >= 4 and x <= 11)):
				img.set_pixel(x, y, Color(0.08, 0.08, 0.1))
	return img


func _place_player() -> void:
	var img := _figure_image(Color(0.92, 0.55, 0.30), Color(0.98, 0.85, 0.70))
	player_sprite = _billboard(img, player_pos, "player", false)   # 計測用: 無影で目立つ色
	player_pivot = billboards[-1]
	if occl == "silhouette":
		# 壁越しに見えるシルエット（深度テスト無し、半透明の暗色）。本体は透明パスで後から描き、見える所では本体が勝つ
		silhouette = Sprite3D.new()
		silhouette.texture = player_sprite.texture
		silhouette.pixel_size = player_sprite.pixel_size
		silhouette.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		silhouette.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		silhouette.shaded = false
		silhouette.no_depth_test = true
		silhouette.modulate = Color(0.55, 0.75, 1.0, 0.75)   # 壁越しに読める明るい青
		silhouette.render_priority = 0
		silhouette.double_sided = true
		silhouette.set_meta("h", player_sprite.get_meta("h"))
		player_pivot.add_child(silhouette)
		player_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		player_sprite.render_priority = 1


# ============================================================================
# 更新
# ============================================================================
func _process(_delta: float) -> void:
	var cam: Camera3D = lookdev.cam
	var basis := cam.global_transform.basis
	for p in billboards:
		p.global_transform.basis = basis
		for sp in p.get_children():
			if not (sp is Sprite3D):
				continue
			var base := p.global_position
			var top := base + basis.y * 1.0
			var h_px := absf(cam.unproject_position(base).y - cam.unproject_position(top).y)
			var ratio: float = h_px / float(lookdev.base_texel_per_meter)
			var sc := maxf(round(ratio), 1.0) / maxf(ratio, 0.001)
			sp.scale = Vector3(sc, sc, sc)
			sp.position = Vector3(0, int(sp.get_meta("h")) * float(lookdev.pixel_size) * 0.5 * sc, 0)
	if player_pivot != null and occl in ["fade", "noroof"]:
		_apply_occlusion(cam)
	if player_pivot != null and not _playerpx_done:
		_playerpx_done = true
		var b := player_pivot.global_position
		var sp := cam.unproject_position(b)
		var h := absf(sp.y - cam.unproject_position(b + basis.y * 1.7).y)
		print("PLAYERPX {\"px\":%.1f,\"py\":%.1f,\"h_px\":%.1f}" % [sp.x, sp.y, h])
	if want_footprint and not _footprint_done:
		_footprint_done = true
		_print_footprint(cam)


## カメラと主人公の間にある建物を探して、壁を半透明にするか屋根を消す。
func _apply_occlusion(cam: Camera3D) -> void:
	var from := cam.global_position
	var to := player_pivot.global_position + Vector3(0, 0.9, 0)
	for key in buildings:
		var b: Dictionary = buildings[key]
		var bb: AABB = block.global_transform * b["aabb"]
		var hit := bb.intersects_segment(from, to) != null
		for mi in b["faces"]:
			var n: String = mi.name
			if occl == "noroof":
				if "_roof" in n or n.ends_with("_top") or "_soffit" in n:
					mi.visible = not hit
			else:
				var m := mi.material_override as StandardMaterial3D
				if m == null:
					continue
				if hit and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color = Color(1, 1, 1, 0.35)
					m.cull_mode = BaseMaterial3D.CULL_BACK
				elif not hit and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					m.albedo_color = Color(1, 1, 1, 1)


## 画面の四隅と中央列を地面に投影して、1 画面に写る範囲を出す（H-6c）。
func _print_footprint(cam: Camera3D) -> void:
	var vp := get_viewport().get_visible_rect().size
	var pts := {}
	for name in [["TL", Vector2(0, 0)], ["TR", Vector2(vp.x, 0)], ["BL", Vector2(0, vp.y)], ["BR", Vector2(vp.x, vp.y)], ["C", vp * 0.5], ["TC", Vector2(vp.x * 0.5, 0)], ["BC", Vector2(vp.x * 0.5, vp.y)]]:
		var o := cam.project_ray_origin(name[1])
		var n := cam.project_ray_normal(name[1])
		if absf(n.y) < 1e-6:
			continue
		var t := -o.y / n.y
		var hit := o + n * t
		pts[name[0]] = hit
	var top_w: float = pts["TL"].distance_to(pts["TR"])
	var bot_w: float = pts["BL"].distance_to(pts["BR"])
	var depth: float = pts["TC"].distance_to(pts["BC"])
	var area := 0.5 * (top_w + bot_w) * depth
	print("FOOTPRINT {\"viewport\":[%d,%d],\"top_width_m\":%.2f,\"bottom_width_m\":%.2f,\"depth_m\":%.2f,\"area_m2\":%.1f,\"center\":[%.2f,%.2f],\"TL\":[%.2f,%.2f],\"TR\":[%.2f,%.2f],\"BL\":[%.2f,%.2f],\"BR\":[%.2f,%.2f]}" % [
		int(vp.x), int(vp.y), top_w, bot_w, depth, area, pts["C"].x, pts["C"].z, pts["TL"].x, pts["TL"].z, pts["TR"].x, pts["TR"].z, pts["BL"].x, pts["BL"].z, pts["BR"].x, pts["BR"].z])
