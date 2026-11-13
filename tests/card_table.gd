extends Control
class_name CardTable
## Native 4-Player Table Manager API

# Preload the original plugin scene
const CARD_SET_SCENE = preload("res://addons/card_fan/src/card_set.tscn")

var players: Dictionary = {}

# Custom signals for the table
signal player_played_card(player_id: String, card: Control)
signal player_clicked_card(player_id: String, card: Control)

func _ready():
	# Make the table fill the screen
	set_anchors_preset(PRESET_FULL_RECT)
	_generate_native_layout()
	test_deal_cards() # Call the test function

func _generate_native_layout():
	var screen_size = get_viewport_rect().size
	var center = screen_size / 2.0
	
	# Calculate safe mobile margins
	var v_offset = screen_size.y / 2.5
	var h_offset = screen_size.x / 2.5
	
	# Spawn all 4 players natively through code
	players["bottom"] = _spawn_hand("bottom", 0, Vector2(center.x, center.y + v_offset), true)
	players["top"] = _spawn_hand("top", 180, Vector2(center.x, center.y - v_offset), false)
	players["left"] = _spawn_hand("left", 90, Vector2(center.x - h_offset, center.y), false)
	players["right"] = _spawn_hand("right", -90, Vector2(center.x + h_offset, center.y), false)

func _spawn_hand(player_id: String, rot_deg: float, pos: Vector2, is_local_player: bool) -> Control:
	var hand = CARD_SET_SCENE.instantiate()
	add_child(hand)
	
	# Force a strict local bounding box so the plugin math works perfectly
	var box_size = Vector2(700, 300)
	hand.set_anchors_preset(PRESET_TOP_LEFT)
	hand.size = box_size
	hand.pivot_offset = box_size / 2.0
	
	# Apply transform
	hand.rotation_degrees = rot_deg
	hand.position = pos - (box_size / 2.0)
	
	# Configure UI & Plugin features
	hand.joystick_enabled = is_local_player
	hand.show_debug_buttons = is_local_player
	hand.debug_logging = true
	
	# Clean up opponent UI text
	if not is_local_player:
		for child in hand.get_children():
			if child is Button or child is Label or child is RichTextLabel:
				child.hide()
	
	# Route plugin signals to the Table Manager
	hand.card_played.connect(func(card): emit_signal("player_played_card", player_id, card))
	hand.card_clicked.connect(func(card): emit_signal("player_clicked_card", player_id, card))
	
	return hand

# --- PUBLIC API FOR YOUR GAME ---

## Add a card to a specific player's hand natively
func give_card_to(player_id: String, suit: String, rank: int):
	if players.has(player_id):
		players[player_id].add_card(suit, rank)

func test_deal_cards():
	# Deal 3 cards to each player
	for i in range(3):
		give_card_to("bottom", "spade", i + 1)
		give_card_to("top", "heart", i + 1)
		give_card_to("left", "diamond", i + 1)
		give_card_to("right", "club", i + 1)
		
		
