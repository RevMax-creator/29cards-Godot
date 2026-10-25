extends Node

const SAVE_SCHEMA_VERSION: int = 2
const SOLO_PREFIX: String = "user://solo_29_save_v1"
const MP_RECOVERY_PREFIX: String = "user://mp_29_recovery_v1"

var _save_sequence_counter: int = 0

func save_solo_state(state: GameState) -> bool:
	return _write_ab_atomic_checkpoint(SOLO_PREFIX, state)

func has_valid_solo_save() -> bool:
	return _read_verified_ab_checkpoint(SOLO_PREFIX) != null

func load_solo_save() -> GameState:
	return _read_verified_ab_checkpoint(SOLO_PREFIX)

func clear_solo_save() -> void:
	_clear_ab_slots(SOLO_PREFIX)

func save_multiplayer_recovery_state(state: GameState) -> bool:
	return _write_ab_atomic_checkpoint(MP_RECOVERY_PREFIX, state)

func load_multiplayer_recovery_state() -> GameState:
	return _read_verified_ab_checkpoint(MP_RECOVERY_PREFIX)

func clear_multiplayer_recovery_state() -> void:
	_clear_ab_slots(MP_RECOVERY_PREFIX)

func _get_slot_a_path(prefix: String) -> String:
	return prefix + "_slot_a.json"

func _get_slot_b_path(prefix: String) -> String:
	return prefix + "_slot_b.json"

func _get_staging_path(prefix: String) -> String:
	return prefix + "_staging.tmp"

func _clear_ab_slots(prefix: String) -> void:
	for path in [_get_slot_a_path(prefix), _get_slot_b_path(prefix), _get_staging_path(prefix)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _write_ab_atomic_checkpoint(prefix: String, state: GameState) -> bool:
	if state == null:
		return false

	_save_sequence_counter += 1
	var state_dict: Dictionary = state.to_authoritative_dict()
	var state_json: String = JSON.stringify(state_dict)
	var sha256_digest: String = state_json.sha256_text()

	# Select the older/inactive slot so a crash mid-write never destroys the last valid checkpoint
	var target_slot_path: String = _choose_target_slot_for_write(prefix)
	var staging_path: String = _get_staging_path(prefix)

	var wrapper: Dictionary = {
		"schema_version": SAVE_SCHEMA_VERSION,
		"save_sequence": _save_sequence_counter,
		"state_revision": state.state_revision,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"sha256": state_json.sha256_text(),
		"payload_json": state_json
	}

	var file := FileAccess.open(staging_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(wrapper))
	file.flush()
	file = null

	# Verify staged file before replacing target slot
	if _parse_and_verify_slot_file(staging_path).is_empty():
		if FileAccess.file_exists(staging_path):
			DirAccess.remove_absolute(staging_path)
		return false

	# Explicitly remove existing target slot file before rename so overwrite succeeds on all OS filesystems
	if FileAccess.file_exists(target_slot_path):
		var rm_err: Error = DirAccess.remove_absolute(target_slot_path)
		if rm_err != OK:
			return false

	var rename_err: Error = DirAccess.rename_absolute(staging_path, target_slot_path)
	return rename_err == OK

func _choose_target_slot_for_write(prefix: String) -> String:
	var slot_a_path: String = _get_slot_a_path(prefix)
	var slot_b_path: String = _get_slot_b_path(prefix)

	var meta_a: Dictionary = _parse_and_verify_slot_file(slot_a_path)
	var meta_b: Dictionary = _parse_and_verify_slot_file(slot_b_path)

	if meta_a.is_empty():
		return slot_a_path
	if meta_b.is_empty():
		return slot_b_path

	var rev_a: int = int(meta_a.get("state_revision", -1))
	var rev_b: int = int(meta_b.get("state_revision", -1))
	if rev_a != rev_b:
		return slot_a_path if rev_a < rev_b else slot_b_path

	var seq_a: int = int(meta_a.get("save_sequence", -1))
	var seq_b: int = int(meta_b.get("save_sequence", -1))
	return slot_a_path if seq_a <= seq_b else slot_b_path

func _read_verified_ab_checkpoint(prefix: String) -> GameState:
	var meta_a: Dictionary = _parse_and_verify_slot_file(_get_slot_a_path(prefix))
	var meta_b: Dictionary = _parse_and_verify_slot_file(_get_slot_b_path(prefix))

	var chosen: Dictionary = {}
	if not meta_a.is_empty() and not meta_b.is_empty():
		var rev_a: int = int(meta_a.get("state_revision", -1))
		var rev_b: int = int(meta_b.get("state_revision", -1))
		if rev_a > rev_b:
			chosen = meta_a
		elif rev_b > rev_a:
			chosen = meta_b
		else:
			var seq_a: int = int(meta_a.get("save_sequence", -1))
			var seq_b: int = int(meta_b.get("save_sequence", -1))
			chosen = meta_a if seq_a >= seq_b else meta_b
	elif not meta_a.is_empty():
		chosen = meta_a
	elif not meta_b.is_empty():
		chosen = meta_b
	else:
		return null

	var restored: GameState = GameState.from_authoritative_dict(chosen["payload"])
	if restored.phase == GameState.Phase.MATCH_OVER:
		return null
	return restored

func _parse_and_verify_slot_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var raw_text: String = FileAccess.get_file_as_string(path)
	if raw_text.is_empty():
		return {}

	var wrapper_parser := JSON.new()
	if wrapper_parser.parse(raw_text) != OK:
		return {}

	var wrapper: Variant = wrapper_parser.data
	if typeof(wrapper) != TYPE_DICTIONARY:
		return {}

	if int(wrapper.get("schema_version", -1)) != SAVE_SCHEMA_VERSION:
		return {}

	var payload_json: Variant = wrapper.get("payload_json", null)
	if typeof(payload_json) != TYPE_STRING:
		return {}

	if str(payload_json).sha256_text() != str(wrapper.get("sha256", "")):
		push_warning("SaveManager: Checksum mismatch in slot file %s; ignoring corrupted slot." % path)
		return {}

	var payload_parser := JSON.new()
	if payload_parser.parse(str(payload_json)) != OK:
		return {}

	if typeof(payload_parser.data) != TYPE_DICTIONARY:
		return {}

	wrapper["payload"] = payload_parser.data
	return wrapper
