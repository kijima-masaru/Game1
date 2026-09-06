extends Node2D
## メインシーン。起動確認用に経過時間をラベルに表示する。

@onready var label: Label = $Label

var _elapsed := 0.0


func _ready() -> void:
	label.text = "Game1 - Godot %s" % Engine.get_version_info().string


func _process(delta: float) -> void:
	_elapsed += delta
	label.text = "Game1 - Godot %s\n経過時間: %.1f 秒" % [
		Engine.get_version_info().string,
		_elapsed,
	]
