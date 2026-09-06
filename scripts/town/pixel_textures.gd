class_name PixelTextures
extends RefCounted
## 構造化した手続きドット絵テクスチャ（H-3 の案 (a′)）。ART_SPEC: 28 texel/m、繰り返し周期 6 texel 以上、
## 壁のアルベド 0.50（リニア輝度）、路面は現行値基準。すべて決定的（seed 固定）。
##
## 1 タイルの大きさは m 単位で決める: TILE(32) texel = 32/28 = 1.143 m。材質側で uv1_scale = 1/1.143。
## 「1 画素ごとにアルベドが散る」路面（砂利アスファルト）を主眼に、色は少数のパレットから選ぶ。

const TILE := 32
const TEXELS_PER_M := 28.0

static var _rng := RandomNumberGenerator.new()


static func _seed(s: int) -> void:
	_rng.seed = s


static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## 色相を保って輝度（リニア）を target に揃える
static func _at_lum(c: Color, target: float) -> Color:
	var k := target / maxf(_lum(c), 0.001)
	return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0))


static func _pick(palette: Array, weights: Array) -> Color:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := _rng.randf() * total
	for i in palette.size():
		r -= float(weights[i])
		if r <= 0.0:
			return palette[i]
	return palette[-1]


# ============================================================================
# 路面
# ============================================================================
## 砂利アスファルト。基本色の周りに 5 色のパレットで 1 画素ずつ散らす（暗い骨材と明るい骨材）。
static func asphalt_gravel(size: int = 64, seed: int = 1) -> Image:
	_seed(seed)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := Color(0.42, 0.39, 0.47)
	var pal := [base, base.darkened(0.18), base.darkened(0.36), base.lightened(0.12), base.lightened(0.28), Color(0.30, 0.27, 0.32)]
	var w := [40, 22, 10, 16, 6, 6]
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, w))
	# 補修跡（少し暗い矩形パッチ）と細いひび
	for i in 2:
		var px := _rng.randi_range(0, size - 12)
		var py := _rng.randi_range(0, size - 12)
		var pw := _rng.randi_range(8, 16)
		var ph := _rng.randi_range(6, 12)
		for y in range(py, mini(py + ph, size)):
			for x in range(px, mini(px + pw, size)):
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12))
	_crack(img, Vector2i(_rng.randi_range(0, size - 1), 0), 18, Color(0.24, 0.22, 0.27))
	return img


static func _crack(img: Image, start: Vector2i, length: int, col: Color) -> void:
	var p := start
	var dir := Vector2i(_rng.randi_range(-1, 1), 1)
	for i in length:
		if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			break
		img.set_pixel(p.x, p.y, col)
		if _rng.randf() < 0.35:
			dir.x = clampi(dir.x + _rng.randi_range(-1, 1), -1, 1)
		p += Vector2i(dir.x, 1)


## マンホール（デカール、TILE 内に円）。周囲は透明。
static func manhole(size: int = 24) -> Image:
	_seed(7)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size * 0.5 - 0.5, size * 0.5 - 0.5)
	var r := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c)
			if d <= r:
				var col := Color(0.36, 0.34, 0.33)
				if d > r - 1.5:
					col = Color(0.22, 0.21, 0.21)
				elif int(x + y) % 4 == 0:
					col = Color(0.31, 0.29, 0.28)
				img.set_pixel(x, y, col)
	return img


## 歩道（コンクリート平板。継ぎ目は 16 texel 周期 = 0.57 m）
static func sidewalk(size: int = 32, seed: int = 3) -> Image:
	_seed(seed)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := Color(0.50, 0.47, 0.52)
	var pal := [base, base.darkened(0.08), base.lightened(0.08), base.darkened(0.16)]
	for y in size:
		for x in size:
			var c := _pick(pal, [50, 25, 20, 5])
			if x % 16 == 0 or y % 16 == 0:
				c = base.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


# ============================================================================
# 壁（アルベド 0.50 基準。リニア輝度で揃える）
# ============================================================================
## モルタル（吹き付け）。粒 + うっすら汚れ
static func mortar(size: int = 32, tint: Color = Color(0.80, 0.78, 0.74), albedo: float = 0.50, seed: int = 11) -> Image:
	_seed(seed)
	var base := _at_lum(tint, albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pal := [base, base.darkened(0.06), base.lightened(0.05), base.darkened(0.14)]
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [55, 25, 15, 5]))
	# 下端に雨だれの汚れ
	for y in range(size - 6, size):
		for x in size:
			if _rng.randf() < 0.3:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12))
	return img


## 下見板（横板張り）。板幅 8 texel = 0.29 m。周期 8（ART_SPEC の 6 以上）
static func weatherboard(size: int = 32, tint: Color = Color(0.55, 0.58, 0.72), albedo: float = 0.50, seed: int = 13) -> Image:
	_seed(seed)
	var base := _at_lum(tint, albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var row := y % 8
		for x in size:
			var c := base
			if row == 0:
				c = base.lightened(0.35)       # 板の上端（光が当たる縁）
			elif row == 7:
				c = base.darkened(0.45)        # 板の下の影
			elif row == 6:
				c = base.darkened(0.15)
			if _rng.randf() < 0.08:
				c = c.darkened(0.08)           # 木目の粒
			img.set_pixel(x, y, c)
	return img


## コンクリート（打ち放し。型枠の目地 16 texel 周期、P コン穴）
static func concrete(size: int = 32, albedo: float = 0.50, seed: int = 17) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.72, 0.72, 0.74), albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pal := [base, base.darkened(0.05), base.lightened(0.04), base.darkened(0.10)]
	for y in size:
		for x in size:
			var c := _pick(pal, [60, 20, 15, 5])
			if x % 16 == 0 or y % 16 == 0:
				c = base.darkened(0.3)
			if (x % 16 == 4 or x % 16 == 12) and (y % 16 == 4 or y % 16 == 12):
				c = base.darkened(0.4)
			img.set_pixel(x, y, c)
	return img


## ブロック塀（横 12 × 縦 6 texel のブロック、目地 1 texel）
static func block_fence(size: int = 32, albedo: float = 0.45, seed: int = 19) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.70, 0.69, 0.66), albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var row := y / 8
		for x in size:
			var xx := (x + (8 if row % 2 == 1 else 0)) % 16
			var c := base
			if y % 8 == 0 or xx == 0:
				c = base.darkened(0.35)
			elif _rng.randf() < 0.1:
				c = base.darkened(0.06)
			img.set_pixel(x, y, c)
	return img


## シャッター（横のスラット 8 texel 周期。フェーズ 9 M-1 で 6 → 8）
static func shutter(size: int = 32, albedo: float = 0.40, seed: int = 23) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.62, 0.66, 0.70), albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var row := y % 8
		for x in size:
			var c := base
			if row == 0:
				c = base.lightened(0.25)
			elif row == 5:
				c = base.darkened(0.20)
			elif row == 6:
				c = base.darkened(0.30)
			elif row == 7:
				c = base.darkened(0.45)
			img.set_pixel(x, y, c)
	return img


# ============================================================================
# 屋根
# ============================================================================
## 瓦（桟瓦）。1 枚 8 × 8 texel（0.29 m）、横にずらして重ねる。周期 8
static var roof_contrast := 1.0   # T-1: 瓦の明暗の強さ（1.0 = 従来）。斜めから見た屋根のちらつきの検証用


static func kawara(size: int = 32, tint: Color = Color(0.36, 0.38, 0.46), albedo: float = 0.22, seed: int = 29) -> Image:
	_seed(seed)
	var base := _at_lum(tint, albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var k := roof_contrast
	for y in size:
		var row := y / 8
		var ry := y % 8
		for x in size:
			var xx := (x + (4 if row % 2 == 1 else 0)) % 8
			var c := base
			if ry == 0:
				c = base.lightened(0.30 * k)   # 瓦の上縁（受光）
			elif ry == 7:
				c = base.darkened(0.5 * k)     # 重なりの影
			elif ry == 6:
				c = base.darkened(0.2 * k)
			if xx == 0 and ry > 0 and ry < 6:
				c = base.darkened(0.3 * k)     # 瓦の継ぎ目（桟）
			if _rng.randf() < 0.05:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)
	return img


## トタン（波板）。山 8 texel 周期（フェーズ 9 M-1 で 6 → 8）
static func corrugated(size: int = 32, albedo: float = 0.30, seed: int = 31) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.55, 0.50, 0.42), albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var col := x % 8
			var c := base
			if col == 0:
				c = base.lightened(0.3)
			elif col == 1:
				c = base.lightened(0.12)
			elif col == 4:
				c = base.darkened(0.3)
			elif col == 5:
				c = base.darkened(0.15)
			if _rng.randf() < 0.06:
				c = c.darkened(0.2)           # 錆
			img.set_pixel(x, y, c)
	return img


# ============================================================================
# 単色（比較用）: 従来のノイズ
# ============================================================================
static func noise(size: int, base: Color, grain: float, seed: int = 1) -> Image:
	_seed(seed)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n := _rng.randf_range(-grain, grain)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n * 1.1))
	return img


## 世界テクスチャ（地面・壁・屋根・塀）のフィルタ。フェーズ 14 T-1 で決める。field_scene の filter= で切り替え
static var world_filter: BaseMaterial3D.TextureFilter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
static var _world_mats: Array = []   # 作った材質の一覧（漏れの確認と一括切り替え用）


static func set_world_filter(name: String) -> void:
	match name:
		"nearest_mip": world_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		"nearest_aniso": world_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
		"linear_aniso": world_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"linear_mip": world_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for m in _world_mats:
		m.texture_filter = world_filter


static func register(m: StandardMaterial3D) -> StandardMaterial3D:
	m.texture_filter = world_filter
	_world_mats.append(m)
	return m


static func world_material_count() -> int:
	return _world_mats.size()


## 材質を作る（world_filter + ミップマップ、UV は m 単位: uv1_scale = 1 / タイルの m）
static func material(img: Image, albedo_tex: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var mip := img.duplicate() as Image
	mip.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(mip)
	register(m)
	m.roughness = 0.95
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tile_m := float(img.get_width()) / TEXELS_PER_M
	m.uv1_scale = Vector3(1.0 / tile_m, 1.0 / tile_m, 1.0)
	return m


## 白い線・光る要素用（ART_SPEC 第 4 節: emission 板）
static func emissive_material(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	register(m)
	m.albedo_color = Color(0, 0, 0, 1)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ============================================================================
# フェーズ 8（F05）で追加
# ============================================================================
## 旧街道の舗装。狭い道の古いアスファルト。片側に側溝の蓋（縦の帯 4 texel）。歩車の区別は無い。
static func old_street(size: int = 64, seed: int = 51) -> Image:
	_seed(seed)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var base := Color(0.40, 0.38, 0.43)
	var pal := [base, base.darkened(0.15), base.darkened(0.30), base.lightened(0.10), base.lightened(0.22), Color(0.31, 0.29, 0.33)]
	var w := [42, 22, 10, 14, 5, 7]
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, w))
	# 補修跡（明るめ）と細いひび 2 本
	var px := _rng.randi_range(4, size - 20)
	var py := _rng.randi_range(4, size - 20)
	for y in range(py, py + 10):
		for x in range(px, px + 16):
			img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.10))
	_crack(img, Vector2i(_rng.randi_range(0, size - 1), 0), 24, Color(0.24, 0.22, 0.27))
	_crack(img, Vector2i(_rng.randi_range(0, size - 1), 0), 16, Color(0.26, 0.24, 0.28))
	return img


## 側溝の蓋（コンクリート、6 texel 周期の横筋）。道の端に帯として貼る。
static func gutter(size: int = 32, seed: int = 53) -> Image:
	_seed(seed)
	var base := Color(0.50, 0.49, 0.50)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var c := base
			if y % 8 == 0:
				c = base.darkened(0.35)
			elif y % 8 == 1:
				c = base.lightened(0.10)
			if _rng.randf() < 0.08:
				c = c.darkened(0.08)
			img.set_pixel(x, y, c)
	return img


## 敷地の土間・簡易コンクリート（建物の前後の地面）。低彩度の灰褐色。
static func lot_ground(size: int = 32, seed: int = 55) -> Image:
	_seed(seed)
	var base := Color(0.46, 0.43, 0.42)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pal := [base, base.darkened(0.10), base.lightened(0.08), base.darkened(0.22)]
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [50, 25, 18, 7]))
	return img


## 寺の境内の砂利（明るい灰、粒）。
static func gravel(size: int = 32, seed: int = 57) -> Image:
	_seed(seed)
	var base := Color(0.60, 0.58, 0.57)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pal := [base, base.darkened(0.12), base.lightened(0.10), base.darkened(0.25), base.lightened(0.18)]
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [40, 25, 18, 9, 8]))
	return img


## 参道の石畳（32 texel = 1.14 m に 2×2 枚。目地 1 texel）。
static func stone_path(size: int = 32, seed: int = 59) -> Image:
	_seed(seed)
	var base := Color(0.52, 0.52, 0.54)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var c := base.darkened(_rng.randf() * 0.10)
			if x % 16 == 0 or y % 16 == 0:
				c = base.darkened(0.4)
			img.set_pixel(x, y, c)
	return img


## 白い漆喰壁（寺・土蔵）。アルベド 0.60。うっすら汚れ。
static func plaster(size: int = 32, albedo: float = 0.60, seed: int = 61) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.86, 0.85, 0.80), albedo)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pal := [base, base.darkened(0.04), base.lightened(0.03), base.darkened(0.10)]
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [64, 20, 12, 4]))
	for y in range(size - 5, size):
		for x in size:
			if _rng.randf() < 0.35:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12))
	return img


## なまこ壁（黒い平瓦を斜めに貼り、白い漆喰の目地を盛る）。1 枚 16 texel、目地 2 texel。周期 16。
static func namako(size: int = 32, seed: int = 63) -> Image:
	_seed(seed)
	var tile := Color(0.14, 0.15, 0.18)
	var joint := Color(0.86, 0.85, 0.80)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			# 45° の格子: (x + y) と (x - y) が 16 の倍数の近くなら目地
			var a := posmod(x + y, 16)
			var b := posmod(x - y + 64, 16)
			var c := tile
			if a < 2 or b < 2:
				c = joint
			elif a == 2 or b == 2:
				c = tile.lightened(0.15)
			if _rng.randf() < 0.03:
				c = c.darkened(0.1)
			img.set_pixel(x, y, c)
	return img


## 駄菓子屋の窓明かり（黄色。emission 板に使う）。格子の影を落とす。
## 芝・草地（ニュータウンの緑地、空き地）
static func grass(size: int = 32, seed: int = 69) -> Image:
	_seed(seed)
	var base := Color(0.34, 0.44, 0.24)
	var pal := [base, base.darkened(0.15), base.lightened(0.10), Color(0.42, 0.44, 0.22), base.darkened(0.3)]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [0.45, 0.2, 0.15, 0.12, 0.08]))
	return img


## 生垣（近景の帯の埋め物）。濃い緑の葉のむら、周期なし
static func hedge(size: int = 32, seed: int = 67) -> Image:
	_seed(seed)
	var base := Color(0.22, 0.34, 0.20)
	var pal := [base, base.darkened(0.25), base.darkened(0.45), base.lightened(0.15), Color(0.30, 0.38, 0.18)]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [0.4, 0.2, 0.15, 0.15, 0.1]))
	return img


static func warm_window(size: int = 16, seed: int = 65) -> Image:
	_seed(seed)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var lit := Color(1.0, 0.82, 0.45)
	for y in size:
		for x in size:
			var c := lit
			if x % 8 == 0 or y % 8 == 0:
				c = Color(0.35, 0.28, 0.15)
			img.set_pixel(x, y, c)
	return img


# ============================================================================
# 地形（フェーズ 14 T-2）。規則的な縞の明暗差は抑え、不規則な粒で情報量を出す（ART_SPEC 第 3 節 T-1b）
# ============================================================================
## 擁壁（コンクリート。16 texel ごとに薄い目地）
static func retaining_wall(size: int = 32, seed: int = 81) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.66, 0.66, 0.64), 0.42)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var c := base.darkened(_rng.randf() * 0.08)
			if y % 16 == 0:
				c = base.darkened(0.16)
			elif _rng.randf() < 0.04:
				c = base.darkened(0.18)
			img.set_pixel(x, y, c)
	return img


## 石垣（不揃いの石。目地は薄く）
static func stone_wall(size: int = 32, seed: int = 83) -> Image:
	_seed(seed)
	var base := _at_lum(Color(0.58, 0.57, 0.55), 0.36)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var row := y / 8
		for x in size:
			var xx := (x + (5 if row % 2 == 1 else 0)) % 11
			var c := base.darkened(_rng.randf() * 0.12)
			if y % 8 == 0 or xx == 0:
				c = base.darkened(0.22)
			elif _rng.randf() < 0.06:
				c = base.lightened(0.08)
			img.set_pixel(x, y, c)
	return img


## 岩（周期なしの粒。青灰）
static func rock(size: int = 32, seed: int = 85) -> Image:
	_seed(seed)
	var base := Color(0.40, 0.42, 0.46)
	var pal := [base, base.darkened(0.18), base.darkened(0.32), base.lightened(0.10), Color(0.44, 0.42, 0.40)]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [0.4, 0.22, 0.12, 0.14, 0.12]))
	return img


## 土（土塁・法面・畦。黄褐色、彩度は路面程度）
static func earth(size: int = 32, seed: int = 87) -> Image:
	_seed(seed)
	var base := Color(0.42, 0.36, 0.28)
	var pal := [base, base.darkened(0.15), base.darkened(0.3), base.lightened(0.08), Color(0.38, 0.38, 0.28)]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [0.45, 0.2, 0.1, 0.15, 0.1]))
	return img


## 石段の踏面（stone_path より目地を薄く、粒を粗く）
static func stone_step(size: int = 32, seed: int = 89) -> Image:
	_seed(seed)
	var base := Color(0.50, 0.50, 0.51)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var c := base.darkened(_rng.randf() * 0.12)
			if x % 16 == 0:
				c = base.darkened(0.2)
			elif _rng.randf() < 0.05:
				c = base.lightened(0.06)
			img.set_pixel(x, y, c)
	return img


## 水田（8 月。稲の緑と水面の暗さ。周期なし）
static func paddy(size: int = 32, seed: int = 91) -> Image:
	_seed(seed)
	var base := Color(0.26, 0.36, 0.22)
	var pal := [base, base.darkened(0.2), base.lightened(0.08), Color(0.20, 0.28, 0.30), base.darkened(0.35)]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, _pick(pal, [0.4, 0.2, 0.15, 0.15, 0.1]))
	return img
