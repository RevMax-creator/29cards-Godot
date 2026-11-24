extends SceneTree

func _init() -> void:
	print("=== RUNNING EXTENDED PASS 22.15 REGRESSION SUITE ===")
	var passed := 0
	var failed := 0

	# 1. Verify AI TRAM restriction
	var state := GameState.new()
	state.session_id = "TEST_TRAM_RESTRICTION"
	state.seat_is_ai = [false, true, true, true]
	state.phase = GameState.Phase.TRICK_PLAY
	state.high_bidder_seat = 1
	state.current_turn_seat = 1
	state.trick_leader_seat = 1
	state.trick_index = 4
	state.stock_deck.clear()
	state.hidden_trump_suit = CardDefs.Suit.HEARTS
	state.trump_revealed = true
	# Setup mock hands
	for s in range(4):
		state.hands[s] = [s * 4 + 1, s * 4 + 2, s * 4 + 3, s * 4 + 4]
	
	var ai_can_tram := RulesEngine.can_call_tram(state, 1)
	if not ai_can_tram:
		passed += 1
		print("[PASS] AI cannot call TRAM (can_call_tram returned false for AI seat)")
	else:
		failed += 1
		printerr("[FAIL] AI should not be allowed to call TRAM")

	# Check human can call tram if conditions match
	var tram_state := GameState.new()
	tram_state.phase = GameState.Phase.TRICK_PLAY
	tram_state.seat_is_ai = [false, true, true, true]
	tram_state.current_turn_seat = 0
	tram_state.trick_leader_seat = 0
	tram_state.trick_index = 6
	tram_state.hidden_trump_suit = CardDefs.Suit.SPADES
	tram_state.trump_revealed = true
	tram_state.high_bidder_seat = 0
	tram_state.current_bid = 15
	tram_state.hands[0] = [
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.JACK),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE)
	]
	tram_state.hands[1] = [CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN), CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.EIGHT)]
	tram_state.hands[2] = [CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.SEVEN), CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.EIGHT)]
	tram_state.hands[3] = [CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.SEVEN), CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.EIGHT)]

	var held: Dictionary = {}
	for seat in range(4):
		for card_id in tram_state.hands[seat]:
			held[int(card_id)] = true
	var public_cards: Array[int] = []
	for card_id in CardDefs.build_full_deck():
		if not held.has(card_id):
			public_cards.append(card_id)
	var played_card_points: int = 0
	for trick_number in range(6):
		var plays: Array[Dictionary] = []
		var trick_points: int = 0
		for offset in range(4):
			var public_card: int = public_cards[trick_number * 4 + offset]
			plays.append({"seat": offset, "card": public_card, "trump_active": true})
			trick_points += CardDefs.get_points(public_card)
		played_card_points += trick_points
		tram_state.completed_tricks.append({
			"trick_index": trick_number,
			"plays": plays,
			"winner_seat": 0,
			"winner_team": 0,
			"points": trick_points
		})
	tram_state.team_card_points = [played_card_points, 0]
	tram_state.team_tricks_won = [6, 0]

	var human_can_tram := RulesEngine.can_call_tram(tram_state, 0)
	if human_can_tram:
		passed += 1
		print("[PASS] Human CAN call TRAM when guaranteed sure tricks")
	else:
		failed += 1
		printerr("[FAIL] Human should be able to call TRAM when all cards are top trumps")

	# 2. Verify AIController._decide_trick_action never returns TRAM
	var view := {
		"tram_available": true,
		"current_trick": [],
		"my_hand": [state.hands[1][0]]
	}
	var ai_action := AIController._decide_trick_action(view, [state.hands[1][0]], AIController.Difficulty.STANDARD)
	if str(ai_action.get("type", "")) == "PLAY_CARD":
		passed += 1
		print("[PASS] AIController trick action ignores tram_available and plays card legally")
	else:
		failed += 1
		printerr("[FAIL] AIController returned action: %s instead of PLAY_CARD" % str(ai_action))

	# 3. Verify match target evaluation for both teams
	var scoring_state := GameState.new()
	scoring_state.session_id = "TEST_MATCH_TARGET"
	scoring_state.high_bidder_seat = 1 # Team 1 (defending against team 0)
	scoring_state.current_bid = 16
	scoring_state.match_game_points = [0, 5] # Team 1 has 5 match points
	scoring_state.team_card_points = [10, 19] # Team 1 captured 19 (made contract)
	scoring_state.completed_tricks.resize(8)
	scoring_state.hands = [[], [], [], []]
	RulesEngine._score_completed_hand(scoring_state)
	if scoring_state.phase == GameState.Phase.MATCH_OVER and scoring_state.winning_team == 1:
		passed += 1
		print("[PASS] Match correctly ends when Team 1 reaches +6 game points")
	else:
		failed += 1
		printerr("[FAIL] Expected MATCH_OVER with winning_team 1, got phase: %s, winning_team: %s" % [scoring_state.phase, scoring_state.winning_team])

	# 4. Verify opponent avatar randomization
	var player_profile = load("res://src/core/player_profile.gd").new()
	player_profile.avatar_id = "byte"
	player_profile.initialize_match_ai_profiles(12345)
	var ai1: Dictionary = player_profile.get_ai_profile(1)
	var ai2: Dictionary = player_profile.get_ai_profile(2)
	var ai3: Dictionary = player_profile.get_ai_profile(3)
	var avatars := [str(ai1["avatar_id"]), str(ai2["avatar_id"]), str(ai3["avatar_id"])]
	var unique_avatars := {}
	for av in avatars:
		unique_avatars[av] = true
	if unique_avatars.size() == 3 and not unique_avatars.has("byte"):
		passed += 1
		print("[PASS] Opponents received 3 unique randomized avatars excluding local player avatar: %s" % str(avatars))
	else:
		failed += 1
		printerr("[FAIL] Opponent avatars not distinct or included local avatar: %s" % str(avatars))

	# 5. Audio BGM volume verification
	var audio_mgr = load("res://src/core/audio_manager.gd")
	if audio_mgr.BGM_VOLUME_DB == -14.5:
		passed += 1
		print("[PASS] AudioManager.BGM_VOLUME_DB correctly boosted to -14.5 dB")
	else:
		failed += 1
		printerr("[FAIL] AudioManager.BGM_VOLUME_DB is %f" % audio_mgr.BGM_VOLUME_DB)

	print("=====================================================")
	print("EXTENDED SUITE TOTAL PASSED: %d | FAILED: %d" % [passed, failed])
	quit(0 if failed == 0 else 1)
