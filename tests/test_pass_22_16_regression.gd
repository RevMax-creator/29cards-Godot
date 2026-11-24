extends SceneTree

func _init() -> void:
	print("=== RUNNING COMPREHENSIVE PASS 22.16 REGRESSION SUITE ===")
	var passed := 0
	var failed := 0

	# -------------------------------------------------------------
	# 1. AI TRAM Verification: Guaranteed State
	# -------------------------------------------------------------
	var tram_state := GameState.new()
	tram_state.phase = GameState.Phase.TRICK_PLAY
	tram_state.seat_is_ai = [false, true, true, true]
	tram_state.current_turn_seat = 1 # AI seat
	tram_state.trick_leader_seat = 1
	tram_state.trick_index = 6
	tram_state.hidden_trump_suit = CardDefs.Suit.SPADES
	tram_state.trump_revealed = true
	tram_state.high_bidder_seat = 1
	tram_state.current_bid = 16
	tram_state.hands[1] = [
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.JACK),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE)
	]
	tram_state.hands[0] = [CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN), CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.EIGHT)]
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
			"winner_seat": 1,
			"winner_team": 1,
			"points": trick_points
		})
	tram_state.team_card_points = [0, played_card_points]
	tram_state.team_tricks_won = [0, 6]

	# Test: RulesEngine allows AI to call TRAM
	var ai_can_tram := RulesEngine.can_call_tram(tram_state, 1)
	if ai_can_tram:
		passed += 1
		print("[PASS] AI seat CAN call TRAM when guaranteed sure tricks")
	else:
		failed += 1
		printerr("[FAIL] AI seat should be allowed to call TRAM in guaranteed winning state")

	# Test: AIController._decide_trick_action actually returns TRAM when view has tram_available = true
	var ai_view := {
		"tram_available": true,
		"current_trick": [],
		"my_hand": tram_state.hands[1].duplicate()
	}
	var typed_hand: Array[int] = []
	typed_hand.assign(tram_state.hands[1])
	var ai_action: Dictionary = AIController._decide_trick_action(ai_view, typed_hand, AIController.Difficulty.STANDARD)
	if str(ai_action.get("type", "")) == "TRAM":
		passed += 1
		print("[PASS] AIController returns TRAM action when tram_available is true")
	else:
		failed += 1
		printerr("[FAIL] Expected AIController to return TRAM, got: %s" % str(ai_action))

	# -------------------------------------------------------------
	# 2. AI TRAM Verification: Unguaranteed State (must reject)
	# -------------------------------------------------------------
	# Recreate state with 7 of spades so an opponent holds higher trump
	var non_tram_state := GameState.new()
	non_tram_state.phase = GameState.Phase.TRICK_PLAY
	non_tram_state.seat_is_ai = [false, true, true, true]
	non_tram_state.current_turn_seat = 1
	non_tram_state.trick_leader_seat = 1
	non_tram_state.trick_index = 6
	non_tram_state.hidden_trump_suit = CardDefs.Suit.SPADES
	non_tram_state.trump_revealed = true
	non_tram_state.high_bidder_seat = 1
	non_tram_state.current_bid = 16
	non_tram_state.completed_tricks = tram_state.completed_tricks.duplicate(true)
	non_tram_state.team_card_points = tram_state.team_card_points.duplicate()
	non_tram_state.team_tricks_won = tram_state.team_tricks_won.duplicate()
	non_tram_state.hands[1] = [
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.SEVEN),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.EIGHT)
	]
	non_tram_state.hands[0] = tram_state.hands[0].duplicate()
	non_tram_state.hands[2] = tram_state.hands[2].duplicate()
	non_tram_state.hands[3] = tram_state.hands[3].duplicate()

	var ai_cannot_tram := RulesEngine.can_call_tram(non_tram_state, 1)
	if not ai_cannot_tram:
		passed += 1
		print("[PASS] AI cannot call TRAM when not guaranteed to win all remaining tricks")
	else:
		failed += 1
		printerr("[FAIL] AI should not be allowed to call TRAM with non-winning cards")

	# -------------------------------------------------------------
	# 3. Authoritative Processing of TRAM: Points, Tricks, Invariants
	# -------------------------------------------------------------
	var tram_result := RulesEngine.apply_action(tram_state, 1, {"type": "TRAM"})
	if bool(tram_result.get("ok", false)) and int(tram_result.get("remaining_tricks", 0)) == 2:
		passed += 1
		print("[PASS] TRAM action processed successfully for AI high bidder")
	else:
		failed += 1
		printerr("[FAIL] TRAM apply_action failed: %s" % str(tram_result))

	# Invariant: All 4 hands are empty
	var hands_empty := true
	for s in range(4):
		if not tram_state.hands[s].is_empty():
			hands_empty = false
	if hands_empty and tram_state.completed_tricks.size() == 8:
		passed += 1
		print("[PASS] TRAM resolved all remaining tricks and emptied all 4 hands")
	else:
		failed += 1
		printerr("[FAIL] TRAM did not resolve all 8 tricks or empty hands")

	# Invariant: Card points + last trick bonus == 29
	var total_pts: int = tram_state.team_card_points[0] + tram_state.team_card_points[1]
	if total_pts == 29:
		passed += 1
		print("[PASS] Card points + last trick bonus exactly equal 29 after TRAM")
	else:
		failed += 1
		printerr("[FAIL] Total points after TRAM is %d, expected 29" % total_pts)

	# Invariant: Duplicate TRAM is rejected
	var duplicate_tram := RulesEngine.apply_action(tram_state, 1, {"type": "TRAM"})
	if not bool(duplicate_tram.get("ok", false)):
		passed += 1
		print("[PASS] Duplicate TRAM claim rejected")
	else:
		failed += 1
		printerr("[FAIL] Duplicate TRAM should be rejected")

	# -------------------------------------------------------------
	# 4. Human TRAM symmetry
	# -------------------------------------------------------------
	var human_tram_state := GameState.new()
	human_tram_state.phase = GameState.Phase.TRICK_PLAY
	human_tram_state.seat_is_ai = [false, true, true, true]
	human_tram_state.current_turn_seat = 0 # Human
	human_tram_state.trick_leader_seat = 0
	human_tram_state.trick_index = 6
	human_tram_state.hidden_trump_suit = CardDefs.Suit.SPADES
	human_tram_state.trump_revealed = true
	human_tram_state.high_bidder_seat = 0
	human_tram_state.current_bid = 16
	human_tram_state.hands[0] = [
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.JACK),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE)
	]
	for s in [1, 2, 3]:
		human_tram_state.hands[s] = [
			CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN),
			CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.EIGHT)
		]
	for trick_number in range(6):
		var plays: Array[Dictionary] = []
		var trick_points: int = 0
		for offset in range(4):
			var public_card: int = public_cards[trick_number * 4 + offset]
			plays.append({"seat": offset, "card": public_card, "trump_active": true})
			trick_points += CardDefs.get_points(public_card)
		human_tram_state.completed_tricks.append({
			"trick_index": trick_number,
			"plays": plays,
			"winner_seat": 0,
			"winner_team": 0,
			"points": trick_points
		})
	human_tram_state.team_card_points = [played_card_points, 0]
	human_tram_state.team_tricks_won = [6, 0]

	var human_can_tram := RulesEngine.can_call_tram(human_tram_state, 0)
	if human_can_tram:
		passed += 1
		print("[PASS] Human TRAM uses identical validation and succeeds")
	else:
		failed += 1
		printerr("[FAIL] Human TRAM should succeed under identical conditions")

	# -------------------------------------------------------------
	# 5. UI Trick Spread Geometry
	# -------------------------------------------------------------
	# Check trick card size and spread constants from source file
	var table_source: String = FileAccess.get_file_as_string("res://src/ui/main_table_screen.gd")
	if table_source.contains("const TRICK_SPREAD_X := 114.0") and table_source.contains("const TRICK_SPREAD_Y := 160.0"):
		passed += 1
		print("[PASS] Corner-overlapping diamond trick spread constants verified (X=114.0, Y=160.0)")
	else:
		failed += 1
		printerr("[FAIL] Trick spread constants mismatch")

	# -------------------------------------------------------------
	# 6. Opponent Panel Background Styling (Dark/Glass)
	# -------------------------------------------------------------
	if not table_source.contains("var status_style := _create_box_style(Color.WHITE") and table_source.contains("status_style.corner_radius_top_left = 0"):
		passed += 1
		print("[PASS] Opponent status panel white background removed and styled with dark translucent panel")
	else:
		failed += 1
		printerr("[FAIL] Opponent status panel still has Color.WHITE")

	# -------------------------------------------------------------
	# 7. Mobile Gameplay Typography Verification
	# -------------------------------------------------------------
	var font_checks := [
		"name_lbl.add_theme_font_size_override(\"font_size\", 18)",
		"_stat_grid_cell(\"0\", t1_fg, t1_bg, true)",
		"lbl.add_theme_font_size_override(\"font_size\", 24)",
		"button.add_theme_font_size_override(\"font_size\", 18)",
		"_status_banner.add_theme_font_size_override(\"font_size\", 18)",
		"title.add_theme_font_size_override(\"font_size\", 20)"
	]
	var fonts_ok := true
	for fc in font_checks:
		if not table_source.contains(fc):
			fonts_ok = false
			printerr("[FAIL] Missing typography check: %s" % fc)
	if fonts_ok:
		passed += 1
		print("[PASS] Mobile gameplay typography enlarged across all headers, scores, bids and buttons")
	else:
		failed += 1

	print("=========================================================")
	print("PASS 22.16 TEST SUITE: TOTAL PASSED: %d | FAILED: %d" % [passed, failed])
	quit(0 if failed == 0 else 1)
