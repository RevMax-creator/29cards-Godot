class_name CardView
extends Control

signal card_selected(card_id: int)

var card_id: int = -1
var is_playable: bool = true
var is_face_down: bool = false

func setup_card(id: int, playable: bool = true, face_down: bool = false) -> void:
	card_id = id
	is_playable = playable
	is_face_down = face_down
	custom_minimum_size = Vector2(148, 216)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not is_playable or is_face_down:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_animate_tap()
		card_selected.emit(card_id)

func _animate_tap() -> void:
	var tw: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(16)

	if is_face_down or card_id < 0:
		style.bg_color = ThemePalette.SURFACE_CHARCOAL
		style.border_color = ThemePalette.ACCENT_WARM_GOLD
		style.set_border_width_all(2)
		draw_style_box(style, rect)
		return

	style.bg_color = ThemePalette.CARD_IVORY
	style.border_color = ThemePalette.ACCENT_CYAN if is_playable else ThemePalette.TEXT_MUTED
	style.set_border_width_all(3 if is_playable else 1)
	draw_style_box(style, rect)

	var suit: int = CardDefs.get_suit(card_id)
	var rank: int = CardDefs.get_rank(card_id)
	var pts: int = CardDefs.get_points(card_id)
	var is_red: bool = (suit == CardDefs.Suit.HEARTS or suit == CardDefs.Suit.DIAMONDS)
	var ink_color: Color = ThemePalette.SUIT_CRIMSON if is_red else ThemePalette.SUIT_OBSIDIAN

	var font: Font = ThemeDB.fallback_font
	var rank_str: String = CardDefs.RANK_LABELS[rank]
	var suit_str: String = CardDefs.SUIT_SYMBOLS[suit]

	# Top-left index
	draw_string(font, Vector2(16, 42), rank_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink_color)
	draw_string(font, Vector2(16, 78), suit_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, ink_color)

	# Center pip
	draw_string(font, Vector2(size.x * 0.34, size.y * 0.62), suit_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 68, ink_color)

	# Subtle Warm Gold point badge for scoring cards (J=3, 9=2, A=1, 10=1)
	if pts > 0:
		draw_string(
			font,
			Vector2(size.x - 48, 36),
			"+%d" % pts,
			HORIZONTAL_ALIGNMENT_RIGHT,
			-1,
			20,
			ThemePalette.ACCENT_WARM_GOLD.darkened(0.25)
		)

	if not is_playable:
		var dim_style := StyleBoxFlat.new()
		dim_style.bg_color = ThemePalette.CARD_DISABLED_OVERLAY
		dim_style.set_corner_radius_all(16)
		draw_style_box(dim_style, rect)