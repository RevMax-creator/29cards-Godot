extends Node

signal profile_changed(profile: Dictionary)

const SAVE_PATH: String = "user://player_profile.cfg"
const AVATAR_CATALOG: Array = [
	{"id": "byte", "name": "Byte", "path": "res://assets/avatars/byte.svg"},
	{"id": "flick", "name": "Flick", "path": "res://assets/avatars/flick.svg"},
	{"id": "sage", "name": "Sage", "path": "res://assets/avatars/sage.svg"},
	{"id": "panda", "name": "Panda", "path": "res://assets/avatars/panda.svg"},
	{"id": "echo", "name": "Echo", "path": "res://assets/avatars/echo.svg"},
	{"id": "moss", "name": "Moss", "path": "res://assets/avatars/moss.svg"},
	{"id": "pixel", "name": "Pixel", "path": "res://assets/avatars/pixel.svg"},
	{"id": "bruno", "name": "Bruno", "path": "res://assets/avatars/bruno.svg"}
]

const DEFAULT_AI_BY_RELATIVE_SEAT: Dictionary = {
	1: {"display_name": "Flick", "avatar_id": "flick"},
	2: {"display_name": "Sage", "avatar_id": "sage"},
	3: {"display_name": "Moss", "avatar_id": "moss"}
}

var display_name: String = "Byte"
var avatar_id: String = "byte"

func _ready() -> void:
	load_profile()

func get_avatar_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in AVATAR_CATALOG:
		result.append(entry.duplicate(true))
	return result

func is_valid_avatar(id: String) -> bool:
	for entry in AVATAR_CATALOG:
		if str(entry["id"]) == id:
			return true
	return false

func get_avatar_name(id: String) -> String:
	for entry in AVATAR_CATALOG:
		if str(entry["id"]) == id:
			return str(entry["name"])
	return "Byte"

func get_avatar_path(id: String) -> String:
	for entry in AVATAR_CATALOG:
		if str(entry["id"]) == id:
			return str(entry["path"])
	return "res://assets/avatars/byte.svg"

func get_avatar_texture(id: String = "") -> Texture2D:
	var resolved_id: String = avatar_id if id.is_empty() else id
	var path: String = get_avatar_path(resolved_id)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func get_profile() -> Dictionary:
	return {"display_name": display_name, "avatar_id": avatar_id, "avatar_name": get_avatar_name(avatar_id)}

func get_ai_profile(relative_seat: int) -> Dictionary:
	var profile: Dictionary = DEFAULT_AI_BY_RELATIVE_SEAT.get(relative_seat, {"display_name": "Player", "avatar_id": "byte"})
	return profile.duplicate(true)

func get_remote_placeholder(relative_seat: int) -> Dictionary:
	return {"display_name": "PLAYER %d" % (relative_seat + 1), "avatar_id": "byte"}

func set_profile(new_display_name: String, new_avatar_id: String) -> void:
	var clean_name: String = new_display_name.strip_edges()
	clean_name = clean_name.left(16)
	if clean_name.is_empty():
		clean_name = get_avatar_name(new_avatar_id) if is_valid_avatar(new_avatar_id) else "Byte"
	display_name = clean_name
	avatar_id = new_avatar_id if is_valid_avatar(new_avatar_id) else "byte"
	save_profile()
	profile_changed.emit(get_profile())

func load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var loaded_id: String = str(config.get_value("profile", "avatar_id", "byte"))
		var loaded_name: String = str(config.get_value("profile", "display_name", "Byte"))
		avatar_id = loaded_id if is_valid_avatar(loaded_id) else "byte"
		display_name = loaded_name.strip_edges().left(16)
		if display_name.is_empty():
			display_name = get_avatar_name(avatar_id)
	else:
		avatar_id = "byte"
		display_name = "Byte"
		save_profile()

func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "display_name", display_name)
	config.set_value("profile", "avatar_id", avatar_id)
	var err: Error = config.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not save player profile: %s" % error_string(err))

func to_network_metadata() -> Dictionary:
	# Safe presentation metadata for the future authenticated M2 seat handshake.
	return {
		"display_name": display_name,
		"avatar_id": avatar_id,
		"profile_schema": 1
	}
