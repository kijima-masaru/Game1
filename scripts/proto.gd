extends Node3D
## 縦切りプロトタイプ（F-2 / G-2）: 8/1〜8/3、NPC 2 人、調査対象 1 つ。
## 背景は lookdev シーンをそのまま子として置く。新規素材は無し（人物は生成した板）。
##
##   godot --path . res://scenes/proto.tscn
##   godot --path . res://scenes/proto.tscn -- proto_shot=<dir>   # デモ操作を自動再生してスクリーンショット
##
## 操作: WASD/矢印 移動  E 話す/調べる  1〜4 選択  Enter/Space 進める
##       N 手帳  F1 デバッグ  T その日を終える  F5 セーブ  F9 ロード  Esc 終了

const SAVE_PATH := "user://proto_save.json"
const SAVE_VERSION := 1
const MOVE_SPEED := 3.0

var lookdev: Node3D
var runner: StoryRunner
var player: Node3D
var player_sprite: Sprite3D
var actors := {}          # id -> {pivot, sprite, pos, kind}
var interact_target := "" # 近くにいる対象の id
var mode := "explore"     # explore / dialogue / notebook / debug / text / ending
var current_step := {}
var current_npc := ""
var pending_text_queue: Array[String] = []

var ui: CanvasLayer
var hud_label: Label
var dlg_panel: PanelContainer
var dlg_name: Label
var dlg_text: Label
var dlg_options: VBoxContainer
var book_panel: PanelContainer
var book_text: Label
var debug_panel: PanelContainer
var debug_text: Label
var hint_label: Label

# デモ撮影
var shot_dir := ""
var _shot_frame := 0
var _shot_plan: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("proto_shot="):
			shot_dir = a.substr(11)
	# 背景: lookdev（既定値 = ART_SPEC）。HUD は消す
	lookdev = load("res://scenes/lookdev.tscn").instantiate()
	add_child(lookdev)
	lookdev.hud_on = false
	lookdev._update_hud()
	# 脚本とエンジン
	var data := StoryRunner.load_script()
	var errs := StoryState.validate(data)
	for e in errs:
		push_error("脚本: " + e)
	runner = StoryRunner.new()
	runner.setup(data)
	_build_actors()
	_build_ui()
	_show_text(data.get("prologue", "") + "\n\n" + runner.intro_text())
	if shot_dir != "":
		_plan_shots()


# ============================================================================
# 人物と対象（単色の板。ART_SPEC 第 5 節: Nearest + 整数倍スナップ、カメラ正対）
# ============================================================================
func _figure_image(body: Color, head: Color, w: int = 16, h: int = 48) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(4, 0, 8, 8), head)                   # 頭
	img.fill_rect(Rect2i(3, 8, 10, 22), body)                 # 胴
	img.fill_rect(Rect2i(3, 30, 4, 18), body.darkened(0.3))   # 脚
	img.fill_rect(Rect2i(9, 30, 4, 18), body.darkened(0.3))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and (x == 3 or x == 12 or y == 0 or y == h - 1 or (y == 8 and x >= 4 and x <= 11)):
				img.set_pixel(x, y, Color(0.08, 0.08, 0.1))
	return img


func _marker_image() -> Image:
	# 調査対象（鳥居のつもりの板）
	var img := Image.create(40, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var red := Color(0.62, 0.16, 0.14)
	img.fill_rect(Rect2i(4, 0, 32, 5), red)
	img.fill_rect(Rect2i(8, 9, 24, 3), red)
	img.fill_rect(Rect2i(8, 5, 4, 51), red)
	img.fill_rect(Rect2i(28, 5, 4, 51), red)
	return img


func _add_actor(id: String, img: Image, pos: Vector3, kind: String) -> void:
	var pivot := Node3D.new()
	pivot.name = "Actor_" + id
	pivot.position = pos
	add_child(pivot)
	var sp := Sprite3D.new()
	sp.texture = ImageTexture.create_from_image(img)
	sp.pixel_size = lookdev.pixel_size
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.alpha_scissor_threshold = 0.5
	sp.shaded = true
	sp.double_sided = true
	sp.position = Vector3(0, img.get_height() * lookdev.pixel_size * 0.5, 0)
	pivot.add_child(sp)
	actors[id] = {"pivot": pivot, "sprite": sp, "kind": kind, "h": img.get_height()}


func _build_actors() -> void:
	_add_actor("player", _figure_image(Color(0.55, 0.58, 0.62), Color(0.85, 0.72, 0.6)), Vector3(-2.0, 0.12, 1.0), "player")
	player = actors["player"]["pivot"]
	player_sprite = actors["player"]["sprite"]
	_add_actor("kanae", _figure_image(Color(0.75, 0.62, 0.7), Color(0.85, 0.72, 0.6)), Vector3(-6.0, 0.12, -2.5), "npc")
	_add_actor("naoto", _figure_image(Color(0.3, 0.35, 0.5), Color(0.8, 0.68, 0.56)), Vector3(2.0, 0.12, 2.5), "npc")
	_add_actor("shrine", _marker_image(), Vector3(-14.0, 0.12, -3.0), "target")


## 板の向きと整数倍スナップ（ART_SPEC 第 5 節）
func _update_billboards() -> void:
	var cam: Camera3D = lookdev.cam
	var basis := cam.global_transform.basis
	for id in actors:
		var a: Dictionary = actors[id]
		var p: Node3D = a["pivot"]
		p.global_transform.basis = basis
		var base := p.global_position
		var top := base + basis.y * 1.0
		var h_px := absf(cam.unproject_position(base).y - cam.unproject_position(top).y)
		var ratio: float = h_px / float(lookdev.base_texel_per_meter)
		var sc := maxf(round(ratio), 1.0) / maxf(ratio, 0.001)
		var sp: Sprite3D = a["sprite"]
		sp.scale = Vector3(sc, sc, sc)
		sp.position = Vector3(0, a["h"] * lookdev.pixel_size * 0.5 * sc, 0)


# ============================================================================
# UI
# ============================================================================
func _panel(minsize: Vector2, anchor_bottom: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = minsize
	if anchor_bottom:
		p.anchor_left = 0.05
		p.anchor_right = 0.95
		p.anchor_top = 0.66
		p.anchor_bottom = 0.98
	else:
		p.anchor_left = 0.05
		p.anchor_right = 0.95
		p.anchor_top = 0.04
		p.anchor_bottom = 0.96
	p.offset_left = 0
	p.offset_right = 0
	p.offset_top = 0
	p.offset_bottom = 0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	sb.border_color = Color(0.7, 0.7, 0.75)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	ui.add_child(p)
	return p


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "ProtoUI"
	add_child(ui)
	hud_label = Label.new()
	hud_label.position = Vector2(8, 6)
	hud_label.add_theme_font_size_override("font_size", 14)
	hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud_label.add_theme_constant_override("shadow_offset_x", 1)
	hud_label.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(hud_label)
	hint_label = Label.new()
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 0.58
	hint_label.anchor_bottom = 0.58
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(hint_label)

	dlg_panel = _panel(Vector2(0, 0), true)
	var v := VBoxContainer.new()
	dlg_panel.add_child(v)
	dlg_name = Label.new()
	dlg_name.add_theme_font_size_override("font_size", 14)
	dlg_name.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	v.add_child(dlg_name)
	dlg_text = Label.new()
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_text.add_theme_font_size_override("font_size", 15)
	dlg_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(dlg_text)
	dlg_options = VBoxContainer.new()
	v.add_child(dlg_options)

	book_panel = _panel(Vector2(0, 0), false)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book_panel.add_child(sc)
	book_text = Label.new()
	book_text.add_theme_font_size_override("font_size", 14)
	book_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(book_text)

	debug_panel = _panel(Vector2(0, 0), false)
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_panel.add_child(sc2)
	debug_text = Label.new()
	debug_text.add_theme_font_size_override("font_size", 11)
	debug_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(debug_text)
	_update_hud()


func _update_hud() -> void:
	var st := runner.state.s
	var parts := ["8/%d" % st["day"]]
	for nid in st["npc"]:
		parts.append("%s: stage %d / %s" % [runner.npc_name(nid), st["npc"][nid]["stage"], st["npc"][nid]["relation"]])
	hud_label.text = "  ".join(parts) + "\n[WASD] 移動  [E] 話す/調べる  [N] 手帳  [T] 日を終える  [F1] デバッグ  [F5] セーブ  [F9] ロード"


# ---- テキスト表示（地の文・結末） ----------------------------------------------------
func _show_text(text: String) -> void:
	mode = "text"
	dlg_panel.visible = true
	dlg_name.text = ""
	dlg_text.text = text
	_clear_options()
	hint_label.text = ""


func _clear_options() -> void:
	for c in dlg_options.get_children():
		c.queue_free()


# ---- 会話 ----------------------------------------------------------------------
func _start_talk(nid: String) -> void:
	current_npc = nid
	mode = "dialogue"
	dlg_panel.visible = true
	_advance()


func _advance() -> void:
	var step := runner.next_step(current_npc)
	current_step = step
	dlg_name.text = runner.npc_name(current_npc)
	_clear_options()
	match step["type"]:
		"line":
			dlg_text.text = step["text"] + "\n\n[Enter] 続ける"
			if step.get("final", false):
				current_step["type"] = "end"
		"end":
			dlg_text.text = step["text"] + "\n\n[Enter] 閉じる"
		"node":
			dlg_text.text = step["node"]["prompt"]
			for o in step["options"]:
				_add_option("%d. %s %s" % [o["index"] + 1, o["label"], o.get("note", "")], o["index"])
		"confront":
			dlg_text.text = step["text"]
			for i in step["options"].size():
				_add_option("%d. %s" % [i + 1, step["options"][i]["label"]], i)
	_update_hud()


func _add_option(label: String, idx: int) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): _pick(idx))
	dlg_options.add_child(b)


func _pick(idx: int) -> void:
	if mode != "dialogue":
		return
	var resp := ""
	if current_step["type"] == "node":
		var r := runner.choose(current_step, idx)
		resp = r["response"]
	elif current_step["type"] == "confront":
		var r := runner.choose_confront(current_step, current_step["options"][idx]["outcome"])
		resp = r["response"]
	else:
		return
	_clear_options()
	dlg_text.text = resp + "\n\n[Enter] 続ける"
	current_step = {"type": "response"}
	_update_hud()


func _close_dialogue() -> void:
	mode = "explore"
	dlg_panel.visible = false
	current_step = {}


# ---- 調べる / 日替わり ---------------------------------------------------------------
func _visit(target: String) -> void:
	var r := runner.visit(target)
	_show_text(r["text"])


func _end_day() -> void:
	var r := runner.end_day()
	_save(true)
	if r["ending"] != "":
		mode = "ending"
		dlg_panel.visible = true
		dlg_name.text = ""
		dlg_text.text = r["text"] + "\n\n（プロトタイプはここまで。[Esc] で終了）"
		_clear_options()
	else:
		_show_text(runner.intro_text())
	_update_hud()


# ---- 手帳 / デバッグ ---------------------------------------------------------------
func _toggle_book() -> void:
	if mode == "notebook":
		book_panel.visible = false
		mode = "explore"
		return
	if mode != "explore":
		return
	book_text.text = "手帳 ─ 私が言ったこと\n\n" + "\n".join(runner.notebook_lines()) + "\n\n[N] 閉じる"
	book_panel.visible = true
	mode = "notebook"


func _toggle_debug() -> void:
	if mode == "debug":
		debug_panel.visible = false
		mode = "explore"
		return
	if mode != "explore":
		return
	var verify := _verify_replay()
	debug_text.text = runner.debug_text() + "\n-- replay check: %s --\n[F1] 閉じる" % verify
	debug_panel.visible = true
	mode = "debug"


func _verify_replay() -> String:
	var rep := StoryState.replay(runner.data, runner.state.events)
	return "一致" if JSON.stringify(rep.s) == JSON.stringify(runner.state.s) else "不一致"


# ---- セーブ / ロード（スナップショットが正。Event 列は監査用） ------------------------------
func _save(auto: bool = false) -> void:
	var d := {
		"version": SAVE_VERSION, "auto": auto,
		"snapshot": runner.state.snapshot(), "events": runner.state.events,
		"player": [player.position.x, player.position.z],
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	hint_label.text = "セーブした（%s）" % ("オート" if auto else "手動")


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		hint_label.text = "セーブが無い"
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != SAVE_VERSION:
		hint_label.text = "セーブの版が違う"
		return
	runner.state.load_snapshot(d["snapshot"])
	runner.state.events = d.get("events", [])
	player.position = Vector3(d["player"][0], 0.12, d["player"][1])
	_close_dialogue()
	hint_label.text = "ロードした"
	_update_hud()


# ============================================================================
# 入力と更新
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k == KEY_ESCAPE:
		get_tree().quit()
		return
	match mode:
		"explore":
			match k:
				KEY_E:
					_interact()
				KEY_N:
					_toggle_book()
				KEY_F1:
					_toggle_debug()
				KEY_T:
					_end_day()
				KEY_F5:
					_save(false)
				KEY_F9:
					_load()
		"dialogue":
			if k == KEY_ENTER or k == KEY_SPACE:
				if current_step.get("type", "") in ["line", "response"]:
					_advance()
				elif current_step.get("type", "") == "end":
					_close_dialogue()
			elif k >= KEY_1 and k <= KEY_4 and current_step.get("type", "") in ["node", "confront"]:
				var idx := k - KEY_1
				if idx < dlg_options.get_child_count():
					_pick(idx)
		"text":
			if k == KEY_ENTER or k == KEY_SPACE:
				_close_dialogue()
		"notebook":
			if k == KEY_N or k == KEY_ENTER:
				_toggle_book()
		"debug":
			if k == KEY_F1 or k == KEY_ENTER:
				_toggle_debug()
		"ending":
			pass


func _interact() -> void:
	if interact_target == "":
		return
	var a: Dictionary = actors[interact_target]
	if a["kind"] == "npc":
		_start_talk(interact_target)
	elif a["kind"] == "target":
		_visit(interact_target)


func _process(delta: float) -> void:
	if mode == "explore":
		var dir := Vector3.ZERO
		# カメラ基準（画面の上 = カメラの前方を地面に投影）
		var cam: Camera3D = lookdev.cam
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir += fwd
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir -= fwd
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir += right
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir -= right
		if dir.length_squared() > 0.0:
			var p := player.position + dir.normalized() * MOVE_SPEED * delta
			p.x = clampf(p.x, -30.0, 12.0)
			p.z = clampf(p.z, -5.2, 5.2)
			player.position = p
		# 近くの対象
		interact_target = ""
		var best := 1.8
		for id in actors:
			if id == "player":
				continue
			var d := player.position.distance_to(actors[id]["pivot"].position)
			if d < best:
				best = d
				interact_target = id
		if interact_target != "":
			var a: Dictionary = actors[interact_target]
			var label: String = runner.npc_name(interact_target) if a["kind"] == "npc" else runner.data["targets"][interact_target]["label"]
			hint_label.text = "[E] %s" % (("%s と話す" % label) if a["kind"] == "npc" else ("%s を調べる" % label))
		elif not hint_label.text.begins_with("セーブ") and not hint_label.text.begins_with("ロード"):
			hint_label.text = ""
	# カメラ追従（注視点 = 主人公の足元。ART_SPEC の基準面）
	lookdev.cam_target = Vector3(player.position.x, 0.0, player.position.z)
	lookdev._apply_camera()
	_update_billboards()
	if shot_dir != "":
		_run_shot_plan()


# ============================================================================
# デモ撮影（proto_shot=<dir>）: 決まった操作列を再生しながら撮る
# ============================================================================
func _plan_shots() -> void:
	_shot_plan = [
		[40, "shot", "01_prologue"],
		[45, "key", KEY_ENTER],
		[50, "move_to", Vector3(-5.0, 0.12, -1.5)],
		[60, "shot", "02_explore"],
		[62, "key", KEY_E],
		[70, "shot", "03_dialogue_choice"],
		[72, "key", KEY_2],
		[80, "shot", "04_dialogue_response"],
		[82, "key", KEY_ENTER],
		[90, "key", KEY_3],
		[96, "key", KEY_ENTER],
		[102, "shot", "05_stage_line"],
		[104, "key", KEY_ENTER],
		[108, "key", KEY_ENTER],
		[112, "key", KEY_N],
		[120, "shot", "06_notebook"],
		[122, "key", KEY_N],
		[126, "key", KEY_F1],
		[134, "shot", "07_debug"],
		[136, "key", KEY_F1],
		[140, "key", KEY_F5],
		[144, "key", KEY_T],
		[152, "shot", "08_day2_intro"],
		[158, "quit", ""],
	]


func _run_shot_plan() -> void:
	_shot_frame += 1
	for item in _shot_plan:
		if item[0] != _shot_frame:
			continue
		match item[1]:
			"shot":
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/%s.png" % [shot_dir, item[2]])
				print("proto: shot %s" % item[2])
			"key":
				var ev := InputEventKey.new()
				ev.keycode = item[2]
				ev.pressed = true
				_unhandled_input(ev)
			"move_to":
				player.position = item[2]
			"quit":
				get_tree().quit()
