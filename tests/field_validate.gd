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
		for l in fd.lots:
			if l.get("near_band", false):
				print("  near-band 1F: %s %s" % [l["id"], str(l["rect"])])
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
