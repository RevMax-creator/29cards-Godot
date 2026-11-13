extends Node

var _haptics_enabled: bool = true

func set_haptics_enabled(enabled: bool) -> void:
	_haptics_enabled = enabled

func light_tap() -> void:
	if _haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(15)

func heavy_impact() -> void:
	if _haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)

func error_buzz() -> void:
	if _haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(80)
