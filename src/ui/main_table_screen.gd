class_name MainTableScreen
extends Control

signal return_to_menu

var _header_label: Label
# Game Stat Grid Labels
var _t1_score_label: Label
var _t1_bid_label: Label
var _t1_dr_label: Label
var _t2_score_label: Label
var _t2_bid_label: Label
var _t2_dr_label: Label

var _hand_fan: Variant
var _opponent_card_fans: Dictionary = {}
var _opponent_fan_counts: Dictionary = {}
var _opponent_fan_generations: Dictionary = {}
var _seat_avatar_icons: Dictionary = {}
var _seat_name_labels: Dictionary = {}
var _seat_panels: Dictionary = {}
var _seat_status_boxes: Dictionary = {}
var _seat_trump_markers: Dictionary = {}
var _seat_trump_marker_labels: Dictionary = {}
var _dealer_badges: Dictionary = {}
var _status_banner: Label
var _trick_slots: Dictionary = {}

var _center_bid_box: PanelContainer
var _bid_vbox: VBoxContainer
var _bid_header_hbox: HBoxContainer
var _bid_buttons_grid: GridContainer
var _bid_buttons_scroll: ScrollContainer
var _bid_title_label: Label
var _bid_current_label: Label
var _trick_arena: Control

var _action_panel: PanelContainer
var _action_content: VBoxContainer

var _card_fan_container: Control
var _hint_box_btn: Button
var _hint_popup: PanelContainer
var _hint_label: Label
var _hint_thought_dots: Array[Panel] = []
var _hint_popup_tween: Tween
var _hint_popup_generation: int = 0
var _hint_recommended_card_id: int = -1
var _hint_phase: int = -1

var _was_my_turn: bool = false
var _last_trick_count: int = 0
var _last_completed_trick_count: int = 0
var _trick_history_initialized: bool = false
var _trick_collection_in_progress: bool = false
var _trick_collection_queue: Array[Dictionary] = []
var _last_view: Dictionary = {}
var _score_projection_warning_reported: bool = false
var _rendered_hand_number: int = -1
var _hand_render_generation: int = 0
var _hand_deal_in_progress_ids: Dictionary = {}
var _deal_queue: Array[Dictionary] = []
var _deal_animation_running: bool = false
var _deal_generation: int = 0
var _last_deal_hand_number: int = -1
var _last_shuffle_hand_number: int = -1
var _last_deal_hand_counts: Array[int] = []
var _last_dealt_local_card_ids: Array[int] = []
var _deal_overlay: Control
var _deal_back_texture: Texture2D
var _table_overlay: Control

var _trick_card_size: Vector2 = Vector2(108, 152)

func _ready() -> void:
	_build_table_ui()
	MultiplayerManager.player_view_updated.connect(_on_player_view_updated)
	MultiplayerManager.action_rejected.connect(_on_action_rejected)
	MultiplayerManager.host_migration_completed.connect(_on_host_migration_completed)
	AudioManager.start_gameplay_music()
	call_deferred("_refresh_existing_match")

func _exit_tree() -> void:
	AudioManager.stop_gameplay_music()

func _build_table_ui() -> void:
	const TRICK_SPREAD_X := 70.0
	const TRICK_SPREAD_Y := 76.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = ThemePalette.BG_MIDNIGHT_NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	margin.add_child(root)

	# 1. Top Header Bar
	var header_panel := PanelContainer.new()
	header_panel.custom_minimum_size = Vector2(0, 56)
	header_panel.add_theme_stylebox_override("panel", _create_box_style(Color("#101722"), Color("#194b56"), 12, 1))
	root.add_child(header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 14)
	header_panel.add_child(header_margin)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 14)
	header_margin.add_child(header_hbox)

	var back_btn := Button.new()
	back_btn.text = "‹"
	back_btn.custom_minimum_size = Vector2(38, 38)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.add_theme_stylebox_override("normal", _create_box_style(Color("#14202e"), Color("#1f5f6b"), 8, 1))
	back_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", 0.02, 0.75)
		return_to_menu.emit()
	)
	header_hbox.add_child(back_btn)

	_header_label = Label.new()
	_header_label.text = "ROUND 1"
	_header_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", Color("#cfdce8"))
	header_hbox.add_child(_header_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)

	_status_banner = Label.new()
	_status_banner.text = "YOUR TURN"
	_status_banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_banner.add_theme_font_size_override("font_size", 13)
	_status_banner.add_theme_color_override("font_color", Color("#00e5ff"))
	header_hbox.add_child(_status_banner)
	

	# 2. Main Felt Playing Table
	var arena := PanelContainer.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena.add_theme_stylebox_override("panel", _create_box_style(Color("#0c3b2e"), Color("#198276"), 26, 3))
	root.add_child(arena)
	
	_table_overlay = Control.new()
	_table_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table_overlay.clip_contents = true
	arena.add_child(_table_overlay)

	# --- 3A. Grid Game Stat Box (Top Right) ---
	var stat_float := PanelContainer.new()
	stat_float.anchor_left = 1.0
	stat_float.anchor_right = 1.0
	stat_float.anchor_top = 0.0
	stat_float.anchor_bottom = 0.0
	stat_float.offset_left = -222
	stat_float.offset_right = -16
	stat_float.offset_top = 16
	stat_float.offset_bottom = 132
	var stat_panel_style := StyleBoxFlat.new()
	stat_panel_style.bg_color = Color(0.04, 0.08, 0.14, 0.72)
	stat_panel_style.border_color = Color("#00D9E8")
	stat_panel_style.set_border_width_all(2)
	stat_panel_style.set_corner_radius_all(12)
	stat_panel_style.shadow_color = Color(0.0, 0.85, 0.95, 0.22)
	stat_panel_style.shadow_size = 10
	stat_panel_style.shadow_offset = Vector2.ZERO
	stat_panel_style.content_margin_left = 4
	stat_panel_style.content_margin_right = 4
	stat_panel_style.content_margin_top = 4
	stat_panel_style.content_margin_bottom = 4
	stat_float.add_theme_stylebox_override("panel", stat_panel_style)
	_table_overlay.add_child(stat_float)

	var stat_grid := GridContainer.new()
	stat_grid.columns = 3
	stat_grid.add_theme_constant_override("h_separation", 2)
	stat_grid.add_theme_constant_override("v_separation", 2)
	stat_float.add_child(stat_grid)

	# Row 1: Team 1 (Blue / You & Partner)
	var t1_bg := Color(0.08, 0.20, 0.36, 0.55)
	var t1_fg := Color("#64B5F6")
	_t1_score_label = _stat_grid_cell("0", t1_fg, t1_bg, true)
	_t1_bid_label = _stat_grid_cell("—", t1_fg, t1_bg, true)
	_t1_dr_label = _stat_grid_cell("—", t1_fg, t1_bg, true)
	stat_grid.add_child(_t1_score_label.get_parent())
	stat_grid.add_child(_t1_bid_label.get_parent())
	stat_grid.add_child(_t1_dr_label.get_parent())

	# Row 2: Headers
	stat_grid.add_child(_stat_grid_header("SCORE"))
	stat_grid.add_child(_stat_grid_header("BID"))
	stat_grid.add_child(_stat_grid_header("D/R"))

	# Row 3: Team 2 (Coral / Opponents)
	var t2_bg := Color(0.32, 0.08, 0.12, 0.55)
	var t2_fg := Color("#FF6E6E")
	_t2_score_label = _stat_grid_cell("0", t2_fg, t2_bg, false)
	_t2_bid_label = _stat_grid_cell("—", t2_fg, t2_bg, false)
	_t2_dr_label = _stat_grid_cell("—", t2_fg, t2_bg, false)
	stat_grid.add_child(_t2_score_label.get_parent())
	stat_grid.add_child(_t2_bid_label.get_parent())
	stat_grid.add_child(_t2_dr_label.get_parent())

	# --- 3B. 4 Player Avatars & Stacked Secondary Status Boxes ---
	_create_seat_Cluster(_table_overlay, 2, "Sage", Color("#64b5f6"), Vector2(0.5, 0.15), Vector2(0,0))
	_create_seat_Cluster(_table_overlay, 1, "Flick", Color("#e57373"), Vector2(0.12, 0.45), Vector2(1,0))
	_create_seat_Cluster(_table_overlay, 3, "Moss", Color("#81c784"), Vector2(0.88, 0.45), Vector2(-1,0))
	_create_seat_Cluster(_table_overlay, 0, "Guest45", Color("#4dd0e1"), Vector2(0.5, 0.77), Vector2(0,0))

	# Trump selection/reveal badge is attached to the actual chooser profile.

	# --- 3D. Hint Box at Bottom-Left ---
	var is_single_player: bool = MultiplayerManager.is_offline_solo
	_hint_box_btn = Button.new()
	_hint_box_btn.name = "HintBoxButton"
	_hint_box_btn.visible = is_single_player
	_hint_box_btn.anchor_left = 0.0
	_hint_box_btn.anchor_right = 0.0
	_hint_box_btn.anchor_top = 1.0
	_hint_box_btn.anchor_bottom = 1.0
	_hint_box_btn.offset_left = 16
	_hint_box_btn.offset_right = 64
	_hint_box_btn.offset_top = -66
	_hint_box_btn.offset_bottom = -18
	_hint_box_btn.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists("res://src/ui/icons/lightbulb.svg"):
		_hint_box_btn.icon = load("res://src/ui/icons/lightbulb.svg")
	else:
		_hint_box_btn.text = "💡"
	_hint_box_btn.expand_icon = true
	_hint_box_btn.add_theme_stylebox_override("normal", _create_box_style(Color("#101b27"), Color("#ffca28"), 12, 1))
	_hint_box_btn.pressed.connect(_on_hint_pressed)
	_table_overlay.add_child(_hint_box_btn)

	# A thought bubble is created only after the player taps the hint button.
	# It replaces the old always-present label beside the lightbulb.
	_hint_popup = PanelContainer.new()
	_hint_popup.name = "HintThoughtBubble"
	_hint_popup.anchor_left = 0.0
	_hint_popup.anchor_right = 0.0
	_hint_popup.anchor_top = 1.0
	_hint_popup.anchor_bottom = 1.0
	_hint_popup.offset_left = 78
	_hint_popup.offset_right = 350
	_hint_popup.offset_top = -166
	_hint_popup.offset_bottom = -82
	_hint_popup.visible = false
	_hint_popup.modulate = Color.WHITE
	_hint_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_popup.z_index = 82
	var hint_bubble_style := _create_box_style(Color("#102B35"), Color("#29E7F5"), 17, 2)
	hint_bubble_style.shadow_color = Color(0.0, 0.86, 1.0, 0.46)
	hint_bubble_style.shadow_size = 12
	hint_bubble_style.shadow_offset = Vector2.ZERO
	hint_bubble_style.content_margin_left = 12
	hint_bubble_style.content_margin_right = 12
	hint_bubble_style.content_margin_top = 8
	hint_bubble_style.content_margin_bottom = 8
	_hint_popup.add_theme_stylebox_override("panel", hint_bubble_style)
	_table_overlay.add_child(_hint_popup)

	var hint_content := VBoxContainer.new()
	hint_content.add_theme_constant_override("separation", 4)
	_hint_popup.add_child(hint_content)

	var hint_heading := Label.new()
	hint_heading.text = "💭  TABLE COACH"
	hint_heading.add_theme_font_size_override("font_size", 10)
	hint_heading.add_theme_color_override("font_color", Color("#39E8F5"))
	hint_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_content.add_child(hint_heading)

	_hint_label = Label.new()
	_hint_label.name = "HintMessage"
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color("#F3FBFF"))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(244, 42)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_content.add_child(_hint_label)

	# Two small thought dots visually connect the bubble to the hint control.
	for dot_config in [
		{"left": 67.0, "right": 81.0, "top": -91.0, "bottom": -77.0, "diameter": 14},
		{"left": 55.0, "right": 65.0, "top": -78.0, "bottom": -68.0, "diameter": 10}
	]:
		var dot := Panel.new()
		dot.anchor_left = 0.0
		dot.anchor_right = 0.0
		dot.anchor_top = 1.0
		dot.anchor_bottom = 1.0
		dot.offset_left = float(dot_config["left"])
		dot.offset_right = float(dot_config["right"])
		dot.offset_top = float(dot_config["top"])
		dot.offset_bottom = float(dot_config["bottom"])
		dot.visible = false
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.z_index = 81
		dot.add_theme_stylebox_override("panel", _create_circle_style(Color("#102B35"), Color("#29E7F5"), int(float(dot_config["diameter"]) / 2.0), 2))
		_table_overlay.add_child(dot)
		_hint_thought_dots.append(dot)

	# --- 3E. Center Trick Arena ---
	_trick_arena = Control.new()
	_trick_arena.anchor_left = 0.5
	_trick_arena.anchor_right = 0.5
	_trick_arena.anchor_top = 0.42
	_trick_arena.anchor_bottom = 0.42
	_table_overlay.add_child(_trick_arena)

	_trick_slots[2] = _create_card_slot(_trick_arena, Vector2(0, -TRICK_SPREAD_Y)) # Partner
	_trick_slots[0] = _create_card_slot(_trick_arena, Vector2(0, TRICK_SPREAD_Y))  # You
	_trick_slots[1] = _create_card_slot(_trick_arena, Vector2(-TRICK_SPREAD_X, 0)) # Left
	_trick_slots[3] = _create_card_slot(_trick_arena, Vector2(TRICK_SPREAD_X, 0))  # Right

	# --- 3G. Card Fan Arc (Bottom) ---
	_card_fan_container = Control.new()
	_card_fan_container.anchor_left = 0.05
	_card_fan_container.anchor_right = 0.95
	_card_fan_container.anchor_top = 1.0
	_card_fan_container.anchor_bottom = 0.90
	# Lift the hand clear of the bottom screen edge and reserve enough
	# vertical space for full-size cards on portrait phones.
	_card_fan_container.offset_top = -370
	_card_fan_container.offset_bottom = -140
	_table_overlay.add_child(_card_fan_container)

	# --- 3F. Center Bid Box (Wide Horizontal Rectangular Panel) ---
	# Authoritative layering: z_index = 100 with z_as_relative = false ensures
	# the bidding panel always draws strictly above opponent avatars, profiles,
	# badges, card fans, and table felt under all refresh scenarios.
	_center_bid_box = PanelContainer.new()
	_center_bid_box.anchor_left = 0.5
	_center_bid_box.anchor_right = 0.5
	_center_bid_box.anchor_top = 0.42
	_center_bid_box.anchor_bottom = 0.42
	_center_bid_box.offset_left = -310
	_center_bid_box.offset_right = 310
	_center_bid_box.offset_top = -115
	_center_bid_box.offset_bottom = 115
	_center_bid_box.z_index = 100
	_center_bid_box.z_as_relative = false
	_center_bid_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var bid_panel_style := StyleBoxFlat.new()
	bid_panel_style.bg_color = Color(0.04, 0.08, 0.13, 0.38)
	bid_panel_style.border_color = Color("#00D9E8")
	bid_panel_style.set_border_width_all(2)
	bid_panel_style.set_corner_radius_all(12)
	bid_panel_style.shadow_color = Color(0.0, 0.85, 0.95, 0.28)
	bid_panel_style.shadow_size = 14
	bid_panel_style.shadow_offset = Vector2.ZERO
	bid_panel_style.content_margin_left = 14
	bid_panel_style.content_margin_right = 14
	bid_panel_style.content_margin_top = 10
	bid_panel_style.content_margin_bottom = 10
	_center_bid_box.add_theme_stylebox_override("panel", bid_panel_style)
	_table_overlay.add_child(_center_bid_box)

	var bid_margin := MarginContainer.new()
	bid_margin.add_theme_constant_override("margin_left", 12)
	bid_margin.add_theme_constant_override("margin_right", 12)
	bid_margin.add_theme_constant_override("margin_top", 8)
	bid_margin.add_theme_constant_override("margin_bottom", 8)
	_center_bid_box.add_child(bid_margin)

	_bid_vbox = VBoxContainer.new()
	_bid_vbox.add_theme_constant_override("separation", 6)
	bid_margin.add_child(_bid_vbox)

	_bid_header_hbox = HBoxContainer.new()
	_bid_header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bid_vbox.add_child(_bid_header_hbox)

	_bid_title_label = Label.new()
	_bid_title_label.text = "PLACE YOUR BID"
	_bid_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bid_title_label.add_theme_font_size_override("font_size", 16)
	_bid_title_label.add_theme_color_override("font_color", Color("#00D9E8"))
	_bid_header_hbox.add_child(_bid_title_label)

	var bid_header_spacer := Control.new()
	bid_header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bid_header_hbox.add_child(bid_header_spacer)

	_bid_current_label = Label.new()
	_bid_current_label.text = "Current bid —"
	_bid_current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bid_current_label.add_theme_font_size_override("font_size", 13)
	_bid_current_label.add_theme_color_override("font_color", Color("#93A8B8"))
	_bid_header_hbox.add_child(_bid_current_label)

	_bid_buttons_scroll = ScrollContainer.new()
	_bid_buttons_scroll.name = "BidButtonsScroll"
	_bid_buttons_scroll.custom_minimum_size = Vector2(0, 84)
	_bid_buttons_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bid_buttons_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bid_buttons_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bid_buttons_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_bid_vbox.add_child(_bid_buttons_scroll)

	_bid_buttons_grid = GridContainer.new()
	_bid_buttons_grid.columns = 7
	_bid_buttons_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bid_buttons_grid.add_theme_constant_override("h_separation", 6)
	_bid_buttons_grid.add_theme_constant_override("v_separation", 6)
	_bid_buttons_scroll.add_child(_bid_buttons_grid)
	
	_action_panel = PanelContainer.new()
	_action_panel.z_index = 100
	_action_panel.z_as_relative = false
	_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var action_panel_style := StyleBoxFlat.new()
	action_panel_style.bg_color = Color(0.04, 0.08, 0.14, 0.72)
	action_panel_style.border_color = Color("#00D9E8")
	action_panel_style.set_border_width_all(2)
	action_panel_style.set_corner_radius_all(12)
	action_panel_style.shadow_color = Color(0.0, 0.85, 0.95, 0.28)
	action_panel_style.shadow_size = 14
	action_panel_style.shadow_offset = Vector2.ZERO
	action_panel_style.content_margin_left = 16
	action_panel_style.content_margin_right = 16
	action_panel_style.content_margin_top = 10
	action_panel_style.content_margin_bottom = 10
	_action_panel.add_theme_stylebox_override("panel", action_panel_style)
	_table_overlay.add_child(_action_panel)
	_action_content = VBoxContainer.new()
	_action_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_content.add_theme_constant_override("separation", 8)
	_action_panel.add_child(_action_content)
	
	_hand_fan = load("res://addons/card_fan/src/card_set.tscn").instantiate()
	_hand_fan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_fan.fan_card_width = 162.0
	_hand_fan.fan_card_height = 250.0
	_hand_fan.fan_radius = 520.0
	_hand_fan.fan_max_angle = 36.0
	_hand_fan.fan_max_angle_step = 5.5
	_hand_fan.fan_center_y_ratio = 0.62
	_hand_fan.tap_select_only = true
	_hand_fan.interaction_enabled = true
	_hand_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_fan.z_index = 2
	_card_fan_container.add_child(_hand_fan)
	_hand_fan.set_process_input(true)
	_hand_fan.set_process(true)
	_hand_fan.card_clicked.connect(_on_fan_card_clicked)

	_deal_overlay = Control.new()
	_deal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_deal_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deal_overlay.z_index = 50
	add_child(_deal_overlay)
	const CARD_BACK_PATH: String = "res://Cards/card backs/orange_back_suits_dark.png"
	if ResourceLoader.exists(CARD_BACK_PATH):
		_deal_back_texture = load(CARD_BACK_PATH) as Texture2D
	else:
		push_warning("Card back texture not found: " + CARD_BACK_PATH)


func _create_seat_Cluster(parent: Control, seat_idx: int, title: String, accent: Color, anchor: Vector2, fan_offset_dir: Vector2) -> void:
	var wrapper := Control.new()
	wrapper.anchor_left = anchor.x
	wrapper.anchor_top = anchor.y
	wrapper.anchor_right = anchor.x
	wrapper.anchor_bottom = anchor.y
	# Side opponents are shifted inward so their profile overlays the centre
	# of the rotated card fan instead of sitting outside it at the screen edge.
	if seat_idx == 1: # Left opponent: toward the table centre (right).
		wrapper.offset_left = 6
		wrapper.offset_right = 134
		wrapper.offset_top = -58
		wrapper.offset_bottom = 62
	elif seat_idx == 3: # Right opponent: toward the table centre (left).
		wrapper.offset_left = -134
		wrapper.offset_right = -6
		wrapper.offset_top = -58
		wrapper.offset_bottom = 62
	parent.add_child(wrapper)
	wrapper.z_index = 8 # Profile/avatar overlays must sit above the card-back fan.
	_seat_panels[seat_idx] = wrapper
	_create_dealer_badge(seat_idx, anchor)
	_create_player_trump_marker(seat_idx, anchor)

	# Remote card backs are deliberately separate from their zero-sized seat
	# anchors so the CardFan texture dimensions are not inherited incorrectly.
	if seat_idx != 0:
		_create_opponent_card_host(seat_idx, anchor)

	# Only the user's partnership (bottom player + top teammate) receives the
	# new horizontal profile card. Opponent profile cards below remain exactly
	# in the original avatar / name pill / score pill arrangement.
	if seat_idx in [0, 2]:
		wrapper.offset_left = -164
		wrapper.offset_right = 164
		wrapper.offset_top = -54
		wrapper.offset_bottom = 54
		_create_blue_team_profile_card(wrapper, seat_idx, title, accent)
		return

	# Original opponent profile UI — intentionally unchanged.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", -16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(vbox)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(88, 88)
	avatar.size = Vector2(88, 88)
	avatar.pivot_offset = Vector2(44, 44)
	avatar.rotation_degrees = -7.0 if seat_idx == 1 else 7.0
	avatar.z_index = 6
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var opponent_avatar_style := _create_circle_style(Color("#1a2838"), accent, 44, 3)
	opponent_avatar_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.58)
	opponent_avatar_style.shadow_size = 11
	opponent_avatar_style.shadow_offset = Vector2.ZERO
	avatar.add_theme_stylebox_override("panel", opponent_avatar_style)

	var av_icon := TextureRect.new()
	av_icon.name = "AvatarTexture_%d" % seat_idx
	av_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av_icon.custom_minimum_size = Vector2(76, 76)
	av_icon.size = Vector2(76, 76)
	av_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var initial_profile: Dictionary = PlayerProfile.get_ai_profile(seat_idx)
	av_icon.texture = PlayerProfile.get_avatar_texture(str(initial_profile.get("avatar_id", "byte")))
	avatar.add_child(av_icon)
	vbox.add_child(avatar)
	_seat_avatar_icons[seat_idx] = av_icon

	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 0)
	vbox.add_child(info_vbox)

	var name_panel := PanelContainer.new()
	name_panel.custom_minimum_size = Vector2(124, 28)
	name_panel.add_theme_stylebox_override("panel", _create_box_style(accent.lightened(0.5), accent, 6, 2))
	var name_lbl := Label.new()
	name_lbl.text = str(initial_profile.get("display_name", title))
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color("#111111"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_panel.add_child(name_lbl)
	info_vbox.add_child(name_panel)
	_seat_name_labels[seat_idx] = name_lbl

	var status_panel := PanelContainer.new()
	status_panel.custom_minimum_size = Vector2(88, 22)
	status_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var status_style := _create_box_style(Color.WHITE, accent, 6, 2)
	status_style.corner_radius_top_left = 0
	status_style.corner_radius_top_right = 0
	status_panel.add_theme_stylebox_override("panel", status_style)

	var status_lbl := Label.new()
	status_lbl.text = "0"
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", Color("#333333"))
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_panel.add_child(status_lbl)
	info_vbox.add_child(status_panel)
	_seat_status_boxes[seat_idx] = status_lbl


func _create_blue_team_profile_card(parent: Control, seat_idx: int, title: String, accent: Color) -> void:
	var initial_profile: Dictionary
	if seat_idx == 0:
		initial_profile = PlayerProfile.get_profile()
	else:
		initial_profile = PlayerProfile.get_ai_profile(seat_idx)

	# The name and score sit on one continuous blue strip. The avatar is a
	# larger circle layered over the centre of that strip, matching avatar_style.png.
	var strip := PanelContainer.new()
	strip.name = "BlueTeamProfileStrip_%d" % seat_idx
	strip.anchor_left = 0.0
	strip.anchor_right = 1.0
	strip.anchor_top = 0.31
	strip.anchor_bottom = 0.69
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_style := _create_box_style(Color("#A9D2F5"), Color("#4FA2E8"), 9, 2)
	strip_style.shadow_color = Color(0.0, 0.78, 0.95, 0.40)
	strip_style.shadow_size = 7
	strip_style.shadow_offset = Vector2.ZERO
	strip.add_theme_stylebox_override("panel", strip_style)
	parent.add_child(strip)
	strip.z_index = 1

	# Name field on the left of the avatar.
	var name_label := Label.new()
	name_label.name = "PlayerName_%d" % seat_idx
	name_label.anchor_left = 0.035
	name_label.anchor_right = 0.345
	name_label.anchor_top = 0.31
	name_label.anchor_bottom = 0.69
	name_label.offset_left = 2
	name_label.offset_right = -2
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text = str(initial_profile.get("display_name", title))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color("#164E78"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(name_label)
	_seat_name_labels[seat_idx] = name_label
	name_label.z_index = 2

	# Individual points captured by this player during the current hand.
	# This is intentionally NOT the top-right partnership match scoreboard.
	var score_label := Label.new()
	score_label.name = "IndividualHandScoreLabel_%d" % seat_idx
	score_label.anchor_left = 0.655
	score_label.anchor_right = 0.965
	score_label.anchor_top = 0.31
	score_label.anchor_bottom = 0.69
	score_label.offset_left = 2
	score_label.offset_right = -2
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.text = "+0"
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", Color("#164E78"))
	score_label.tooltip_text = "Individual card points captured this hand"
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(score_label)
	_seat_status_boxes[seat_idx] = score_label
	score_label.z_index = 2

	# Large circular avatar deliberately overlaps the horizontal strip.
	var avatar_frame := PanelContainer.new()
	avatar_frame.name = "AvatarFrame_%d" % seat_idx
	avatar_frame.position = Vector2(112, 2)
	avatar_frame.size = Vector2(104, 104)
	avatar_frame.custom_minimum_size = Vector2(104, 104)
	avatar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avatar_style := _create_circle_style(Color("#142333"), Color("#4FA2E8"), 52, 3)
	avatar_style.shadow_color = Color(0.0, 0.86, 1.0, 0.62)
	avatar_style.shadow_size = 13
	avatar_style.shadow_offset = Vector2.ZERO
	avatar_frame.add_theme_stylebox_override("panel", avatar_style)
	parent.add_child(avatar_frame)
	avatar_frame.z_index = 5

	var avatar_icon := TextureRect.new()
	avatar_icon.name = "AvatarTexture_%d" % seat_idx
	avatar_icon.custom_minimum_size = Vector2(88, 88)
	avatar_icon.size = Vector2(88, 88)
	avatar_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_icon.texture = PlayerProfile.get_avatar_texture(str(initial_profile.get("avatar_id", "byte")))
	avatar_frame.add_child(avatar_icon)
	_seat_avatar_icons[seat_idx] = avatar_icon


func _create_player_trump_marker(relative_seat: int, seat_anchor: Vector2) -> void:
	# This small independent badge follows the high bidder who selected trump.
	# It shows '?' until public reveal, then the actual large suit glyph.
	var marker := PanelContainer.new()
	marker.name = "TrumpChooserMarker_%d" % relative_seat
	marker.anchor_left = seat_anchor.x
	marker.anchor_right = seat_anchor.x
	marker.anchor_top = seat_anchor.y
	marker.anchor_bottom = seat_anchor.y
	marker.custom_minimum_size = Vector2(38, 38)
	marker.z_index = 38
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	match relative_seat:
		0, 2:
			# Beside the score end of the blue name/avatar/score strip.
			marker.offset_left = 132
			marker.offset_right = 170
			marker.offset_top = -54
			marker.offset_bottom = -16
		1:
			# Upper-right rim of the left opponent avatar.
			marker.offset_left = 98
			marker.offset_right = 136
			marker.offset_top = -52
			marker.offset_bottom = -14
		3:
			# Upper-right rim of the right opponent avatar (mirrored coordinates).
			marker.offset_left = -42
			marker.offset_right = -4
			marker.offset_top = -52
			marker.offset_bottom = -14

	var marker_style := _create_box_style(Color("#F4F7FA"), Color("#00BFD3"), 8, 2)
	marker.add_theme_stylebox_override("panel", marker_style)
	var glyph := Label.new()
	glyph.name = "TrumpChooserGlyph_%d" % relative_seat
	glyph.text = "?"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 26)
	glyph.add_theme_color_override("font_color", Color("#17232E"))
	marker.add_child(glyph)
	_table_overlay.add_child(marker)
	marker.visible = false
	_seat_trump_markers[relative_seat] = marker
	_seat_trump_marker_labels[relative_seat] = glyph


func _update_player_trump_markers(view: Dictionary, viewer_seat: int) -> void:
	var is_selected: bool = bool(view.get("trump_selected", false))
	var is_revealed: bool = bool(view.get("trump_revealed", false))
	var bidder_absolute: int = int(view.get("high_bidder_seat", -1))
	var bidder_relative: int = _relative_seat_for_absolute(bidder_absolute, viewer_seat) if bidder_absolute >= 0 else -1
	var visible_suit: int = int(view.get("visible_trump_suit", -1))

	for relative_seat in _seat_trump_markers.keys():
		var marker: PanelContainer = _seat_trump_markers[relative_seat] as PanelContainer
		var glyph: Label = _seat_trump_marker_labels[relative_seat] as Label
		var is_trump_chooser: bool = is_selected and int(relative_seat) == bidder_relative
		marker.visible = is_trump_chooser
		if not is_trump_chooser:
			continue

		if is_revealed and visible_suit >= 0:
			glyph.text = str(CardDefs.SUIT_SYMBOLS.get(visible_suit, "✦"))
			glyph.add_theme_font_size_override("font_size", 29)
			glyph.add_theme_color_override(
				"font_color",
				ThemePalette.SUIT_CRIMSON if visible_suit in [CardDefs.Suit.HEARTS, CardDefs.Suit.DIAMONDS] else ThemePalette.SUIT_OBSIDIAN
			)
			marker.add_theme_stylebox_override(
				"panel",
				_create_box_style(Color("#F7FAFC"), Color("#00BFD3"), 8, 2)
			)
		else:
			glyph.text = "?"
			glyph.add_theme_font_size_override("font_size", 26)
			glyph.add_theme_color_override("font_color", Color("#17232E"))
			marker.add_theme_stylebox_override(
				"panel",
				_create_box_style(Color("#F6C84A"), Color("#B98A18"), 8, 2)
			)



func _create_dealer_badge(relative_seat: int, seat_anchor: Vector2) -> void:
	var badge := PanelContainer.new()
	badge.name = "DealerBadge_%d" % relative_seat
	badge.anchor_left = seat_anchor.x
	badge.anchor_right = seat_anchor.x
	badge.anchor_top = seat_anchor.y
	badge.anchor_bottom = seat_anchor.y
	badge.z_index = 35
	badge.custom_minimum_size = Vector2(28, 28)
	match relative_seat:
		2: # Partner / top — clipped to the avatar's upper-right rim.
			badge.offset_left = 35
			badge.offset_right = 65
			badge.offset_top = -53
			badge.offset_bottom = -23
		1: # Left opponent: upper-left rim, opposite the trump marker.
			badge.offset_left = 14
			badge.offset_right = 42
			badge.offset_top = -58
			badge.offset_bottom = -30
		3: # Right opponent: upper-left rim, opposite the trump marker.
			badge.offset_left = -126
			badge.offset_right = -98
			badge.offset_top = -58
			badge.offset_bottom = -30
		0: # Local player / bottom — clipped to the avatar's upper-right rim.
			badge.offset_left = 35
			badge.offset_right = 65
			badge.offset_top = -53
			badge.offset_bottom = -23
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("#F6C84A")
	badge_style.border_color = Color("#9D7413")
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(14)
	badge.add_theme_stylebox_override("panel", badge_style)
	var label := Label.new()
	label.text = "D"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("#19222B"))
	badge.add_child(label)
	badge.visible = false
	_table_overlay.add_child(badge)
	_dealer_badges[relative_seat] = badge


func _update_dealer_badges(view: Dictionary, viewer_seat: int) -> void:
	var dealer_absolute: int = int(view.get("dealer_seat", -1))
	var dealer_relative: int = _relative_seat_for_absolute(dealer_absolute, viewer_seat) if dealer_absolute >= 0 else -1
	for relative_seat in _dealer_badges.keys():
		var badge: Control = _dealer_badges[relative_seat] as Control
		badge.visible = int(relative_seat) == dealer_relative


func _format_match_points(value: int) -> String:
	if value >= 0:
		return "+%d" % value
	return str(value)


func _create_opponent_card_host(relative_seat: int, seat_anchor: Vector2) -> void:
	# Every remote seat uses the same CardFan addon as the local hand.
	# Its fan is computed in its own local bounding box by card_set.gd, then
	# the entire Control is rotated around its center to face the table center.
	var fan_scene: PackedScene = load("res://addons/card_fan/src/card_set.tscn") as PackedScene
	if fan_scene == null:
		push_error("Unable to load CardFan scene for opponent seat %d" % relative_seat)
		return

	var fan: Control = fan_scene.instantiate() as Control
	fan.name = "OpponentCardFan_%d" % relative_seat
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fan.z_index = 1
	fan.custom_minimum_size = Vector2(360, 160)
	fan.size = Vector2(360, 160)
	fan.pivot_offset = Vector2(180, 80)

	# Match the bottom hand's curve parameters while scaling the backs down
	# slightly so all eight cards fit comfortably around the portrait seats.
	fan.fan_card_width = 80.0
	fan.fan_card_height = 113.0
	fan.fan_radius = 430.0
	fan.fan_max_angle = 38.0
	fan.fan_max_angle_step = 5.5
	fan.fan_center_y_ratio = 0.88
	fan.fan_arrange_duration = 0.24
	fan.fan_enter_duration = 0.32
	fan.interaction_enabled = false
	fan.tap_select_only = false
	fan.joystick_enabled = false
	fan.hover_offset = 0.0
	fan.hover_avoid_angle = 0.0
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fan.show_debug_buttons = false
	fan.set_process_input(false)
	fan.set_process_unhandled_input(false)
	fan.set_process(false)

	# All four fans use the same local geometry. Only the root transform differs:
	# bottom = 0° (local player's existing fan), partner = 180°,
	# left opponent = +90°, right opponent = -90°.
	fan.anchor_left = seat_anchor.x
	fan.anchor_right = seat_anchor.x
	fan.anchor_top = seat_anchor.y
	fan.anchor_bottom = seat_anchor.y
	match relative_seat:
		2: # Partner: horizontal fan above teammate, flipped toward the table.
			fan.offset_left = -180.0
			fan.offset_right = 180.0
			fan.offset_top = -30.0
			fan.offset_bottom = 130.0
			fan.rotation = PI
		1: # Left opponent: vertical fan to the right of the avatar, inward.
			fan.offset_left = 30.0
			fan.offset_right = 390.0
			fan.offset_top = -80.0
			fan.offset_bottom = 80.0
			fan.rotation = PI * 0.5
		3: # Right opponent: mirrored vertical fan to the left of the avatar.
			fan.offset_left = -390.0
			fan.offset_right = -30.0
			fan.offset_top = -80.0
			fan.offset_bottom = 80.0
			fan.rotation = -PI * 0.5

	_table_overlay.add_child(fan)
	_opponent_card_fans[relative_seat] = fan
	_opponent_fan_counts[relative_seat] = -1


func _sort_card_ids_by_suit(card_ids: Array[int]) -> Array[int]:
	return CardDefs.sort_hand_by_suit_and_rank(card_ids)


func _sync_deal_from_player_view(view: Dictionary, viewer_seat: int) -> void:
	var counts_variant: Variant = view.get("hand_counts", [])
	if not counts_variant is Array or counts_variant.size() < 4:
		return
	var current_counts: Array[int] = []
	for seat in range(4):
		current_counts.append(clampi(int(counts_variant[seat]), 0, 8))
	var current_hand_number: int = int(view.get("hand_number", 0))
	var current_local_hand: Array[int] = []
	current_local_hand.assign(view.get("my_hand", []))
	current_local_hand = _sort_card_ids_by_suit(current_local_hand)

	if current_hand_number != _last_deal_hand_number:
		_last_deal_hand_number = current_hand_number
		_deal_generation += 1
		_last_deal_hand_counts.assign([0, 0, 0, 0])
		_last_dealt_local_card_ids.clear()
		_deal_queue.clear()
		_hand_render_generation += 1
		_hand_deal_in_progress_ids.clear()
		_hand_fan.clear_all_cards()
		_trick_collection_queue.clear()
		_trick_collection_in_progress = false
		_last_completed_trick_count = 0
		_clear_trick_slots()
		for relative_seat in [1, 2, 3]:
			if _opponent_card_fans.has(relative_seat):
				var remote_fan: Control = _opponent_card_fans[relative_seat] as Control
				remote_fan.clear_all_cards()

	var deltas: Array[int] = []
	var has_new_cards: bool = false
	for seat in range(4):
		var previous: int = _last_deal_hand_counts[seat] if _last_deal_hand_counts.size() == 4 else 0
		var delta: int = current_counts[seat] - previous
		deltas.append(delta)
		if delta > 0:
			has_new_cards = true

	# Cards removed by trick play are removed from opponent fans immediately.
	for relative_seat in [1, 2, 3]:
		if not _opponent_card_fans.has(relative_seat):
			continue
		var absolute_seat: int = posmod(viewer_seat + relative_seat, 4)
		var remote_fan: Control = _opponent_card_fans[relative_seat] as Control
		while remote_fan.get_card_count() > current_counts[absolute_seat]:
			remote_fan.remove_card()

	if has_new_cards:
		var local_new_ids: Array[int] = []
		for card_id in current_local_hand:
			if not _last_dealt_local_card_ids.has(card_id):
				local_new_ids.append(card_id)
		local_new_ids = _sort_card_ids_by_suit(local_new_ids)
		var batch: Dictionary = {
			"deltas": deltas.duplicate(),
			"local_card_ids": local_new_ids,
			"dealer_seat": int(view.get("dealer_seat", 0)),
			"viewer_seat": viewer_seat,
			"generation": _deal_generation,
			"hand_number": current_hand_number
		}
		_deal_queue.append(batch)

	_last_deal_hand_counts = current_counts.duplicate()
	_last_dealt_local_card_ids = current_local_hand.duplicate()
	_rendered_hand_number = current_hand_number
	if not _deal_animation_running and not _deal_queue.is_empty():
		_run_clockwise_deal_queue()


func _run_clockwise_deal_queue() -> void:
	if _deal_animation_running:
		return
	_deal_animation_running = true
	while not _deal_queue.is_empty():
		var batch: Dictionary = _deal_queue.pop_front()
		var batch_generation: int = int(batch.get("generation", -1))
		if batch_generation != _deal_generation:
			continue # A newer hand superseded this queued deal.
		var deltas: Array = batch.get("deltas", [0, 0, 0, 0])
		var local_card_ids: Array = batch.get("local_card_ids", [])
		var dealer_absolute: int = int(batch.get("dealer_seat", 0))
		var viewer_seat: int = int(batch.get("viewer_seat", 0))
		var max_cards_to_deal: int = 0
		for delta_value in deltas:
			max_cards_to_deal = maxi(max_cards_to_deal, int(delta_value))
		var local_card_cursor: int = 0
		var batch_cancelled: bool = false
		var batch_hand_number: int = int(batch.get("hand_number", -1))
		if batch_hand_number != _last_shuffle_hand_number:
			AudioManager.play_sfx("deck_shuffle", 0.02, 0.30)
			_last_shuffle_hand_number = batch_hand_number
		# One card per player per pass, clockwise from the dealer's left.
		for card_round in range(max_cards_to_deal):
			if batch_generation != _deal_generation:
				batch_cancelled = true
				break
			for offset in range(4):
				if batch_generation != _deal_generation:
					batch_cancelled = true
					break
				var absolute_seat: int = posmod(dealer_absolute + 1 + offset, 4)
				if card_round >= int(deltas[absolute_seat]):
					continue
				var relative_seat: int = _relative_seat_for_absolute(absolute_seat, viewer_seat)
				if relative_seat == 0:
					if local_card_cursor < local_card_ids.size():
						_add_local_card_from_deck(int(local_card_ids[local_card_cursor]))
						local_card_cursor += 1
						# Each device hears the four cards arriving in its own hand,
						# not a burst of 16 overlapping remote-seat deal clicks.
						AudioManager.play_sfx("card_deal", 0.025, 0.44)
				else:
					_add_remote_card_from_deck(relative_seat)
				await get_tree().create_timer(0.105).timeout
				if batch_generation != _deal_generation:
					batch_cancelled = true
					break
			if batch_cancelled:
				break
		if batch_cancelled:
			continue
		# Recover any local card delta from older/partially restored saves.
		while local_card_cursor < local_card_ids.size():
			if batch_generation != _deal_generation:
				batch_cancelled = true
				break
			_add_local_card_from_deck(int(local_card_ids[local_card_cursor]))
			local_card_cursor += 1
			AudioManager.play_sfx("card_deal", 0.025, 0.44)
		await get_tree().create_timer(0.12).timeout
		_apply_local_hand_order(true)
	_deal_animation_running = false
	_reconcile_remote_fans_to_latest_view()

	# A newer state may have arrived while this batch was animating. Drain every
	# queued batch before releasing the authoritative action barrier.
	if not _deal_queue.is_empty():
		_run_clockwise_deal_queue()
		return

	if not _last_view.is_empty():
		if bool(_last_view.get("deal_animation_pending", false)) and MultiplayerManager.is_authoritative_host:
			# Host completion is broadcast to every peer. Until that update arrives,
			# all clients remain unable to bid, double, or play a card.
			MultiplayerManager.notify_local_deal_animation_completed()
		else:
			var viewer: int = int(_last_view.get("viewer_seat", 0))
			var phase: int = int(_last_view.get("phase", -1))
			var turn: int = int(_last_view.get("current_turn_seat", -1))
			_rebuild_hand(_last_view, phase, viewer, turn)


func _reconcile_remote_fans_to_latest_view() -> void:
	if _last_view.is_empty():
		return
	var counts: Array = _last_view.get("hand_counts", [])
	if counts.size() < 4:
		return
	var viewer_seat: int = int(_last_view.get("viewer_seat", 0))
	for relative_seat in [1, 2, 3]:
		if not _opponent_card_fans.has(relative_seat):
			continue
		var absolute_seat: int = posmod(viewer_seat + relative_seat, 4)
		var expected_count: int = clampi(int(counts[absolute_seat]), 0, 8)
		var fan: Control = _opponent_card_fans[relative_seat] as Control
		while fan.get_card_count() > expected_count:
			fan.remove_card()


func _deal_start_position_for_fan(fan: Control) -> Vector2:
	var fan_cards_container: Control = fan.cards_container
	var start_global: Vector2 = _table_overlay.get_global_rect().get_center()
	var inverse: Transform2D = fan_cards_container.get_global_transform_with_canvas().affine_inverse()
	return inverse * start_global


func _add_remote_card_from_deck(relative_seat: int) -> void:
	if not _opponent_card_fans.has(relative_seat) or _deal_back_texture == null:
		return
	var fan: Control = _opponent_card_fans[relative_seat] as Control
	var start_local: Vector2 = _deal_start_position_for_fan(fan)
	fan.add_card_with_texture_from(_deal_back_texture, "spade", 7, start_local)


func _add_local_card_from_deck(card_id: int) -> void:
	if not is_instance_valid(_hand_fan):
		return
	var suit_names: Array[String] = ["spade", "heart", "club", "diamond"]
	var asset_rank_by_domain_rank: Array[String] = ["7", "8", "12", "13", "10", "1", "9", "11"]
	var suit_name: String = suit_names[CardDefs.get_suit(card_id)]
	var asset_rank: String = asset_rank_by_domain_rank[CardDefs.get_rank(card_id)]
	var texture_path: String = "res://Cards/simplecard_%s_%s.png" % [suit_name, asset_rank]
	var texture: Texture2D = load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else null
	var start_local: Vector2 = _deal_start_position_for_fan(_hand_fan)
	var card_node: Control = _hand_fan.add_card_with_texture_from(texture, suit_name, int(asset_rank), start_local)
	if is_instance_valid(card_node):
		card_node.set_meta("domain_card_id", card_id)
		card_node.set_meta("is_legal", false)
		_hand_deal_in_progress_ids.erase(card_id)


func _apply_local_hand_order(play_sound: bool = false) -> void:
	if not is_instance_valid(_hand_fan):
		return
	var nodes_by_id: Dictionary = {}
	var current_cards: Array = _hand_fan.get_cards()
	for card_node in current_cards:
		if is_instance_valid(card_node) and card_node.has_meta("domain_card_id"):
			nodes_by_id[int(card_node.get_meta("domain_card_id"))] = card_node
	var ordered_ids: Array[int] = _sort_card_ids_by_suit(_last_dealt_local_card_ids)
	var ordered_nodes: Array = []
	for card_id in ordered_ids:
		if nodes_by_id.has(card_id):
			ordered_nodes.append(nodes_by_id[card_id])
	var order_changed: bool = false
	if current_cards.size() != ordered_nodes.size():
		order_changed = true
	else:
		for i in range(ordered_nodes.size()):
			if current_cards[i] != ordered_nodes[i]:
				order_changed = true
				break
	if order_changed:
		_hand_fan.set_card_order(ordered_nodes)
		if play_sound and ordered_nodes.size() >= 2:
			AudioManager.play_sfx("card_sort", 0.03, 0.62)



func _refresh_seat_profiles(view: Dictionary) -> void:
	var viewer_seat: int = int(view.get("viewer_seat", 0))
	var seat_is_ai: Array = view.get("seat_is_ai", [])
	for relative_seat in range(4):
		var profile: Dictionary
		if relative_seat == 0:
			profile = PlayerProfile.get_profile()
		else:
			var absolute_seat: int = posmod(viewer_seat + relative_seat, 4)
			var ai_seat: bool = seat_is_ai.size() > absolute_seat and bool(seat_is_ai[absolute_seat])
			profile = PlayerProfile.get_ai_profile(relative_seat) if ai_seat else PlayerProfile.get_remote_placeholder(relative_seat)

		if _seat_avatar_icons.has(relative_seat):
			var avatar_icon: TextureRect = _seat_avatar_icons[relative_seat]
			avatar_icon.texture = PlayerProfile.get_avatar_texture(str(profile.get("avatar_id", "byte")))
		if _seat_name_labels.has(relative_seat):
			(_seat_name_labels[relative_seat] as Label).text = str(profile.get("display_name", "PLAYER"))



func _stat_grid_cell(default_val: String, text_color: Color, bg_color: Color, is_top: bool) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(66, 40)
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color("#00D9E8").darkened(0.4)
	style.set_border_width_all(1)
	if is_top:
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
	else:
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	
	var lbl := Label.new()
	lbl.text = default_val
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.add_theme_color_override("font_color", text_color)
	panel.add_child(lbl)
	return lbl

func _stat_grid_header(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(66, 26)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.12, 0.20, 0.55)
	style.border_color = Color("#00D9E8").darkened(0.5)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	
	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#8EB8D0"))
	panel.add_child(lbl)
	return panel
	
func _create_card_slot(parent: Control, offset: Vector2) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.size = _trick_card_size
	slot.custom_minimum_size = _trick_card_size
	slot.position = offset - (_trick_card_size / 2.0)
	# Keep the slot as an invisible positioning anchor; do not draw an empty
	# card-shaped outline before a player actually lays a card.
	slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	return slot

func _create_box_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb

func _create_circle_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb

func _relative_seat_for_absolute(absolute_seat: int, viewer_seat: int) -> int:
	return posmod(absolute_seat - viewer_seat, 4)

func set_table_phase(is_bidding_phase: bool, is_my_turn: bool) -> void:
	# Show bidding controls only when this device owns the active auction turn.
	if is_instance_valid(_center_bid_box):
		_center_bid_box.visible = is_bidding_phase and is_my_turn
	if is_instance_valid(_trick_arena):
		_trick_arena.visible = not is_bidding_phase

func update_seat_status(seat_index: int, status_text: String) -> void:
	if _seat_status_boxes.has(seat_index):
		var lbl: Label = _seat_status_boxes[seat_index]
		lbl.text = status_text

func _get_live_hand_points(view: Dictionary) -> Array:
	# GameState.team_card_points is the authoritative current-hand point total.
	# It sums the actual card values in completed tricks (J=3, 9=2, A/10=1)
	# and includes the +1 last-trick bonus. It is not a count of tricks won.
	var snapshot: Variant = view.get("team_card_points", [0, 0])
	if snapshot is Array and snapshot.size() >= 2:
		return [int(snapshot[0]), int(snapshot[1])]

	# Compatibility fallback for a legacy projection without team_card_points.
	var totals: Array[int] = [0, 0]
	var completed: Array = view.get("completed_tricks", [])
	for record in completed:
		if not record is Dictionary:
			continue
		var winner_team: int = int(record.get("winner_team", -1))
		if winner_team >= 0 and winner_team < 2:
			totals[winner_team] += int(record.get("points", 0))
	return [totals[0], totals[1]]



func _on_player_view_updated(view: Dictionary) -> void:
	var previous_view: Dictionary = _last_view.duplicate(true)
	_process_audio_view_events(previous_view, view)
	_last_view = view.duplicate(true)
	var my_seat: int = int(view.get("viewer_seat", 0))
	var turn_seat: int = int(view.get("current_turn_seat", 0))
	var phase: int = int(view.get("phase", -1))
	var bid: int = int(view.get("current_bid", 0))
	if _hint_popup != null and _hint_popup.visible and (phase != _hint_phase or my_seat != turn_seat):
		_clear_hint_presentation()

	_sync_deal_from_player_view(view, my_seat)
	_refresh_seat_profiles(view)
	_update_dealer_badges(view, my_seat)

	var current_hand_number: int = int(view.get("hand_number", 1))
	_header_label.text = "ROUND %d" % current_hand_number

	# The top-right board remains a partnership match scoreboard. Its two
	# score cells are always local team (blue) and opposing team (coral).
	# Bid and Double/Redouble values are placed on the row of the team that
	# actually won the auction, not unconditionally in the blue row.
	var match_points: Array = view.get("match_game_points", [0, 0])
	var my_team: int = GameState.get_team(my_seat)
	_t1_score_label.text = _format_match_points(int(match_points[my_team]))
	_t2_score_label.text = _format_match_points(int(match_points[1 - my_team]))
	_t1_bid_label.text = "—"
	_t1_dr_label.text = "—"
	_t2_bid_label.text = "—"
	_t2_dr_label.text = "—"

	var high_bidder_seat: int = int(view.get("high_bidder_seat", -1))
	var stake_multiplier: int = int(view.get("stake_multiplier", GameState.StakeMultiplier.NORMAL))
	if high_bidder_seat >= 0 and bid > 0:
		var bidding_team: int = GameState.get_team(high_bidder_seat)
		var bidder_dr: String = "—" if stake_multiplier <= 1 else ("2×" if stake_multiplier == GameState.StakeMultiplier.DOUBLED else "4×")
		if bidding_team == my_team:
			_t1_bid_label.text = str(bid)
			_t1_dr_label.text = bidder_dr
		else:
			_t2_bid_label.text = str(bid)
			_t2_dr_label.text = bidder_dr
	
	_update_player_trump_markers(view, my_seat)
			
	var latest_bid_by_seat: Dictionary = {}
	for bid_event in view.get("bidding_history", []):
		var event_seat: int = int(bid_event.get("seat", -1))
		if event_seat >= 0:
			latest_bid_by_seat[event_seat] = bid_event
			
	var is_bidding_phase = (phase == GameState.Phase.BIDDING or phase == GameState.Phase.SET_HIDDEN_TRUMP)

	# Every profile score is individual captured card points for this hand.
	# Partnership totals remain exclusively on the unchanged top-right scoreboard.
	var individual_points: Array = view.get("seat_card_points", [0, 0, 0, 0])

	for relative_seat in _seat_status_boxes.keys():
		var absolute_seat: int = posmod(my_seat + int(relative_seat), 4)
		var status_text: String = ""

		if is_bidding_phase:
			if latest_bid_by_seat.has(absolute_seat):
				var bid_event: Dictionary = latest_bid_by_seat[absolute_seat]
				status_text = "Pass" if str(bid_event.get("type", "")) == "PASS" else "Bid " + str(bid_event.get("amount", ""))
			else:
				status_text = "Waiting..."
		else:
			var personal_points: int = int(individual_points[absolute_seat]) if individual_points.size() > absolute_seat else 0
			if relative_seat in [0, 2]:
				status_text = "+%d" % personal_points
			else:
				# Keep the old opponent pill, but display the opponent's own points.
				status_text = "+%d" % personal_points

		update_seat_status(relative_seat, status_text)
		
	var is_my_turn: bool = my_seat == turn_seat
	set_table_phase(phase == GameState.Phase.BIDDING, is_my_turn)
	_status_banner.text = "DEALING" if (_deal_animation_running or bool(view.get("deal_animation_pending", false))) else ("YOUR TURN" if is_my_turn else "")
	if is_my_turn and not _was_my_turn:
		AudioManager.play_sfx("turn_alert")
		HapticsManager.light_tap()
	_was_my_turn = is_my_turn
	
	var trick: Array = view.get("current_trick", [])
	_last_trick_count = trick.size()

	_update_trick_visuals(view, my_seat)
	_rebuild_phase_controls(view, phase, is_my_turn)
	_rebuild_hand(view, phase, my_seat, turn_seat)

func _process_audio_view_events(previous: Dictionary, current: Dictionary) -> void:
	# First view is a baseline (for example after save recovery); never replay
	# old bids or cards merely because the table scene was opened again.
	if previous.is_empty():
		return
	if str(previous.get("session_id", "")) != str(current.get("session_id", "")):
		return

	var previous_hand: int = int(previous.get("hand_number", -1))
	var current_hand: int = int(current.get("hand_number", -1))
	if previous_hand != current_hand:
		return

	# Announce every newly accepted auction entry, including AI and remote bids.
	# Compare the common prefix rather than relying only on array size; this also
	# handles a restored or reconstructed history whose tail was replaced.
	var old_bids: Array = previous.get("bidding_history", [])
	var new_bids: Array = current.get("bidding_history", [])
	var common_prefix: int = 0
	var shared_count: int = mini(old_bids.size(), new_bids.size())
	while common_prefix < shared_count and old_bids[common_prefix] == new_bids[common_prefix]:
		common_prefix += 1
	for i in range(common_prefix, new_bids.size()):
		var bid_event: Dictionary = new_bids[i]
		var seat: int = int(bid_event.get("seat", 0))
		var bid_type: String = str(bid_event.get("type", ""))
		if bid_type == "BID":
			AudioManager.play_bid_callout(int(bid_event.get("amount", 0)), seat)
		elif bid_type == "PASS":
			AudioManager.play_sfx("bid_pass", 0.02, 0.32)
			AudioManager.play_pass_callout(seat)

	var previous_multiplier: int = int(previous.get("stake_multiplier", GameState.StakeMultiplier.NORMAL))
	var current_multiplier: int = int(current.get("stake_multiplier", GameState.StakeMultiplier.NORMAL))
	if current_multiplier > previous_multiplier:
		AudioManager.play_sfx("redouble" if current_multiplier >= GameState.StakeMultiplier.REDOUBLED else "double", 0.02, 0.9)

	if not bool(previous.get("trump_selected", false)) and bool(current.get("trump_selected", false)):
		AudioManager.play_sfx("trump_select", 0.02, 0.72)
	if not bool(previous.get("trump_revealed", false)) and bool(current.get("trump_revealed", false)):
		AudioManager.play_sfx("trump_reveal", 0.02, 0.85)

	var previous_pair_team: int = int(previous.get("pair_declared_by_team", -1))
	var current_pair_team: int = int(current.get("pair_declared_by_team", -1))
	if previous_pair_team == -1 and current_pair_team >= 0:
		AudioManager.play_sfx("pair_declared", 0.02, 0.9)

	# One crisp card sound per accepted play. Count the exact difference in total trick cards.
	var old_trick: Array = previous.get("current_trick", [])
	var new_trick: Array = current.get("current_trick", [])
	var old_completed: int = int(previous.get("completed_tricks_count", previous.get("completed_tricks", []).size()))
	var new_completed: int = int(current.get("completed_tricks_count", current.get("completed_tricks", []).size()))
	var old_total_cards: int = old_completed * 4 + old_trick.size()
	var new_total_cards: int = new_completed * 4 + new_trick.size()
	var card_plays: int = 0
	if new_completed <= old_completed + 1:
		card_plays = clampi(new_total_cards - old_total_cards, 0, 4)
	for i in range(card_plays):
		AudioManager.play_sfx("card_play", 0.035, 0.9)

	# Result cue plays once when the authoritative state enters its result phase.
	var old_phase: int = int(previous.get("phase", -1))
	var new_phase: int = int(current.get("phase", -1))
	if old_phase not in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER] and new_phase in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER]:
		var summary: Dictionary = current.get("last_hand_summary", {})
		var contract_made: bool = bool(summary.get("contract_succeeded", false))
		if new_phase == GameState.Phase.MATCH_OVER:
			var local_team: int = GameState.get_team(int(current.get("viewer_seat", 0)))
			var won_match: bool = int(current.get("winning_team", -1)) == local_team
			AudioManager.play_sfx("match_win" if won_match else "match_loss", 0.015, 0.9)
		else:
			var local_team: int = GameState.get_team(int(current.get("viewer_seat", 0)))
			var bidding_team: int = int(summary.get("bidding_team", -1))
			var local_won_hand: bool = contract_made if local_team == bidding_team else not contract_made
			AudioManager.play_sfx("hand_win" if local_won_hand else "hand_loss", 0.02, 0.82)


func _update_trick_visuals(view: Dictionary, viewer_seat: int) -> void:
	var completed: Array = view.get("completed_tricks", [])
	var completed_count: int = int(view.get("completed_tricks_count", completed.size()))
	if not _trick_history_initialized:
		_trick_history_initialized = true
		_last_completed_trick_count = completed_count
		_render_trick_entries(view.get("current_trick", []), viewer_seat)
		return

	if completed_count < _last_completed_trick_count:
		_last_completed_trick_count = completed_count
		if not _trick_collection_in_progress:
			_render_trick_entries(view.get("current_trick", []), viewer_seat)
		return

	if completed_count > _last_completed_trick_count:
		for i in range(_last_completed_trick_count, mini(completed_count, completed.size())):
			_trick_collection_queue.append(completed[i].duplicate(true))
		_last_completed_trick_count = completed_count
		if not _trick_collection_in_progress:
			_process_trick_collection_queue(viewer_seat)
		return

	if not _trick_collection_in_progress and _trick_collection_queue.is_empty():
		_render_trick_entries(view.get("current_trick", []), viewer_seat)

func _clear_trick_slots() -> void:
	for slot in _trick_slots.values():
		for child in slot.get_children():
			child.queue_free()

func _render_trick_entries(entries: Array, viewer_seat: int) -> Array[Control]:
	_clear_trick_slots()
	var rendered: Array[Control] = []
	for entry in entries:
		var absolute_seat: int = int(entry.get("seat", -1))
		var relative_seat: int = _relative_seat_for_absolute(absolute_seat, viewer_seat)
		if not _trick_slots.has(relative_seat):
			continue
		var card := CardView.new()
		card.setup_card(int(entry.get("card", -1)), false, false)
		card.custom_minimum_size = _trick_card_size
		card.size = _trick_card_size
		_trick_slots[relative_seat].add_child(card)
		rendered.append(card)
	return rendered

func _process_trick_collection_queue(viewer_seat: int) -> void:
	if _trick_collection_in_progress:
		return
	_trick_collection_in_progress = true
	while not _trick_collection_queue.is_empty():
		var completed: Dictionary = _trick_collection_queue.pop_front()
		var plays: Array = completed.get("plays", [])
		var winner_seat: int = int(completed.get("winner_seat", -1))
		var winner_relative: int = _relative_seat_for_absolute(winner_seat, viewer_seat)
		var cards: Array[Control] = _render_trick_entries(plays, viewer_seat)
		await get_tree().create_timer(0.48).timeout
		if cards.size() == 4 and _trick_slots.has(winner_relative):
			var winner_seat_panel: Control = _seat_panels.get(winner_relative) as Control
			var destination: Vector2 = winner_seat_panel.get_global_rect().get_center() if is_instance_valid(winner_seat_panel) else _trick_slots[winner_relative].get_global_rect().get_center()
			var tweens: Array[Tween] = []
			for i in range(cards.size()):
				var card: Control = cards[i]
				if not is_instance_valid(card):
					continue
				card.pivot_offset = card.size * 0.5
				if is_instance_valid(_deal_overlay):
					card.reparent(_deal_overlay, true)
				var target_position: Vector2 = destination - card.size * 0.5
				var tween: Tween = create_tween()
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.set_ease(Tween.EASE_IN)
				tween.tween_interval(float(i) * 0.035)
				tween.tween_property(card, "global_position", target_position, 0.42)
				tween.parallel().tween_property(card, "scale", Vector2(0.28, 0.28), 0.42)
				tween.parallel().tween_property(card, "modulate:a", 0.15, 0.42)
				tweens.append(tween)
			if not tweens.is_empty():
				await tweens[tweens.size() - 1].finished
		for card in cards:
			if is_instance_valid(card):
				card.queue_free()
		_clear_trick_slots()
		AudioManager.play_sfx("trick_collect", 0.02, 0.82)
	_trick_collection_in_progress = false
	_render_trick_entries(_last_view.get("current_trick", []), int(_last_view.get("viewer_seat", viewer_seat)))

	# Reveal the HAND COMPLETE / MATCH OVER panel only after final collection.
	var final_phase: int = int(_last_view.get("phase", -1))
	if final_phase in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER]:
		var final_viewer: int = int(_last_view.get("viewer_seat", viewer_seat))
		var final_turn: int = int(_last_view.get("current_turn_seat", -1))
		_rebuild_phase_controls(_last_view, final_phase, final_viewer == final_turn)

func _rebuild_hand(view: Dictionary, phase: int, my_seat: int, turn_seat: int) -> void:
	if not is_instance_valid(_hand_fan):
		return

	var hand: Array[int] = []
	hand.assign(view.get("my_hand", []))
	hand = _sort_card_ids_by_suit(hand)
	var hand_number: int = int(view.get("hand_number", 0))
	_rendered_hand_number = hand_number

	var legal: Array[int] = []
	var is_local_turn: bool = phase == GameState.Phase.TRICK_PLAY and my_seat == turn_seat and not bool(view.get("deal_animation_pending", false)) and not _deal_animation_running
	if is_local_turn:
		legal = AIController._get_legal_cards_from_view(view, hand)

	var should_dim_off_suit: bool = is_local_turn and not view.get("current_trick", []).is_empty() and legal.size() < hand.size()
	var existing: Dictionary = {}
	for card_node in _hand_fan.get_cards():
		if is_instance_valid(card_node) and card_node.has_meta("domain_card_id"):
			existing[int(card_node.get_meta("domain_card_id"))] = card_node

	for existing_id in existing.keys():
		if not hand.has(int(existing_id)):
			_hand_fan.remove_specific_card(existing[existing_id])
			existing.erase(existing_id)

	for card_id in hand:
		if existing.has(card_id):
			var current_node: Control = existing[card_id]
			var card_is_legal: bool = legal.has(card_id) if is_local_turn else true
			current_node.set_meta("is_legal", card_is_legal)
			# Only dim when the player actually has to follow the lead suit (or
			# must play revealed trump). If void in the lead suit, all discards
			# remain fully visible. Never dim just because it is another seat's turn.
			current_node.modulate = Color(0.62, 0.62, 0.62, 1.0) if should_dim_off_suit and not card_is_legal else Color.WHITE

	# Card creation is centralized in the clockwise deal queue so the local
	# face-up cards arrive in the same sequence as the three remote card backs.
	_apply_local_hand_order(false)
	_refresh_hint_card_glow()


func _on_fan_card_clicked(card: Control) -> void:
	if not is_instance_valid(card) or _last_view.is_empty():
		return

	if _deal_animation_running or bool(_last_view.get("deal_animation_pending", false)):
		return
	var phase: int = int(_last_view.get("phase", -1))
	var viewer_seat: int = int(_last_view.get("viewer_seat", -1))
	var turn_seat: int = int(_last_view.get("current_turn_seat", -2))
	if phase != GameState.Phase.TRICK_PLAY or viewer_seat < 0 or viewer_seat != turn_seat:
		return

	var card_id: int = int(card.get_meta("domain_card_id", -1))
	if card_id < 0:
		return

	# Recalculate from the latest sanitized PlayerView: cached `is_legal` can
	# become stale while card dealing or turn-change updates are in flight.
	var hand: Array[int] = []
	hand.assign(_last_view.get("my_hand", []))
	var legal_cards: Array[int] = AIController._get_legal_cards_from_view(_last_view, hand)
	if not legal_cards.has(card_id):
		_show_hint_popup("Follow the lead suit. Only legal cards can be played.")
		AudioManager.play_sfx("error")
		return

	_clear_hint_presentation()
	MultiplayerManager.submit_local_action({"type": "PLAY_CARD", "card": card_id})

func _is_hand_fully_resolved(view: Dictionary) -> bool:
	var completed_tricks: Array = view.get("completed_tricks", [])
	var completed_count: int = int(view.get("completed_tricks_count", completed_tricks.size()))
	var hand_counts: Array = view.get("hand_counts", [])
	if completed_count != 8 or not view.get("current_trick", []).is_empty() or hand_counts.size() < 4:
		return false
	for count_value in hand_counts:
		if int(count_value) != 0:
			return false
	return true


func _is_final_trick_animation_running() -> bool:
	return _trick_collection_in_progress or not _trick_collection_queue.is_empty()


func _rebuild_phase_controls(view: Dictionary, phase: int, is_my_turn: bool) -> void:
	# Remove phase-specific controls while preserving persistent UI containers.

	if is_instance_valid(_action_content):
		for child in _action_content.get_children():
			_action_content.remove_child(child)
			child.queue_free()

	if is_instance_valid(_bid_buttons_grid):
		for child in _bid_buttons_grid.get_children():
			_bid_buttons_grid.remove_child(child)
			child.queue_free()

	if is_instance_valid(_bid_vbox):
		for child in _bid_vbox.get_children():
			if child != _bid_header_hbox and child != _bid_buttons_scroll:
				_bid_vbox.remove_child(child)
				child.queue_free()

	_action_panel.visible = false

	var deal_locked: bool = bool(view.get("deal_animation_pending", false)) or _deal_animation_running
	_center_bid_box.visible = phase == GameState.Phase.BIDDING and is_my_turn and not deal_locked
	if is_instance_valid(_bid_header_hbox):
		_bid_header_hbox.visible = phase == GameState.Phase.BIDDING and is_my_turn and not deal_locked

	if deal_locked:
		_action_panel.visible = false
		return

	if phase == GameState.Phase.HAND_SCORING or phase == GameState.Phase.MATCH_OVER:
		_action_panel.visible = true
		_action_panel.anchor_left = 0.5
		_action_panel.anchor_right = 0.5
		_action_panel.anchor_top = 0.60
		_action_panel.anchor_bottom = 0.60
		_action_panel.offset_left = -132
		_action_panel.offset_right = 132
		_action_panel.offset_top = -58
		_action_panel.offset_bottom = 58

		var title := Label.new()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN)
		_action_content.add_child(title)

		if phase == GameState.Phase.HAND_SCORING:
			if not _is_hand_fully_resolved(view):
				title.text = "FINAL TRICK IN PROGRESS"
				return
			if _is_final_trick_animation_running():
				title.text = "COLLECTING FINAL TRICK"
				var trick_records: Array = view.get("completed_tricks", [])
				if not trick_records.is_empty():
					var last_record: Dictionary = trick_records[trick_records.size() - 1]
					var winner_seat: int = int(last_record.get("winner_seat", -1))
					if winner_seat >= 0:
						var viewer_seat: int = int(view.get("viewer_seat", 0))
						var relative_winner: int = _relative_seat_for_absolute(winner_seat, viewer_seat)
						var winner_name: String = "PLAYER"
						if _seat_name_labels.has(relative_winner):
							winner_name = (_seat_name_labels[relative_winner] as Label).text
						var detail := Label.new()
						detail.text = "%s takes +%d" % [winner_name, int(last_record.get("points", 0))]
						detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
						detail.add_theme_color_override("font_color", Color("#EAF5F7"))
						_action_content.add_child(detail)
				return

			title.text = "HAND COMPLETE"
			var summary: Dictionary = view.get("last_hand_summary", {})
			var delta: int = int(summary.get("game_point_delta", 0))
			var result_label := Label.new()
			result_label.text = "CONTRACT %s  %s%d" % [
				"MADE" if bool(summary.get("contract_succeeded", false)) else "MISSED",
				"+" if delta >= 0 else "",
				delta
			]
			result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			result_label.add_theme_color_override("font_color", Color("#EAF5F7"))
			_action_content.add_child(result_label)

			var next_button := _make_action_button("NEXT HAND", func() -> void:
				if not MultiplayerManager.is_authoritative_host:
					return
				var state: GameState = MultiplayerManager.authoritative_state
				if state == null or state.phase != GameState.Phase.HAND_SCORING:
					return
				if state.completed_tricks.size() != 8 or not state.current_trick.is_empty():
					return
				if state.team_card_points[0] + state.team_card_points[1] != 29:
					return
				for seat in range(4):
					if not state.hands[seat].is_empty():
						return
				RulesEngine.start_new_hand(state, (state.dealer_seat + 1) % 4, state.match_seed)
				MultiplayerManager._broadcast_state_from_host()
			)
			next_button.custom_minimum_size = Vector2(180, 44)
			_action_content.add_child(next_button)
		else:
			title.text = "MATCH OVER"
			var winning_team: int = int(view.get("winning_team", -1))
			var winner_label := Label.new()
			winner_label.text = "BLUE TEAM WINS" if winning_team == 0 else ("CORAL TEAM WINS" if winning_team == 1 else "FINAL RESULT")
			winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			winner_label.add_theme_color_override("font_color", Color("#EAF5F7"))
			_action_content.add_child(winner_label)
			var menu_button := _make_action_button("RETURN TO MENU", func() -> void:
				return_to_menu.emit()
			)
			menu_button.custom_minimum_size = Vector2(180, 44)
			_action_content.add_child(menu_button)
		return

	if not is_my_turn:
		return

	match phase:
		GameState.Phase.BIDDING:
			var current_bid: int = int(view.get("current_bid", 0))
			var minimum: int = RulesEngine.MIN_BID if current_bid == 0 else current_bid + 1
			_bid_current_label.text = "Current bid  —" if current_bid <= 0 else "Current bid  %d" % current_bid

			for amount in range(RulesEngine.MIN_BID, RulesEngine.MAX_BID + 1):
				var chosen: int = amount
				var bid_button := _make_action_button(str(chosen), func() -> void:
					_center_bid_box.visible = false
					MultiplayerManager.submit_local_action({"type": "BID", "amount": chosen})
				)
				bid_button.custom_minimum_size = Vector2(0, 36)
				bid_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bid_button.disabled = chosen < minimum
				bid_button.add_theme_color_override("font_color", Color("#EAF5F7"))
				bid_button.add_theme_color_override("font_disabled_color", Color("#60717D"))
				bid_button.add_theme_stylebox_override("normal", _create_box_style(Color("#172A39"), Color("#31586A"), 8, 1))
				bid_button.add_theme_stylebox_override("hover", _create_box_style(Color("#17414B"), Color("#00D9E8"), 8, 2))
				bid_button.add_theme_stylebox_override("pressed", _create_box_style(Color("#07515A"), Color("#00E5FF"), 8, 2))
				bid_button.add_theme_stylebox_override("disabled", _create_box_style(Color("#1B2731"), Color("#34414A"), 8, 1))
				_bid_buttons_grid.add_child(bid_button)

			# Exactly one Pass button is created for the local bidding turn.
			var pass_row := CenterContainer.new()
			pass_row.name = "SinglePassRow"
			pass_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var pass_button := _make_action_button("PASS", func() -> void:
				_center_bid_box.visible = false
				MultiplayerManager.submit_local_action({"type": "PASS_BID"})
			)
			pass_button.custom_minimum_size = Vector2(160, 38)
			pass_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pass_button.add_theme_color_override("font_color", Color("#19222B"))
			pass_button.add_theme_stylebox_override("normal", _create_box_style(Color("#E6B84F"), Color("#F4D178"), 8, 1))
			pass_button.add_theme_stylebox_override("hover", _create_box_style(Color("#F2CC70"), Color("#FFF0B8"), 8, 2))
			pass_button.add_theme_stylebox_override("pressed", _create_box_style(Color("#D5A43B"), Color("#FFF0B8"), 8, 2))
			pass_row.add_child(pass_button)
			_bid_vbox.add_child(pass_row)

		GameState.Phase.SET_HIDDEN_TRUMP:
			_action_panel.visible = true
			_action_panel.anchor_left = 0.5
			_action_panel.anchor_right = 0.5
			_action_panel.anchor_top = 0.58
			_action_panel.anchor_bottom = 0.58
			_action_panel.offset_left = -150
			_action_panel.offset_right = 150
			_action_panel.offset_top = -54
			_action_panel.offset_bottom = 54
			var title := Label.new()
			title.text = "CHOOSE TRUMP"
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 16)
			title.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN)
			_action_content.add_child(title)
			
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 10)
			_action_content.add_child(row)
			for suit_id in range(4):
				var button := Button.new()
				var symbol: String = str(CardDefs.SUIT_SYMBOLS[suit_id])
				var ink: Color = ThemePalette.SUIT_CRIMSON if suit_id in [CardDefs.Suit.HEARTS, CardDefs.Suit.DIAMONDS] else ThemePalette.ACCENT_CYAN
				button.text = symbol
				button.custom_minimum_size = Vector2(60, 56)
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.add_theme_font_size_override("font_size", 34)
				button.add_theme_color_override("font_color", ink)
				button.add_theme_stylebox_override("normal", _create_box_style(Color("#132738"), Color("#26556C"), 10, 1))
				button.add_theme_stylebox_override("hover", _create_box_style(Color("#1A3E52"), Color("#00D9E8"), 10, 2))
				button.add_theme_stylebox_override("pressed", _create_box_style(Color("#0E4D5C"), Color("#00FFFF"), 10, 2))
				button.pressed.connect(func() -> void:
					AudioManager.play_sfx("ui_click", 0.02, 0.75)
					MultiplayerManager.submit_local_action({"type": "SET_TRUMP", "suit": suit_id})
				)
				row.add_child(button)

		GameState.Phase.DOUBLE_DECISION:
			_action_panel.visible = true
			_action_panel.anchor_left = 0.5
			_action_panel.anchor_right = 0.5
			_action_panel.anchor_top = 0.58
			_action_panel.anchor_bottom = 0.58
			_action_panel.offset_left = -120
			_action_panel.offset_right = 120
			_action_panel.offset_top = -46
			_action_panel.offset_bottom = 46
			var title := Label.new()
			title.text = "DOUBLE?"
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 16)
			title.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN)
			_action_content.add_child(title)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var btn_double := _make_action_button("2×", func() -> void: MultiplayerManager.submit_local_action({"type": "CALL_DOUBLE", "double": true}))
			btn_double.add_theme_color_override("font_color", Color("#17222B"))
			btn_double.add_theme_stylebox_override("normal", _create_box_style(Color("#E6B84F"), Color("#F4D178"), 8, 1))
			btn_double.add_theme_stylebox_override("hover", _create_box_style(Color("#F2CC70"), Color("#FFF0B8"), 8, 2))
			btn_double.add_theme_stylebox_override("pressed", _create_box_style(Color("#D5A43B"), Color("#FFF0B8"), 8, 2))
			row.add_child(btn_double)
			var btn_hold := _make_action_button("HOLD", func() -> void: MultiplayerManager.submit_local_action({"type": "CALL_DOUBLE", "double": false}))
			row.add_child(btn_hold)
			_action_content.add_child(row)
			
		GameState.Phase.REDOUBLE_DECISION:
			_action_panel.visible = true
			_action_panel.anchor_left = 0.5
			_action_panel.anchor_right = 0.5
			_action_panel.anchor_top = 0.58
			_action_panel.anchor_bottom = 0.58
			_action_panel.offset_left = -120
			_action_panel.offset_right = 120
			_action_panel.offset_top = -46
			_action_panel.offset_bottom = 46
			var title := Label.new()
			title.text = "REDOUBLE?"
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 16)
			title.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN)
			_action_content.add_child(title)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var btn_redouble := _make_action_button("4×", func() -> void: MultiplayerManager.submit_local_action({"type": "CALL_REDOUBLE", "redouble": true}))
			btn_redouble.add_theme_color_override("font_color", Color("#FFFFFF"))
			btn_redouble.add_theme_stylebox_override("normal", _create_box_style(Color("#C62828"), Color("#EF5350"), 8, 1))
			btn_redouble.add_theme_stylebox_override("hover", _create_box_style(Color("#E53935"), Color("#FF8A80"), 8, 2))
			btn_redouble.add_theme_stylebox_override("pressed", _create_box_style(Color("#B71C1C"), Color("#FF8A80"), 8, 2))
			row.add_child(btn_redouble)
			var btn_hold := _make_action_button("HOLD", func() -> void: MultiplayerManager.submit_local_action({"type": "CALL_REDOUBLE", "redouble": false}))
			row.add_child(btn_hold)
			_action_content.add_child(row)
			
		GameState.Phase.TRICK_PLAY:
			# Trump reveal is automatic when a player cannot follow suit.
			# TRAM is shown only when the authoritative RulesEngine proves it.
			if bool(view.get("tram_available", false)):
				var tram_button := _make_action_button("TRAM  ·  THE REST ARE MINE", func() -> void:
					MultiplayerManager.submit_local_action({"type": "TRAM"})
				)
				tram_button.custom_minimum_size = Vector2(224, 48)
				tram_button.add_theme_color_override("font_color", Color("#19222B"))
				tram_button.add_theme_stylebox_override("normal", _create_box_style(Color("#E6B84F"), Color("#F4D178"), 10, 1))
				tram_button.add_theme_stylebox_override("hover", _create_box_style(Color("#F2CC70"), Color("#FFF0B8"), 10, 2))
				_action_content.add_child(tram_button)
				_action_panel.visible = true
				_action_panel.anchor_left = 0.5
				_action_panel.anchor_right = 0.5
				_action_panel.anchor_top = 0.73
				_action_panel.anchor_bottom = 0.73
				_action_panel.offset_left = -124
				_action_panel.offset_right = 124
				_action_panel.offset_top = -32
				_action_panel.offset_bottom = 32

		GameState.Phase.PAIR_DECISION:
			var pair_title := Label.new()
			pair_title.text = "ROYAL PAIR?"
			pair_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pair_title.add_theme_font_size_override("font_size", 16)
			pair_title.add_theme_color_override("font_color", ThemePalette.ACCENT_CYAN)
			_action_content.add_child(pair_title)

			var pair_row := HBoxContainer.new()
			pair_row.add_theme_constant_override("separation", 10)
			var btn_declare := _make_action_button("DECLARE +4", func() -> void:
				MultiplayerManager.submit_local_action({"type": "DECLARE_PAIR"})
			)
			btn_declare.add_theme_color_override("font_color", Color("#17222B"))
			btn_declare.add_theme_stylebox_override("normal", _create_box_style(Color("#E6B84F"), Color("#F4D178"), 8, 1))
			btn_declare.add_theme_stylebox_override("hover", _create_box_style(Color("#F2CC70"), Color("#FFF0B8"), 8, 2))
			btn_declare.add_theme_stylebox_override("pressed", _create_box_style(Color("#D5A43B"), Color("#FFF0B8"), 8, 2))
			pair_row.add_child(btn_declare)
			var btn_pass := _make_action_button("PASS", func() -> void:
				MultiplayerManager.submit_local_action({"type": "PASS_PAIR"})
			)
			pair_row.add_child(btn_pass)
			_action_content.add_child(pair_row)
			_action_panel.visible = true
			_action_panel.anchor_left = 0.5
			_action_panel.anchor_right = 0.5
			_action_panel.anchor_top = 0.73
			_action_panel.anchor_bottom = 0.73
			_action_panel.offset_left = -124
			_action_panel.offset_right = 124
			_action_panel.offset_top = -42
			_action_panel.offset_bottom = 42

func _make_action_button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(80, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("#EAF5F7"))
	button.add_theme_color_override("font_hover_color", Color("#00FFFF"))
	button.add_theme_color_override("font_pressed_color", Color("#FFFFFF"))
	button.add_theme_stylebox_override("normal", _create_box_style(Color("#132738"), Color("#26556C"), 8, 1))
	button.add_theme_stylebox_override("hover", _create_box_style(Color("#1A3E52"), Color("#00D9E8"), 8, 2))
	button.add_theme_stylebox_override("pressed", _create_box_style(Color("#0E4D5C"), Color("#00FFFF"), 8, 2))
	button.add_theme_stylebox_override("disabled", _create_box_style(Color("#141D26"), Color("#28343E"), 8, 1))
	button.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", 0.02, 0.75)
		callback.call()
	)
	return button

func _on_hint_pressed() -> void:
	AudioManager.play_sfx("ui_click", 0.02, 0.75)
	if _last_view.is_empty():
		return

	_clear_hint_presentation()
	var phase: int = int(_last_view.get("phase", -1))
	var viewer_seat: int = int(_last_view.get("viewer_seat", -1))
	var turn_seat: int = int(_last_view.get("current_turn_seat", -2))
	if _deal_animation_running or bool(_last_view.get("deal_animation_pending", false)):
		_show_hint_popup("The cards are still being dealt. Your hint will be ready when the deal finishes.")
		return
	if viewer_seat < 0 or viewer_seat != turn_seat:
		_show_hint_popup("The coach will help when it is your turn.")
		return

	var action: Dictionary = AIController.choose_action(_last_view, AIController.Difficulty.MASTER)
	var kind := str(action.get("type", "NONE"))
	var hint_text := "No recommendation is available for this moment."

	match kind:
		"PLAY_CARD":
			var recommended_card: int = int(action.get("card", -1))
			var hand: Array[int] = []
			hand.assign(_last_view.get("my_hand", []))
			var legal_cards: Array[int] = AIController._get_legal_cards_from_view(_last_view, hand)
			if recommended_card >= 0 and hand.has(recommended_card) and legal_cards.has(recommended_card):
				_hint_recommended_card_id = recommended_card
				hint_text = "Try playing %s. Its glowing edge marks the suggested card." % CardDefs.format_card(recommended_card)
				_refresh_hint_card_glow()
			else:
				hint_text = "Choose one of the cards that follows the current lead."
		"BID":
			hint_text = "Suggested bid: %d." % int(action.get("amount", 0))
		"PASS_BID":
			hint_text = "The coach recommends passing this bid."
		"SET_TRUMP":
			var suit_name: String = str(CardDefs.SUIT_NAMES.get(int(action.get("suit", -1)), "the selected suit"))
			hint_text = "Choose %s as trump." % suit_name
		"CALL_DOUBLE":
			hint_text = "The coach recommends doubling." if bool(action.get("double", false)) else "Hold. The coach does not recommend doubling."
		"CALL_REDOUBLE":
			hint_text = "The coach recommends redoubling." if bool(action.get("redouble", false)) else "Hold. The coach does not recommend redoubling."
		"DECLARE_PAIR":
			hint_text = "Declare the pair now."
		"TRAM":
			hint_text = "TRAM is available: your side is guaranteed to win every remaining trick."
		_:
			hint_text = "There is no move to recommend in the current phase."

	_show_hint_popup(hint_text)


func _refresh_hint_card_glow() -> void:
	if not is_instance_valid(_hand_fan):
		return
	for card_node in _hand_fan.get_cards():
		if not is_instance_valid(card_node) or not card_node.has_method("set_hint_highlight"):
			continue
		var card_id: int = int(card_node.get_meta("domain_card_id", -1))
		card_node.set_hint_highlight(_hint_recommended_card_id >= 0 and card_id == _hint_recommended_card_id)


func _clear_hint_card_glow() -> void:
	if not is_instance_valid(_hand_fan):
		return
	for card_node in _hand_fan.get_cards():
		if is_instance_valid(card_node) and card_node.has_method("set_hint_highlight"):
			card_node.set_hint_highlight(false)


func _show_hint_popup(message: String) -> void:
	if not is_instance_valid(_hint_popup):
		return
	if _hint_popup_tween != null and _hint_popup_tween.is_valid():
		_hint_popup_tween.kill()

	_hint_label.text = message
	_hint_phase = int(_last_view.get("phase", -1))
	_hint_popup.visible = true
	_hint_popup.modulate = Color.WHITE
	for dot in _hint_thought_dots:
		dot.visible = true
		dot.modulate = Color.WHITE

	_hint_popup_generation += 1
	var generation: int = _hint_popup_generation
	_hint_popup_tween = create_tween()
	_hint_popup_tween.tween_interval(7.0)
	_hint_popup_tween.tween_property(_hint_popup, "modulate:a", 0.0, 0.35)
	for dot in _hint_thought_dots:
		_hint_popup_tween.parallel().tween_property(dot, "modulate:a", 0.0, 0.35)
	_hint_popup_tween.tween_callback(func() -> void:
		if generation != _hint_popup_generation:
			return
		_hint_popup.visible = false
		for dot in _hint_thought_dots:
			dot.visible = false
		_hint_recommended_card_id = -1
		_clear_hint_card_glow()
	)


func _clear_hint_presentation() -> void:
	_hint_popup_generation += 1
	if _hint_popup_tween != null and _hint_popup_tween.is_valid():
		_hint_popup_tween.kill()
	if is_instance_valid(_hint_popup):
		_hint_popup.visible = false
		_hint_popup.modulate = Color.WHITE
	for dot in _hint_thought_dots:
		dot.visible = false
		dot.modulate = Color.WHITE
	_hint_recommended_card_id = -1
	_hint_phase = -1
	_clear_hint_card_glow()


func _on_action_rejected(error_code: String) -> void:
	_show_hint_popup("That move was not accepted. Check the current rules and try a legal action.")
	AudioManager.play_sfx("error")
	HapticsManager.error_buzz()

	# If an auction action was rejected, restore the controls for the still-active
	# local turn. Accepted bids/passes remain hidden until PlayerView assigns
	# the next turn to this seat.
	if not _last_view.is_empty():
		var phase: int = int(_last_view.get("phase", -1))
		var viewer: int = int(_last_view.get("viewer_seat", -1))
		var active: int = int(_last_view.get("current_turn_seat", -2))
		if phase == GameState.Phase.BIDDING and viewer == active:
			_center_bid_box.visible = true
			_rebuild_phase_controls(_last_view, phase, true)

func _on_host_migration_completed(new_host_seat: int) -> void:
	_status_banner.text = "HOST CHANGED"

func _refresh_existing_match() -> void:
	if MultiplayerManager.authoritative_state != null:
		MultiplayerManager._broadcast_state_from_host()


# Pass 20 notes:
# - Card back texture is assigned only after card.tscn enters the scene tree,
#   because Card.gd's CardSprite reference is @onready.
# - SCORE and seat hand-status plaques show team_card_points (card point values),
#   never team_tricks_won. A completed trick can award 0, 1, 2, 3, ... points.


# Pass 21 UI/input fixes:
# - Bidding panel is visible only when phase=BIDDING and local viewer owns the turn.
# - Pass row is detached immediately before queue_free, preventing duplicate actions.
# - Bid panel uses the app's midnight/cyan/gold styling and exactly one gold PASS.
# - Local CardFan interaction is explicitly enabled; remote fans remain display-only.
# - Card click legality is recalculated from the newest PlayerView.

# Pass 21.1: rejected auction actions restore the bidding panel for the same active local turn.


# Pass 22 rules/UI alignment:
# - Top-right SCORE displays cumulative match_game_points (+/-1, +/-2, +/-4),
#   while player plaques retain current-hand card points (J=3, 9=2, A/10=1).
# - First and second batches are physically allocated round-robin clockwise
#   starting at the dealer's left, and the UI animates in that same order.
# - Dealer D badge follows sanitized PlayerView.dealer_seat every hand.
# - Local hand is grouped by suit, then ranked high-to-low within each suit.
# - Off-suit cards are dimmed only when a lead suit or forced revealed trump
#   is actually mandatory; void hands and off-turn hands are not greyed.
