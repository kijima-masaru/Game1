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
##   billboard=y|full  shaded=0|1  filter=nearest|mipmap  glow_intensity=<f>  glow_threshold=<f>  glow_levels=3,5  emissive_energy=<f>  hud=0|1
##   white=<f>（tonemap_white。Reinhard は 1.0 だと恒等写像になる）  lamps=0|1（点光源と発光板の強制 on/off）
##   ambient_mul=<f>（環境光エネルギーの倍率。較正用）  ambient_desat=<f>（環境光の彩度を輝度一定で落とす。0〜1）  wall_albedo=<f>（壁の基準アルベド。未指定はプリセット色）
##   bands=0|1（壁の白い細帯ジオメトリ）  probe=x,z;x,z（路面上の計測点。撮影時に画素値を PROBE 行で出力）
##   probe_grid=1（路面全体の候補点を格子で出力。較正ツールが日向・日陰の芯を選ぶ）
##   fov=<deg>（縦 FOV。距離は基準面で base_texel_per_meter になるよう逆算）  texel=<f>（基準 texel 密度）
##   c1=1（投影検証: 平地と画面上端/中央/下端の同一サイズ板）
##   seq=<dir> seq_frames=60 pan=2.0（等速パンの連番撮影）  snap=0|1（カメラを texel 格子へスナップ）
##   fxaa=0|1  flat=0|1（世界テクスチャを単色にして影のエッジだけを見る）
##   walk=A|B|C|D walk_from=x,z walk_to=x,z seq=<dir> seq_frames=90（E-3b: テストスプライトを奥→手前に歩かせて連番撮影）
##   ao=0|1 ao_power=<f> ao_ray_len=<m> ao_rays=<n> ao_debug=0|1（街区スケールの AO ベイク。E-2）
##   yaw=<deg>（カメラのヨー）  layout=v1|v2（建物配置）  sun_desat=<0-1>（太陽色の彩度を輝度一定で落とす）
##   skylight=0|1 skylight_energy=<f> skylight_angle=<deg> skylight_pitch=<deg> skylight_yaw=<deg>（疑似スカイライト）  sun_elev=<deg>  sun_az=<deg>  exposure=<f>
##   shot=<PNGの絶対パス>   指定フレーム後に撮影して終了
##   frames=<n>             撮影までに待つフレーム数（既定 40）
##
## キー操作（HUD にも表示）:
##   1〜4 時間帯   O 正射影/透視   T トーンマップ   F DOF   G Glow   Z Fog
##   A SSAO   I SSIL   P 描画解像度   B 影のやわらかさ   N 影の解像度
##   L 点光源の影   V ビルボード方式   K スプライトの受光   M テクスチャフィルタ   H HUD
##   [ ] 太陽の高度   , . 太陽の方位   - = 露出   S 撮影(user://)   Esc 終了

## 世界の 1m あたりの texel 数（全素材で統一。PixelLab 素材に合わせて 28）。
## 基準面（画面中央の地面）でこの密度になるようカメラ距離を逆算する。
@export var base_texel_per_meter := 28.0
var pixel_size := 1.0 / 28.0                   # Sprite3D.pixel_size と同じ。_ready で base から再計算
const BASE_W := 1280
const BASE_H := 720
const DESIGN_H := 360                          # 構図を決める基準の描画高さ（px）。pixel=2 で 1 texel = 1 px
var cam_distance := 18.0                        # fov と base_texel_per_meter から _apply_camera で逆算
const ORTHO_DISTANCE := 30.0
const CAM_PITCH_DEG := -42.0
var cam_yaw_deg := 60.0                        # 街路（X 軸）を斜めに奥へ見通す。v1 レイアウトは 34
var cam_target := Vector3(-5.0, 0.0, -1.0)     # 注視点（v2: 街路の少し奥）。v1 は (2, 0, -3)

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
		"sun_elev": 13.0, "sun_az": 165.0, "sun_color": Color(0.905, 0.833, 0.815), "sun_energy": 4.2,   # (1.0,0.84,0.70) を輝度一定で彩度 0.3 倍（D-3: 明部彩度 0.29→0.19、参考 0.17）。   # 方位 165: v2 レイアウトで奥の路面に日が差し、見える壁面は全て日陰（フェーズ3 D-2/D-4）
		"sky_top": Color(0.20, 0.18, 0.34), "sky_horizon": Color(0.85, 0.45, 0.30),
		"ground_horizon": Color(0.30, 0.22, 0.26), "ground_bottom": Color(0.08, 0.07, 0.10),
		"ambient": Color(0.327, 0.345, 0.429), "ambient_energy": 0.386,   # フェーズ4: 焼き込み AO（路面で 0.54〜0.71）を入れた分 x1.65。P_core/P_sun 0.12 を維持   # 輝度は (0.28,0.34,0.62) と同じ、彩度を 0.3 倍（影の彩度 0.80→0.54、参考 0.43）。0.18 x 1.30 で路面の影比 0.120
		"fog_color": Color(0.55, 0.32, 0.30), "fog_density": 0.0015, "fog_energy": 0.7,
		"exposure": 1.15, "lamps": false, "sky_energy": 0.7,   # 夕方は街灯を点けない（街灯が路面の大半を照らして較正を狂わせる）
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
var dof_on := false            # ドット絵に光学ボケは掛けない（フェーズ4 E-0b）。参考画像のボケ再現は F キーで
var glow_on := true
var fog_on := false           # Fog は黒を浮かせる。参考画像に霞は無い
var ssao_on := false
var ssil_on := false
var pixel_scale := 2            # 1 = 1280x720 そのまま、2 = 640x360 を 2 倍、3 = 426x240 を 3 倍
var soft_level := 0             # 0 硬い / 1 少し / 2 やわらかい
var shadow_res := 4096
var omni_shadows := true
var billboard_full := true      # true: カメラ正対、false: Y 軸回転のみ
var sprites_shaded := true
var mipmaps := true             # 世界テクスチャは Nearest + ミップマップ（C-2/C-3。スプライトは常に Nearest）
var hud_on := true
var glow_intensity := 1.0
var glow_threshold := 0.9
var tonemap_white := 1.0
var walk_mode := ""             # E-3b: "A" Nearest / "B" 線形+ミップマップ / "C" 整数 texel 比スナップ / "D" C + 画面位置を整数 px にスナップ。空で無効
var walk_from := Vector3(-13.0, 0.0, 0.5)
var walk_to := Vector3(2.0, 0.0, 0.5)
var walk_pivot: Node3D
var walk_sprite: Sprite3D
const WALK_TEX_H := 56          # 28x56 texel = 1x2 m
var ao_on := true               # 街区スケールの空の遮蔽を焼いた AO（E-2）。ao_light_affect=0 で環境光にのみ効く
var ao_power := 1.0             # 焼いた AO に掛ける指数（芯を深くする較正ノブ）
var ao_ray_len := 18.0          # 遮蔽レイの最大距離 (m)。建物高さの 2〜3 倍
var ao_rays := 24               # 半球サンプル数（コサイン重み、決定的）
var ao_texel := 2.0             # ベイク解像度 (texel/m)。表示時に 4 倍へバイリニア拡大
var ao_debug := false           # AO だけを白地に表示（確認用）
var ground_ao_img: Image
var layout := "v2"              # v1: フェーズ1/2 の配置（手前に大きな箱）。v2: 両側に建物、街路が奥へ抜ける
var sun_desat := 0.0            # 太陽色の彩度を輝度一定で落とす割合
var skylight_on := false        # 疑似スカイライト（2 本目の DirectionalLight3D、影あり）
var skylight_energy := 0.3
var skylight_angle := 20.0      # light_angular_distance（半影の広がり）
var skylight_pitch := -75.0
var skylight_yaw := 180.0       # カメラ相対。180 = 奥側（向こう側の建物の裏）から
var skylight: DirectionalLight3D
var extra_dirlights := 0        # 影付き DirectionalLight3D の本数上限を実測するためのダミー
var fov_deg := 18.0             # 縦 FOV（透視）。C-1 の実測で 18 を採用（上端/下端の見かけ倍率 1.33 倍、距離 40.6 m）
var c1_mode := false            # C-1: 建物を消し、画面上端・中央・下端に同一サイズの板を置く
var seq_dir := ""               # C-2: 連番 PNG の出力先。指定すると等速パンしながら撮影して終了
var seq_frames := 60
var pan_meters := 2.0
var snap_on := false            # C-2: カメラ位置を 1 texel 格子にスナップ
var fxaa_on := false
var flat_on := false            # 世界テクスチャを単色に（影のエッジだけを見る）
var _seq_i := 0
var _cam_base_pos := Vector3.ZERO
var c1_boards: Array[MeshInstance3D] = []
var lamps_override := -1        # -1: プリセットに従う / 0,1: 強制
var ambient_desat := 0.0        # 環境光の彩度を輝度を保って落とす割合（0 = そのまま、0.5 = 半分）
var ambient_mul := 1.0          # 較正用。既定値 1.0 = プリセットの ambient_energy そのまま
var wall_albedo := 0.50         # 壁の基準アルベド（リニア輝度）。0.35 未満は日陰で黒に潰れる。NAN でプリセット色
var bands_on := true
var probes: Array[Vector3] = []
var probe_grid := false
var bldg_aabbs: Array[AABB] = []
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
	pixel_size = 1.0 / base_texel_per_meter
	if c1_mode:
		_build_c1_ground()
	else:
		_build_world()
		_build_sprites()
	_build_lights()
	_build_environment()
	_build_camera()
	_build_hud()
	_apply_all()
	if c1_mode:
		_build_c1_boards()
	_cam_base_pos = cam.position


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
			"white":
				tonemap_white = float(v)
			"fov":
				fov_deg = float(v)
			"yaw":
				cam_yaw_deg = float(v)
			"walk":
				walk_mode = v.to_upper()
			"walk_from":
				var wf := v.split(",")
				if wf.size() == 2:
					walk_from = Vector3(float(wf[0]), 0.0, float(wf[1]))
			"walk_to":
				var wt := v.split(",")
				if wt.size() == 2:
					walk_to = Vector3(float(wt[0]), 0.0, float(wt[1]))
			"ao":
				ao_on = _b(v)
			"ao_power":
				ao_power = float(v)
			"ao_ray_len":
				ao_ray_len = float(v)
			"ao_rays":
				ao_rays = maxi(int(v), 4)
			"ao_debug":
				ao_debug = _b(v)
			"layout":
				layout = v
				if v == "v1":
					cam_target = Vector3(2.0, 0.0, -3.0)
					cam_yaw_deg = 34.0
			"target":
				var tz := v.split(",")
				if tz.size() == 2:
					cam_target = Vector3(float(tz[0]), 0.0, float(tz[1]))
			"sun_desat":
				sun_desat = float(v)
			"skylight":
				skylight_on = _b(v)
			"skylight_energy":
				skylight_energy = float(v)
			"skylight_angle":
				skylight_angle = float(v)
			"skylight_pitch":
				skylight_pitch = float(v)
			"skylight_yaw":
				skylight_yaw = float(v)
			"extra_dirlights":
				extra_dirlights = int(v)
			"texel":
				base_texel_per_meter = float(v)
			"c1":
				c1_mode = _b(v)
			"seq":
				seq_dir = v
			"seq_frames":
				seq_frames = maxi(int(v), 2)
			"pan":
				pan_meters = float(v)
			"snap":
				snap_on = _b(v)
			"fxaa":
				fxaa_on = _b(v)
			"flat":
				flat_on = _b(v)
			"lamps":
				lamps_override = 1 if _b(v) else 0
			"ambient_mul":
				ambient_mul = float(v)
			"ambient_desat":
				ambient_desat = float(v)
			"wall_albedo":
				wall_albedo = float(v)
			"bands":
				bands_on = _b(v)
			"probe":
				for pt in v.split(";", false):
					var xz := pt.split(",")
					if xz.size() == 2:
						probes.append(Vector3(float(xz[0]), 0.0, float(xz[1])))
			"probe_grid":
				probe_grid = _b(v)
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
			# 路面と同系の低彩度（オリーブ色は明部の色相・彩度統計を汚した。E-0c）
			var c := Color(0.40, 0.38, 0.40).lerp(Color(0.47, 0.44, 0.44), t)
			if _rng.randf() < 0.08:
				c = Color(0.33, 0.32, 0.33)
			img.set_pixel(x, y, c)
	return img


func _mat(img: Image, world_scale: float = 1.0, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if flat_on:
		# 単色（テクスチャの平均色）。影のエッジのちらつきだけを測るため
		var acc := Color(0, 0, 0)
		for y in img.get_height():
			for x in img.get_width():
				acc += img.get_pixel(x, y)
		m.albedo_color = acc / float(img.get_width() * img.get_height())
	else:
		m.albedo_texture = _tex(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = rough
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# 三平面マッピング（ワールド座標）で、どの面にも同じ密度で貼る
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var texels_per_tile := float(img.get_width())
	var meters_per_tile := texels_per_tile / base_texel_per_meter * world_scale
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


## 壁の基準色。wall_albedo が指定されていれば、色相を保って輝度（リニア）をその値に揃える。
func _wall_base(preset: Color) -> Color:
	if is_nan(wall_albedo):
		return preset
	var lum := 0.2126 * preset.r + 0.7152 * preset.g + 0.0722 * preset.b
	var k := wall_albedo / maxf(lum, 0.001)
	return Color(minf(preset.r * k, 1.0), minf(preset.g * k, 1.0), minf(preset.b * k, 1.0))


func _build_world() -> void:
	# 地面（路面）。街路は X 軸方向、幅 7m。AO は建物の配置後に焼くので、ここでは材質だけ作る
	var asphalt := _mat(_asphalt_image(64, Color(0.42, 0.39, 0.47), 0.06))

	# 歩道（少し明るい帯）
	var sidewalk := _mat(_asphalt_image(32, Color(0.50, 0.47, 0.52), 0.04))
	_box(Vector3(120, 0.12, 1.8), Vector3(0, 0.06, 4.4), sidewalk, "SidewalkN")
	_box(Vector3(120, 0.12, 1.8), Vector3(0, 0.06, -4.4), sidewalk, "SidewalkS")

	# 草地（建物の裏側・空き地）
	var grass := _mat(_grass_image())
	if layout == "v1":
		_box(Vector3(14, 0.05, 10), Vector3(6, 0.025, 14), grass, "GrassN")
		_box(Vector3(10, 0.05, 8), Vector3(-22, 0.025, -12), grass, "GrassS")
	else:
		_box(Vector3(17, 0.05, 12), Vector3(-17, 0.025, -11.5), grass, "GrassLot")   # 向こう側の空き地

	# 車線の白線（破線）
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.85, 0.82)
	white.roughness = 1.0
	white.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in range(-6, 7):
		var b := _box(Vector3(2.0, 0.02, 0.15), Vector3(i * 5.0, 0.011, 0.0), white, "Lane%d" % (i + 6))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 建物: 直方体 + 屋根の薄い直方体。街路の両側に並べる。
	var wall_a := _mat(_siding_image(_wall_base(Color(0.16, 0.16, 0.24)), Color(0.62, 0.62, 0.70)))
	var wall_b := _mat(_siding_image(_wall_base(Color(0.20, 0.18, 0.22)), Color(0.55, 0.52, 0.55)))
	var wall_c := _mat(_siding_image(_wall_base(Color(0.30, 0.28, 0.32)), Color(0.70, 0.68, 0.72)))
	var roof := _mat(_roof_image())
	var specs := []
	if layout == "v1":
		specs = [
			# [x, side(+1 手前/-1 向こう), width, height, depth, wall]
			[-12.0, -1, 10.0, 8.0, 8.0, wall_a],
			[-1.0, -1, 6.0, 6.5, 7.0, wall_b],
			[7.0, -1, 5.0, 7.5, 6.0, wall_c],
			[15.0, -1, 8.0, 6.0, 7.0, wall_a],
			[25.0, -1, 6.0, 9.0, 6.0, wall_b],
			[-14.0, 1, 7.0, 4.0, 6.0, wall_c],
			[-4.0, 1, 5.0, 3.5, 5.0, wall_a],
			[6.0, 1, 8.0, 4.5, 7.0, wall_b],
			[17.0, 1, 6.0, 4.0, 6.0, wall_c],
		]
	else:
		# v2: 街路（X 軸、-X が奥）の両側に 2 階建て相当の建物を等間隔で並べる。
		# 手前側にも同じ高さの列を置き、奥（-X）へ抜ける見通しを作る。
		# 向こう側（-Z）は x が -24〜-8 の区間を空き地にして、奥の路面に日が差し込む抜けを作る
		for i in range(-5, 4):
			var x := -30.0 + (i + 5) * 7.0
			var far_h: Array[float] = [6.5, 7.5, 6.0, 8.0, 7.0, 6.5, 7.5, 6.0, 7.0]
			var near_h: Array[float] = [6.0, 7.0, 6.5, 6.0, 7.5, 6.5, 6.0, 7.0, 6.5]
			var h_far: float = far_h[i + 5]
			var h_near: float = near_h[i + 5]
			var mats: Array[StandardMaterial3D] = [wall_a, wall_b, wall_c]
			if x < -26.0 or x > -8.0:
				specs.append([x, -1, 5.5, h_far, 7.0, mats[(i + 5) % 3]])
			specs.append([x + 3.0, 1, 5.5, h_near, 7.0, mats[(i + 6) % 3]])
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.85, 0.85, 0.85)
	band_mat.roughness = 1.0
	band_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var idx := 0
	for s in specs:
		var x: float = s[0]
		var side: int = s[1]
		var w: float = s[2]
		var h: float = s[3]
		var d: float = s[4]
		var m: Material = s[5]
		var z := side * (3.5 + 1.8 + 1.0 + d * 0.5)
		_box(Vector3(w + 0.8, 0.35, d + 0.8), Vector3(x, h + 0.175, z), roof, "Roof%d" % idx)
		bldg_aabbs.append(AABB(Vector3(x - w * 0.5, 0.0, z - d * 0.5), Vector3(w, h, d)))
		bldg_aabbs.append(AABB(Vector3(x - (w + 0.8) * 0.5, h, z - (d + 0.8) * 0.5), Vector3(w + 0.8, 0.35, d + 0.8)))
		if ao_on:
			_building_with_ao(Vector3(w, h, d), Vector3(x, h * 0.5, z), m as StandardMaterial3D, "Bldg%d" % idx)
		else:
			_box(Vector3(w, h, d), Vector3(x, h * 0.5, z), m, "Bldg%d" % idx)
		if bands_on:
			# 白い細帯（幅 0.1m・albedo 0.85）。街路に面した壁に数本。日陰で「線」として読めるかを見る
			var face_z := z - side * (d * 0.5 + 0.02)
			var band_y := 1.2
			while band_y < h - 0.6:
				var bb := _box(Vector3(w * 0.9, 0.1, 0.04), Vector3(x, band_y, face_z), band_mat, "Band%d_%d" % [idx, int(band_y * 10)])
				bb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				band_y += 1.2
		idx += 1

	# 地面。UV2 に街区スケールの AO を焼いて貼る（ao_light_affect = 0: 環境光にのみ効く）
	_build_ground(asphalt)


# ============================================================================
# AO ベイク（E-2）。半球のコサイン重みサンプルを建物 AABB と地面に当て、遮蔽率を焼く。
# SSAO とは目的が違う: 数十 cm ではなく 15〜20 m 先の建物による空の遮蔽を焼く。
# ============================================================================
func _hemi_dirs(n: int) -> Array[Vector3]:
	# 接空間（z = 法線）でのコサイン重みサンプル。Hammersley 列で決定的に。
	var out: Array[Vector3] = []
	for i in n:
		var u := (float(i) + 0.5) / float(n)
		var v := 0.0
		var f := 0.5
		var k := i
		while k > 0:
			if k & 1:
				v += f
			f *= 0.5
			k >>= 1
		var r := sqrt(u)
		var th := TAU * v
		out.append(Vector3(r * cos(th), r * sin(th), sqrt(maxf(1.0 - u, 0.0))))
	return out


## 点 p・法線 n の空の可視率（0..1）。建物 AABB と地面（y=0）を遮蔽物にする。
func _sky_visibility(p: Vector3, n: Vector3, dirs: Array[Vector3], tangent: Vector3, bitangent: Vector3, skip_ground: bool) -> float:
	var open := 0
	for dl in dirs:
		var d := (tangent * dl.x + bitangent * dl.y + n * dl.z).normalized()
		var blocked := false
		if not skip_ground and d.y < -1e-4:
			var t := -p.y / d.y
			if t <= ao_ray_len:
				blocked = true
		if not blocked:
			for bb in bldg_aabbs:
				var hit = bb.intersects_ray(p, d)
				if hit != null and (hit as Vector3).distance_to(p) <= ao_ray_len:
					blocked = true
					break
		if not blocked:
			open += 1
	return float(open) / float(dirs.size())


func _ao_to_texture(img: Image, upscale: int) -> ImageTexture:
	# ao_power を掛け、バイリニアで拡大（材質の Nearest フィルタでもブロックが見えないように）
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := pow(img.get_pixel(x, y).r, ao_power)
			out.set_pixel(x, y, Color(a, a, a, 1.0))
	out.resize(out.get_width() * upscale, out.get_height() * upscale, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(out)


func _apply_ao(m: StandardMaterial3D, tex: ImageTexture) -> StandardMaterial3D:
	var mm := m.duplicate() as StandardMaterial3D
	mm.ao_enabled = true
	mm.ao_texture = tex
	mm.ao_on_uv2 = true
	mm.ao_light_affect = 0.0          # 直接光には効かせない（明示）
	mm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ao_debug:
		mm.albedo_texture = null
		mm.albedo_color = Color(1, 1, 1)
		mm.uv1_triplanar = false
	return mm


## 四角形メッシュ（UV と UV2 が 0..1）。origin から u 軸・v 軸に沿って張る。
func _quad(origin: Vector3, u_axis: Vector3, v_axis: Vector3, normal: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for c in corners:
		st.set_normal(normal)
		st.set_uv(c)
		st.set_uv2(c)
		st.add_vertex(origin + u_axis * c.x + v_axis * c.y)
	st.add_index(0); st.add_index(1); st.add_index(2)
	st.add_index(0); st.add_index(2); st.add_index(3)
	return st.commit()


func _build_ground(asphalt: StandardMaterial3D) -> void:
	var half := 60.0
	var mesh := _quad(Vector3(-half, 0, -half), Vector3(2 * half, 0, 0), Vector3(0, 0, 2 * half), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Ground"
	if ao_on:
		var t0 := Time.get_ticks_msec()
		var n := int(2 * half * ao_texel)
		var img := Image.create(n, n, false, Image.FORMAT_RF)
		img.fill(Color(1, 1, 1))
		var dirs := _hemi_dirs(ao_rays)
		# 建物のある範囲だけ焼く（外は 1.0）
		var x0 := -42.0
		var x1 := 42.0
		var z0 := -24.0
		var z1 := 24.0
		for iy in n:
			var wz := -half + (float(iy) + 0.5) / ao_texel
			if wz < z0 or wz > z1:
				continue
			for ix in n:
				var wx := -half + (float(ix) + 0.5) / ao_texel
				if wx < x0 or wx > x1:
					continue
				var a := _sky_visibility(Vector3(wx, 0.02, wz), Vector3.UP, dirs, Vector3.RIGHT, Vector3.BACK, true)
				img.set_pixel(ix, iy, Color(a, a, a))
		ground_ao_img = img
		mi.material_override = _apply_ao(asphalt, _ao_to_texture(img, 4))
		print("lookdev: ground AO baked %dx%d, %d rays, %.1f s" % [n, n, ao_rays, (Time.get_ticks_msec() - t0) / 1000.0])
	else:
		asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = asphalt
	add_child(mi)


## 建物を 4 面の壁（UV2 に AO）+ 天面で作る。
func _building_with_ao(size: Vector3, pos: Vector3, wall: StandardMaterial3D, name_: String) -> void:
	var dirs := _hemi_dirs(ao_rays)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := pos.y - size.y * 0.5
	# 面: [origin, u_axis, v_axis, normal]
	var faces := [
		[Vector3(pos.x - hx, y0, pos.z + hz), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), Vector3.BACK],     # +Z
		[Vector3(pos.x + hx, y0, pos.z - hz), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3.FORWARD], # -Z
		[Vector3(pos.x + hx, y0, pos.z + hz), Vector3(0, 0, -size.z), Vector3(0, size.y, 0), Vector3.RIGHT],   # +X
		[Vector3(pos.x - hx, y0, pos.z - hz), Vector3(0, 0, size.z), Vector3(0, size.y, 0), Vector3.LEFT],     # -X
	]
	var fi := 0
	for f in faces:
		var origin: Vector3 = f[0]
		var ua: Vector3 = f[1]
		var va: Vector3 = f[2]
		var nrm: Vector3 = f[3]
		var nu := maxi(int(ceil(ua.length() * ao_texel)), 2)
		var nv := maxi(int(ceil(va.length() * ao_texel)), 2)
		var img := Image.create(nu, nv, false, Image.FORMAT_RF)
		var tangent := ua.normalized()
		var bitangent := va.normalized()
		for iy in nv:
			for ix in nu:
				var p := origin + ua * ((float(ix) + 0.5) / nu) + va * ((float(iy) + 0.5) / nv) + nrm * 0.02
				var a := _sky_visibility(p, nrm, dirs, tangent, bitangent, false)
				img.set_pixel(ix, iy, Color(a, a, a))
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(origin, ua, va, nrm)
		mi.material_override = _apply_ao(wall, _ao_to_texture(img, 4))
		mi.name = "%s_f%d" % [name_, fi]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		fi += 1
	# 天面（AO なし）
	var top := MeshInstance3D.new()
	top.mesh = _quad(Vector3(pos.x - hx, y0 + size.y, pos.z - hz), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), Vector3.UP)
	var tm := wall.duplicate() as StandardMaterial3D
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	top.material_override = tm
	top.name = name_ + "_top"
	add_child(top)


## 路面上の点の焼き込み AO 値（ao_power 適用後）。PROBE 行の "ao" に出す。
func _ground_ao_at(p: Vector3) -> float:
	if ground_ao_img == null:
		return 1.0
	var n := ground_ao_img.get_width()
	var ix := clampi(int((p.x + 60.0) * ao_texel), 0, n - 1)
	var iy := clampi(int((p.z + 60.0) * ao_texel), 0, n - 1)
	return pow(ground_ao_img.get_pixel(ix, iy).r, ao_power)


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
	sp.pixel_size = pixel_size
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 向きは pivot で手動制御
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD       # 影を落とせるようにする
	sp.alpha_scissor_threshold = 0.5
	sp.double_sided = true
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sp.shaded = sprites_shaded
	# 足元を pivot に合わせる（centered のまま高さの半分だけ持ち上げる）
	sp.position = Vector3(0, img.get_height() * pixel_size * 0.5, 0)
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
	q.size = Vector2(size.x, size.y) * pixel_size
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, size.y * pixel_size * 0.5, 0.005)   # 本体のわずかに手前
	pivot.add_child(mi)
	emissives.append(mi)


## E-3b: 行の間引きが見えるテスト用スプライト（28x56 texel = 1x2 m）。
## 上半分は 1 texel おきの横縞、下半分は 2 texel の市松。輪郭は白。
func _walk_sprite_image() -> Image:
	var img := Image.create(28, WALK_TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in WALK_TEX_H:
		for x in 28:
			var c: Color
			if x == 0 or x == 27 or y == 0 or y == WALK_TEX_H - 1:
				c = Color(1, 1, 1)
			elif y < WALK_TEX_H / 2:
				c = Color(0.95, 0.25, 0.20) if (y % 2 == 0) else Color(0.10, 0.10, 0.12)
			else:
				c = Color(0.20, 0.55, 0.95) if (((x / 2) + (y / 2)) % 2 == 0) else Color(0.95, 0.90, 0.30)
			img.set_pixel(x, y, c)
	return img


func _build_walk_sprite() -> void:
	walk_pivot = Node3D.new()
	walk_pivot.name = "WalkPivot"
	walk_pivot.position = walk_from
	add_child(walk_pivot)
	walk_sprite = Sprite3D.new()
	walk_sprite.texture = _tex(_walk_sprite_image())
	walk_sprite.pixel_size = pixel_size
	walk_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	walk_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	walk_sprite.alpha_scissor_threshold = 0.5
	walk_sprite.shaded = false                     # 判定対象は標本化なので照明の影響を外す
	walk_sprite.double_sided = true
	walk_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if walk_mode == "B" else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	walk_sprite.position = Vector3(0, WALK_TEX_H * pixel_size * 0.5, 0)
	walk_pivot.add_child(walk_sprite)
	billboards.append(walk_pivot)


## C 条件: 画面上の高さが texel 数の整数倍になるようスケールを毎フレーム丸める。
## 透視では距離に応じて見かけの texel/px 比が変わる（FOV 18 で 0.86〜1.14）。
## 比を最も近い整数（この範囲ではすべて 1）に丸めるので、サイズは距離に依らず 56 px になる。
func _walk_snap_scale() -> float:
	if walk_mode != "C" and walk_mode != "D":
		return 1.0
	var base := walk_pivot.global_position
	var top := base + cam.global_transform.basis.y * 1.0     # 板はカメラ正対なので、カメラの上方向に 1 m
	var h_px := absf(cam.unproject_position(base).y - cam.unproject_position(top).y)   # 1 m の見かけ px
	var ratio := h_px / base_texel_per_meter                                              # px / texel
	var snapped := maxf(round(ratio), 1.0)
	return snapped / ratio


func _build_sprites() -> void:
	if walk_mode != "":
		_build_walk_sprite()
	if layout != "v1":
		_add_billboard("vending", Vector3(-2.0, 0.12, -4.9))
		_add_emissive(billboards[-1], Vector2i(16, 30), Rect2i(3, 2, 8, 12), Color(0.75, 0.95, 0.90), 1.8)
		_add_billboard("streetlight", Vector3(-9.0, 0.12, 4.0))
		_add_emissive(billboards[-1], Vector2i(12, 80), Rect2i(3, 6, 6, 3), Color(1.0, 0.92, 0.70), 2.5)
		_add_billboard("pole", Vector3(5.0, 0.12, -4.9))
		_add_billboard("streetlight", Vector3(3.0, 0.12, 4.0))
		_add_emissive(billboards[-1], Vector2i(12, 80), Rect2i(3, 6, 6, 3), Color(1.0, 0.92, 0.70), 2.5)
		return
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

	# 疑似スカイライト（D-1）。ほぼ真下向きの 2 本目の平行光。影あり・鏡面なし・広い半影。
	skylight = DirectionalLight3D.new()
	skylight.name = "SkyLight"
	skylight.shadow_enabled = true
	skylight.light_specular = 0.0
	skylight.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	skylight.directional_shadow_max_distance = 120.0
	skylight.shadow_bias = 0.05
	skylight.shadow_normal_bias = 2.0
	skylight.visible = false
	add_child(skylight)

	# 上限テスト用ダミー（極めて弱い光。影だけ有効）
	for i in extra_dirlights:
		var dl := DirectionalLight3D.new()
		dl.name = "Dummy%d" % i
		dl.light_energy = 0.001
		dl.shadow_enabled = true
		dl.rotation_degrees = Vector3(-60.0 - i * 3.0, 40.0 * i, 0.0)
		add_child(dl)

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
	env.tonemap_white = tonemap_white
	env.sdfgi_enabled = false
	env.ssr_enabled = false
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
	cam_attr.dof_blur_far_distance = cam_distance + 8.0
	cam_attr.dof_blur_far_transition = 14.0
	cam_attr.dof_blur_near_distance = cam_distance - 9.0
	cam_attr.dof_blur_near_transition = 6.0
	cam_attr.dof_blur_amount = 0.25
	cam.attributes = cam_attr
	add_child(cam)
	cam.make_current()   # 位置・向きは _apply_camera で決める


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
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa_on else Viewport.SCREEN_SPACE_AA_DISABLED
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
	sun.rotation_degrees = Vector3(-elev, cam_yaw_deg + az, 0.0)
	var sc: Color = t["sun_color"]
	if sun_desat > 0.0:
		# 輝度一定で彩度だけ落とす（sun_energy には触らない）
		var ys := 0.2126 * sc.r + 0.7152 * sc.g + 0.0722 * sc.b
		sc = Color(lerpf(sc.r, ys, sun_desat), lerpf(sc.g, ys, sun_desat), lerpf(sc.b, ys, sun_desat))
	sun.light_color = sc
	sun.light_energy = t["sun_energy"]
	sun.visible = t["sun_energy"] > 0.0

	sky_mat.sky_top_color = t["sky_top"]
	sky_mat.sky_horizon_color = t["sky_horizon"]
	sky_mat.ground_horizon_color = t["ground_horizon"]
	sky_mat.ground_bottom_color = t["ground_bottom"]
	sky_mat.energy_multiplier = t["sky_energy"]
	var amb: Color = t["ambient"]
	if ambient_desat > 0.0:
		var y := 0.2126 * amb.r + 0.7152 * amb.g + 0.0722 * amb.b
		amb = Color(lerpf(amb.r, y, ambient_desat), lerpf(amb.g, y, ambient_desat), lerpf(amb.b, y, ambient_desat))
	env.ambient_light_color = amb
	# 疑似スカイライト: 色は環境光と同じ、輝度は独立
	skylight.visible = skylight_on
	skylight.light_color = amb
	skylight.light_energy = skylight_energy
	skylight.light_angular_distance = skylight_angle
	skylight.rotation_degrees = Vector3(skylight_pitch, cam_yaw_deg + skylight_yaw, 0.0)
	env.ambient_light_energy = t["ambient_energy"] * ambient_mul
	env.fog_light_color = t["fog_color"]
	env.fog_density = t["fog_density"]
	env.fog_light_energy = t["fog_energy"]
	env.tonemap_exposure = t["exposure"] if is_nan(exposure_override) else exposure_override

	var lamps_on: bool = t["lamps"]
	if lamps_override >= 0:
		lamps_on = lamps_override == 1
	for l in lamps:
		l.visible = lamps_on
	for e in emissives:
		e.visible = lamps_on


func _apply_camera() -> void:
	# 基準面 = 画面中央の地面（カメラの注視点）。そこで 1 m が base_texel_per_meter px になる。
	var view_h_m := float(DESIGN_H) * pixel_size          # 基準面での画面の縦幅 (m)
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = view_h_m
		cam_distance = ORTHO_DISTANCE
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = fov_deg
		# 縦 FOV で基準面の縦幅が view_h_m になる距離を逆算
		cam_distance = (view_h_m * 0.5) / tan(deg_to_rad(fov_deg * 0.5))
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAM_PITCH_DEG), deg_to_rad(cam_yaw_deg), 0.0))
	cam.position = cam_target + basis.z * cam_distance
	cam.look_at(cam_target, Vector3.UP)
	_cam_base_pos = cam.position
	# 影の描画距離とDOF の距離をカメラ距離に追従させる（FOV を絞ると距離が 40〜60 m になる）
	sun.directional_shadow_max_distance = cam_distance + 40.0
	cam_attr.dof_blur_far_distance = cam_distance + 8.0
	cam_attr.dof_blur_near_distance = maxf(cam_distance - 9.0, 1.0)
	cam_attr.dof_blur_far_enabled = dof_on and not ortho
	cam_attr.dof_blur_near_enabled = dof_on and not ortho


func _apply_env_toggles() -> void:
	env.tonemap_mode = TONEMAPS[tonemap]
	env.tonemap_white = tonemap_white
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
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # スプライトは常に Nearest
	for m in world_mats:
		m.texture_filter = f


func _process(_delta: float) -> void:
	_face_billboards()
	if seq_dir != "" and walk_mode != "":
		_frame += 1
		if _frame > shot_frames:
			var t := float(_seq_i) / float(seq_frames)
			walk_pivot.position = walk_from.lerp(walk_to, t)
			_face_billboards()
			var sc := _walk_snap_scale()
			walk_sprite.scale = Vector3(sc, sc, sc)
			walk_sprite.position = Vector3(0, WALK_TEX_H * pixel_size * 0.5 * sc, 0)
			if walk_mode == "D":
				# 足元の画面位置を整数ピクセルへ。同じ奥行きで、丸めた画面座標に対応するワールド位置に置き直す
				var b0 := walk_pivot.global_position
				var sp0 := cam.unproject_position(b0)
				var depth := (b0 - cam.global_position).dot(-cam.global_transform.basis.z)
				walk_pivot.global_position = cam.project_position(Vector2(round(sp0.x), round(sp0.y)), depth)
			if _seq_i >= 1:
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/f%03d.png" % [seq_dir, _seq_i - 1])
				var base := walk_pivot.global_position
				var sp := cam.unproject_position(base)
				var h_px := absf(cam.unproject_position(base).y - cam.unproject_position(base + cam.global_transform.basis.y * (WALK_TEX_H * pixel_size * sc)).y)
				print("WALK {\"i\":%d,\"px\":%.1f,\"py\":%.1f,\"h_px\":%.2f,\"scale\":%.3f}" % [_seq_i - 1, sp.x, sp.y, h_px, sc])
			_seq_i += 1
			if _seq_i > seq_frames:
				print("lookdev: walk seq done %d frames -> %s" % [seq_frames, seq_dir])
				get_tree().quit()
		return
	if seq_dir != "":
		_frame += 1
		if _frame > shot_frames:
			# 等速パン: カメラの右方向に pan_meters / seq_frames ずつ動かす
			var right := cam.global_transform.basis.x
			var t := float(_seq_i) / float(seq_frames)
			cam.position = _cam_base_pos + right * (pan_meters * t)
			if snap_on:
				cam.position = _snap_to_texel_grid(cam.position)
			if _seq_i >= 1:
				# 1 フレーム前に動かした位置が描画されているので、今フレームで撮る
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/f%03d.png" % [seq_dir, _seq_i - 1])
			_seq_i += 1
			if _seq_i > seq_frames:
				print("lookdev: seq done %d frames -> %s" % [seq_frames, seq_dir])
				get_tree().quit()
		return
	if shot_path != "":
		_frame += 1
		if _frame == shot_frames:
			_take_shot(shot_path)
			get_tree().quit()


## カメラ位置を、注視点基準で「画面 1 px = 1 texel」の格子にスナップする（右・上方向のみ）。
func _snap_to_texel_grid(p: Vector3) -> Vector3:
	var b := cam.global_transform.basis
	var d := p - cam_target
	var r := d.dot(b.x)
	var u := d.dot(b.y)
	var f := d.dot(b.z)
	r = round(r / pixel_size) * pixel_size
	u = round(u / pixel_size) * pixel_size
	return cam_target + b.x * r + b.y * u + b.z * f


# ============================================================================
# C-1: 投影の検証用。平らな地面と、画面上端・中央・下端に置いた同一サイズの板
# ============================================================================
func _build_c1_ground() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.5, 0.5)
	m.roughness = 1.0
	ground.material_override = m
	ground.name = "C1Ground"
	add_child(ground)


func _build_c1_boards() -> void:
	# 画面の縦 8% / 50% / 92%（横は中央）から地面への交点に、高さ 1 m・幅 0.25 m の板を立てる
	var rw := float(BASE_W / maxi(pixel_scale, 1))
	var rh := float(_render_height())
	for frac in [0.08, 0.5, 0.92]:
		var sp := Vector2(rw * 0.5, rh * frac)
		var o := cam.project_ray_origin(sp)
		var n := cam.project_ray_normal(sp)
		if absf(n.y) < 1e-6:
			continue
		var t := -o.y / n.y
		var hit := o + n * t
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.25, 1.0)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 0, 1)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pivot := Node3D.new()
		pivot.position = hit
		add_child(pivot)
		mi.position = Vector3(0, 0.5, 0)
		pivot.add_child(mi)
		billboards.append(pivot)   # カメラ正対（_face_billboards が回す）
		c1_boards.append(mi)
		print("C1BOARD {\"frac\":%.2f,\"world\":[%.2f,%.2f,%.2f],\"dist\":%.3f}" % [frac, hit.x, hit.y, hit.z, cam.global_position.distance_to(hit + Vector3(0, 0.5, 0))])
	print("C1CAM {\"fov\":%.2f,\"ortho\":%s,\"distance\":%.3f,\"height\":%.3f,\"pitch\":%.1f}" % [cam.fov, "true" if ortho else "false", cam_distance, cam.global_position.y, -CAM_PITCH_DEG])


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
	_report_probes(img)


## 路面上の計測点。ワールド座標 (x, 0, z) を画面へ投影し、3x3 の平均画素値と、
## 太陽光が建物に遮られているか（幾何で判定）、日向/日陰の縁からの余裕（m）を出力する。
## 出力は 1 行 1 点の JSON（先頭 "PROBE "）。較正ツールがこれを読む。
func _report_probes(img: Image) -> void:
	var pts := probes.duplicate()
	if probe_grid:
		for xi in range(-34, 35):
			for zz in [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]:
				pts.append(Vector3(float(xi), 0.0, zz))
	if pts.is_empty():
		return
	var sun_dir := -sun.global_transform.basis.z   # 光の進む向き
	var size := img.get_size()
	for p in pts:
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var px := int(round(sp.x))
		var py := int(round(sp.y))
		if px < 1 or py < 1 or px >= size.x - 1 or py >= size.y - 1:
			continue
		var acc := Vector3.ZERO
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := img.get_pixel(px + dx, py + dy)
				acc += Vector3(c.r, c.g, c.b)
		acc /= 9.0
		var shadow := _in_sun_shadow(p, sun_dir)
		var sky_shadow := false
		if skylight_on:
			sky_shadow = _in_sun_shadow(p, -skylight.global_transform.basis.z)
		var margin := 0.0
		for r in [0.5, 1.0, 1.5, 2.0]:
			var same := true
			for o in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
				if _in_sun_shadow(p + o, sun_dir) != shadow:
					same = false
					break
			if not same:
				break
			margin = r
		var wall_dist := _dist_to_buildings(p)
		print("PROBE {\"x\":%.2f,\"z\":%.2f,\"px\":%d,\"py\":%d,\"rgb\":[%.4f,%.4f,%.4f],\"shadow\":%s,\"sky_shadow\":%s,\"margin\":%.1f,\"wall\":%.2f,\"ao\":%.3f}" % [
			p.x, p.z, px, py, acc.x, acc.y, acc.z, "true" if shadow else "false", "true" if sky_shadow else "false", margin, wall_dist, _ground_ao_at(p)])


func _in_sun_shadow(p: Vector3, sun_dir: Vector3) -> bool:
	var from := p + Vector3(0, 0.02, 0)
	var to_sun := -sun_dir
	for bb in bldg_aabbs:
		if bb.intersects_ray(from, to_sun) != null:
			return true
	return false


func _dist_to_buildings(p: Vector3) -> float:
	var best := 1e9
	for bb in bldg_aabbs:
		var q := Vector3(clampf(p.x, bb.position.x, bb.end.x), p.y, clampf(p.z, bb.position.z, bb.end.z))
		best = minf(best, p.distance_to(q))
	return best


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
	var proj_s := ("ORTHO size=%.1fm" % cam.size) if ortho else ("PERSP fov=%.1f dist=%.1fm" % [cam.fov, cam_distance])
	hud.text = "\n".join([
		"[1-4] time=%s   sun elev=%.0f az=%.0f (rel. to camera)   exposure=%.2f   skylight=%s e=%.2f ang=%.0f" % [time_name, _cur_elev(), _cur_az(), _cur_exposure(), _oo(skylight_on), skylight_energy, skylight_angle],
		"[O] %s   [P] render %dx%d x%d   [T] tonemap=%s" % [proj_s, rw, rh, pixel_scale, tonemap],
		"[F] dof=%s  [G] glow=%s  [Z] fog=%s  [A] ssao=%s  [I] ssil=%s" % [_oo(dof_on and not ortho), _oo(glow_on), _oo(fog_on), _oo(ssao_on), _oo(ssil_on)],
		"[B] shadow soft=%d  [N] shadow res=%d  [L] omni shadows=%s" % [soft_level, shadow_res, _oo(omni_shadows)],
		"[V] billboard=%s  [K] sprites shaded=%s  [M] filter=%s  pixel_size=%.4f (%d texel/m)  snap=%s fxaa=%s" % ["full" if billboard_full else "y-axis", _oo(sprites_shaded), "nearest+mipmap" if mipmaps else "nearest", pixel_size, int(base_texel_per_meter), _oo(snap_on), _oo(fxaa_on)],
		"[ ] sun elev  , . sun az  - = exposure  [S] screenshot  [H] hud  [Esc] quit",
	])


func _oo(b: bool) -> String:
	return "on" if b else "off"
