class_name ThemePalette
extends RefCounted

const BG_MIDNIGHT_NAVY := Color("#0A0E17")
const SURFACE_CHARCOAL := Color("#121824")
const TABLE_FELT_EMERALD := Color("#0A3D2E")
const TABLE_BORDER_EMERALD := Color("#136F53")
const ACCENT_CYAN := Color("#00E5FF")
const ACCENT_WARM_GOLD := Color("#D4AF37")
const CARD_IVORY := Color("#F7F9FC")
const CARD_DISABLED_OVERLAY := Color(0.05, 0.07, 0.11, 0.58)
const SUIT_CRIMSON := Color("#D92B4B")
const SUIT_OBSIDIAN := Color("#141923")
const TEXT_PRIMARY := Color("#F0F4F8")
const TEXT_MUTED := Color("#8A99AD")
const DANGER_ROSE := Color("#FF4D6D")

static func create_panel_style(bg: Color, border: Color, corner_radius: int = 20, border_width: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(corner_radius)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	return box

static func create_button_style(bg: Color, border: Color, corner_radius: int = 18) -> StyleBoxFlat:
	var box := create_panel_style(bg, border, corner_radius, 1)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 8
	return box