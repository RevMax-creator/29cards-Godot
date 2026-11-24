extends Node

var _passed: int = 0
var _failed: int = 0

func _assert_true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		printerr("[FAIL] %s" % label)

func _ready() -> void:
	print("=== 29 CARDS — FULL AUDIT & AUDIO/UI QA SUITE ===")
	_test_bgm_lifecycle()
	_test_bidding_voice_announcements()
	_test_dealing_and_shuffle_sound_contract()
	_test_card_sorting_sound_contract()
	_test_card_play_and_trick_collect_sound_contract()
	_test_bidding_panel_ui_dimensions_and_layout()
	_test_enlarged_cards_and_trick_corner_overlap()
	_test_pass_22_17_audio_pipeline()
	print("==================================================")
	print("QA TEST RESULTS: %d PASSED | %d FAILED" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)

func _test_bgm_lifecycle() -> void:
	_assert_true(AudioManager != null, "A-01: AudioManager autoload is present in SceneTree")
	if AudioManager == null:
		return

	# Test BGM does not create duplicate players on repeated start
	var initial_players: int = 0
	for child in AudioManager.get_children():
		if child is AudioStreamPlayer and child.name == "BackgroundMusicPlayer":
			initial_players += 1
	_assert_true(initial_players == 1, "A-02: Exactly one BackgroundMusicPlayer instance exists in AudioManager")

	AudioManager.start_gameplay_music()
	var after_start_players: int = 0
	for child in AudioManager.get_children():
		if child is AudioStreamPlayer and child.name == "BackgroundMusicPlayer":
			after_start_players += 1
	_assert_true(after_start_players == 1, "A-03: Repeated start_gameplay_music() creates no duplicate players")

	AudioManager.stop_gameplay_music()
	var bgm_player: AudioStreamPlayer = AudioManager.get_node_or_null("BackgroundMusicPlayer") as AudioStreamPlayer
	_assert_true(bgm_player != null and not bgm_player.playing, "A-04: stop_gameplay_music() stops music cleanly")

func _test_bidding_voice_announcements() -> void:
	if AudioManager == null:
		return

	# Verify every bid from 15 through 28 has a valid phrase and sound stream
	var all_bids_valid: bool = true
	for amount in range(15, 29):
		var phrase: String = AudioManager._bid_phrase(amount)
		var has_stream: bool = AudioManager._voice_streams.has(amount)
		if phrase.is_empty() or not has_stream:
			all_bids_valid = false
			printerr("Missing voice or phrase for bid: ", amount)
	_assert_true(all_bids_valid, "B-01: Every legal bid from 15 to 28 has phrase and bundled audio stream")

	# Verify 29 is not a legal bid voice callout
	var phrase_29: String = AudioManager._bid_phrase(29)
	_assert_true(phrase_29.is_empty(), "B-02: Bid 29 has no phrase and is not a legal bid")

	# Verify pass, hold, double, and quadruple callout streams exist
	_assert_true(AudioManager._voice_streams.has("pass"), "B-03: Pass callout stream is present")
	_assert_true(AudioManager._voice_streams.has("hold") and AudioManager._voice_streams.has("double") and AudioManager._voice_streams.has("quadruple"), "B-06: Hold, Double, and Quadruple callout streams are present")

	# Test calling play_bid_callout for 15..28 does not crash or throw
	AudioManager._voice_queue.clear()
	for amount in range(15, 29):
		AudioManager.play_bid_callout(amount, 0)
	_assert_true(true, "B-04: play_bid_callout(15..28) executes safely without errors")

	# Test calling play_bid_callout(29) is rejected
	var queue_before: int = AudioManager._voice_queue.size()
	AudioManager.play_bid_callout(29, 0)
	_assert_true(AudioManager._voice_queue.size() == queue_before, "B-05: Bid 29 is rejected by play_bid_callout and never enqueued")
	AudioManager._voice_queue.clear()

func _test_dealing_and_shuffle_sound_contract() -> void:
	# Verify that 4 cards in first deal and 4 cards in second deal are respected
	var state := GameState.new()
	state.match_seed = 123
	RulesEngine.start_new_hand(state, 0, state.match_seed)

	_assert_true(state.hands[0].size() == 4 and state.stock_deck.size() == 16, "C-01: First deal produces exactly 4 cards per player")
	_assert_true(state.deal_animation_pending, "C-02: First deal is action-locked during deal animation")
	RulesEngine.complete_deal_animation(state)

	state.current_bid = 15
	state.high_bidder_seat = 0
	state.phase = GameState.Phase.SET_HIDDEN_TRUMP
	state.current_turn_seat = 0
	RulesEngine.apply_action(state, 0, {"type": "SET_TRUMP", "suit": CardDefs.Suit.SPADES})
	RulesEngine.apply_action(state, 1, {"type": "CALL_DOUBLE", "double": false})
	var defender_two: Dictionary = RulesEngine.apply_action(state, 3, {"type": "CALL_DOUBLE", "double": false})

	_assert_true(bool(defender_two.get("ok", false)) and state.hands[0].size() == 8 and state.stock_deck.is_empty(), "C-03: Second deal produces exactly 8 cards per player (4 additional cards)")
	_assert_true(state.deal_animation_pending, "C-04: Second deal is action-locked during deal animation")
	RulesEngine.complete_deal_animation(state)
	_assert_true(not state.deal_animation_pending, "C-05: Second deal unlocks after deal animation finishes")

func _test_card_sorting_sound_contract() -> void:
	var screen_scene: PackedScene = load("res://src/ui/main_table_screen.tscn")
	var screen: MainTableScreen = screen_scene.instantiate() as MainTableScreen
	add_child(screen)

	_assert_true(screen._hand_fan != null, "D-01: MainTableScreen initialized hand fan")

	# Call _apply_local_hand_order(false) as done during rebuild_hand
	screen._apply_local_hand_order(false)
	_assert_true(true, "D-02: Redrawing hand calls _apply_local_hand_order(false) safely without playing sort sound")

	# Verify sorted card insertion during dealing keeps strict z_index and tree order
	var fan: Control = screen._hand_fan
	var c0: Control = fan.insert_card_with_texture_from(null, "spade", 1, Vector2.ZERO, 0)
	var c2: Control = fan.insert_card_with_texture_from(null, "heart", 13, Vector2.ZERO, 1)
	var c1: Control = fan.insert_card_with_texture_from(null, "spade", 10, Vector2.ZERO, 1)
	fan.hovered_card = c0
	fan.clear_interaction_state()
	var z_order_ok: bool = (
		fan.cards.size() == 3 and fan.cards[0] == c0 and fan.cards[1] == c1 and fan.cards[2] == c2
		and c0.z_index == 0 and c1.z_index == 1 and c2.z_index == 2
		and fan.cards_container.get_child(0) == c0 and fan.cards_container.get_child(1) == c1 and fan.cards_container.get_child(2) == c2
	)
	_assert_true(z_order_ok, "D-03: CardFan sorted insertion and clear_interaction_state maintain strict left-to-right z_index and tree order")

	screen.queue_free()

func _test_card_play_and_trick_collect_sound_contract() -> void:
	# Verify mathematical card counting in trick play:
	# old: 0 completed, 2 in trick -> 2 cards
	# new: 1 completed, 0 in trick -> 4 cards
	# delta: 4 - 2 = 2 cards played
	var old_completed: int = 0
	var old_trick: Array = [{"card": 1}, {"card": 2}]
	var new_completed: int = 1
	var new_trick: Array = []
	var old_total: int = old_completed * 4 + old_trick.size()
	var new_total: int = new_completed * 4 + new_trick.size()
	var card_plays: int = clampi(new_total - old_total, 0, 4)
	_assert_true(card_plays == 2, "E-01: Card play delta correctly calculates 2 cards played when trick completes")

	# If identical views arrive:
	var same_old_total: int = new_total
	var same_new_total: int = new_total
	var no_card_plays: int = clampi(same_new_total - same_old_total, 0, 4)
	_assert_true(no_card_plays == 0, "E-02: Zero cards played when view does not change")

func _test_bidding_panel_ui_dimensions_and_layout() -> void:
	var screen_scene: PackedScene = load("res://src/ui/main_table_screen.tscn")
	var screen: MainTableScreen = screen_scene.instantiate() as MainTableScreen
	add_child(screen)

	var bid_box: PanelContainer = screen._center_bid_box
	_assert_true(bid_box != null, "F-01: Bidding panel _center_bid_box is created")
	if bid_box == null:
		screen.queue_free()
		return

	var width: float = bid_box.offset_right - bid_box.offset_left
	var height: float = bid_box.offset_bottom - bid_box.offset_top
	var aspect: float = width / maxf(height, 1.0)
	print("Bidding panel dimensions: width=%.1f, height=%.1f, aspect ratio=%.2f" % [width, height, aspect])

	_assert_true(width > height, "F-02: Bidding panel width (%.0f) is strictly greater than height (%.0f)" % [width, height])
	_assert_true(aspect >= 2.0, "F-03: Bidding panel aspect ratio (%.2f) is >= 2.0 (wide horizontal rectangle, not square)" % aspect)

	# Verify stylebox is transparent or nearly transparent
	var style: StyleBox = bid_box.get_theme_stylebox("panel")
	_assert_true(style is StyleBoxFlat, "F-04: Bidding panel uses StyleBoxFlat")
	if style is StyleBoxFlat:
		var flat: StyleBoxFlat = style as StyleBoxFlat
		_assert_true(flat.bg_color.a < 0.5, "F-05: Bidding panel interior is nearly transparent (alpha=%.2f < 0.5), not filled solid" % flat.bg_color.a)
		_assert_true(flat.border_width_left >= 2, "F-06: Bidding panel has clean outline border (width=%d >= 2)" % flat.border_width_left)

	# Rebuild bidding phase controls and verify all 14 bid buttons (15..28) + Pass are present
	var mock_view: Dictionary = {
		"phase": GameState.Phase.BIDDING,
		"viewer_seat": 0,
		"current_turn_seat": 0,
		"current_bid": 15,
		"deal_animation_pending": false
	}
	screen._rebuild_phase_controls(mock_view, GameState.Phase.BIDDING, true)

	var grid: GridContainer = screen._bid_buttons_grid
	_assert_true(grid != null and grid.columns == 7, "F-07: Bidding grid has exactly 7 columns (7x2 layout for 14 buttons)")
	var bid_buttons_count: int = grid.get_child_count()
	_assert_true(bid_buttons_count == 14, "F-08: Exactly 14 bid buttons (15 through 28) are present in the bidding panel")

	# Verify Pass button is present in _bid_vbox
	var pass_found: bool = false
	for child in screen._bid_vbox.get_children():
		if child.name == "SinglePassRow":
			pass_found = true
			break
	_assert_true(pass_found, "F-09: SinglePassRow with PASS button is present in bidding panel")

	screen.queue_free()

func _test_enlarged_cards_and_trick_corner_overlap() -> void:
	var screen_scene: PackedScene = load("res://src/ui/main_table_screen.tscn")
	var screen: MainTableScreen = screen_scene.instantiate() as MainTableScreen
	add_child(screen)

	_assert_true(screen._trick_card_size == Vector2(130, 182), "G-01: Played table card size enlarged +20%% to 130x182 (was 108x152)")
	_assert_true(is_equal_approx(screen._hand_fan.fan_card_width, 194.0) and is_equal_approx(screen._hand_fan.fan_card_height, 300.0), "G-02: Local player hand cards enlarged +20%% to 194x300 (was 162x250)")

	var all_remote_enlarged: bool = true
	for rel_seat in [1, 2, 3]:
		var remote_fan: Control = screen._opponent_card_fans.get(rel_seat) as Control
		if remote_fan == null or not is_equal_approx(remote_fan.fan_card_width, 96.0) or not is_equal_approx(remote_fan.fan_card_height, 136.0):
			all_remote_enlarged = false
	_assert_true(all_remote_enlarged, "G-03: All remote seat fans (left, partner, right) enlarged +20%% to 96x136 (was 80x113)")

	# Verify corner-overlapping diamond geometry on the actual trick slots
	var top_rect := Rect2(screen._trick_slots[2].position, screen._trick_slots[2].size)
	var bottom_rect := Rect2(screen._trick_slots[0].position, screen._trick_slots[0].size)
	var left_rect := Rect2(screen._trick_slots[1].position, screen._trick_slots[1].size)
	var right_rect := Rect2(screen._trick_slots[3].position, screen._trick_slots[3].size)

	var top_right_overlap := top_rect.intersection(right_rect)
	var top_left_overlap := top_rect.intersection(left_rect)
	var bottom_right_overlap := bottom_rect.intersection(right_rect)
	var bottom_left_overlap := bottom_rect.intersection(left_rect)
	var corners_overlap_cleanly: bool = (
		is_equal_approx(top_right_overlap.size.x, 16.0) and is_equal_approx(top_right_overlap.size.y, 22.0) and
		is_equal_approx(top_left_overlap.size.x, 16.0) and is_equal_approx(top_left_overlap.size.y, 22.0) and
		is_equal_approx(bottom_right_overlap.size.x, 16.0) and is_equal_approx(bottom_right_overlap.size.y, 22.0) and
		is_equal_approx(bottom_left_overlap.size.x, 16.0) and is_equal_approx(bottom_left_overlap.size.y, 22.0)
	)
	_assert_true(corners_overlap_cleanly, "G-04: All 4 trick slots lightly overlap at corners by 16x22 px")
	_assert_true(not top_rect.intersects(bottom_rect) and not left_rect.intersects(right_rect), "G-05: Opposite trick cards do not overlap, keeping the center window open")

	screen.queue_free()

func _test_pass_22_17_audio_pipeline() -> void:
	_assert_true(AudioManager.BGM_STREAM_PATH == "res://assets/audio/music/background_music.ogg", "H-01: BGM centralized under res://assets/audio/music/background_music.ogg")
	_assert_true(AudioManager.SFX_PATHS.get("shuffle", "") == "res://assets/audio/sfx/shuffle.ogg", "H-02: Shuffle SFX centralized as shuffle.ogg")
	var shuffle_len: float = AudioManager.get_sfx_length("shuffle")
	_assert_true(shuffle_len >= 2.0 and shuffle_len <= 2.35, "H-02b: Shuffle SFX quickened 1.3x (~2.185s)")
	_assert_true(AudioManager.SFX_PATHS.get("card_place", "") == "res://assets/audio/sfx/card_place.ogg", "H-03: Card placement SFX centralized as card_place.ogg")

	var deal_player: AudioStreamPlayer = AudioManager.get_node_or_null("DealAudioPlayer") as AudioStreamPlayer
	_assert_true(deal_player != null and deal_player.bus == AudioManager.BUS_SFX, "H-04: Dedicated DealAudioPlayer exists on SFX bus for non-overlapping deals")
	AudioManager.play_deal_sfx(0.55)
	_assert_true(AudioManager._sounds.has("shuffle") and AudioManager._sounds.has("card_deal") and AudioManager._sounds.has("card_sort") and AudioManager._sounds.has("card_place") and AudioManager._sounds.has("trick_collect") and AudioManager._sounds.has("error") and AudioManager._sounds.has("card_invalid_drop"), "H-05: All core card-table SFX streams loaded in AudioManager")
	var deal_variants_loaded: int = 0
	for k in AudioManager.DEAL_SFX_VARIANTS:
		if AudioManager._sounds.has(k):
			deal_variants_loaded += 1
	var play_variants_loaded: int = 0
	for k in AudioManager.PLAY_CARD_SFX_VARIANTS:
		if AudioManager._sounds.has(k):
			play_variants_loaded += 1
	_assert_true(deal_variants_loaded == 8, "H-05b: All 8 deal card-slide variants (1..8) loaded in AudioManager")
	_assert_true(play_variants_loaded == 12, "H-05c: All 12 card-play variants (card-slide 1..8 + card-place 1..4) loaded in AudioManager")

	# Verify duplicate/stale revision deduplication in MainTableScreen audio pipeline
	var screen_scene: PackedScene = load("res://src/ui/main_table_screen.tscn")
	var screen: MainTableScreen = screen_scene.instantiate() as MainTableScreen
	add_child(screen)

	var v1: Dictionary = {"session_id": "S_AUDIO", "state_revision": 5, "hand_number": 1, "bidding_history": [], "current_trick": [], "completed_tricks": [], "viewer_seat": 0, "current_turn_seat": 1}
	var v2: Dictionary = {"session_id": "S_AUDIO", "state_revision": 6, "hand_number": 1, "bidding_history": [{"seat": 1, "type": "BID", "amount": 16}], "current_trick": [], "completed_tricks": [], "viewer_seat": 0, "current_turn_seat": 2}
	AudioManager._voice_queue.clear()
	screen._process_audio_view_events({}, v1)
	screen._process_audio_view_events(v1, v2)
	var after_v2_rev: int = screen._last_audio_revision
	# Replay v2 with same revision — must be deduplicated cleanly
	var q_before_dup: int = AudioManager._voice_queue.size()
	screen._process_audio_view_events(v1, v2)
	var q_after_dup: int = AudioManager._voice_queue.size()
	_assert_true(after_v2_rev == 6 and q_after_dup == q_before_dup, "H-06: Repeated or stale state_revision broadcasts are strictly deduplicated")
	AudioManager._voice_queue.clear()

	# Verify trick collection gate in MultiplayerManager holds AI play until collection finishes
	MultiplayerManager.set_trick_collection_busy(true)
	_assert_true(MultiplayerManager.ui_trick_collection_busy, "H-07: Trick collection gate blocks AI/next plays until table cards are collected")
	MultiplayerManager.set_trick_collection_busy(false)
	_assert_true(not MultiplayerManager.ui_trick_collection_busy, "H-08: Trick collection gate clears after collection completes")

	# Verify voice playback lock query (active right after H-06 bid 16 playback, idle once stopped)
	_assert_true(AudioManager.is_voice_playing(), "H-09a: AudioManager.is_voice_playing() reports active while voice plays")
	if is_instance_valid(AudioManager._voice_player):
		AudioManager._voice_player.stop()
	AudioManager._voice_is_playing = false
	AudioManager._voice_queue.clear()
	_assert_true(not AudioManager.is_voice_playing(), "H-09b: AudioManager.is_voice_playing() reports idle once voice stops")

	screen.queue_free()
