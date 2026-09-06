extends SceneTree
## スモークテスト。ヘッドレスでメインシーンをロード・実体化して、
## スクリプトがエラーなく動くことを確認する。
##
##   godot --headless --path . --script res://tests/smoke_test.gd


func _init() -> void:
	var failures: PackedStringArray = []

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		failures.append("main.tscn をロードできません")
	else:
		var main := packed.instantiate()
		root.add_child(main)
		if not (main is Node2D):
			failures.append("Main ノードが Node2D ではありません")
		if main.get_node_or_null("Label") == null:
			failures.append("Label ノードがありません")
		else:
			var label: Label = main.get_node("Label")
			if not label.text.begins_with("Game1"):
				failures.append("Label のテキストが想定外です: %s" % label.text)
		main.queue_free()

	if failures.is_empty():
		print("smoke_test: OK")
		quit(0)
	else:
		for f in failures:
			printerr("smoke_test: FAIL - %s" % f)
		quit(1)
