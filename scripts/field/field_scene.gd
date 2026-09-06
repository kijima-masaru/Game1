extends Node3D
## フィールドを歩く（J-4）。lookdev（layout=empty）を土台に FieldBuilder で街を組み、主人公を動かす。
##
##   godot --path . res://scenes/fields/f05_kaido.tscn -- time=evening
##   引数: field=F05  field_yaw=<deg>  time=  shot=  regen=1  flags=a,b  player=x,y（タイル）  target=x,y（タイル）
##         walk_demo=1（北の出入口から南の出入口まで自動で歩き、秒数とフレーム時間を出す）  areamask=1  occl=fade|none
## 操作: WASD/矢印（画面基準。W = 画面の上）  E 調べる  F1 デバッグ  F2 通行判定  Esc 終了

@export var field_id := "F05"

const MOVE_SPEED := 3.0
const INTERACT_TILES := 2.0

var lookdev: Node3D
var fd: FieldData
var builder: FieldBuilder
var field_root: Node3D
var player: Node3D
var player_sprite: Sprite3D
var flags := {}
var occl := "fade"
var field_yaw_override := NAN
var walk_demo := false
var areamask := false
var fixed_target := false   # target= 指定時はカメラを追従させない（比較用スクリーンショット）
var ui: CanvasLayer
var hud: Label
var msg: Label
var debug_panel: PanelContainer
var debug_label: Label
var pass_rect: TextureRect
var minimap: Minimap
var mode := "explore"
var near_point := {}
var near_exit := {}
var _demo_state := {}
var _frame_times: Array[float] = []
var _fade_frames := 0
var _faded := {}
var _fade_ids := {}
var _measure_frame := 0
var _deltas: Array[float] = []
var vignette := 0
var vignette_rect: ColorRect


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var player_tile := Vector2(-1, -1)
	var target_tile := Vector2(-1, -1)
	var regen := false
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"field":
				field_id = kv[1]
			"field_yaw":
				field_yaw_override = float(kv[1])
			"regen":
				regen = kv[1] == "1"
			"flags":
				for f in kv[1].split(","):
					if f != "":
						flags[f] = true
			"player":
				player_tile = Vector2(float(kv[1].split(",")[0]), float(kv[1].split(",")[1]))
			"target":
				target_tile = Vector2(float(kv[1].split(",")[0]), float(kv[1].split(",")[1]))
			"walk_demo":
				walk_demo = kv[1] == "1"
			"areamask":
				areamask = kv[1] == "1"
			"occl":
				occl = kv[1]
			"vignette":
				vignette = clampi(int(kv[1]), 0, 3)
	lookdev = load("res://scenes/lookdev.tscn").instantiate()
	lookdev.layout = "empty"
	add_child(lookdev)
	if not OS.get_cmdline_user_args().has("hud=1"):
		lookdev.hud_on = false   # lookdev の検証用 HUD はフィールドでは出さない
		if lookdev.hud != null:
			lookdev.hud.visible = false
	fd = FieldData.new()
	# field_yaw の上書きは配置（近景の帯）に効くので、読み込み後に再配置する
	fd.load("res://data/fields/%s.json" % field_id.to_lower(), "res://data/assets/objects.json", flags)
	if not is_nan(field_yaw_override):
		fd.d["field_yaw"] = field_yaw_override
		fd.relayout(flags)
	for e in fd.errors:
		push_error("field %s: %s" % [field_id, e])
	for w in fd.warnings:
		push_warning("field %s: %s" % [field_id, w])
	# フィールドごとの太陽方位（カメラ基準、時間帯ごと。field_yaw とは独立）
	var sa: Dictionary = fd.d.get("sun_az", {})
	if sa.has(lookdev.time_name) and is_nan(lookdev.sun_az_override):   # 引数 sun_az= があればそちらを優先
		lookdev.sun_az_override = float(sa[lookdev.time_name])
		lookdev._apply_time()
	builder = FieldBuilder.new()
	builder.pixel_size = lookdev.pixel_size
	field_root = builder.build(fd, self, flags, lookdev.cam_yaw_deg, regen)
	builder.set_lights(_lamps_on(), lookdev.time_name in ["evening", "night"])
	if areamask:
		_apply_areamask()
	# 主人公: 既定は北の出入口の spawn
	var spawn := _exit_spawn("N")
	if player_tile.x >= 0:
		spawn = player_tile
	_build_player(spawn)
	if target_tile.x >= 0:
		lookdev.cam_target = field_root.to_global(FieldData.tile_to_world(target_tile.x, target_tile.y))
		lookdev._apply_camera()
		fixed_target = true
	_build_ui()
	if OS.get_cmdline_user_args().has("measure=1"):
		_print_ground_range()
	if walk_demo:
		var exits: Array = fd.d.get("exits", [])
		var b := _exit_spawn("S") if _has_exit("S") else _spawn_of(exits[exits.size() - 1])
		var a := _exit_spawn("N") if _has_exit("N") else b
		if a == b:
			for e in exits:   # 北の出入口が無ければ、終点と違う最初の出入口から
				if _spawn_of(e) != b:
					a = _spawn_of(e)
					break
		var path := fd.find_path(Vector2i(a), Vector2i(b))
		_demo_state = {"from": a, "to": b, "path": path, "i": 0, "done": path.is_empty(), "start_ms": Time.get_ticks_msec()}
		player.position = FieldData.tile_to_world(a.x, a.y) + Vector3(0, 0.02, 0)   # 自動歩行は始点から
		if path.is_empty():
			printerr("walk_demo: 経路が無い %s(passable %s) → %s(passable %s)" % [str(Vector2i(a)), str(fd.is_passable(int(a.x), int(a.y))), str(Vector2i(b)), str(fd.is_passable(int(b.x), int(b.y)))])
	print("FIELD %s built in %.2fs (AO %.2fs, cache %s), faces=%d, passable=%d/%d" % [field_id, (Time.get_ticks_msec() - t0) / 1000.0, builder.bake_seconds, "hit" if builder.cache_hit else "baked", builder.gen.faces.size(), fd.reachable_count(), fd.size.x * fd.size.y])


func _lamps_on() -> bool:
	return bool(lookdev.TIMES[lookdev.time_name]["lamps"])


func _has_exit(dir: String) -> bool:
	for e in fd.d.get("exits", []):
		if e["dir"] == dir:
			return true
	return false


func _spawn_of(e: Dictionary) -> Vector2:
	return Vector2(float(e["spawn"][0]) + 0.5, float(e["spawn"][1]) + 0.5)


func _exit_spawn(dir: String) -> Vector2:
	for e in fd.d.get("exits", []):
		if e["dir"] == dir:
			return Vector2(float(e["spawn"][0]) + 0.5, float(e["spawn"][1]) + 0.5)
	var exits: Array = fd.d.get("exits", [])
	if not exits.is_empty():
		return _spawn_of(exits[0])   # その向きの出入口が無ければ最初の出入口（中央は建物の中のことがある）
	return Vector2(fd.size.x * 0.5, fd.size.y * 0.5)


# ============================================================================
# 主人公
# ============================================================================
func _figure_image() -> Image:
	# 仮の主人公 28×56 texel（P-3）。頭・髪・胴・腕・脚・靴を色分け。本番の素材はシナリオレビュー後
	var w := 28
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hair := Color(0.20, 0.15, 0.13)
	var skin := Color(0.90, 0.76, 0.64)
	var shirt := Color(0.36, 0.44, 0.58)
	var shirt_d := Color(0.28, 0.34, 0.46)
	var pants := Color(0.22, 0.22, 0.27)
	var shoe := Color(0.12, 0.10, 0.10)
	img.fill_rect(Rect2i(8, 2, 12, 12), skin)          # 顔
	img.fill_rect(Rect2i(7, 0, 14, 5), hair)           # 髪
	img.fill_rect(Rect2i(6, 3, 3, 7), hair)
	img.fill_rect(Rect2i(19, 3, 3, 6), hair)
	img.fill_rect(Rect2i(11, 8, 2, 2), Color(0.1, 0.1, 0.12))   # 目
	img.fill_rect(Rect2i(16, 8, 2, 2), Color(0.1, 0.1, 0.12))
	img.fill_rect(Rect2i(12, 14, 4, 2), skin)          # 首
	img.fill_rect(Rect2i(6, 16, 16, 18), shirt)        # 胴
	img.fill_rect(Rect2i(6, 16, 3, 18), shirt_d)       # 胴の陰
	img.fill_rect(Rect2i(3, 17, 3, 14), shirt)         # 腕
	img.fill_rect(Rect2i(22, 17, 3, 14), shirt_d)
	img.fill_rect(Rect2i(3, 31, 3, 4), skin)           # 手
	img.fill_rect(Rect2i(22, 31, 3, 4), skin)
	img.fill_rect(Rect2i(7, 34, 6, 18), pants)         # 脚
	img.fill_rect(Rect2i(15, 34, 6, 18), pants)
	img.fill_rect(Rect2i(6, 52, 7, 4), shoe)           # 靴
	img.fill_rect(Rect2i(15, 52, 7, 4), shoe)
	# 輪郭 1 px（暗色）
	var src := img.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var edge := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and src.get_pixel(q.x, q.y).a > 0.0:
					edge = true
			if edge:
				img.set_pixel(x, y, Color(0.08, 0.07, 0.09))
	return img


func _build_player(tile: Vector2) -> void:
	player = Node3D.new()
	player.name = "Player"
	field_root.add_child(player)
	player.position = FieldData.tile_to_world(tile.x, tile.y) + Vector3(0, 0.02, 0)
	var img := _figure_image()
	player_sprite = Sprite3D.new()
	player_sprite.texture = ImageTexture.create_from_image(img)
	player_sprite.pixel_size = lookdev.pixel_size
	player_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	player_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	player_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	player_sprite.alpha_scissor_threshold = 0.5
	player_sprite.shaded = true
	player_sprite.double_sided = true
	player_sprite.set_meta("h", img.get_height())
	player_sprite.position = Vector3(0, img.get_height() * lookdev.pixel_size * 0.5, 0)
	player.add_child(player_sprite)
	builder.billboards.append(player)


func _player_tile() -> Vector2:
	return Vector2(player.position.x / FieldData.TILE, player.position.z / FieldData.TILE)


## 画面基準の入力をフィールドのローカル方向へ。通行判定は軸ごとに滑らせる。
func _move(dir_world: Vector3, delta: float) -> void:
	if dir_world.length_squared() < 1e-6:
		return
	var local_dir := field_root.global_transform.basis.inverse() * dir_world
	local_dir.y = 0.0
	if minimap != null:
		minimap.heading = Vector2(local_dir.x, local_dir.z)
	var step := local_dir.normalized() * MOVE_SPEED * delta
	var p := player.position
	var nx := Vector3(p.x + step.x, p.y, p.z)
	if fd.is_passable_world(nx + Vector3(0.25 * signf(step.x), 0, 0)):
		p = nx
	var nz := Vector3(p.x, p.y, p.z + step.z)
	if fd.is_passable_world(nz + Vector3(0, 0, 0.25 * signf(step.z))):
		p = nz
	player.position = p


# ============================================================================
# UI
# ============================================================================
func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(8, 6)
	hud.size = Vector2(get_window().content_scale_size.x - 100, 40)   # ミニマップ（右上 72 px）と重ねない
	hud.add_theme_font_size_override("font_size", 12)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(hud)
	msg = Label.new()
	msg.anchor_left = 0.05
	msg.anchor_right = 0.95
	msg.anchor_top = 0.84
	msg.anchor_bottom = 0.98
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	msg.add_theme_constant_override("shadow_offset_x", 1)
	msg.add_theme_constant_override("shadow_offset_y", 1)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(msg)
	debug_panel = PanelContainer.new()
	debug_panel.anchor_left = 0.55
	debug_panel.anchor_right = 0.99
	debug_panel.anchor_top = 0.04
	debug_panel.anchor_bottom = 0.75
	debug_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	sb.set_content_margin_all(8)
	debug_panel.add_theme_stylebox_override("panel", sb)
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 11)
	debug_panel.add_child(debug_label)
	ui.add_child(debug_panel)
	pass_rect = TextureRect.new()
	pass_rect.position = Vector2(8, 60)
	pass_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pass_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pass_rect.custom_minimum_size = Vector2(fd.size.x * 4, fd.size.y * 4)
	pass_rect.size = pass_rect.custom_minimum_size
	pass_rect.texture = ImageTexture.create_from_image(fd.passable_image())
	pass_rect.modulate = Color(1, 1, 1, 0.75)
	pass_rect.visible = false
	ui.add_child(pass_rect)
	minimap = Minimap.new()
	minimap.fd = fd
	minimap.field_root = field_root
	minimap.cam = lookdev.cam
	minimap.player = player
	minimap.flags = flags
	minimap.map_px = 72.0
	minimap.position = Vector2(get_window().content_scale_size.x - 80, 8)
	# ビネット（P-2b）: 画面周辺を落とす。vignette=1..3
	if vignette > 0:
		vignette_rect = ColorRect.new()
		vignette_rect.anchor_right = 1.0
		vignette_rect.anchor_bottom = 1.0
		vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float strength = 0.5;\nvoid fragment() { vec2 p = (UV - 0.5) * vec2(1.0, 0.8); float d = length(p) * 2.0; float v = smoothstep(0.55, 1.35, d); COLOR = vec4(0.0, 0.0, 0.0, v * strength); }"
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("strength", [0.0, 0.35, 0.55, 0.75][vignette])
		vignette_rect.material = sm
		ui.add_child(vignette_rect)
		ui.move_child(vignette_rect, 0)
	ui.add_child(minimap)


func _frame_ms() -> float:
	var sum := 0.0
	for v in _deltas:
		sum += v
	return sum / maxf(_deltas.size(), 1) * 1000.0


func _update_hud() -> void:
	# 通常時の HUD は日付と所持品だけ（P-1b）。座標・フレーム時間は F1 のデバッグ画面
	var tod: String = {"morning": "朝", "noon": "昼", "evening": "夕方", "night": "夜"}.get(lookdev.time_name, "")
	hud.text = "8月20日（%s）  %s\n所持品: なし" % [tod, fd.d["name"]]
	if not near_point.is_empty():
		msg.text = "[E] %s" % near_point["label"]
	elif not near_exit.is_empty():
		msg.text = "→ %s（%s）" % [near_exit["to"], near_exit["label"]]
	elif mode == "explore":
		msg.text = ""


# ============================================================================
# 更新
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_F1:
			debug_panel.visible = not debug_panel.visible
		KEY_F2:
			pass_rect.visible = not pass_rect.visible
		KEY_E:
			if not near_point.is_empty():
				msg.text = "%s（%s）を調べた。" % [near_point["label"], near_point["kind"]]
			elif not near_exit.is_empty():
				msg.text = "%s へ移動（このプロトタイプでは切り替えない）" % near_exit["to"]


func _process(delta: float) -> void:
	var cam: Camera3D = lookdev.cam
	_frame_times.append(delta * 1000.0)
	_deltas.append(delta)
	if _deltas.size() > 30:
		_deltas.pop_front()
	if walk_demo and not _demo_state.get("done", true):
		_demo_step(delta)
	else:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir += fwd
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir -= fwd
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir += right
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir -= right
		_move(dir, delta)
	# カメラ追従
	if not fixed_target:
		lookdev.cam_target = player.global_position
		lookdev.cam_target.y = 0.0
		lookdev._apply_camera()
	builder.update_billboards(cam, float(lookdev.base_texel_per_meter))
	_update_near()
	if occl == "fade":
		_apply_occlusion(cam)
	_update_hud()
	if debug_panel.visible:
		_update_debug()
	# measure=1: カメラが主人公に追従した後（20 フレーム目）に、画面内の配置物の数を出す
	_measure_frame += 1
	if _measure_frame == 20 and OS.get_cmdline_user_args().has("measure=1"):
		var n_props := 0
		for pv in builder.billboards:
			if pv != player and cam.is_position_in_frustum(pv.global_position + Vector3(0, 0.5, 0)):
				n_props += 1
		print("PROPS_IN_VIEW %d  render=%s  player=%s" % [n_props, str(get_viewport().get_visible_rect().size), str(_player_tile())])


func _update_near() -> void:
	near_point = {}
	near_exit = {}
	var t := _player_tile()
	var best := INTERACT_TILES
	for p in fd.d.get("points", []):
		if not FieldData.when_ok(p.get("when"), flags):
			continue
		var d := t.distance_to(Vector2(float(p["at"][0]) + 0.5, float(p["at"][1]) + 0.5))
		if d < best:
			best = d
			near_point = p
	for e in fd.d.get("exits", []):
		if t.distance_to(Vector2(float(e["at"][0]) + 0.5, float(e["at"][1]) + 0.5)) < 1.2:
			near_exit = e


## R-2: 主人公とカメラの間にある幾何をフェードで抜く（ART_SPEC 第 2 節）。
## 判定は頭（1.6 m）と腰（0.9 m）の 2 点とカメラを結ぶ線分が、建物・塀の面（壁・屋根の板）に当たるか。
## 建物・塀は α 0.35 まで、配置物（ビルボード）は α 0.5 まで。入り 0.15 s、戻り 0.35 s。シルエットは残す
const FADE_ALPHA_BUILDING := 0.35
const FADE_ALPHA_PROP := 0.5
const FADE_IN_S := 0.15
const FADE_OUT_S := 0.35
var _fade_alpha := {}      # id -> 現在の α

func _apply_occlusion(cam: Camera3D) -> void:
	var from := field_root.to_local(cam.global_position)
	var targets := [player.position + Vector3(0, 1.6, 0), player.position + Vector3(0, 0.9, 0)]
	var delta := get_process_delta_time()
	var any := false
	for id in builder.lot_aabbs:
		var bb: AABB = builder.lot_aabbs[id]
		var hit := false
		for to in targets:
			if bb.intersects_segment(from, to) != null and not bb.has_point(to) and _segment_hits_quads(from, to, builder.lot_quads.get(id, [])):
				hit = true
				break
		if hit:
			any = true
			_fade_ids[id] = int(_fade_ids.get(id, 0)) + 1
		var target := FADE_ALPHA_BUILDING if hit else 1.0
		var cur: float = _fade_alpha.get(id, 1.0)
		var rate := (1.0 - FADE_ALPHA_BUILDING) / (FADE_IN_S if hit else FADE_OUT_S)
		var nxt := move_toward(cur, target, rate * delta)
		if absf(nxt - cur) < 1e-4 and _faded.get(id, false) == hit and nxt == target:
			continue
		_fade_alpha[id] = nxt
		_faded[id] = hit
		for mi in builder.lot_faces[id]:
			var m := mi.material_override as StandardMaterial3D
			if m == null:
				continue
			if nxt >= 0.999:
				m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				m.albedo_color = Color(1, 1, 1, 1)
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			else:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(1, 1, 1, nxt)
				m.cull_mode = BaseMaterial3D.CULL_BACK
	# 配置物（ビルボード）: カメラと主人公の間の帯（線分から 0.6 m 以内）に立つものを薄くする
	for pv in builder.billboards:
		if pv == player:
			continue
		var p := pv.position
		var seg_a := from
		var seg_b := player.position + Vector3(0, 0.9, 0)
		var ab := seg_b - seg_a
		var t := clampf((p - seg_a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var closest := seg_a + ab * t
		var near := t < 0.98 and Vector2(closest.x - p.x, closest.z - p.z).length() < 0.6 and closest.y < 2.5
		var pid := "prop_" + pv.name
		var ptarget := FADE_ALPHA_PROP if near else 1.0
		var pcur: float = _fade_alpha.get(pid, 1.0)
		var pnxt := move_toward(pcur, ptarget, (1.0 - FADE_ALPHA_PROP) / (FADE_IN_S if near else FADE_OUT_S) * delta)
		if absf(pnxt - pcur) < 1e-4:
			continue
		_fade_alpha[pid] = pnxt
		for sp in pv.get_children():
			if sp is Sprite3D:
				sp.modulate = Color(1, 1, 1, pnxt)
		if near:
			any = true
	if any:
		_fade_frames += 1


## 線分と四角形（origin + a·u + b·v, 0 ≤ a, b ≤ 1。tri なら a + b ≤ 1）の交差
static func _segment_hits_quads(from: Vector3, to: Vector3, quads: Array) -> bool:
	var d := to - from
	for q in quads:
		var o: Vector3 = q["o"]
		var u: Vector3 = q["u"]
		var v: Vector3 = q["v"]
		var n := u.cross(v)
		var denom := n.dot(d)
		if absf(denom) < 1e-6:
			continue
		var t := n.dot(o - from) / denom
		if t < 0.0 or t > 1.0:
			continue
		var p := from + d * t - o
		var a := p.dot(u) / u.length_squared()
		var b := p.dot(v) / v.length_squared()
		if a < 0.0 or b < 0.0 or a > 1.0 or b > 1.0:
			continue
		if q.get("tri", false) and a + b > 1.0:
			continue
		return true
	return false


func _update_debug() -> void:
	var t := _player_tile()
	var lines := ["field %s  yaw %d  flags %s" % [field_id, int(fd.d.get("field_yaw", 0)), str(flags.keys())]]
	lines.append("tile (%.2f, %.2f)  passable %s" % [t.x, t.y, fd.is_passable_world(player.position)])
	lines.append("faces %d  AO %.2fs (%s)  lights %d" % [builder.gen.faces.size(), builder.bake_seconds, "cache" if builder.cache_hit else "baked", builder.lights.size()])
	lines.append("frame %.2f ms  fps %d  fade frames %d  (process %.2f ms)" % [_frame_ms(), int(round(1000.0 / maxf(_frame_ms(), 0.01))), _fade_frames, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	lines.append("[WASD] 移動（画面基準）  [E] 調べる  [F2] 通行判定  [Esc] 終了")
	lines.append("draw calls %d  objects %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	lines.append("near: %s / %s" % [near_point.get("id", "-"), near_exit.get("dir", "-")])
	for w in fd.warnings:
		lines.append("warn: " + w)
	debug_label.text = "\n".join(lines)


# ---- 自動歩行（J-4 の計測） ------------------------------------------------------------
func _demo_step(delta: float) -> void:
	var to: Vector2 = _demo_state["to"]
	var target := FieldData.tile_to_world(to.x, to.y)
	var path: Array[Vector2i] = _demo_state["path"]
	var i: int = _demo_state["i"]
	# 経路のタイル中心を順に辿る（最後は出入口の spawn 位置）
	var wp := target
	if i < path.size():
		wp = FieldData.tile_center(path[i].x, path[i].y)
	var d := wp - player.position
	d.y = 0.0
	if i < path.size() and d.length() < 0.15:
		_demo_state["i"] = i + 1
		return
	if i >= path.size() and d.length() < 0.3:
		_demo_state["done"] = true
		var secs := (Time.get_ticks_msec() - int(_demo_state["start_ms"])) / 1000.0
		var ft := _frame_times.slice(10)
		var avg := 0.0
		var mx := 0.0
		for v in ft:
			avg += v
			mx = maxf(mx, v)
		avg /= maxf(ft.size(), 1)
		print("WALK_DEMO {\"seconds\":%.1f,\"frames\":%d,\"frame_ms_avg\":%.2f,\"frame_ms_max\":%.2f,\"fade_frames\":%d,\"distance_m\":%.1f}" % [secs, ft.size(), avg, mx, _fade_frames, FieldData.tile_to_world(_demo_state["from"].x, _demo_state["from"].y).distance_to(target)])
		var rel := field_root.to_local(get_viewport().get_camera_3d().global_position) - player.position
		print("WALK_DEMO_DEBUG toward_cam_measured=(%.2f, %.2f) toward_cam_layout=%s faded=%s" % [Vector2(rel.x, rel.z).normalized().x, Vector2(rel.x, rel.z).normalized().y, str(fd.layout.toward_cam), str(_fade_ids)])
		if OS.get_cmdline_user_args().has("quit_after_demo=1"):
			get_tree().quit()
		return
	var world_dir := field_root.global_transform.basis * d.normalized()
	_move(world_dir, delta)


func _apply_areamask() -> void:
	var cols := {"wall": Color(1, 0, 0), "front": Color(1, 1, 0), "roof": Color(0, 1, 0), "ground": Color(0, 0, 1), "margin": Color(1, 0, 1)}
	for mi in field_root.get_children():
		if not (mi is MeshInstance3D):
			continue
		var n: String = mi.name
		var kind := "wall"
		if n.begins_with("margin_"):
			kind = "margin"
		elif n == "ground" or n.begins_with("walk_") or n.begins_with("narrow_") or n.begins_with("open_") or n.begins_with("patch_"):
			kind = "ground"
		elif "_roof" in n or n.ends_with("_top") or "_soffit" in n or "_gable" in n or n.ends_with("_cap"):
			kind = "roof"
		elif mi.has_meta("front"):
			kind = "front"
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = cols[kind]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
	# 配置物はシアンの無陰影で残す（画面下 1/3 の空白率の計測用。地面 = 青、配置物 = シアン）
	for p in builder.billboards:
		if p == player:
			p.visible = false
			continue
		for sp in p.get_children():
			if sp is Sprite3D:
				sp.shaded = false
				sp.modulate = Color(0, 1, 1)
	if minimap != null:
		minimap.visible = false
	if vignette_rect != null:
		vignette_rect.visible = false


## M-1: 1 画面に写る地面の範囲（画面の四隅の視線と y = 0 の交点）
func _print_ground_range() -> void:
	var cam: Camera3D = lookdev.cam
	var vp := get_viewport().get_visible_rect().size
	var corners := [Vector2(0, 0), Vector2(vp.x, 0), Vector2(0, vp.y), Vector2(vp.x, vp.y)]
	var pts: Array[Vector3] = []
	for c in corners:
		var o: Vector3 = cam.project_ray_origin(c)
		var dir: Vector3 = cam.project_ray_normal(c)
		var t: float = -o.y / dir.y
		pts.append(o + dir * t)
	var top: float = pts[0].distance_to(pts[1])
	var bottom: float = pts[2].distance_to(pts[3])
	var mid_top: Vector3 = (pts[0] + pts[1]) * 0.5
	var mid_bottom: Vector3 = (pts[2] + pts[3]) * 0.5
	var depth: float = mid_top.distance_to(mid_bottom)
	print("GROUND_RANGE {\"pitch\":%.1f,\"top_m\":%.1f,\"bottom_m\":%.1f,\"depth_m\":%.1f,\"area_m2\":%.0f,\"cam_height_m\":%.1f,\"cam_distance_m\":%.1f}" % [-lookdev.cam_pitch_deg, top, bottom, depth, (top + bottom) * 0.5 * depth, cam.global_position.y, lookdev.cam_distance])
