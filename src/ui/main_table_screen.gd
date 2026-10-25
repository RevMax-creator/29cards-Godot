class_name MainTableScreen
extends Control

signal return_to_menu

var _safe_root: MarginContainer
var _header_label: Label
var _score_label: Label
var _status_banner: Label
var _trick_center_box: HBoxContainer
var _action_panel: VBoxContainer
var _hand_container: HBoxContainer
var _hint_label: Label

func _ready() -> void:
	_build_adaptive_portrait_ui()
	_apply_safe_area_insets()
	get_tree().root.size_changed.connect(_apply_safe_area_insets)

	MultiplayerManager.player_view_updated.connect(_on_player_view_updated)
	MultiplayerManager.action_rejected.connect(_on_action_rejected)
	MultiplayerManager.host_migration_completed.connect(_on_host_migration_completed)
	call_deferred("_refresh_existing_match")

func _build_adaptive_portrait_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = ThemePalette.BG_MIDNIGHT_NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_safe_root = MarginContainer.new()
	_safe_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe_root)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	_safe_root.add_child(main_vbox)

	# 1. Top Telemetry & Match Score Bar
	var top_bar := PanelContainer.new()
	top_bar.add_theme_stylebox_override(
		"panel",
		ThemePalette.create_panel_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.ACCENT_CYAN, 20, 1)
	)
	main_vbox.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_bar.add_child(top_hbox)

	_header_label = Label.new()
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.add_theme_font_size_override("font_size", 26)
	_header_label.add_theme_color_override("font_color", ThemePalette.TEXT_PRIMARY)
	top_hbox.add_child(_header_label)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 26)
	_score_label.add_theme_color_override("font_color", ThemePalette.ACCENT_WARM_GOLD)
	top_hbox.add_child(_score_label)

	# 2. Central Emerald Card Table Arena
	var table_panel := PanelContainer.new()
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_theme_stylebox_override(
		"panel",
		ThemePalette.create_panel_style(ThemePalette.TABLE_FELT_EMERALD, ThemePalette.TABLE_BORDER_EMERALD, 36, 3)
	)
	main_vbox.add_child(table_panel)

	var table_vbox := VBoxContainer.new()
	table_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	table_vbox.add_theme_constant_override("separation", 20)
	table_panel.add_child(table_vbox)

	_status_banner = Label.new()
	_status_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_banner.add_theme_font_size_override("font_size", 28)
	_status_banner.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN)
	table_vbox.add_child(_status_banner)

	_trick_center_box = HBoxContainer.new()
	_trick_center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_trick_center_box.add_theme_constant_override("separation", 18)
	table_vbox.add_child(_trick_center_box)

	_action_panel = VBoxContainer.new()
	_action_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_panel.add_theme_constant_override("separation", 14)
	table_vbox.add_child(_action_panel)

	# 3. Hint & Utility Row (Fixed Godot 4 BoxContainer.ALIGNMENT_CENTER)
	var utility_hbox := HBoxContainer.new()
	utility_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(utility_hbox)

	var menu_btn := Button.new()
	menu_btn.text = ""
	menu_btn.icon = load("res://src/ui/icons/menu.svg") as Texture2D
	menu_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_btn.tooltip_text = "Main menu"
	menu_btn.custom_minimum_size = Vector2(76, 60)
	menu_btn.add_theme_stylebox_override("normal", ThemePalette.create_button_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.TABLE_BORDER_EMERALD))
	menu_btn.pressed.connect(func() -> void:
		return_to_menu.emit()
	)
	utility_hbox.add_child(menu_btn)

	var hint_btn := Button.new()
	hint_btn.text = "Hint"
	hint_btn.icon = load("res://src/ui/icons/lightbulb.svg") as Texture2D
	hint_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint_btn.custom_minimum_size = Vector2(140, 60)
	hint_btn.add_theme_stylebox_override(
		"normal",
		ThemePalette.create_button_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.ACCENT_WARM_GOLD)
	)
	hint_btn.pressed.connect(_on_hint_pressed)
	utility_hbox.add_child(hint_btn)

	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 24)
	_hint_label.add_theme_color_override("font_color", ThemePalette.ACCENT_WARM_GOLD)
	utility_hbox.add_child(_hint_label)

	# 4. Player Hand Fan Tray
	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size = Vector2(0, 230)
	main_vbox.add_child(hand_scroll)

	_hand_container = HBoxContainer.new()
	_hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_container.add_theme_constant_override("separation", 12)
	hand_scroll.add_child(_hand_container)

func _apply_safe_area_insets() -> void:
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.x <= 0 or win_size.y <= 0:
		return
	var top_inset: int = maxi(24, safe_rect.position.y)
	var bottom_inset: int = maxi(24, win_size.y - (safe_rect.position.y + safe_rect.size.y))
	_safe_root.add_theme_constant_override("margin_top", top_inset)
	_safe_root.add_theme_constant_override("margin_bottom", bottom_inset)
	_safe_root.add_theme_constant_override("margin_left", 24)
	_safe_root.add_theme_constant_override("margin_right", 24)

func _on_player_view_updated(view: Dictionary) -> void:
	_hint_label.text = ""
	var my_seat: int = int(view["viewer_seat"])
	var turn_seat: int = int(view["current_turn_seat"])
	var phase: int = int(view["phase"])
	var bid_val: int = int(view["current_bid"])
	var target_val: int = int(view["effective_contract_target"])
	var vis_trump: int = int(view["visible_trump_suit"])
	var trump_str: String = "Hidden" if vis_trump < 0 else CardDefs.SUIT_SYMBOLS.get(vis_trump, "Hidden")

	_header_label.text = "HAND %d     BID %d · TARGET %d     TRUMP %s" % [
		int(view["hand_number"]), bid_val, target_val, trump_str
	]
	var gp: Array = view["match_game_points"]
	var cp: Array = view["team_card_points"]
	_score_label.text = "US %+d     OPPONENTS %+d     ·     %d–%d" % [
		int(gp[0]), int(gp[1]), int(cp[0]), int(cp[1])
	]

	_status_banner.text = "YOUR TURN" if turn_seat == my_seat else "PLAYER %d IS PLAYING" % (turn_seat + 1)

	for child in _trick_center_box.get_children():
		child.queue_free()
	for entry in view["current_trick"]:
		var cv := CardView.new()
		cv.setup_card(int(entry["card"]), false, false)
		_trick_center_box.add_child(cv)

	_rebuild_phase_controls(view, phase, my_seat == turn_seat)

	for child in _hand_container.get_children():
		child.queue_free()

	
	var my_hand: Array[int] = []
	for raw_card_id in view.get("my_hand", []):
		my_hand.append(int(raw_card_id))

	var legal_cards: Array[int] = []

	if phase == GameState.Phase.TRICK_PLAY and my_seat == turn_seat:
		var raw_legal_cards: Array = AIController._get_legal_cards_from_view(view, my_hand)
		for card_id in raw_legal_cards:
			legal_cards.append(int(card_id))

	for c_id in my_hand:
		var card_widget := CardView.new()
		var can_play: bool = (phase == GameState.Phase.TRICK_PLAY and my_seat == turn_seat and legal_cards.has(c_id))
		card_widget.setup_card(c_id, can_play, false)
		card_widget.card_selected.connect(func(selected_id: int) -> void:
			MultiplayerManager.submit_local_action({"type": "PLAY_CARD", "card": selected_id})
		)
		_hand_container.add_child(card_widget)

func _rebuild_phase_controls(view: Dictionary, phase: int, is_my_turn: bool) -> void:
	for child in _action_panel.get_children():
		child.queue_free()

	if phase == GameState.Phase.HAND_SCORING:
		var summary: Dictionary = view["last_hand_summary"]
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "Hand Complete! Contract %s (%+d Game Pts)" % [
			"MADE" if bool(summary.get("contract_succeeded", false)) else "FAILED",
			int(summary.get("game_point_delta", 0))
		]
		_action_panel.add_child(lbl)

		var next_btn := _make_action_button("Deal Next Hand", func() -> void:
			if MultiplayerManager.is_authoritative_host:
				var st: GameState = MultiplayerManager.authoritative_state
				RulesEngine.start_new_hand(st, (st.dealer_seat + 1) % 4, st.match_seed)
				MultiplayerManager._broadcast_state_from_host()
		)
		_action_panel.add_child(next_btn)
		return

	if not is_my_turn:
		return

	match phase:
		GameState.Phase.BIDDING:
			var cur_bid: int = int(view["current_bid"])
			var min_next: int = RulesEngine.MIN_BID if cur_bid == 0 else cur_bid + 1
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 12)
			_action_panel.add_child(row)

			for b_val in range(min_next, mini(min_next + 4, RulesEngine.MAX_BID + 1)):
				row.add_child(_make_action_button("Bid %d" % b_val, func() -> void:
					MultiplayerManager.submit_local_action({"type": "BID", "amount": b_val})
				))
			row.add_child(_make_action_button("Pass", func() -> void:
				MultiplayerManager.submit_local_action({"type": "PASS_BID"})
			))

		GameState.Phase.SET_HIDDEN_TRUMP:
			var chooser := PanelContainer.new()
			chooser.add_theme_stylebox_override("panel", ThemePalette.create_panel_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.ACCENT_CYAN, 22, 2))
			_action_panel.add_child(chooser)
			var chooser_content := VBoxContainer.new()
			chooser_content.add_theme_constant_override("separation", 14)
			chooser.add_child(chooser_content)
			var title := Label.new()
			title.text = "CHOOSE TRUMP"
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 20)
			title.add_theme_color_override("font_color", ThemePalette.TEXT_PRIMARY)
			chooser_content.add_child(title)
			var subtitle := Label.new()
			subtitle.text = "Select a suit"
			subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			subtitle.add_theme_font_size_override("font_size", 14)
			subtitle.add_theme_color_override("font_color", ThemePalette.TEXT_MUTED)
			chooser_content.add_child(subtitle)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 10)
			chooser_content.add_child(row)
			for s_id in range(4):
				row.add_child(_make_suit_button(s_id))

		GameState.Phase.DOUBLE_DECISION:
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 16)
			_action_panel.add_child(row)
			row.add_child(_make_action_button("Call Double (2x)", func() -> void:
				MultiplayerManager.submit_local_action({"type": "CALL_DOUBLE", "double": true})
			))
			row.add_child(_make_action_button("Pass Double", func() -> void:
				MultiplayerManager.submit_local_action({"type": "CALL_DOUBLE", "double": false})
			))

		GameState.Phase.REDOUBLE_DECISION:
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 16)
			_action_panel.add_child(row)
			row.add_child(_make_action_button("Redouble (4x)", func() -> void:
				MultiplayerManager.submit_local_action({"type": "CALL_REDOUBLE", "redouble": true})
			))
			row.add_child(_make_action_button("Hold (2x)", func() -> void:
				MultiplayerManager.submit_local_action({"type": "CALL_REDOUBLE", "redouble": false})
			))

		GameState.Phase.TRICK_PLAY:
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 16)
			_action_panel.add_child(row)

			if not bool(view["trump_revealed"]) and not view["current_trick"].is_empty():
				row.add_child(_make_action_button("Reveal Trump", func() -> void:
					MultiplayerManager.submit_local_action({"type": "REQUEST_TRUMP_REVEAL"})
				))

			if bool(view["trump_revealed"]) and int(view["pair_declared_by_team"]) == -1:
				row.add_child(_make_action_button("Declare Pair (±4)", func() -> void:
					MultiplayerManager.submit_local_action({"type": "DECLARE_PAIR"})
				))


func _make_suit_button(suit_id: int) -> Button:
	var suit_button := Button.new()
	var symbol: String = str(CardDefs.SUIT_SYMBOLS[suit_id])
	var suit_color: Color = ThemePalette.SUIT_OBSIDIAN
	if suit_id == CardDefs.Suit.HEARTS or suit_id == CardDefs.Suit.DIAMONDS:
		suit_color = ThemePalette.SUIT_CRIMSON
	suit_button.text = symbol
	suit_button.tooltip_text = str(CardDefs.SUIT_NAMES[suit_id])
	suit_button.custom_minimum_size = Vector2(72, 82)
	suit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	suit_button.add_theme_font_size_override("font_size", 48)
	suit_button.add_theme_color_override("font_color", suit_color)
	suit_button.add_theme_color_override("font_hover_color", suit_color.lightened(0.2))
	suit_button.add_theme_color_override("font_pressed_color", ThemePalette.ACCENT_CYAN)
	suit_button.add_theme_stylebox_override("normal", ThemePalette.create_button_style(ThemePalette.CARD_IVORY, ThemePalette.TABLE_BORDER_EMERALD, 16))
	suit_button.add_theme_stylebox_override("hover", ThemePalette.create_button_style(Color.WHITE, ThemePalette.ACCENT_CYAN, 16))
	suit_button.add_theme_stylebox_override("pressed", ThemePalette.create_button_style(ThemePalette.CARD_IVORY, ThemePalette.ACCENT_WARM_GOLD, 16))
	suit_button.pressed.connect(func() -> void:
		MultiplayerManager.submit_local_action({"type": "SET_TRUMP", "suit": suit_id})
	)
	return suit_button

func _make_action_button(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(150, 60)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override(
		"normal",
		ThemePalette.create_button_style(ThemePalette.SURFACE_CHARCOAL, ThemePalette.ACCENT_CYAN, 16)
	)
	btn.add_theme_stylebox_override("hover", ThemePalette.create_button_style(ThemePalette.SURFACE_CHARCOAL.lightened(0.12), ThemePalette.ACCENT_CYAN, 16))
	btn.add_theme_stylebox_override("pressed", ThemePalette.create_button_style(ThemePalette.SURFACE_CHARCOAL.darkened(0.12), ThemePalette.ACCENT_WARM_GOLD, 16))
	btn.add_theme_color_override("font_color", ThemePalette.TEXT_PRIMARY)
	btn.pressed.connect(callback)
	return btn

func _on_hint_pressed() -> void:
	if MultiplayerManager.latest_player_view.is_empty():
		return
	var recommendation: Dictionary = AIController.choose_action(
		MultiplayerManager.latest_player_view,
		AIController.Difficulty.MASTER
	)
	var rec_type: String = str(recommendation.get("type", "NONE"))
	if rec_type == "PLAY_CARD":
		_hint_label.text = "Suggested Play: %s" % CardDefs.format_card(int(recommendation["card"]))
	elif rec_type == "BID":
		_hint_label.text = "Suggested Bid: %d" % int(recommendation["amount"])
	else:
		_hint_label.text = "Suggested Action: %s" % rec_type

func _on_action_rejected(error_code: String) -> void:
	_hint_label.text = "Action Rejected: %s" % error_code

func _on_host_migration_completed(new_host_seat: int) -> void:
	_status_banner.text = "Host Migrated Seamlessly to Seat %d" % new_host_seat

func _refresh_existing_match() -> void:
	if MultiplayerManager.authoritative_state != null:
		MultiplayerManager._broadcast_state_from_host()
