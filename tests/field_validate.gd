extends SceneTree
## data/fields/*.json をすべて読み、検証（未定義 kind / asset、矩形の重なり、出入口、連結性）する。
##   godot --headless --path . --script res://tests/field_validate.gd


func _init() -> void:
	var dir := DirAccess.open("res://data/fields")
	if dir == null:
		printerr("field_validate: data/fields が無い")
		quit(1)
		return
	var failed := 0
	var count := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		count += 1
		var fd := FieldData.new()
		var ok := fd.load("res://data/fields/" + f)
		print("field_validate: %s size=%s walk=%d buildings=%d lots=%d props=%d points=%d exits=%d reachable=%d/%d %s" % [
			f, str(fd.size), fd.walk_count(), fd.d.get("buildings", []).size(), fd.lots.size(), fd.d.get("props", []).size(), fd.d.get("points", []).size(), fd.d.get("exits", []).size(),
			fd.reachable_count(), fd.walk_count(), "OK" if ok else "FAIL"])
		var lowered := 0
		for l in fd.lots:
			if l.get("lowered", false):
				lowered += 1
				print("  階数を落とした: %s %s ← %s" % [l["id"], str(l["rect"]), l.get("lowered_by", "")])
		print("  遮蔽の式（助言）: 主人公を隠しうる建物 %d、隠される歩行可能タイル %d（実行時はフェードで抜く）" % [fd.lots.filter(func(l): return int(l.get("violates", 0)) > 0).size(), fd.layout.violations.size()])
		for v in fd.layout.violations.slice(0, 8):
			print("    %s が (%d,%d) を隠す: %s まで %.1f m、必要 %.1f m" % [v["lot"], v["tile"].x, v["tile"].y, v["part"], v["dist_m"], v["need_m"]])
		print("  近景の屋根（5 m 以内）: 建物 %d、歩行可能タイル %d" % [fd.lots.filter(func(l): return int(l.get("near_roof", 0)) > 0).size(), fd.layout.near_roofs.size()])
		for v in fd.layout.near_roofs.slice(0, 6):
			print("    %s が (%d,%d) の手前 %.1f m" % [v["lot"], v["tile"].x, v["tile"].y, v["dist_m"]])
		var ts: Dictionary = fd.terrain_stats
		if ts.get("height", false):
			print("  高さ: terrain %d、登れない段差の縁（歩けるタイル間） %d、段差で分断 %d、急な坂のタイル %d" % [int(ts.get("rects", 0)), int(ts.get("blocked_edges", 0)), int(ts.get("cut_off", 0)), int(ts.get("steep_tiles", 0))])
			for st in ts.get("stairs", []):
				print("    階段 %s: %d 段、%.1f m（%s%s）" % [str(st["rect"]), int(st["steps"]), float(st["rise_m"]), st["axis"], "+" if int(st["dir"]) > 0 else "-"])
		var out := "res://cache/fields/%s/occlusion.png" % fd.d["id"]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		fd.layout.occlusion_image().save_png(ProjectSettings.globalize_path(out))
		print("  図: %s" % out)
		for e in fd.errors:
			printerr("  ERROR " + e)
		for w in fd.warnings:
			print("  warn  " + w)
		if not ok:
			failed += 1
	if count == 0:
		printerr("field_validate: フィールドが無い")
		quit(1)
		return
	quit(0 if failed == 0 else 1)
