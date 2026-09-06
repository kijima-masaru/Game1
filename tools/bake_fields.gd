extends SceneTree
## 全フィールドの AO キャッシュ（res://cache/fields/<id>/）を焼き直す。配布ビルド前と、テクスチャ生成を変えたときに実行する。
##   godot --headless --path . --script res://tools/bake_fields.gd            # キャッシュが古いものだけ
##   godot --headless --path . --script res://tools/bake_fields.gd -- all     # すべて焼き直す
## 描画は要らない（AO は CPU のレイキャスト）。所要時間をフィールドごとに出す。


func _init() -> void:
	var force := OS.get_cmdline_user_args().has("all")
	var dir := DirAccess.open("res://data/fields")
	if dir == null:
		printerr("bake_fields: data/fields が無い")
		quit(1)
		return
	var failed := 0
	var root := Node3D.new()
	get_root().add_child(root)
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var fd := FieldData.new()
		if not fd.load("res://data/fields/" + f):
			for e in fd.errors:
				printerr("  ERROR " + e)
			failed += 1
			continue
		var t0 := Time.get_ticks_msec()
		var b := FieldBuilder.new()
		var node := b.build(fd, root, {}, 0.0, force)
		print("bake_fields: %s faces=%d AO %.2fs (%s) total %.2fs" % [fd.d["id"], b.gen.faces.size(), b.bake_seconds, "cache hit" if b.cache_hit else "baked", (Time.get_ticks_msec() - t0) / 1000.0])
		node.queue_free()
	quit(0 if failed == 0 else 1)
