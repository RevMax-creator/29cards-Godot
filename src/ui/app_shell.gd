extends Control

## Application navigation shell. Screens are built from native Godot Controls so
## the project stays asset-light and scales with the portrait viewport.

const GAMEPLAY_SCENE: PackedScene = preload("res://src/ui/main_table_screen.tscn")
const SETTINGS_PATH: String = "user://29card_settings.cfg"

var _page: Control
var _selected_difficulty: int = AIController.Difficulty.STANDARD
var _selected_avatar_id: String = "byte"
var _profile_name_input: LineEdit
var _profile_avatar_buttons: Dictionary = {}
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
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
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
	button.custom_minimum_size = Vector2(0, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	var bg := ThemePalette.ACCENT_CYAN.darkened(0.72) if primary else ThemePalette.SURFACE_CHARCOAL
	var border := ThemePalette.ACCENT_CYAN if primary else ThemePalette.TABLE_BORDER_EMERALD
	button.add_theme_stylebox_override("normal", ThemePalette.create_button_style(bg, border, 18))
	button.add_theme_stylebox_override("hover", ThemePalette.create_button_style(bg.lightened(0.12), ThemePalette.ACCENT_CYAN, 18))
	button.add_theme_stylebox_override("pressed", ThemePalette.create_button_style(bg.darkened(0.15), ThemePalette.ACCENT_WARM_GOLD, 18))
	button.add_theme_color_override("font_color", ThemePalette.TEXT_PRIMARY)
	button.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", 0.02, 0.75)
		callback.call()
	)
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
	var row := HBoxContainer.new()
	var back := Button.new()
	back.text = "‹"
	back.tooltip_text = "Back"
	back.custom_minimum_size = Vector2(48, 48)
	back.add_theme_font_size_override("font_size", 36)
	back.add_theme_stylebox_override("normal", ThemePalette.create_button_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.TABLE_BORDER_EMERALD, 16))
	back.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", 0.02, 0.75)
		action.call()
	)
	row.add_child(back)
	page.add_child(row)

func _build_logo_fan() -> Control:
	# Stable two-card mark: the 2 sits behind/left and the 9 of hearts
	# sits in front/right. Positions are recalculated from the available width.
	var fan := Control.new()
	fan.name = "LogoFan"
	fan.custom_minimum_size = Vector2(0, 455)
	fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fan.mouse_filter = Control.MOUSE_FILTER_PASS

	var card_two := TextureRect.new()
	card_two.name = "LogoTwo"
	card_two.texture = load("res://Cards/simplecard_spade_2.png") as Texture2D
	card_two.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_two.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_two.size = Vector2(250, 343)
	card_two.pivot_offset = card_two.size * 0.5
	card_two.mouse_filter = Control.MOUSE_FILTER_STOP
	card_two.rotation = deg_to_rad(-12.0)
	fan.add_child(card_two)

	var card_nine := TextureRect.new()
	card_nine.name = "LogoNine"
	card_nine.texture = load("res://Cards/simplecard_heart_9.png") as Texture2D
	card_nine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_nine.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_nine.size = Vector2(250, 343)
	card_nine.pivot_offset = card_nine.size * 0.5
	card_nine.mouse_filter = Control.MOUSE_FILTER_STOP
	card_nine.rotation = deg_to_rad(9.0)
	# Added second so the 9 is visibly in front of the 2.
	fan.add_child(card_nine)

	var layout_cards := func() -> void:
		var center_x: float = fan.size.x * 0.5
		card_two.position = Vector2(center_x - 168.0, 18.0)
		card_nine.position = Vector2(center_x - 58.0, 92.0)

	fan.resized.connect(layout_cards)
	# Set initial positions immediately; the resized callback keeps them
	# centred on narrow and wide portrait devices.
	call_deferred("_layout_logo_cards", fan, card_two, card_nine)

	var animate_card := func(card: TextureRect, rest_rotation: float) -> void:
		var tween := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2(1.06, 1.06), 0.12)
		tween.tween_property(card, "rotation", rest_rotation + deg_to_rad(4.0), 0.12)
		tween.tween_property(card, "scale", Vector2.ONE, 0.16)
		tween.tween_property(card, "rotation", rest_rotation, 0.16)

	card_two.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
			animate_card.call(card_two, deg_to_rad(-12.0))
	)
	card_nine.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
			animate_card.call(card_nine, deg_to_rad(9.0))
	)
	return fan

func _layout_logo_cards(fan: Control, card_two: TextureRect, card_nine: TextureRect) -> void:
	if not is_instance_valid(fan) or not is_instance_valid(card_two) or not is_instance_valid(card_nine):
		return
	var center_x: float = fan.size.x * 0.5
	card_two.position = Vector2(center_x - 168.0, 18.0)
	card_nine.position = Vector2(center_x - 58.0, 92.0)

func _add_flexible_space(page: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer)

func _show_main_menu() -> void:
	var page := _clear_page()
	_add_flexible_space(page)
	var logo := _build_logo_fan()
	page.add_child(logo)
	_add_flexible_space(page)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	page.add_child(actions)
	var single := _button("SINGLE PLAYER", Callable(self, "_show_solo_difficulty"), true, "res://src/ui/icons/single_player.svg")
	single.custom_minimum_size.y = 66
	actions.add_child(single)
	if SaveManager.has_valid_solo_save():
		var resume := _button("CONTINUE", Callable(self, "_continue_solo_match"), false, "res://src/ui/icons/play.svg")
		resume.custom_minimum_size.y = 66
		actions.add_child(resume)
	var multiplayer_button := _button("MULTIPLAYER", Callable(self, "_show_multiplayer_lobby"), false, "res://src/ui/icons/groups.svg")
	multiplayer_button.custom_minimum_size.y = 66
	actions.add_child(multiplayer_button)
	var settings_button := _button("SETTINGS", Callable(self, "_show_settings"), false, "res://src/ui/icons/settings.svg")
	settings_button.custom_minimum_size.y = 66
	actions.add_child(settings_button)

	var help := _button("HOW TO PLAY", Callable(self, "_show_rules_help"), false, "res://src/ui/icons/info.svg")
	help.custom_minimum_size.y = 54
	actions.add_child(help)

func _show_solo_difficulty() -> void:
	var page := _clear_page()

	# Header: a visually unboxed back arrow at the left and a truly centred
	# mode title, independent of the arrow's width.
	var header := Control.new()
	header.custom_minimum_size = Vector2(0, 58)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_row.add_theme_constant_override("separation", 8)
	header.add_child(header_row)
	var back := Button.new()
	back.text = "‹"
	back.tooltip_text = "Back to main menu"
	back.flat = true
	back.custom_minimum_size = Vector2(52, 52)
	back.add_theme_font_size_override("font_size", 38)
	back.add_theme_color_override("font_color", ThemePalette.TEXT_PRIMARY)
	back.add_theme_color_override("font_hover_color", ThemePalette.ACCENT_CYAN)
	back.add_theme_color_override("font_pressed_color", ThemePalette.ACCENT_WARM_GOLD)
	back.pressed.connect(Callable(self, "_show_main_menu"))
	header_row.add_child(back)

	var mode_label := _label("SINGLE PLAYER", 19, ThemePalette.ACCENT_CYAN)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(mode_label)

	var title := _label("Choose difficulty", 30, ThemePalette.TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)

	# Expandable space above and below the choices keeps the group around the
	# visual centre, while Start Match remains in the lower thumb zone.
	_add_flexible_space(page)

	var choices: Array[Dictionary] = [
		{"name": "CASUAL", "icon": "🌱", "value": AIController.Difficulty.CASUAL},
		{"name": "STANDARD", "icon": "⚔️", "value": AIController.Difficulty.STANDARD},
		{"name": "MASTER", "icon": "👑", "value": AIController.Difficulty.MASTER}
	]

	var difficulty_group := VBoxContainer.new()
	difficulty_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_group.add_theme_constant_override("separation", 26)
	page.add_child(difficulty_group)

	var first_row := HBoxContainer.new()
	first_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first_row.add_theme_constant_override("separation", 18)
	difficulty_group.add_child(first_row)
	for index in range(2):
		first_row.add_child(_difficulty_tile(choices[index]))

	var second_row := CenterContainer.new()
	second_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_group.add_child(second_row)
	var master_width: float = clampf(get_viewport_rect().size.x * 0.58, 190.0, 360.0)
	var master := _difficulty_tile(choices[2])
	master.custom_minimum_size = Vector2(master_width, 116)
	master.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	second_row.add_child(master)

	_add_flexible_space(page)
	var start := _button("START MATCH", Callable(self, "_start_solo_match"), true)
	start.custom_minimum_size.y = 62
	page.add_child(start)

func _difficulty_tile(choice: Dictionary) -> Button:
	var value: int = int(choice["value"])
	var selected: bool = value == _selected_difficulty
	var tile := Button.new()
	tile.text = str(choice["icon"]) + "\n" + str(choice["name"])
	tile.custom_minimum_size = Vector2(0, 112)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.focus_mode = Control.FOCUS_ALL
	tile.add_theme_font_size_override("font_size", 18)
	tile.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN if selected else ThemePalette.TEXT_PRIMARY)
	var edge: Color = ThemePalette.ACCENT_CYAN if selected else ThemePalette.TABLE_BORDER_EMERALD
	var fill: Color = ThemePalette.SURFACE_CHARCOAL
	tile.add_theme_stylebox_override("normal", ThemePalette.create_button_style(fill, edge, 18))
	tile.add_theme_stylebox_override("hover", ThemePalette.create_button_style(fill.lightened(0.12), ThemePalette.ACCENT_CYAN, 18))
	tile.add_theme_stylebox_override("pressed", ThemePalette.create_button_style(fill.darkened(0.08), ThemePalette.ACCENT_WARM_GOLD, 18))
	tile.pressed.connect(Callable(self, "_set_difficulty").bind(value))
	return tile

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
	_add_back_button(page, Callable(self, "_show_main_menu"))
	_add_flexible_space(page)
	_add_heading(page, "LOCAL NETWORK", "Multiplayer", "Host or join a room.")
	var identity_panel := _panel(page)
	identity_panel.add_child(_label("YOUR PLAYER ID", 15, ThemePalette.ACCENT_CYAN))
	var identity_row := HBoxContainer.new()
	identity_row.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_row.add_theme_constant_override("separation", 12)
	identity_panel.add_child(identity_row)
	var identity_avatar := TextureRect.new()
	identity_avatar.custom_minimum_size = Vector2(56, 56)
	identity_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	identity_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity_avatar.texture = PlayerProfile.get_avatar_texture()
	identity_row.add_child(identity_avatar)
	identity_row.add_child(_label(PlayerProfile.display_name, 18, ThemePalette.TEXT_PRIMARY))
	identity_panel.add_child(_label("Remote player profiles will appear after M2 seat handshake.", 12, ThemePalette.TEXT_MUTED))

	var host_panel := _panel(page)
	host_panel.add_child(_label("HOST A ROOM", 24, ThemePalette.ACCENT_CYAN))
	host_panel.add_child(_button("CREATE ROOM", Callable(self, "_host_room"), true))
	var join_panel := _panel(page)
	join_panel.add_child(_label("JOIN A ROOM", 24, ThemePalette.ACCENT_WARM_GOLD))
	_join_ip_input = LineEdit.new()
	_join_ip_input.placeholder_text = "Host IP address"
	_join_ip_input.custom_minimum_size.y = 54
	join_panel.add_child(_join_ip_input)
	join_panel.add_child(_button("CONNECT", Callable(self, "_join_room")))
	_lobby_status_label = _label("Not connected", 16, ThemePalette.TEXT_MUTED)
	page.add_child(_lobby_status_label)
	page.add_child(_button("DISCONNECT", Callable(self, "_disconnect_lobby")))
	_add_flexible_space(page)

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
	_add_back_button(page)
	_add_flexible_space(page)
	_add_heading(page, "PREFERENCES", "Settings", "Saved on this device.")
	var profile_panel := _panel(page)
	profile_panel.add_child(_label("PLAYER PROFILE", 22, ThemePalette.ACCENT_CYAN))
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 14)
	profile_panel.add_child(profile_row)
	var profile_portrait := TextureRect.new()
	profile_portrait.custom_minimum_size = Vector2(72, 72)
	profile_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	profile_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	profile_portrait.texture = PlayerProfile.get_avatar_texture()
	profile_row.add_child(profile_portrait)
	var profile_copy := VBoxContainer.new()
	profile_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_copy.alignment = BoxContainer.ALIGNMENT_CENTER
	profile_copy.add_child(_label(PlayerProfile.display_name, 19, ThemePalette.TEXT_PRIMARY))
	profile_copy.add_child(_label(PlayerProfile.get_avatar_name(PlayerProfile.avatar_id), 13, ThemePalette.TEXT_MUTED))
	profile_row.add_child(profile_copy)
	profile_panel.add_child(_button("EDIT PLAYER PROFILE", Callable(self, "_show_player_profile"), false))

	var audio_panel := _panel(page)
	audio_panel.add_child(_label("AUDIO", 22, ThemePalette.ACCENT_CYAN))
	var volume_label := _label("Volume  %d%%" % roundi(float(_settings["master_volume"]) * 100.0), 18)
	audio_panel.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = float(_settings["master_volume"])
	volume.value_changed.connect(func(value: float) -> void:
		_settings["master_volume"] = value
		volume_label.text = "Volume  %d%%" % roundi(value * 100.0)
		_apply_audio_settings()
		_save_settings()
	)
	audio_panel.add_child(volume)
	audio_panel.add_child(_button("SOUND  " + ("ON" if bool(_settings["sound_enabled"]) else "OFF"), func() -> void:
		_settings["sound_enabled"] = not bool(_settings["sound_enabled"])
		_save_settings()
		_show_settings()
	))
	var play_panel := _panel(page)
	play_panel.add_child(_label("GAMEPLAY", 22, ThemePalette.ACCENT_CYAN))
	play_panel.add_child(_button("HAPTICS  " + ("ON" if bool(_settings["haptics_enabled"]) else "OFF"), func() -> void:
		_settings["haptics_enabled"] = not bool(_settings["haptics_enabled"])
		HapticsManager.set_haptics_enabled(bool(_settings["haptics_enabled"]))
		_save_settings()
		_show_settings()
	))
	page.add_child(_button("RESTORE DEFAULTS", Callable(self, "_reset_settings")))
	_add_flexible_space(page)

func _show_player_profile() -> void:
	var page := _clear_page()
	_add_back_button(page, Callable(self, "_show_settings"))
	_add_heading(page, "PLAYER IDENTITY", "Choose your avatar", "Pick a portrait and a player name.")
	_selected_avatar_id = PlayerProfile.avatar_id
	_profile_avatar_buttons.clear()

	var preview_row := HBoxContainer.new()
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_theme_constant_override("separation", 16)
	page.add_child(preview_row)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(112, 112)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = PlayerProfile.get_avatar_texture(_selected_avatar_id)
	preview.name = "ProfilePreview"
	preview_row.add_child(preview)
	var preview_copy := VBoxContainer.new()
	preview_copy.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_copy.add_child(_label(PlayerProfile.get_avatar_name(_selected_avatar_id), 20, ThemePalette.ACCENT_CYAN))
	preview_copy.add_child(_label("PLAYER AVATAR", 12, ThemePalette.TEXT_MUTED))
	preview_row.add_child(preview_copy)

	page.add_child(_label("PLAYER NAME", 13, ThemePalette.TEXT_MUTED))
	_profile_name_input = LineEdit.new()
	_profile_name_input.text = PlayerProfile.display_name
	_profile_name_input.placeholder_text = "Enter your player name"
	_profile_name_input.max_length = 16
	_profile_name_input.custom_minimum_size.y = 54
	page.add_child(_profile_name_input)

	page.add_child(_label("SELECT AVATAR", 14, ThemePalette.TEXT_MUTED))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(grid)

	for avatar in PlayerProfile.get_avatar_catalog():
		var avatar_id: String = str(avatar["id"])
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 112)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 4)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(58, 58)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = PlayerProfile.get_avatar_texture(avatar_id)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(portrait)
		var name_label := _label(str(avatar["name"]), 11, ThemePalette.TEXT_PRIMARY)
		content.add_child(name_label)
		card.pressed.connect(Callable(self, "_select_profile_avatar").bind(avatar_id))
		_profile_avatar_buttons[avatar_id] = card
		grid.add_child(card)

	_refresh_profile_avatar_buttons()
	var save_button := _button("SAVE PROFILE", Callable(self, "_save_player_profile"), true)
	save_button.custom_minimum_size.y = 60
	page.add_child(save_button)

func _select_profile_avatar(avatar_id: String) -> void:
	if not PlayerProfile.is_valid_avatar(avatar_id):
		return
	_selected_avatar_id = avatar_id
	_refresh_profile_avatar_buttons()
	for child in _page.get_children():
		if child is HBoxContainer:
			for item in child.get_children():
				if item is TextureRect and item.name == "ProfilePreview":
					item.texture = PlayerProfile.get_avatar_texture(_selected_avatar_id)
				elif item is VBoxContainer and item.get_child_count() > 0 and item.get_child(0) is Label:
					(item.get_child(0) as Label).text = PlayerProfile.get_avatar_name(_selected_avatar_id)

func _refresh_profile_avatar_buttons() -> void:
	for avatar_id in _profile_avatar_buttons.keys():
		var button: Button = _profile_avatar_buttons[avatar_id]
		var selected: bool = str(avatar_id) == _selected_avatar_id
		var border: Color = ThemePalette.ACCENT_CYAN if selected else ThemePalette.TABLE_BORDER_EMERALD
		var fill: Color = Color("#17313A") if selected else ThemePalette.SURFACE_CHARCOAL
		button.add_theme_stylebox_override("normal", ThemePalette.create_button_style(fill, border, 14))
		button.add_theme_stylebox_override("hover", ThemePalette.create_button_style(fill.lightened(0.1), ThemePalette.ACCENT_CYAN, 14))

func _save_player_profile() -> void:
	var requested_name: String = _profile_name_input.text if is_instance_valid(_profile_name_input) else PlayerProfile.display_name
	PlayerProfile.set_profile(requested_name, _selected_avatar_id)
	_show_settings()

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
	HapticsManager.set_haptics_enabled(bool(_settings["haptics_enabled"]))

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
	_add_back_button(page)
	_add_heading(page, "RULEBOOK", "How to play 29", "Standard four-player rules")

	var rules := _panel(page)
	_add_rule_section(rules, "Rank of cards",
		"The Jack card has the highest rank. The next-highest rank is the 9 card, followed by Ace, 10, King, Queen, 8 and 7 (lowest). Once the trump suit has been declared, cards in the trump suit outrank all other cards.")

	_add_rule_section(rules, "Objective",
		"The objective is to be the first team to reach 6 game points. A team that reaches −6 game points loses.")

	_add_rule_section(rules, "Deal",
		"A random player is chosen to be the dealer. Each player is dealt a hand of 4 cards from a deck containing only A, K, Q, J, 10, 9, 8 and 7 of each suit. Everyone gets 4 more cards after bidding and the Double/Redouble decision.")

	_add_rule_section(rules, "Bid",
		"Starting with the player to the dealer's left and proceeding clockwise around the table, each player places a bid. The bid is a guess at how many points they think their team can take. Players may choose to pass instead of bidding. If not passing, they must bid at least 15, up to a maximum of 28.")

	_add_rule_paragraph(rules,
		"If one player makes a bid, the next player must bid higher than that or pass. Bidding continues either until a player bids 28 or until 3 consecutive players pass. If a bid has already been made, the passes end the bidding and the highest bid wins. If the first three players pass before anyone has bid, the dealer is forced to bid 15.")

	_add_rule_section(rules, "Choosing trump",
		"The player who bid highest chooses the trump suit. Cards in the trump suit outrank cards of all other suits. When the trump suit is chosen, it remains hidden from everyone. It is known only to the player who chose it and is revealed later in the game.")

	_add_rule_section(rules, "Double / redouble",
		"After the bid has been won and trump has been chosen, either player on the defending team may call Double before the remaining cards are dealt. A Double makes the hand worth 2 game points instead of 1. In response, either player on the declaring team may call Redouble, making the hand worth 4 game points instead of 2.")

	_add_rule_section(rules, "Second deal",
		"After the Double/Redouble decision is complete, 4 more cards are dealt to each player, for a total of 8 cards in hand.")

	_add_rule_section(rules, "Play",
		"The player to the dealer's left starts the trick by playing any card from their hand. Play continues in clockwise order until 4 cards are in the middle pile. You must play a card of the same suit as the lead card if you have one.")

	_add_rule_paragraph(rules,
		"The trick is taken by whoever played the highest card with the same suit as the lead card. The Jack is worth 3 points and the 9 is worth 2 points. Ace and 10 are worth 1 point each. Other cards are not counted. For example, a pile containing 1 Jack, 2 Aces and a 7 is worth 5 points. The trick-taker receives the points in the pile. The team that takes the last trick gets an extra point, so the total is always 29. The trick winner starts the next trick.")

	_add_rule_paragraph(rules,
		"As soon as a player cannot play a card with the same suit as the lead card, the trump suit is declared immediately. That player may play any other card in their hand. Even after trump is declared, players must always follow the lead suit if they have one. Each trick is normally won by the highest card of the lead suit. If one or more trump cards are played, the highest trump wins instead.")

	_add_rule_section(rules, "TRAM — The rest are mine",
		"When you lead a trick and every card you hold is a sure winner, you may call TRAM to take all remaining tricks at once. This is the case when each of your cards is the highest card left in its suit and either all your cards are trumps or no other player has a trump left.")

	_add_rule_paragraph(rules,
		"TRAM is not offered on the first or last trick. If you can only win every trick by playing your cards in the right order — for example, by drawing out the last trumps first — the button does not appear, so play the tricks out.")

	_add_rule_section(rules, "Score",
		"After each hand, scores are calculated for each team by adding up the teammates' card points. The team that took the last trick gets an extra point so that the total is 29. The player who chose trump is part of the declaring team. The other team is the defending team.")

	_add_rule_paragraph(rules,
		"If the declaring team makes at least the number of points they bid, they receive 1 game point. Otherwise, they lose 1 game point. The defending team does not score game points. Double changes the result to +2 or −2; Redouble changes it to +4 or −4.")

	_add_rule_section(rules, "Royal Pair",
		"The King and Queen of the trump suit are called the Royal Pair. After trump has been declared, the player who holds both cards in their hand can announce the Pair immediately after they or their partner wins a trick. It is possible that no one holds the Royal Pair, in which case this rule is never active.")

	_add_rule_paragraph(rules,
		"Announcing the Royal Pair affects the requirements for the bid. If a member of the declaring team announces it, their bid is reduced by 4 points, to a minimum of 15. If a member of the defending team announces it, 4 points are added to the bid, up to a maximum of 28.")

	_add_rule_section(rules, "Seventh card — optional variant",
		"The Seventh Card option is not enabled in the standard game. In games where it is allowed, the high bidder may choose trump to be determined by the suit of the seventh card dealt to them. This seventh card is kept out of their hand and may not be played until they cannot follow suit during a trick. It cannot be used to lead a trick unless it is the only card the bidder has left.")

	_add_rule_paragraph(rules,
		"If the Seventh Card option is used, trump-suit cards already in your hand do not have the power to trump until the trump suit is declared. Do not expect a trump-suit card to win a trick while trump is hidden. When you play the seventh card, trump is declared automatically. Trump is also declared if another player cannot follow suit, as usual.")

	_add_rule_paragraph(rules,
		"When trump is declared, the seventh card is moved into the declarer's hand. It may then be played according to the usual rules.")

	_add_rule_section(rules, "Game end",
		"The first team to reach 6 game points wins. If a team reaches −6 game points, it loses.")

	_add_flexible_space(page)

func _add_rule_section(parent: VBoxContainer, heading_text: String, body_text: String) -> void:
	var heading := _label(heading_text, 21, ThemePalette.ACCENT_CYAN)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(heading)
	_add_rule_paragraph(parent, body_text)

func _add_rule_paragraph(parent: VBoxContainer, body_text: String) -> void:
	var body := _label(body_text, 16, ThemePalette.TEXT_PRIMARY)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(body)

func _on_player_view_updated(view: Dictionary) -> void:
	if int(view.get("phase", -1)) != GameState.Phase.MATCH_OVER:
		return
	var revision := int(view.get("state_revision", -1))
	if revision == _results_session_revision:
		return
	_results_session_revision = revision
	# Defer transition slightly to ensure any final trick collection animation
	# on the active table has completed gracefully.
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		_show_match_results(view.duplicate(true))
	)

func _show_match_results(view: Dictionary) -> void:
	var page := _clear_page()
	var winning_team := int(view.get("winning_team", -1))
	var viewer_seat := int(view.get("viewer_seat", 0))
	var player_team := GameState.get_team(viewer_seat)
	var player_won := winning_team == player_team
	var summary: Dictionary = view.get("last_hand_summary", {})
	var scores: Array = view.get("match_game_points", [0, 0])

	# 1. Hero Header
	var title_text := "🏆 VICTORY!" if player_won else "DEFEAT"
	var subtitle_text := "Congratulations! Your partnership conquered the table!" if player_won else "Defending team claimed victory. Better luck in the next match!"
	var title_color := ThemePalette.ACCENT_WARM_GOLD if player_won else Color("#FF6E6E")
	
	_add_heading(page, "MATCH RESULTS", title_text, subtitle_text)
	
	# 2. Main Match Score Hero Panel
	var hero_panel := _panel(page)
	hero_panel.add_child(_label("FINAL MATCH OUTCOME", 14, ThemePalette.ACCENT_CYAN))

	var team_row := HBoxContainer.new()
	team_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_row.add_theme_constant_override("separation", 16)
	hero_panel.add_child(team_row)

	# Team 1 (Blue) Card
	var t1_card := PanelContainer.new()
	t1_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t1_border := ThemePalette.ACCENT_WARM_GOLD if winning_team == 0 else Color("#1A4B6E")
	t1_card.add_theme_stylebox_override("panel", ThemePalette.create_panel_style(Color("#0B2236"), t1_border, 14, 2))
	var t1_box := VBoxContainer.new()
	t1_box.alignment = BoxContainer.ALIGNMENT_CENTER
	t1_box.add_theme_constant_override("separation", 4)
	t1_card.add_child(t1_box)
	t1_box.add_child(_label("TEAM 1 (BLUE)" + (" 👑" if winning_team == 0 else ""), 13, Color("#64B5F6")))
	t1_box.add_child(_label("%+d" % int(scores[0]), 36, ThemePalette.ACCENT_WARM_GOLD if winning_team == 0 else ThemePalette.TEXT_PRIMARY))
	t1_box.add_child(_label("WINNER" if winning_team == 0 else "RUNNER UP", 11, ThemePalette.TEXT_MUTED))
	team_row.add_child(t1_card)

	# Team 2 (Coral) Card
	var t2_card := PanelContainer.new()
	t2_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t2_border := ThemePalette.ACCENT_WARM_GOLD if winning_team == 1 else Color("#6E2B2B")
	t2_card.add_theme_stylebox_override("panel", ThemePalette.create_panel_style(Color("#2B1214"), t2_border, 14, 2))
	var t2_box := VBoxContainer.new()
	t2_box.alignment = BoxContainer.ALIGNMENT_CENTER
	t2_box.add_theme_constant_override("separation", 4)
	t2_card.add_child(t2_box)
	t2_box.add_child(_label("TEAM 2 (CORAL)" + (" 👑" if winning_team == 1 else ""), 13, Color("#FF6E6E")))
	t2_box.add_child(_label("%+d" % int(scores[1]), 36, ThemePalette.ACCENT_WARM_GOLD if winning_team == 1 else ThemePalette.TEXT_PRIMARY))
	t2_box.add_child(_label("WINNER" if winning_team == 1 else "RUNNER UP", 11, ThemePalette.TEXT_MUTED))
	team_row.add_child(t2_card)

	# 3. 4 Players Grid with Avatars & Team Indicators
	var roster_panel := _panel(page)
	roster_panel.add_child(_label("TABLE PLAYERS", 14, ThemePalette.ACCENT_CYAN))

	var player_grid := GridContainer.new()
	player_grid.columns = 2
	player_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_grid.add_theme_constant_override("h_separation", 10)
	player_grid.add_theme_constant_override("v_separation", 10)
	roster_panel.add_child(player_grid)

	for rel_seat in range(4):
		var abs_seat := posmod(viewer_seat + rel_seat, 4)
		var team := GameState.get_team(abs_seat)
		var p_profile: Dictionary = PlayerProfile.get_profile() if rel_seat == 0 else PlayerProfile.get_ai_profile(rel_seat)

		var p_card := PanelContainer.new()
		p_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_bg := Color("#0F283E") if team == 0 else Color("#38171C")
		var card_edge := Color("#4FA2E8") if team == 0 else Color("#FF6E6E")
		p_card.add_theme_stylebox_override("panel", ThemePalette.create_panel_style(card_bg, card_edge, 10, 1))

		var p_row := HBoxContainer.new()
		p_row.add_theme_constant_override("separation", 8)
		p_card.add_child(p_row)

		var p_avatar := TextureRect.new()
		p_avatar.custom_minimum_size = Vector2(44, 44)
		p_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p_avatar.texture = PlayerProfile.get_avatar_texture(str(p_profile.get("avatar_id", "byte")))
		p_row.add_child(p_avatar)

		var p_details := VBoxContainer.new()
		p_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_details.alignment = BoxContainer.ALIGNMENT_CENTER
		var display_str: String = str(p_profile.get("display_name", "Player"))
		if rel_seat == 0:
			display_str += " (You)"
		var p_name := _label(display_str, 14, ThemePalette.TEXT_PRIMARY)
		p_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		p_details.add_child(p_name)
		var team_str: String = "Team 1 (Blue)" if team == 0 else "Team 2 (Coral)"
		var p_team_lbl := _label(team_str, 11, Color("#64B5F6") if team == 0 else Color("#FF6E6E"))
		p_team_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		p_details.add_child(p_team_lbl)
		p_row.add_child(p_details)

		player_grid.add_child(p_card)

	# 4. Final Hand Breakdown Card
	if not summary.is_empty():
		var breakdown_panel := _panel(page)
		breakdown_panel.add_child(_label("FINAL HAND BREAKDOWN", 14, ThemePalette.ACCENT_CYAN))

		var contract_made: bool = bool(summary.get("contract_succeeded", false))
		var bidding_team: int = int(summary.get("bidding_team", 0))
		var target: int = int(summary.get("final_target", 0))
		var captured: int = int(summary.get("bidder_points", 0))
		var defenders: int = int(summary.get("defender_points", 0))
		var delta: int = int(summary.get("game_point_delta", 0))

		var status_str: String = "CONTRACT %s (%+d GAME POINTS)" % ["MADE" if contract_made else "MISSED", delta]
		var status_color := ThemePalette.ACCENT_WARM_GOLD if contract_made else Color("#FF6E6E")
		breakdown_panel.add_child(_label(status_str, 16, status_color))

		var detail_grid := GridContainer.new()
		detail_grid.columns = 2
		detail_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_grid.add_theme_constant_override("h_separation", 16)
		detail_grid.add_theme_constant_override("v_separation", 4)
		breakdown_panel.add_child(detail_grid)

		detail_grid.add_child(_label("Contract Target:", 13, ThemePalette.TEXT_MUTED))
		detail_grid.add_child(_label("%d Points" % target, 13, ThemePalette.TEXT_PRIMARY))
		detail_grid.add_child(_label("Declaring Team Captured:", 13, ThemePalette.TEXT_MUTED))
		detail_grid.add_child(_label("%d / 29 Points" % captured, 13, ThemePalette.TEXT_PRIMARY))
		detail_grid.add_child(_label("Defending Team Captured:", 13, ThemePalette.TEXT_MUTED))
		detail_grid.add_child(_label("%d / 29 Points" % defenders, 13, ThemePalette.TEXT_PRIMARY))

	# 5. Actions
	_add_flexible_space(page)
	var play_again := _button("PLAY AGAIN", Callable(self, "_show_solo_difficulty"), true)
	play_again.custom_minimum_size.y = 60
	page.add_child(play_again)
	
	var main_menu := _button("MAIN MENU", Callable(self, "_show_main_menu"))
	main_menu.custom_minimum_size.y = 54
	page.add_child(main_menu)
