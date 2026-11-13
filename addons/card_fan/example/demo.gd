extends Control
## 4-Player CardFan Table (Dynamic Code Generation)

@onready var player_bottom: Control = $CardSet

func _ready():
	$VBoxContainer/Title.text = "🃏 4-Player Mobile Table"
	$VBoxContainer/Hint.text = "Generated entirely via code"

	# Generate opponents after the initial UI layout has settled
	call_deferred("_generate_opponents")

func _generate_opponents():
	var screen_size = get_viewport_rect().size
	var center = screen_size / 2.0
	
	# Define how far from the center the cards should be placed
	var vertical_offset = screen_size.y / 2.5 
	var horizontal_offset = screen_size.x / 2.5 
	
	# Clone the bottom player to create the opponents
	create_opponent("Top Player", 180, Vector2(center.x, center.y - vertical_offset))
	create_opponent("Left Player", 90, Vector2(center.x - horizontal_offset, center.y))
	create_opponent("Right Player", -90, Vector2(center.x + horizontal_offset, center.y))

	# Setup the bottom player last
	setup_player(player_bottom, "Bottom Player")
	player_bottom.joystick_enabled = true

func create_opponent(player_name: String, rot_degrees: float, target_pos: Vector2):
	var new_player = player_bottom.duplicate()
	add_child(new_player)
	
	# Force a specific size for the bounding box
	var fixed_size = Vector2(700, 300)
	
	# Disconnect anchors so the size is strictly respected
	new_player.anchor_left = 0
	new_player.anchor_right = 0
	new_player.anchor_top = 0
	new_player.anchor_bottom = 0
	
	# Apply size and set pivot to the exact center
	new_player.size = fixed_size
	new_player.pivot_offset = fixed_size / 2.0
	
	# Rotate and position relative to the center pivot
	new_player.rotation_degrees = rot_degrees
	new_player.position = target_pos - (fixed_size / 2.0)
	
	# Disable the joystick for opponents
	new_player.joystick_enabled = false
	new_player.show_debug_buttons = false
	
	# Connect signals
	setup_player(new_player, player_name)

func setup_player(card_set_node: Control, player_name: String) -> void:
	if not card_set_node: return
	card_set_node.debug_logging = true
	card_set_node.card_played.connect(_on_card_played.bind(player_name))
	card_set_node.card_clicked.connect(_on_card_clicked.bind(player_name))

func _on_card_played(card, player_name: String):
	var card_name = card.get_card_name() if card.has_method("get_card_name") else str(card)
	$VBoxContainer/Status.text = player_name + " played: " + card_name

func _on_card_clicked(card, player_name: String):
	var card_name = card.get_card_name() if card.has_method("get_card_name") else str(card)
	$VBoxContainer/Status.text = player_name + " clicked: " + card_name
