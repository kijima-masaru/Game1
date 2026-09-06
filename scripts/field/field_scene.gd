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
var mode := "explore"
var near_point := {}
var near_exit := {}
var _demo_state := {}
var _frame_times: Array[float] = []
var _fade_frames := 0
var _faded := {}


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
	lookdev = load("res://scenes/lookdev.tscn").instantiate()
	lookdev.layout = "empty"
	add_child(lookdev)
	fd = FieldData.new()
	fd.load("res://data/fields/%s.json" % field_id.to_lower())
	for e in fd.errors:
		push_error("field %s: %s" % [field_id, e])
	if not is_nan(field_yaw_override):
		fd.d["field_yaw"] = field_yaw_override
	builder = FieldBuilder.new()
	builder.pixel_size = lookdev.pixel_size
	field_root = builder.build(fd, self, flags, lookdev.cam_yaw_deg, regen)
	builder.set_lights(_lamps_on())
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
	if walk_demo:
		var path := fd.find_path(Vector2i(_exit_spawn("N")), Vector2i(_exit_spawn("S")))
		_demo_state = {"from": _exit_spawn("N"), "to": _exit_spawn("S"), "path": path, "i": 0, "done": path.is_empty(), "start_ms": Time.get_ticks_msec()}
		if path.is_empty():
			printerr("walk_demo: 北→南の経路が無い")
	print("FIELD %s built in %.2fs (AO %.2fs, cache %s), faces=%d, passable=%d/%d" % [field_id, (Time.get_ticks_msec() - t0) / 1000.0, builder.bake_seconds, "hit" if builder.cache_hit else "baked", builder.gen.faces.size(), fd.reachable_count(), fd.size.x * fd.size.y])


func _lamps_on() -> bool:
	return bool(lookdev.TIMES[lookdev.time_name]["lamps"])


func _exit_spawn(dir: String) -> Vector2:
	for e in fd.d.get("exits", []):
		if e["dir"] == dir:
			return Vector2(float(e["spawn"][0]) + 0.5, float(e["spawn"][1]) + 0.5)
	return Vector2(fd.size.x * 0.5, fd.size.y * 0.5)


# ============================================================================
# 主人公
# ============================================================================
func _figure_image() -> Image:
	var w := 16
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(4, 0, 8, 8), Color(0.85, 0.72, 0.6))
	img.fill_rect(Rect2i(3, 8, 10, 22), Color(0.55, 0.58, 0.62))
	img.fill_rect(Rect2i(3, 30, 4, 18), Color(0.35, 0.36, 0.40))
	img.fill_rect(Rect2i(9, 30, 4, 18), Color(0.35, 0.36, 0.40))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and (x == 3 or x == 12 or y == 0 or y == h - 1 or (y == 8 and x >= 4 and x <= 11)):
				img.set_pixel(x, y, Color(0.08, 0.08, 0.1))
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
	hud.add_theme_font_size_override("font_size", 13)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(hud)
	msg = Label.new()
	msg.anchor_left = 0.05
	msg.anchor_right = 0.95
	msg.anchor_top = 0.82
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


func _update_hud() -> void:
	var t := _player_tile()
	var parts := ["%s %s   tile (%.1f, %.1f)   %.1f ms/frame  %d fps" % [field_id, fd.d["name"], t.x, t.y, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, int(Engine.get_frames_per_second())]]
	parts.append("[WASD] 移動（画面基準）  [E] 調べる  [F1] デバッグ  [F2] 通行判定  field_yaw %d" % int(fd.d.get("field_yaw", 0)))
	hud.text = "\n".join(parts)
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
	_frame_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
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


func _apply_occlusion(cam: Camera3D) -> void:
	var from := field_root.to_local(cam.global_position)
	var to := player.position + Vector3(0, 0.9, 0)
	var any := false
	for id in builder.lot_aabbs:
		var bb: AABB = builder.lot_aabbs[id]
		var hit := bb.intersects_segment(from, to) != null and not bb.has_point(to)
		if hit:
			any = true
		if hit == _faded.get(id, false):
			continue
		_faded[id] = hit
		for mi in builder.lot_faces[id]:
			var m := mi.material_override as StandardMaterial3D
			if m == null:
				continue
			if hit:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(1, 1, 1, 0.35)
				m.cull_mode = BaseMaterial3D.CULL_BACK
			else:
				m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				m.albedo_color = Color(1, 1, 1, 1)
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if any:
		_fade_frames += 1


func _update_debug() -> void:
	var t := _player_tile()
	var lines := ["field %s  yaw %d  flags %s" % [field_id, int(fd.d.get("field_yaw", 0)), str(flags.keys())]]
	lines.append("tile (%.2f, %.2f)  passable %s" % [t.x, t.y, fd.is_passable_world(player.position)])
	lines.append("faces %d  AO %.2fs (%s)  lights %d" % [builder.gen.faces.size(), builder.bake_seconds, "cache" if builder.cache_hit else "baked", builder.lights.size()])
	lines.append("frame %.2f ms  fps %d  fade frames %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, int(Engine.get_frames_per_second()), _fade_frames])
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
		if OS.get_cmdline_user_args().has("quit_after_demo=1"):
			get_tree().quit()
		return
	var world_dir := field_root.global_transform.basis * d.normalized()
	_move(world_dir, delta)


func _apply_areamask() -> void:
	var cols := {"wall": Color(1, 0, 0), "roof": Color(0, 1, 0), "ground": Color(0, 0, 1), "margin": Color(1, 0, 1)}
	for mi in field_root.get_children():
		if not (mi is MeshInstance3D):
			continue
		var n: String = mi.name
		var kind := "wall"
		if n.begins_with("margin_"):
			kind = "margin"
		elif n == "ground" or n.begins_with("road_") or n.begins_with("patch_"):
			kind = "ground"
		elif "_roof" in n or n.ends_with("_top") or "_soffit" in n or "_gable" in n or n.ends_with("_cap"):
			kind = "roof"
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = cols[kind]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
	for p in builder.billboards:
		p.visible = false
