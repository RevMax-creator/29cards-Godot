extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("=== 29 CARD GAME — MILESTONE 1 DOMAIN & PERSISTENCE TEST SUITE ===")
	_test_t01_deck_and_point_conservation()
	_test_t02_hidden_information_projections()
	_test_t03_dealing_4_plus_4_and_all_pass_redeal()
	_test_t04_trump_revelation_optional_and_silent_trump_non_power()
	_test_t05_exact_unclamped_pair_arithmetic_and_trick_requirement()
	_test_t06_scoring_multipliers_unrevealed_trump_and_match_bounds()
	_test_t07_ab_slot_atomic_persistence_overwrite_and_corruption_fallback()
	_test_t08_safe_point_human_restoration_all_phases()
	_test_t09_complete_hand_progression_and_ai_difficulties()

	print("==================================================================")
	print("TOTAL PASSED: %d | TOTAL FAILED: %d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _assert_true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		printerr("[FAIL] %s" % label)

func _test_t01_deck_and_point_conservation() -> void:
	var deck: Array[int] = CardDefs.build_full_deck()
	var seen: Dictionary = {}
	var total_card_pts: int = 0
	for c in deck:
		seen[c] = true
		total_card_pts += CardDefs.get_points(c)
	_assert_true(deck.size() == 32 and seen.size() == 32, "T-01a: Deck contains 32 unique cards")
	_assert_true(total_card_pts == 28, "T-01b: Card points sum to 28 (+1 last trick = 29)")

func _test_t02_hidden_information_projections() -> void:
	var state := GameState.new()
	RulesEngine.start_new_hand(state, 0, 12345)
	state.high_bidder_seat = 0
	state.hidden_trump_suit = CardDefs.Suit.HEARTS
	state.trump_revealed = false

	var bidder_view: Dictionary = state.build_player_view(0)
	var defender_view: Dictionary = state.build_player_view(1)
	var partner_view: Dictionary = state.build_player_view(2)

	_assert_true(int(bidder_view["visible_trump_suit"]) == CardDefs.Suit.HEARTS, "T-02a: High bidder sees concealed trump suit")
	_assert_true(int(defender_view["visible_trump_suit"]) == CardDefs.Suit.NONE, "T-02b: Defender cannot see concealed trump before reveal")
	_assert_true(int(partner_view["visible_trump_suit"]) == CardDefs.Suit.NONE, "T-02c: Bidder's partner cannot see concealed trump before reveal")
	_assert_true(not defender_view.has("hands") and not defender_view.has("stock_deck"), "T-02d: PlayerView strips authoritative hands and stock_deck")
	_assert_true(defender_view["my_hand"].size() == 4, "T-02e: PlayerView exposes only viewer's 4-card initial hand")

func _test_t03_dealing_4_plus_4_and_all_pass_redeal() -> void:
	var state := GameState.new()
	state.match_seed = 777
	RulesEngine.start_new_hand(state, 0, state.match_seed)

	_assert_true(state.hands[0].size() == 4 and state.stock_deck.size() == 16, "T-03a: First deal distributes 4 cards/seat and retains 16 stock cards")
	var rev_before_passes: int = state.state_revision

	RulesEngine.apply_action(state, 1, {"type": "PASS_BID"})
	RulesEngine.apply_action(state, 2, {"type": "PASS_BID"})
	RulesEngine.apply_action(state, 3, {"type": "PASS_BID"})
	var fourth_pass: Dictionary = RulesEngine.apply_action(state, 0, {"type": "PASS_BID"})

	_assert_true(str(fourth_pass.get("event", "")) == "all_pass_redeal", "T-03b: Four opening passes trigger all_pass_redeal")
	_assert_true(state.dealer_seat == 1 and state.current_turn_seat == 2, "T-03c: All-pass redeal rotates dealer clockwise from 0 to 1")
	_assert_true(state.state_revision == rev_before_passes + 4, "T-03d: Each of the 4 passes increments state_revision by exactly 1")

func _test_t04_trump_revelation_optional_and_silent_trump_non_power() -> void:
	var state := GameState.new()
	state.phase = GameState.Phase.TRICK_PLAY
	state.high_bidder_seat = 1
	state.hidden_trump_suit = CardDefs.Suit.SPADES
	state.trump_revealed = false
	state.trick_leader_seat = 0
	state.current_turn_seat = 0

	var h7: int = CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN)
	var sj: int = CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.JACK)
	var c8: int = CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.EIGHT)
	var d8: int = CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.EIGHT)

	state.hands[0] = [h7]
	state.hands[1] = [sj] # Bidder is void in Hearts and plays hidden trump Jack WITHOUT revealing trump
	state.hands[2] = [c8]
	state.hands[3] = [d8]

	RulesEngine.apply_action(state, 0, {"type": "PLAY_CARD", "card": h7})
	var silent_trump_play: Dictionary = RulesEngine.apply_action(state, 1, {"type": "PLAY_CARD", "card": sj})
	RulesEngine.apply_action(state, 2, {"type": "PLAY_CARD", "card": c8})
	var trick_res: Dictionary = RulesEngine.apply_action(state, 3, {"type": "PLAY_CARD", "card": d8})

	_assert_true(bool(silent_trump_play.get("ok", false)), "T-04a: Void player may discard without revealing trump (revelation is optional)")
	_assert_true(int(trick_res.get("winner_seat", -1)) == 0, "T-04b: Hidden trump played before revelation has zero cutting power (even for bidder)")

func _test_t05_exact_unclamped_pair_arithmetic_and_trick_requirement() -> void:
	# Case A: Bidder Pair on bid 15 -> unclamped target = 11
	var state := GameState.new()
	state.phase = GameState.Phase.TRICK_PLAY
	state.high_bidder_seat = 0
	state.current_bid = 15
	state.effective_contract_target = 15
	state.hidden_trump_suit = CardDefs.Suit.DIAMONDS
	state.trump_revealed = true
	state.current_turn_seat = 0

	var dk: int = CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.KING)
	var dq: int = CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.QUEEN)
	state.hands[0] = [dk, dq]

	var pair_low: Dictionary = RulesEngine.apply_action(state, 0, {"type": "DECLARE_PAIR"})
	_assert_true(bool(pair_low.get("ok", false)) and state.effective_contract_target == 11, "T-05a: Bidder Pair on 15 uses exact arithmetic (15 - 4 = 11, unclamped)")

	# Case B: Defender Pair on bid 26 -> unclamped target = 30 (impossible out of 29, so 29 points fails!)
	var state_high := GameState.new()
	state_high.phase = GameState.Phase.TRICK_PLAY
	state_high.high_bidder_seat = 0
	state_high.current_bid = 26
	state_high.effective_contract_target = 26
	state_high.hidden_trump_suit = CardDefs.Suit.CLUBS
	state_high.trump_revealed = true
	state_high.current_turn_seat = 1

	var ck: int = CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.KING)
	var cq: int = CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.QUEEN)
	state_high.hands[1] = [ck, cq]

	var pair_high: Dictionary = RulesEngine.apply_action(state_high, 1, {"type": "DECLARE_PAIR"})
	_assert_true(bool(pair_high.get("ok", false)) and state_high.effective_contract_target == 30, "T-05b: Defender Pair on 26 uses exact arithmetic (26 + 4 = 30, unclamped)")

	# Verify that if Defending Team (Team 1) wins >= 1 trick, target 30 fails; if Team 1 wins 0 tricks, target reverts to 26
	state_high.team_card_points = [28, 1]
	state_high.team_tricks_won = [7, 1]
	RulesEngine._score_completed_hand(state_high)
	_assert_true(not bool(state_high.last_hand_summary["contract_succeeded"]), "T-05c: Target 30 fails when defending team wins at least 1 trick")

	state_high.match_game_points = [0, 0]
	state_high.team_card_points = [29, 0]
	state_high.team_tricks_won = [8, 0]
	RulesEngine._score_completed_hand(state_high)
	_assert_true(bool(state_high.last_hand_summary["contract_succeeded"]) and int(state_high.last_hand_summary["final_target"]) == 26, "T-05d: Pair adjustment ignored when declaring partnership wins 0 tricks")

func _test_t06_scoring_multipliers_unrevealed_trump_and_match_bounds() -> void:
	var state := GameState.new()
	state.high_bidder_seat = 0
	state.current_bid = 28
	state.effective_contract_target = 28
	state.trump_revealed = false # Never revealed
	state.stake_multiplier = GameState.StakeMultiplier.NORMAL
	state.team_card_points = [28, 1]
	state.team_tricks_won = [7, 1]

	# Provisional Decision #5 & flat base stake on 28:
	RulesEngine._score_completed_hand(state)
	_assert_true(bool(state.last_hand_summary["contract_succeeded"]) and int(state.last_hand_summary["game_point_delta"]) == 1, "T-06a: Unrevealed trump hand scores normally and bid 28 uses flat +1 base stake")

	# Double (2x) loss -> -2
	state.stake_multiplier = GameState.StakeMultiplier.DOUBLED
	state.team_card_points = [20, 9]
	RulesEngine._score_completed_hand(state)
	_assert_true(int(state.last_hand_summary["game_point_delta"]) == -2, "T-06b: Doubled failed contract deducts -2 game points")

	# Redouble (4x) win -> +4, and reaching >= +6 ends match
	state.match_game_points = [3, 0]
	state.stake_multiplier = GameState.StakeMultiplier.REDOUBLED
	state.team_card_points = [29, 0]
	RulesEngine._score_completed_hand(state)
	_assert_true(int(state.last_hand_summary["game_point_delta"]) == 4 and state.match_game_points[0] == 7 and state.phase == GameState.Phase.MATCH_OVER and state.winning_team == 0, "T-06c: Redoubled made contract awards +4 and triggers MATCH_OVER at >= +6")


func _test_t07_ab_slot_atomic_persistence_overwrite_and_corruption_fallback() -> void:
	var save_manager_script: GDScript = load("res://src/persistence/save_manager.gd") as GDScript
	var sm: Node = save_manager_script.new()

	# SaveManager extends Node, so attach it to the SceneTree.
	root.add_child(sm)

	sm.clear_solo_save()

	var state := GameState.new()
	RulesEngine.start_new_hand(state, 0, 5555)

	var all_saves_ok: bool = true

	for rev in range(1, 26):
		state.state_revision = rev
		state.current_bid = 15 + (rev % 10)

		if not sm.save_solo_state(state):
			all_saves_ok = false
			break

	var loaded_latest: GameState = sm.load_solo_save()

	_assert_true(
		all_saves_ok and loaded_latest != null and loaded_latest.state_revision == 25,
		"T-07a: 25 consecutive A/B atomic overwrites succeed and load revision 25"
	)

	# Corrupt the newest slot and verify fallback to revision 24.
	var newest_slot_path: String = sm._get_slot_a_path(sm.SOLO_PREFIX)
	var meta_a: Dictionary = sm._parse_and_verify_slot_file(newest_slot_path)

	if int(meta_a.get("state_revision", -1)) != 25:
		newest_slot_path = sm._get_slot_b_path(sm.SOLO_PREFIX)

	var f := FileAccess.open(newest_slot_path, FileAccess.WRITE)

	if f != null:
		f.store_string("{corrupted_json_payload")
		f.flush()
		f = null

	var fallback_state: GameState = sm.load_solo_save()

	_assert_true(
		fallback_state != null and fallback_state.state_revision == 24,
		"T-07b: Corrupted primary slot automatically falls back to prior valid slot (revision 24)"
	)

	# Clean up persisted test data and release the Node.
	sm.clear_solo_save()
	sm.free()
	sm = null
	save_manager_script = null

func _test_t08_safe_point_human_restoration_all_phases() -> void:
	var state := GameState.new()
	state.seat_is_ai = [false, true, false, false]
	state.seat_pending_human_reclaim = [false, true, false, false]

	# 1. During SET_HIDDEN_TRUMP when Seat 0 is high bidder, Seat 1 is not active turn -> Safe point
	state.phase = GameState.Phase.SET_HIDDEN_TRUMP
	state.current_turn_seat = 0
	RulesEngine._process_safe_point_reclaims(state)
	_assert_true(state.seat_is_ai[1] == false, "T-08a: Reclaim succeeds during SET_HIDDEN_TRUMP when seat is not active turn")

	# 2. During TRICK_PLAY mid-trick -> Not safe
	state.phase = GameState.Phase.TRICK_PLAY
	state.seat_is_ai[1] = true
	state.seat_pending_human_reclaim[1] = true
	state.current_trick.append({"seat": 0, "card": 0, "trump_active": false})
	RulesEngine._process_safe_point_reclaims(state)
	_assert_true(state.seat_is_ai[1] == true, "T-08b: Reclaim deferred while trick is in progress")

	# 3. Trick completes -> Safe point
	state.current_trick.clear()
	RulesEngine._process_safe_point_reclaims(state)
	_assert_true(state.seat_is_ai[1] == false, "T-08c: Reclaim completes at trick boundary")


func _test_t09_complete_hand_progression_and_ai_difficulties() -> void:
	var difficulties: Array[int] = [
		AIController.Difficulty.CASUAL,
		AIController.Difficulty.STANDARD,
		AIController.Difficulty.MASTER
	]
	var total_hands_completed: int = 0
	var illegal_actions: int = 0
	var point_conservation_errors: int = 0

	for diff in difficulties:
		var state := GameState.new()
		state.match_seed = 9000 + diff * 100
		state.seat_is_ai = [true, true, true, true]

		for h in range(10):
			RulesEngine.start_new_hand(state, h % 4, state.match_seed + h * 37)
			var steps: int = 0

			while state.phase not in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER] and steps < 120:

				var seat: int = state.current_turn_seat

				# DIAGNOSTIC: Check authoritative state before AI action.
				if state.phase == GameState.Phase.BIDDING and state.passed_seats[seat]:
					print("BIDDING STATE CORRUPTED | difficulty=%s | hand=%d | step=%d | dealer=%d | turn=%d | passed=%s | bid=%d | bidder=%d | history=%s" % [
						str(diff),
						h,
						steps,
						state.dealer_seat,
						state.current_turn_seat,
						str(state.passed_seats),
						state.current_bid,
						state.high_bidder_seat,
						str(state.bidding_history)
					])
					break

				var view: Dictionary = state.build_player_view(seat)
				var action: Dictionary = AIController.choose_action(view, diff)
				var res: Dictionary = RulesEngine.apply_action(state, seat, action)

				if not bool(res.get("ok", false)):
					illegal_actions += 1

					print("AI FAILURE | difficulty=%s | hand=%d | step=%d | seat=%d | phase=%s | action=%s | result=%s | passed=%s | bid=%d | bidder=%d | history=%s" % [
						str(diff),
						h,
						steps,
						seat,
						str(state.phase),
						str(action),
						str(res),
						str(state.passed_seats),
						state.current_bid,
						state.high_bidder_seat,
						str(state.bidding_history)
					])
					break

				steps += 1

			if state.phase in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER]:
				total_hands_completed += 1
				var sum_pts: int = state.team_card_points[0] + state.team_card_points[1]

				if sum_pts != 29:
					point_conservation_errors += 1

	_assert_true(illegal_actions == 0, "T-09a: 0 illegal actions across 30 hands (Casual, Standard, Master)")
	_assert_true(total_hands_completed == 30, "T-09b: All 30 seeded hands reached HAND_SCORING or MATCH_OVER")
	_assert_true(point_conservation_errors == 0, "T-09c: Every completed hand conserved exactly 29 card+last-trick points")
