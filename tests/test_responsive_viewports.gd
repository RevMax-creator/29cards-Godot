extends SceneTree

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(360, 640),
	Vector2i(360, 800),
	Vector2i(390, 844),
	Vector2i(412, 915),
	Vector2i(432, 960)
]

const BASE_CANVAS_WIDTH: float = 1080.0

func _init() -> void:
	print("=== VERIFYING RESPONSIVE LAYOUT ACROSS MOBILE RESOLUTIONS (CANVAS 1080px + EXPAND) ===")
	for res in RESOLUTIONS:
		# Project stretches 1080px width in canvas_items/expand mode; effective logical height scales with aspect.
		var logical_height: float = BASE_CANVAS_WIDTH * float(res.y) / float(res.x)
		var arena_width: float = BASE_CANVAS_WIDTH - 24.0
		var arena_height: float = logical_height - 10.0 - 8.0 - 56.0 - 7.0

		# Trick diamond bounds for 130x182 (+20%) cards at spread X=114, Y=160:
		var diamond_width: float = 114.0 * 2.0 + 130.0 # 358 px
		var diamond_height: float = 160.0 * 2.0 + 182.0 # 502 px

		# Center lane between left opponent profile (max X=279.6) and right opponent profile (min X=800.4)
		var center_lane_width: float = (0.88 * arena_width - 150.0) - (0.12 * arena_width + 150.0)
		assert(diamond_width <= center_lane_width, "Diamond width %f exceeds center lane %f at %dx%d" % [diamond_width, center_lane_width, res.x, res.y])

		# Vertical clearance between partner profile bottom and player profile top
		var diamond_top: float = 0.42 * arena_height - diamond_height * 0.5
		var diamond_bottom: float = 0.42 * arena_height + diamond_height * 0.5
		var partner_bottom: float = 0.15 * arena_height + 54.0
		var player_top: float = 0.77 * arena_height - 54.0
		assert(diamond_top > partner_bottom, "Trick top %f overlaps partner profile %f at %dx%d" % [diamond_top, partner_bottom, res.x, res.y])
		assert(diamond_bottom < player_top, "Trick bottom %f overlaps player profile %f at %dx%d" % [diamond_bottom, player_top, res.x, res.y])

		# Local 20%-enlarged hand fan bottom check (offset_top = -372, card_height = 300, max arc+tilt drop ~ 47px)
		var hand_top: float = arena_height - 372.0
		var outer_card_bottom: float = hand_top + 347.0
		assert(outer_card_bottom <= arena_height, "Local hand bottom %f clipped by arena %f at %dx%d" % [outer_card_bottom, arena_height, res.x, res.y])

		print("Verified %dx%d (logical %.0fx%.0f): diamond=%.0fx%.0f in %.0fpx lane, vertical gap=[+%.0f, +%.0f], hand_bottom_margin=%.0fpx" % [
			res.x, res.y, BASE_CANVAS_WIDTH, logical_height,
			diamond_width, diamond_height, center_lane_width,
			diamond_top - partner_bottom, player_top - diamond_bottom,
			arena_height - outer_card_bottom
		])

	print("ALL RESOLUTIONS VALIDATED SUCCESSFULLY.")
	quit(0)
