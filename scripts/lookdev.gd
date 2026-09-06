extends Node3D
## 「3D背景 + ドット絵スプライト」方式の見え方を確かめる検証シーン。
##
## **ゲーム本体ではない。素材も作り込まない。** 形が分かる仮素材を
## スクリプトで生成し、カメラ・ライト・環境・解像度の設定を切り替えて
## 参考画像（refs/reference_evening.png・Git 管理外）と比べるためのもの。
##
## 起動:
##   godot --path . res://scenes/lookdev.tscn
##   godot --path . res://scenes/lookdev.tscn -- time=evening proj=ortho tonemap=aces
##
## コマンドライン引数（`--` の後、key=value）:
##   time=morning|noon|evening|night   proj=persp|ortho   tonemap=linear|reinhard|filmic|aces|agx
##   dof=0|1  glow=0|1  fog=0|1  ssao=0|1  ssil=0|1  pixel=1|2|3（描画解像度の縮小倍率）
##   soft=0|1|2（影のやわらかさ）  shadowres=2048|4096|8192  omnishadow=0|1
##   billboard=y|full  shaded=0|1  filter=nearest|mipmap  glow_intensity=<f>  glow_threshold=<f>  glow_levels=3,5  emissive_energy=<f>  hud=0|1  sun_elev=<deg>  sun_az=<deg>  exposure=<f>
##   shot=<PNGの絶対パス>   指定フレーム後に撮影して終了
##   frames=<n>             撮影までに待つフレーム数（既定 40）
##
## キー操作（HUD にも表示）:
##   1〜4 時間帯   O 正射影/透視   T トーンマップ   F DOF   G Glow   Z Fog
##   A SSAO   I SSIL   P 描画解像度   B 影のやわらかさ   N 影の解像度
##   L 点光源の影   V ビルボード方式   K スプライトの受光   M テクスチャフィルタ   H HUD
##   [ ] 太陽の高度   , . 太陽の方位   - = 露出   S 撮影(user://)   Esc 終了

const TEXELS_PER_METER := 20.0                 # 世界の 1m あたりの texel 数（全素材で統一）
const PIXEL_SIZE := 1.0 / TEXELS_PER_METER     # Sprite3D.pixel_size と同じ
const BASE_W := 1280
const BASE_H := 720
const DESIGN_H := 360                          # 構図を決める基準の描画高さ（px）。pixel=2 で 1 texel = 1 px
const CAM_DISTANCE := 18.0
const CAM_PITCH_DEG := -42.0
const CAM_YAW_DEG := 34.0
const CAM_TARGET := Vector3(2.0, 0.0, -3.0)   # 街路の少し向こう側を見る（近景の屋根を画面外へ）

const TONEMAPS := {
	"linear": Environment.TONE_MAPPER_LINEAR,
	"reinhard": Environment.TONE_MAPPER_REINHARDT,
	"filmic": Environment.TONE_MAPPER_FILMIC,
	"aces": Environment.TONE_MAPPER_ACES,
	"agx": Environment.TONE_MAPPER_AGX,
}
const TONEMAP_ORDER := ["linear", "reinhard", "filmic", "aces", "agx"]

## 時間帯プリセット。太陽の方位はカメラのヨーに対する相対角（度）。
##   0 = カメラの真後ろから照らす、180 = 真正面（逆光）。
## 参考画像は逆光気味（影が手前右へ伸びる）なので夕方は 180 前後にしてある。
const TIMES := {
	"morning": {
		"sun_elev": 22.0, "sun_az": 205.0, "sun_color": Color(1.0, 0.86, 0.72), "sun_energy": 2.4,
		"sky_top": Color(0.42, 0.58, 0.85), "sky_horizon": Color(0.95, 0.82, 0.70),
		"ground_horizon": Color(0.70, 0.62, 0.58), "ground_bottom": Color(0.25, 0.22, 0.20),
		"ambient": Color(0.62, 0.68, 0.85), "ambient_energy": 0.55,
		"fog_color": Color(0.85, 0.80, 0.78), "fog_density": 0.0015, "fog_energy": 0.8,
		"exposure": 0.9, "lamps": false, "sky_energy": 1.0,
	},
	"noon": {
		"sun_elev": 68.0, "sun_az": 150.0, "sun_color": Color(1.0, 0.98, 0.94), "sun_energy": 2.2,
		"sky_top": Color(0.30, 0.50, 0.90), "sky_horizon": Color(0.72, 0.80, 0.92),
		"ground_horizon": Color(0.62, 0.62, 0.62), "ground_bottom": Color(0.20, 0.20, 0.20),
		"ambient": Color(0.62, 0.70, 0.90), "ambient_energy": 0.70,
		"fog_color": Color(0.80, 0.84, 0.90), "fog_density": 0.001, "fog_energy": 0.6,
		"exposure": 0.85, "lamps": false, "sky_energy": 1.0,
	},
	"evening": {
		"sun_elev": 13.0, "sun_az": 205.0, "sun_color": Color(1.0, 0.84, 0.70), "sun_energy": 4.2,
		"sky_top": Color(0.20, 0.18, 0.34), "sky_horizon": Color(0.85, 0.45, 0.30),
		"ground_horizon": Color(0.30, 0.22, 0.26), "ground_bottom": Color(0.08, 0.07, 0.10),
		"ambient": Color(0.28, 0.34, 0.62), "ambient_energy": 0.18,
		"fog_color": Color(0.55, 0.32, 0.30), "fog_density": 0.0015, "fog_energy": 0.7,
		"exposure": 1.15, "lamps": true, "sky_energy": 0.7,
	},
	"night": {
		"sun_elev": 40.0, "sun_az": 120.0, "sun_color": Color(0.55, 0.65, 0.95), "sun_energy": 0.10,
		"sky_top": Color(0.02, 0.03, 0.07), "sky_horizon": Color(0.08, 0.08, 0.14),
		"ground_horizon": Color(0.05, 0.05, 0.08), "ground_bottom": Color(0.02, 0.02, 0.03),
		"ambient": Color(0.20, 0.26, 0.45), "ambient_energy": 0.10,
		"fog_color": Color(0.06, 0.07, 0.12), "fog_density": 0.003, "fog_energy": 0.5,
		"exposure": 0.9, "lamps": true, "sky_energy": 0.3,
	},
}
const TIME_ORDER := ["morning", "noon", "evening", "night"]

# ---- 現在の設定 --------------------------------------------------------------
var time_name := "evening"
var ortho := false
var tonemap := "filmic"
var dof_on := true
var glow_on := true
var fog_on := true
var ssao_on := false
var ssil_on := false
var pixel_scale := 2            # 1 = 1280x720 そのまま、2 = 640x360 を 2 倍、3 = 426x240 を 3 倍
var soft_level := 0             # 0 硬い / 1 少し / 2 やわらかい
var shadow_res := 4096
var omni_shadows := true
var billboard_full := true      # true: カメラ正対、false: Y 軸回転のみ
var sprites_shaded := true
var mipmaps := false            # true: Nearest + ミップマップ（斜めの面のモアレを抑える）
var hud_on := true
var glow_intensity := 1.0
var glow_threshold := 0.9
var emissive_energy := 4.0     # 発光板の emission 倍率。1〜2 では Glow の閾値(0.9)に届かず光らない。4〜8 が実用域、12 以上は塊になる
var glow_levels := "3,5"        # 有効にする Glow レベル（1 = 1/2 解像度 … 7 = 1/128）。Godot 既定は 3,5
var sun_elev_override := NAN
var sun_az_override := NAN
var exposure_override := NAN

var shot_path := ""
var shot_frames := 40
var _frame := 0

# ---- ノード ------------------------------------------------------------------
var cam: Camera3D
var cam_attr: CameraAttributesPractical
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var lamps: Array[OmniLight3D] = []
var billboards: Array[Node3D] = []    # 各要素は pivot。子に Sprite3D
var sprites: Array[Sprite3D] = []
var emissives: Array[MeshInstance3D] = []   # 発光パネル（無影・HDR）。Glow の効きを見るためのもの
var world_mats: Array[StandardMaterial3D] = []
var hud: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 12345
	_parse_args()
	_build_world()
	_build_sprites()
	_build_lights()
	_build_environment()
	_build_camera()
	_build_hud()
	_apply_all()


# ============================================================================
# 引数
# ============================================================================
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		var k := kv[0].strip_edges()
		var v := kv[1].strip_edges()
		match k:
			"time":
				if TIMES.has(v):
					time_name = v
			"proj":
				ortho = (v == "ortho")
			"tonemap":
				if TONEMAPS.has(v):
					tonemap = v
			"dof":
				dof_on = _b(v)
			"glow":
				glow_on = _b(v)
			"fog":
				fog_on = _b(v)
			"ssao":
				ssao_on = _b(v)
			"ssil":
				ssil_on = _b(v)
			"pixel":
				pixel_scale = clampi(int(v), 1, 4)
			"soft":
				soft_level = clampi(int(v), 0, 2)
			"shadowres":
				shadow_res = clampi(int(v), 1024, 16384)
			"omnishadow":
				omni_shadows = _b(v)
			"billboard":
				billboard_full = (v == "full")
			"shaded":
				sprites_shaded = _b(v)
			"filter":
				mipmaps = (v == "mipmap")
			"glow_intensity":
				glow_intensity = float(v)
			"glow_threshold":
				glow_threshold = float(v)
			"glow_levels":
				glow_levels = v
			"emissive_energy":
				emissive_energy = float(v)
			"hud":
				hud_on = _b(v)
			"sun_elev":
				sun_elev_override = float(v)
			"sun_az":
				sun_az_override = float(v)
			"exposure":
				exposure_override = float(v)
			"shot":
				shot_path = v
			"frames":
				shot_frames = maxi(int(v), 2)


func _b(v: String) -> bool:
	return v == "1" or v == "true" or v == "on"


# ============================================================================
# 仮素材（テクスチャはすべてスクリプト生成・Nearest）
# ============================================================================
func _tex(img: Image) -> ImageTexture:
	var with_mips := img.duplicate() as Image
	with_mips.generate_mipmaps()
	return ImageTexture.create_from_image(with_mips)


## 路面: 灰紫のアスファルト。粒を入れて Nearest の「ドット」が見えるようにする。
func _asphalt_image(size: int, base: Color, grain: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n := _rng.randf_range(-grain, grain)
			var c := Color(base.r + n, base.g + n, base.b + n * 1.1)
			if _rng.randf() < 0.04:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


## 建物の壁: 下見板（横縞）。暗い藍に白っぽい縞。参考画像の建物に寄せた。
func _siding_image(base: Color, line: Color) -> Image:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var c := base
			if y % 8 == 0:
				c = base.lerp(line, 0.6)
			elif y % 8 == 7:
				c = base.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


## 屋根: 瓦っぽい格子。
func _roof_image() -> Image:
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var a := Color(0.13, 0.13, 0.17)
	var b := Color(0.19, 0.19, 0.24)
	for y in s:
		for x in s:
			var c := a if ((int(x / 4) + int(y / 4)) % 2 == 0) else b
			if y % 4 == 3:
				c = c.darkened(0.4)
			img.set_pixel(x, y, c)
	return img


## 8月の草: 灰緑〜黄褐色。
func _grass_image() -> Image:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var t := _rng.randf()
			var c := Color(0.42, 0.44, 0.28).lerp(Color(0.55, 0.48, 0.30), t)
			if _rng.randf() < 0.08:
				c = Color(0.30, 0.33, 0.20)
			img.set_pixel(x, y, c)
	return img


func _mat(img: Image, world_scale: float = 1.0, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = rough
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# 三平面マッピング（ワールド座標）で、どの面にも同じ密度で貼る
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var texels_per_tile := float(img.get_width())
	var meters_per_tile := texels_per_tile / TEXELS_PER_METER * world_scale
	m.uv1_scale = Vector3.ONE / meters_per_tile
	world_mats.append(m)
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, name_: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.name = name_
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi


func _build_world() -> void:
	# 地面（路面）。街路は X 軸方向、幅 7m。
	var asphalt := _mat(_asphalt_image(64, Color(0.42, 0.39, 0.47), 0.06))
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	ground.material_override = asphalt
	ground.name = "Ground"
	add_child(ground)

	# 歩道（少し明るい帯）
	var sidewalk := _mat(_asphalt_image(32, Color(0.50, 0.47, 0.52), 0.04))
	_box(Vector3(120, 0.12, 1.8), Vector3(0, 0.06, 4.4), sidewalk, "SidewalkN")
	_box(Vector3(120, 0.12, 1.8), Vector3(0, 0.06, -4.4), sidewalk, "SidewalkS")

	# 草地（建物の裏側・空き地）
	var grass := _mat(_grass_image())
	_box(Vector3(14, 0.05, 10), Vector3(6, 0.025, 14), grass, "GrassN")
	_box(Vector3(10, 0.05, 8), Vector3(-22, 0.025, -12), grass, "GrassS")

	# 車線の白線（破線）
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.85, 0.82)
	white.roughness = 1.0
	white.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in range(-6, 7):
		var b := _box(Vector3(2.0, 0.02, 0.15), Vector3(i * 5.0, 0.011, 0.0), white, "Lane%d" % (i + 6))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 建物: 直方体 + 屋根の薄い直方体。街路の両側に並べる。
	var wall_a := _mat(_siding_image(Color(0.16, 0.16, 0.24), Color(0.62, 0.62, 0.70)))
	var wall_b := _mat(_siding_image(Color(0.20, 0.18, 0.22), Color(0.55, 0.52, 0.55)))
	var wall_c := _mat(_siding_image(Color(0.30, 0.28, 0.32), Color(0.70, 0.68, 0.72)))
	var roof := _mat(_roof_image())
	var specs := [
		# [x, side(+1 手前/-1 向こう), width, height, depth, wall]
		# 向こう側（カメラから見て奥）は 2 階建て相当で高く、長い影を街路に落とす
		[-12.0, -1, 10.0, 8.0, 8.0, wall_a],   # 参考画像の「手前左の大きな建物」相当
		[-1.0, -1, 6.0, 6.5, 7.0, wall_b],
		[7.0, -1, 5.0, 7.5, 6.0, wall_c],
		[15.0, -1, 8.0, 6.0, 7.0, wall_a],
		[25.0, -1, 6.0, 9.0, 6.0, wall_b],
		# 手前側は低め。多くは画面外に出る
		[-14.0, 1, 7.0, 4.0, 6.0, wall_c],
		[-4.0, 1, 5.0, 3.5, 5.0, wall_a],
		[6.0, 1, 8.0, 4.5, 7.0, wall_b],
		[17.0, 1, 6.0, 4.0, 6.0, wall_c],
	]
	var idx := 0
	for s in specs:
		var x: float = s[0]
		var side: int = s[1]
		var w: float = s[2]
		var h: float = s[3]
		var d: float = s[4]
		var m: Material = s[5]
		var z := side * (3.5 + 1.8 + 1.0 + d * 0.5)
		_box(Vector3(w, h, d), Vector3(x, h * 0.5, z), m, "Bldg%d" % idx)
		_box(Vector3(w + 0.8, 0.35, d + 0.8), Vector3(x, h + 0.175, z), roof, "Roof%d" % idx)
		idx += 1


## Sprite3D 用の板。ドット絵のつもりの仮画像（自販機・街灯・電柱）。
func _sprite_image(kind: String) -> Image:
	var img: Image
	match kind:
		"vending":
			img = Image.create(16, 30, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			img.fill_rect(Rect2i(1, 0, 14, 30), Color(0.12, 0.13, 0.20))
			img.fill_rect(Rect2i(2, 1, 12, 28), Color(0.22, 0.24, 0.34))
			img.fill_rect(Rect2i(3, 2, 8, 12), Color(0.75, 0.95, 0.90))    # 発光パネル
			img.fill_rect(Rect2i(3, 15, 10, 4), Color(0.10, 0.10, 0.15))   # 取り出し口
			img.fill_rect(Rect2i(12, 3, 2, 3), Color(0.9, 0.3, 0.3))       # ボタン
			img.fill_rect(Rect2i(12, 7, 2, 3), Color(0.9, 0.7, 0.3))
		"streetlight":
			img = Image.create(12, 80, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			img.fill_rect(Rect2i(5, 6, 2, 74), Color(0.35, 0.36, 0.40))    # 柱
			img.fill_rect(Rect2i(3, 78, 6, 2), Color(0.30, 0.30, 0.34))    # 台座
			img.fill_rect(Rect2i(2, 3, 8, 4), Color(0.30, 0.30, 0.34))     # 笠
			img.fill_rect(Rect2i(3, 6, 6, 3), Color(1.0, 0.92, 0.70))      # 灯
		"pole":
			img = Image.create(10, 128, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			img.fill_rect(Rect2i(4, 0, 2, 128), Color(0.40, 0.38, 0.36))   # 柱
			img.fill_rect(Rect2i(0, 8, 10, 1), Color(0.30, 0.28, 0.26))    # 腕金
			img.fill_rect(Rect2i(0, 16, 10, 1), Color(0.30, 0.28, 0.26))
			img.fill_rect(Rect2i(1, 6, 1, 3), Color(0.8, 0.8, 0.8))        # 碍子
			img.fill_rect(Rect2i(8, 6, 1, 3), Color(0.8, 0.8, 0.8))
			img.fill_rect(Rect2i(2, 30, 6, 10), Color(0.35, 0.33, 0.30))   # 変圧器
		_:
			img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
	return img


func _add_billboard(kind: String, pos: Vector3) -> void:
	var img := _sprite_image(kind)
	var pivot := Node3D.new()
	pivot.name = "BB_" + kind
	pivot.position = pos
	add_child(pivot)

	var sp := Sprite3D.new()
	sp.texture = _tex(img)
	sp.pixel_size = PIXEL_SIZE
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 向きは pivot で手動制御
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD       # 影を落とせるようにする
	sp.alpha_scissor_threshold = 0.5
	sp.double_sided = true
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sp.shaded = sprites_shaded
	# 足元を pivot に合わせる（centered のまま高さの半分だけ持ち上げる）
	sp.position = Vector3(0, img.get_height() * PIXEL_SIZE * 0.5, 0)
	pivot.add_child(sp)
	billboards.append(pivot)
	sprites.append(sp)


## 発光部分だけを emission 付きの板（QuadMesh）で重ねる。
## Sprite3D の modulate は 8bit に丸められて HDR にならないため、Glow に拾わせるには
## StandardMaterial3D の emission を使う必要がある。
## ドット絵の「光源だけが彩度を持つ」部分をこの方法で光らせる想定の最小構成。
func _add_emissive(pivot: Node3D, size: Vector2i, rect: Rect2i, color: Color, energy: float) -> void:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(rect, color)
	var tex := _tex(img)
	var m := StandardMaterial3D.new()
	# UNSHADED だと emission が無視される（albedo のみ出力）ので通常シェーディングのまま
	# albedo を黒にして emission だけを出す。alpha はテクスチャの alpha を scissor に使う。
	m.albedo_texture = tex
	m.albedo_color = Color(0, 0, 0, 1)
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission = Color(0, 0, 0)
	m.emission_energy_multiplier = energy * emissive_energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size.x, size.y) * PIXEL_SIZE
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, size.y * PIXEL_SIZE * 0.5, 0.005)   # 本体のわずかに手前
	pivot.add_child(mi)
	emissives.append(mi)


func _build_sprites() -> void:
	_add_billboard("vending", Vector3(-4.5, 0.12, -4.9))      # 向こう側歩道、建物の前
	_add_emissive(billboards[-1], Vector2i(16, 30), Rect2i(3, 2, 8, 12), Color(0.75, 0.95, 0.90), 1.8)
	_add_billboard("streetlight", Vector3(2.0, 0.12, 4.0))    # 手前側歩道
	_add_emissive(billboards[-1], Vector2i(12, 80), Rect2i(3, 6, 6, 3), Color(1.0, 0.92, 0.70), 2.5)
	_add_billboard("pole", Vector3(10.5, 0.12, -4.9))         # 向こう側歩道
	_add_billboard("streetlight", Vector3(14.0, 0.12, -4.0))  # 向こう側歩道
	_add_emissive(billboards[-1], Vector2i(12, 80), Rect2i(3, 6, 6, 3), Color(1.0, 0.92, 0.70), 2.5)


# ============================================================================
# ライト
# ============================================================================
func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_split_1 = 0.4
	sun.directional_shadow_fade_start = 0.9
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	add_child(sun)

	# 点光源: 街灯（暖色）と自販機（寒色）
	_add_lamp(Vector3(2.0, 4.6, 4.0), Color(1.0, 0.78, 0.48), 5.0, 11.0, 1.6)    # 街灯 1
	_add_lamp(Vector3(-4.5, 1.3, -4.2), Color(0.62, 0.92, 1.0), 1.6, 5.0, 1.8)   # 自販機
	_add_lamp(Vector3(14.0, 4.6, -4.0), Color(1.0, 0.78, 0.48), 5.0, 11.0, 1.6)  # 街灯 2


func _add_lamp(pos: Vector3, color: Color, energy: float, range_: float, atten: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_
	l.omni_attenuation = atten
	l.shadow_enabled = omni_shadows
	l.shadow_bias = 0.05
	add_child(l)
	lamps.append(l)


# ============================================================================
# 環境・カメラ・HUD
# ============================================================================
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_white = 1.0
	env.glow_intensity = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE   # SOFTLIGHT は低解像度ではほぼ見えない
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.4
	env.ssao_radius = 1.5
	env.ssao_intensity = 2.0
	env.ssil_intensity = 1.0
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.5
	cam.far = 200.0
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_distance = CAM_DISTANCE + 8.0
	cam_attr.dof_blur_far_transition = 14.0
	cam_attr.dof_blur_near_distance = CAM_DISTANCE - 9.0
	cam_attr.dof_blur_near_transition = 6.0
	cam_attr.dof_blur_amount = 0.25
	cam.attributes = cam_attr
	add_child(cam)
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAM_PITCH_DEG), deg_to_rad(CAM_YAW_DEG), 0.0))
	var target := CAM_TARGET
	cam.position = target + basis.z * CAM_DISTANCE   # basis.z はカメラの後ろ向き
	cam.look_at(target, Vector3.UP)
	cam.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(8, 6)
	hud.add_theme_font_size_override("font_size", 13)
	hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)


# ============================================================================
# 設定の適用
# ============================================================================
func _apply_all() -> void:
	_apply_pixel_scale()
	_apply_time()
	_apply_camera()
	_apply_env_toggles()
	_apply_shadows()
	_apply_sprites()
	_update_hud()


func _apply_pixel_scale() -> void:
	var win := get_window()
	if pixel_scale <= 1:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		win.content_scale_size = Vector2i(BASE_W, BASE_H)
		win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	else:
		# 低解像度で描いて整数倍に拡大する。3D も 2D もまとめて拡大される。
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		win.content_scale_size = Vector2i(BASE_W / pixel_scale, BASE_H / pixel_scale)
		win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	# 内部で使うアンチエイリアスは切る（ドットの縁を保つ）
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0


func _render_height() -> int:
	return BASE_H / maxi(pixel_scale, 1)


func _apply_time() -> void:
	var t: Dictionary = TIMES[time_name]
	var elev: float = t["sun_elev"] if is_nan(sun_elev_override) else sun_elev_override
	var az: float = t["sun_az"] if is_nan(sun_az_override) else sun_az_override
	# 方位はカメラのヨーに対する相対角。0 = カメラの背後から、180 = 正面から（逆光）。
	sun.rotation_degrees = Vector3(-elev, CAM_YAW_DEG + az, 0.0)
	sun.light_color = t["sun_color"]
	sun.light_energy = t["sun_energy"]
	sun.visible = t["sun_energy"] > 0.0

	sky_mat.sky_top_color = t["sky_top"]
	sky_mat.sky_horizon_color = t["sky_horizon"]
	sky_mat.ground_horizon_color = t["ground_horizon"]
	sky_mat.ground_bottom_color = t["ground_bottom"]
	sky_mat.energy_multiplier = t["sky_energy"]
	env.ambient_light_color = t["ambient"]
	env.ambient_light_energy = t["ambient_energy"]
	env.fog_light_color = t["fog_color"]
	env.fog_density = t["fog_density"]
	env.fog_light_energy = t["fog_energy"]
	env.tonemap_exposure = t["exposure"] if is_nan(exposure_override) else exposure_override

	var lamps_on: bool = t["lamps"]
	for l in lamps:
		l.visible = lamps_on
	for e in emissives:
		e.visible = lamps_on


func _apply_camera() -> void:
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		# 基準高さ(px) × pixel_size = 画面の縦の世界サイズ。描画高さが DESIGN_H のとき
		# スプライトの 1 texel がちょうど 1 画面ピクセルになる（構図は解像度で変えない）
		cam.size = float(DESIGN_H) * PIXEL_SIZE
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		# 正射影と同じ縦幅になる FOV（距離 CAM_DISTANCE の位置で）
		var half_h := float(DESIGN_H) * PIXEL_SIZE * 0.5
		cam.fov = rad_to_deg(2.0 * atan(half_h / CAM_DISTANCE))
	cam_attr.dof_blur_far_enabled = dof_on and not ortho
	cam_attr.dof_blur_near_enabled = dof_on and not ortho


func _apply_env_toggles() -> void:
	env.tonemap_mode = TONEMAPS[tonemap]
	env.glow_enabled = glow_on
	env.glow_intensity = glow_intensity
	env.glow_hdr_threshold = glow_threshold
	var on := glow_levels.split(",", false)
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, 1.0 if on.has(str(i)) else 0.0)
	env.fog_enabled = fog_on
	env.ssao_enabled = ssao_on
	env.ssil_enabled = ssil_on


func _apply_shadows() -> void:
	RenderingServer.directional_shadow_atlas_set_size(shadow_res, true)
	match soft_level:
		0:
			sun.shadow_blur = 0.0
			sun.light_angular_distance = 0.0
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		1:
			sun.shadow_blur = 1.0
			sun.light_angular_distance = 0.5
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		_:
			sun.shadow_blur = 2.0
			sun.light_angular_distance = 1.5
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	for l in lamps:
		l.shadow_enabled = omni_shadows


func _apply_sprites() -> void:
	var f := BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if mipmaps else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for sp in sprites:
		sp.shaded = sprites_shaded
		sp.texture_filter = f
	for m in world_mats:
		m.texture_filter = f


func _process(_delta: float) -> void:
	_face_billboards()
	if shot_path != "":
		_frame += 1
		if _frame == shot_frames:
			_take_shot(shot_path)
			get_tree().quit()


## ビルボードの向き。full: カメラに正対（足元は地面に固定）。y: Y 軸回転のみ。
func _face_billboards() -> void:
	var cam_basis := cam.global_transform.basis
	for p in billboards:
		if billboard_full:
			p.global_transform.basis = cam_basis
		else:
			var to_cam := cam.global_position - p.global_position
			to_cam.y = 0.0
			if to_cam.length_squared() > 0.0001:
				p.look_at(p.global_position - to_cam, Vector3.UP)


func _take_shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("lookdev: shot %s size=%s err=%d" % [path, img.get_size(), err])


# ============================================================================
# キー操作
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	match k:
		KEY_1:
			time_name = "morning"
		KEY_2:
			time_name = "noon"
		KEY_3:
			time_name = "evening"
		KEY_4:
			time_name = "night"
		KEY_O:
			ortho = not ortho
		KEY_T:
			tonemap = TONEMAP_ORDER[(TONEMAP_ORDER.find(tonemap) + 1) % TONEMAP_ORDER.size()]
		KEY_F:
			dof_on = not dof_on
		KEY_G:
			glow_on = not glow_on
		KEY_Z:
			fog_on = not fog_on
		KEY_A:
			ssao_on = not ssao_on
		KEY_I:
			ssil_on = not ssil_on
		KEY_P:
			pixel_scale = pixel_scale % 3 + 1
		KEY_B:
			soft_level = (soft_level + 1) % 3
		KEY_N:
			shadow_res = 2048 if shadow_res >= 8192 else shadow_res * 2
		KEY_L:
			omni_shadows = not omni_shadows
		KEY_V:
			billboard_full = not billboard_full
		KEY_K:
			sprites_shaded = not sprites_shaded
		KEY_M:
			mipmaps = not mipmaps
		KEY_H:
			hud_on = not hud_on
		KEY_BRACKETLEFT:
			sun_elev_override = _cur_elev() - 2.0
		KEY_BRACKETRIGHT:
			sun_elev_override = _cur_elev() + 2.0
		KEY_COMMA:
			sun_az_override = _cur_az() - 5.0
		KEY_PERIOD:
			sun_az_override = _cur_az() + 5.0
		KEY_MINUS:
			exposure_override = _cur_exposure() * 0.9
		KEY_EQUAL:
			exposure_override = _cur_exposure() / 0.9
		KEY_S:
			var p := "user://lookdev_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
			_take_shot(p)
			print("saved: ", ProjectSettings.globalize_path(p))
			return
		KEY_ESCAPE:
			get_tree().quit()
			return
		_:
			return
	if k in [KEY_1, KEY_2, KEY_3, KEY_4]:
		sun_elev_override = NAN
		sun_az_override = NAN
		exposure_override = NAN
	_apply_all()


func _cur_elev() -> float:
	return TIMES[time_name]["sun_elev"] if is_nan(sun_elev_override) else sun_elev_override


func _cur_az() -> float:
	return TIMES[time_name]["sun_az"] if is_nan(sun_az_override) else sun_az_override


func _cur_exposure() -> float:
	return TIMES[time_name]["exposure"] if is_nan(exposure_override) else exposure_override


func _update_hud() -> void:
	hud.visible = hud_on
	var rh := _render_height()
	var rw := BASE_W / maxi(pixel_scale, 1)
	var proj_s := ("ORTHO size=%.1fm" % cam.size) if ortho else ("PERSP fov=%.1f" % cam.fov)
	hud.text = "\n".join([
		"[1-4] time=%s   sun elev=%.0f az=%.0f (rel. to camera)   exposure=%.2f" % [time_name, _cur_elev(), _cur_az(), _cur_exposure()],
		"[O] %s   [P] render %dx%d x%d   [T] tonemap=%s" % [proj_s, rw, rh, pixel_scale, tonemap],
		"[F] dof=%s  [G] glow=%s  [Z] fog=%s  [A] ssao=%s  [I] ssil=%s" % [_oo(dof_on and not ortho), _oo(glow_on), _oo(fog_on), _oo(ssao_on), _oo(ssil_on)],
		"[B] shadow soft=%d  [N] shadow res=%d  [L] omni shadows=%s" % [soft_level, shadow_res, _oo(omni_shadows)],
		"[V] billboard=%s  [K] sprites shaded=%s  [M] filter=%s  pixel_size=%.4f (%d texel/m)" % ["full" if billboard_full else "y-axis", _oo(sprites_shaded), "nearest+mipmap" if mipmaps else "nearest", PIXEL_SIZE, int(TEXELS_PER_METER)],
		"[ ] sun elev  , . sun az  - = exposure  [S] screenshot  [H] hud  [Esc] quit",
	])


func _oo(b: bool) -> String:
	return "on" if b else "off"
