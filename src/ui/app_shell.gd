extends Control

## Application navigation shell. Screens are built from native Godot Controls so
## the project stays asset-light and scales with the portrait viewport.

const GAMEPLAY_SCENE: PackedScene = preload("res://src/ui/main_table_screen.tscn")
const SETTINGS_PATH: String = "user://sovereign29_settings.cfg"

var _page: Control
var _selected_difficulty: int = AIController.Difficulty.STANDARD
var _settings := {
	"master_volume": 0.8,
	"sound_enabled": true,
	"haptics_enabled": true
}
var _results_session_revision: int = -1
var _lobby_status_label: Label
var _join_ip_input: LineEdit

func _ready() -> void:
	_load_settings()
	MultiplayerManager.player_view_updated.connect(_on_player_view_updated)
	_show_main_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_show_main_menu()

func _clear_page() -> VBoxContainer:
	for child in get_children():
		child.queue_free()
	_page = null

	var background := ColorRect.new()
	background.color = ThemePalette.BG_MIDNIGHT_NAVY
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)
	scroll.add_child(page)
	_page = page
	return page

func _add_heading(page: VBoxContainer, eyebrow: String, title: String, subtitle: String) -> void:
	var eyebrow_label := _label(eyebrow.to_upper(), 13, ThemePalette.ACCENT_CYAN)
	eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(eyebrow_label)

	var title_label := _label(title, 32, ThemePalette.TEXT_PRIMARY)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title_label)

	var subtitle_label := _label(subtitle, 16, ThemePalette.TEXT_MUTED)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(subtitle_label)

func _label(text_value: String, font_size: int = 22, color: Color = ThemePalette.TEXT_PRIMARY) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text_value: String, callback: Callable, primary: bool = false, icon_path: String = "") -> Button:
	var button := Button.new()
	button.text = text_value
	if not icon_path.is_empty():
		button.icon = load(icon_path) as Texture2D
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	var bg := ThemePalette.ACCENT_CYAN.darkened(0.72) if primary else ThemePalette.SURFACE_CHARCOAL
	var border := ThemePalette.ACCENT_CYAN if primary else ThemePalette.TABLE_BORDER_EMERALD
	button.add_theme_stylebox_override("normal", ThemePalette.create_button_style(bg, border, 18))
	button.add_theme_stylebox_override("hover", ThemePalette.create_button_style(bg.lightened(0.12), ThemePalette.ACCENT_CYAN, 18))
	button.add_theme_stylebox_override("pressed", ThemePalette.create_button_style(bg.darkened(0.15), ThemePalette.ACCENT_WARM_GOLD, 18))
	button.add_theme_color_override("font_color", ThemePalette.TEXT_PRIMARY)
	button.pressed.connect(callback)
	return button

func _panel(page: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemePalette.create_panel_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.TABLE_BORDER_EMERALD, 20, 1))
	page.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	return content

func _add_back_button(page: VBoxContainer, callback: Callable = Callable()) -> void:
	var action := callback if callback.is_valid() else Callable(self, "_show_main_menu")
	page.add_child(_button("←  Back", action))

func _show_main_menu() -> void:
	var page := _clear_page()
	page.add_child(Control.new())
	page.get_child(0).custom_minimum_size.y = 36
	_add_heading(page, "FOUR PLAYERS · TWO TEAMS", "29", "A game of partnership, nerve and perfect timing.")

	var crest := _label("♠     ♥     ♦     ♣", 44, ThemePalette.ACCENT_WARM_GOLD)
	page.add_child(crest)
	page.add_child(Control.new())
	page.get_child(2).custom_minimum_size.y = 24
	page.add_child(_button("PLAY", Callable(self, "_show_game_mode_selection"), true, "res://src/ui/icons/play.svg"))
	if SaveManager.has_valid_solo_save():
		page.add_child(_button("CONTINUE SOLO MATCH", Callable(self, "_continue_solo_match")))
	page.add_child(_button("MULTIPLAYER", Callable(self, "_show_multiplayer_lobby"), false, "res://src/ui/icons/groups.svg"))
	page.add_child(_button("SETTINGS", Callable(self, "_show_settings"), false, "res://src/ui/icons/settings.svg"))
	page.add_child(_button("HOW TO PLAY", Callable(self, "_show_rules_help"), false, "res://src/ui/icons/info.svg"))
	var footer := _label("FOUR PLAYERS  •  TWO TEAMS  •  29 POINTS", 15, ThemePalette.TEXT_MUTED)
	page.add_child(footer)

func _show_game_mode_selection() -> void:
	var page := _clear_page()
	_add_heading(page, "NEW MATCH", "Choose your table", "Select how you want to play.")
	var solo := _panel(page)
	solo.add_child(_label("SOLO VS AI", 28, ThemePalette.ACCENT_CYAN))
	solo.add_child(_label("Play with three AI partners and opponents. Choose a difficulty before dealing.", 18, ThemePalette.TEXT_MUTED))
	solo.add_child(_button("CHOOSE DIFFICULTY", Callable(self, "_show_solo_difficulty"), true))
	var multi := _panel(page)
	multi.add_child(_label("FOUR-PHONE MULTIPLAYER", 28, ThemePalette.ACCENT_WARM_GOLD))
	multi.add_child(_label("Create or join a room over your local network. Full seat handshake and Nearby support are scheduled for M2.", 18, ThemePalette.TEXT_MUTED))
	multi.add_child(_button("OPEN MULTIPLAYER LOBBY", Callable(self, "_show_multiplayer_lobby")))
	_add_back_button(page)

func _show_solo_difficulty() -> void:
	var page := _clear_page()
	_add_heading(page, "SOLO MATCH", "Choose difficulty", "You will play Seat 1 with three AI-controlled players.")
	var choices: Array[Dictionary] = [
		{"name": "CASUAL", "desc": "Relaxed play with simpler decisions.", "value": AIController.Difficulty.CASUAL},
		{"name": "STANDARD", "desc": "Balanced bidding and card selection.", "value": AIController.Difficulty.STANDARD},
		{"name": "MASTER", "desc": "Stronger card counting and deeper decisions.", "value": AIController.Difficulty.MASTER}
	]
	for choice in choices:
		var value: int = int(choice["value"])
		var text_value: String = str(choice["name"]) + ("   ✓" if value == _selected_difficulty else "")
		var card := _panel(page)
		card.add_child(_label(text_value, 26, ThemePalette.ACCENT_CYAN if value == _selected_difficulty else ThemePalette.TEXT_PRIMARY))
		card.add_child(_label(str(choice["desc"]), 18, ThemePalette.TEXT_MUTED))
		card.add_child(_button("SELECT " + str(choice["name"]), Callable(self, "_set_difficulty").bind(value), value == _selected_difficulty))
	page.add_child(_button("START MATCH", Callable(self, "_start_solo_match"), true))
	_add_back_button(page, Callable(self, "_show_game_mode_selection"))

func _set_difficulty(value: int) -> void:
	_selected_difficulty = value
	_show_solo_difficulty()

func _start_solo_match() -> void:
	MultiplayerManager.start_solo_ai_match(_selected_difficulty, false)
	_open_gameplay()

func _continue_solo_match() -> void:
	MultiplayerManager.start_solo_ai_match(_selected_difficulty, true)
	_open_gameplay()

func _open_gameplay() -> void:
	for child in get_children():
		child.queue_free()
	var game := GAMEPLAY_SCENE.instantiate() as MainTableScreen
	add_child(game)
	game.return_to_menu.connect(_show_main_menu)
	_results_session_revision = -1
	MultiplayerManager._broadcast_state_from_host()

func _show_multiplayer_lobby() -> void:
	var page := _clear_page()
	_add_heading(page, "LOCAL NETWORK", "Multiplayer lobby", "Host a room or enter the host device's local IP address.")
	var host_panel := _panel(page)
	host_panel.add_child(_label("HOST A ROOM", 26, ThemePalette.ACCENT_CYAN))
	host_panel.add_child(_label("Start a local ENet host on port %d." % MultiplayerManager.GAME_PORT, 18, ThemePalette.TEXT_MUTED))
	host_panel.add_child(_button("CREATE ROOM", Callable(self, "_host_room"), true))

	var join_panel := _panel(page)
	join_panel.add_child(_label("JOIN A ROOM", 26, ThemePalette.ACCENT_WARM_GOLD))
	_join_ip_input = LineEdit.new()
	_join_ip_input.placeholder_text = "Host IP address (e.g. 192.168.1.10)"
	_join_ip_input.custom_minimum_size.y = 64
	_join_ip_input.add_theme_font_size_override("font_size", 20)
	join_panel.add_child(_join_ip_input)
	join_panel.add_child(_button("CONNECT", Callable(self, "_join_room")))

	_lobby_status_label = _label("No room connection started.", 18, ThemePalette.TEXT_MUTED)
	page.add_child(_lobby_status_label)
	var note := _label("M1 lobby preview: room hosting and connection initiation are wired to the existing ENet manager. Seat assignment, ready checks, player identity and match launch remain M2 work.", 16, ThemePalette.TEXT_MUTED)
	page.add_child(note)
	page.add_child(_button("DISCONNECT / RESET", Callable(self, "_disconnect_lobby")))
	_add_back_button(page)

func _host_room() -> void:
	var err: Error = MultiplayerManager.host_multiplayer_room()
	if err == OK:
		_lobby_status_label.text = "Host started on port %d. Share your local IP with other players." % MultiplayerManager.GAME_PORT
	else:
		_lobby_status_label.text = "Could not start host: %s" % error_string(err)

func _join_room() -> void:
	var host_ip := _join_ip_input.text.strip_edges()
	if host_ip.is_empty():
		_lobby_status_label.text = "Enter the host device's local IP address first."
		return
	var err: Error = MultiplayerManager.join_multiplayer_room(host_ip)
	if err == OK:
		_lobby_status_label.text = "Connection attempt started for %s. Seat assignment is not available until M2." % host_ip
	else:
		_lobby_status_label.text = "Could not start connection: %s" % error_string(err)

func _disconnect_lobby() -> void:
	multiplayer.multiplayer_peer = null
	_lobby_status_label.text = "Disconnected. You can create or join another room."

func _show_settings() -> void:
	var page := _clear_page()
	_add_heading(page, "PREFERENCES", "Settings", "Your preferences are saved locally on this device.")
	var audio_panel := _panel(page)
	audio_panel.add_child(_label("AUDIO", 25, ThemePalette.ACCENT_CYAN))
	var volume_label := _label("Master volume: %d%%" % roundi(float(_settings["master_volume"]) * 100.0), 19)
	audio_panel.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = float(_settings["master_volume"])
	volume.custom_minimum_size.y = 48
	volume.value_changed.connect(func(value: float) -> void:
		_settings["master_volume"] = value
		volume_label.text = "Master volume: %d%%" % roundi(value * 100.0)
		_apply_audio_settings()
		_save_settings()
	)
	audio_panel.add_child(volume)
	audio_panel.add_child(_button("SOUND: " + ("ON" if bool(_settings["sound_enabled"]) else "OFF"), func() -> void:
		_settings["sound_enabled"] = not bool(_settings["sound_enabled"])
		_save_settings()
		_show_settings()
	))
	var play_panel := _panel(page)
	play_panel.add_child(_label("GAMEPLAY", 25, ThemePalette.ACCENT_CYAN))
	play_panel.add_child(_button("HAPTIC FEEDBACK: " + ("ON" if bool(_settings["haptics_enabled"]) else "OFF"), func() -> void:
		_settings["haptics_enabled"] = not bool(_settings["haptics_enabled"])
		_save_settings()
		_show_settings()
	))
	play_panel.add_child(_label("Haptic preference is stored; device vibration hooks can be connected during the mobile polish pass.", 16, ThemePalette.TEXT_MUTED))
	page.add_child(_button("RESTORE DEFAULTS", Callable(self, "_reset_settings")))
	_add_back_button(page)

func _reset_settings() -> void:
	_settings = {"master_volume": 0.8, "sound_enabled": true, "haptics_enabled": true}
	_save_settings()
	_apply_audio_settings()
	_show_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_settings["master_volume"] = clampf(float(config.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)
		_settings["sound_enabled"] = bool(config.get_value("audio", "sound_enabled", true))
		_settings["haptics_enabled"] = bool(config.get_value("gameplay", "haptics_enabled", true))
	_apply_audio_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", _settings["master_volume"])
	config.set_value("audio", "sound_enabled", _settings["sound_enabled"])
	config.set_value("gameplay", "haptics_enabled", _settings["haptics_enabled"])
	config.save(SETTINGS_PATH)

func _apply_audio_settings() -> void:
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, not bool(_settings["sound_enabled"]))
		var volume: float = float(_settings["master_volume"])
		AudioServer.set_bus_volume_db(master_index, linear_to_db(maxf(volume, 0.001)))

func _show_rules_help() -> void:
	var page := _clear_page()
	_add_heading(page, "QUICK REFERENCE", "How to play 29", "Four players form two partnerships. Partners sit opposite each other.")
	var rules := _panel(page)
	rules.add_child(_label("THE DEAL", 24, ThemePalette.ACCENT_CYAN))
	rules.add_child(_label("Each player receives four cards, bidding takes place, then the remaining four cards are dealt after trump is selected.", 18, ThemePalette.TEXT_MUTED))
	rules.add_child(_label("BIDDING", 24, ThemePalette.ACCENT_CYAN))
	rules.add_child(_label("The minimum bid is 15 and the maximum is 29. The highest bidder selects a hidden trump suit.", 18, ThemePalette.TEXT_MUTED))
	rules.add_child(_label("CARD POINTS", 24, ThemePalette.ACCENT_CYAN))
	rules.add_child(_label("J = 3, 9 = 2, A = 1, 10 = 1. The last trick adds one point, making 29 total.", 18, ThemePalette.TEXT_MUTED))
	rules.add_child(_label("SPECIAL CALLS", 24, ThemePalette.ACCENT_CYAN))
	rules.add_child(_label("A qualifying King–Queen pair adjusts the contract by four. Double and redouble multiply the game-point stake.", 18, ThemePalette.TEXT_MUTED))
	page.add_child(_label("Quick reference for the current rules configuration.", 15, ThemePalette.TEXT_MUTED))
	_add_back_button(page)

func _on_player_view_updated(view: Dictionary) -> void:
	if int(view.get("phase", -1)) != GameState.Phase.MATCH_OVER:
		return
	var revision := int(view.get("state_revision", -1))
	if revision == _results_session_revision:
		return
	_results_session_revision = revision
	call_deferred("_show_match_results", view.duplicate(true))

func _show_match_results(view: Dictionary) -> void:
	var page := _clear_page()
	var winning_team := int(view.get("winning_team", -1))
	var player_team := GameState.get_team(int(view.get("viewer_seat", 0)))
	var player_won := winning_team == player_team
	_add_heading(page, "MATCH COMPLETE", "VICTORY" if player_won else "MATCH OVER", "Your partnership " + ("reached the winning target." if player_won else "did not reach the winning target this match."))
	var score_panel := _panel(page)
	score_panel.add_child(_label("FINAL MATCH SCORE", 22, ThemePalette.ACCENT_CYAN))
	var scores: Array = view.get("match_game_points", [0, 0])
	score_panel.add_child(_label("TEAM 1     %+d" % int(scores[0]), 32, ThemePalette.ACCENT_WARM_GOLD if winning_team == 0 else ThemePalette.TEXT_PRIMARY))
	score_panel.add_child(_label("TEAM 2     %+d" % int(scores[1]), 32, ThemePalette.ACCENT_WARM_GOLD if winning_team == 1 else ThemePalette.TEXT_PRIMARY))
	var summary: Dictionary = view.get("last_hand_summary", {})
	if not summary.is_empty():
		score_panel.add_child(_label("Last contract: %s  •  Game points: %+d" % ["MADE" if bool(summary.get("contract_succeeded", false)) else "FAILED", int(summary.get("game_point_delta", 0))], 18, ThemePalette.TEXT_MUTED))
	page.add_child(_button("PLAY AGAIN", Callable(self, "_show_game_mode_selection"), true))
	page.add_child(_button("MAIN MENU", Callable(self, "_show_main_menu")))
