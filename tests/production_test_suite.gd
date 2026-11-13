extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("=== 29 CARD GAME — MILESTONE 1 DOMAIN & PERSISTENCE TEST SUITE ===")
	_test_t01_deck_and_point_conservation()
	_test_t02_hidden_information_projections()
	_test_t03_dealing_4_plus_4_and_dealer_forced_bid()
	_test_t12_deal_animation_action_barrier()
	_test_t04_automatic_trump_revelation_on_void()
	_test_t05_royal_pair_timing_and_caps()
	_test_t06_scoring_multipliers_unrevealed_trump_and_match_bounds()
	_test_t10_double_before_second_deal_and_tram()
	_test_t11_eighth_trick_completion_gate()
	_test_t07_ab_slot_atomic_persistence_overwrite_and_corruption_fallback()
	_test_t08_safe_point_human_restoration_all_phases()
	_test_t09_complete_hand_progression_and_ai_difficulties()

	print("==================================================================")
	print("TOTAL PASSED: %d | TOTAL FAILED: %d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _complete_test_deal_animation(state: GameState) -> bool:
	if not state.deal_animation_pending:
		return true
	var result: Dictionary = RulesEngine.complete_deal_animation(state)
	return bool(result.get("ok", false))


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
	_assert_true(bool(defender_view.get("trump_selected", false)) and int(defender_view["visible_trump_suit"]) == CardDefs.Suit.NONE, "T-02f: PlayerView exposes selected-state without leaking concealed trump suit")
	state.match_game_points = [-2, 4]
	var score_view: Dictionary = state.build_player_view(0)
	_assert_true(score_view.get("match_game_points", []) == [-2, 4], "T-02g: PlayerView exposes cumulative match points separately from hand card points")

	var individual_state := GameState.new()
	individual_state.completed_tricks.append({"winner_seat": 0, "winner_team": 0, "points": 4})
	individual_state.completed_tricks.append({"winner_seat": 2, "winner_team": 0, "points": 3})
	individual_state.completed_tricks.append({"winner_seat": 1, "winner_team": 1, "points": 5})
	individual_state.completed_tricks.append({"winner_seat": 3, "winner_team": 1, "points": 2})
	individual_state.team_card_points = [7, 7]
	var individual_view: Dictionary = individual_state.build_player_view(0)
	var seat_points: Array = individual_view.get("seat_card_points", [])
	_assert_true(seat_points.size() == 4 and int(seat_points[0]) == 4 and int(seat_points[2]) == 3 and int(seat_points[1]) == 5 and int(seat_points[3]) == 2, "T-02h: All four profiles receive only their own captured-trick card points")
	_assert_true(int(seat_points[0]) + int(seat_points[2]) == 7 and int(seat_points[1]) + int(seat_points[3]) == 7, "T-02i: Individual captured points aggregate to existing partnership hand totals")

func _test_t03_dealing_4_plus_4_and_dealer_forced_bid() -> void:
	var state := GameState.new()
	state.match_seed = 777
	RulesEngine.start_new_hand(state, 0, state.match_seed)

	_assert_true(state.hands[0].size() == 4 and state.stock_deck.size() == 16, "T-03a: First deal distributes 4 cards/seat and retains 16 stock cards")
	# Verify the physical deal follows four clockwise rounds starting left of dealer.
	var expected_deck: Array[int] = CardDefs.build_full_deck()
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = state.match_seed + state.hand_number * 7919
	for shuffle_i in range(expected_deck.size() - 1, 0, -1):
		var shuffle_j: int = expected_rng.randi_range(0, shuffle_i)
		var shuffle_tmp: int = expected_deck[shuffle_i]
		expected_deck[shuffle_i] = expected_deck[shuffle_j]
		expected_deck[shuffle_j] = shuffle_tmp
	var expected_hands: Array = [[], [], [], []]
	var expected_order: Array[int] = [1, 2, 3, 0]
	var expected_cursor: int = 0
	for deal_round in range(4):
		for expected_seat in expected_order:
			expected_hands[expected_seat].append(expected_deck[expected_cursor])
			expected_cursor += 1
	for expected_seat in range(4):
		expected_hands[expected_seat].sort()
	_assert_true(state.hands == expected_hands, "T-03j: First four cards are dealt clockwise from dealer's left")
	_assert_true(state.deal_animation_pending, "T-03m: Initial deal remains action-locked until its animation completes")
	_assert_true(_complete_test_deal_animation(state), "T-03n: Initial deal barrier clears after all four cards reach every seat")

	var round_rotation_state := GameState.new()
	RulesEngine.start_new_hand(round_rotation_state, 0, 551)
	var first_hand_number: int = round_rotation_state.hand_number
	RulesEngine.start_new_hand(round_rotation_state, 1, 551)
	var rotated_view: Dictionary = round_rotation_state.build_player_view(0)
	_assert_true(int(rotated_view.get("hand_number", -1)) == first_hand_number + 1 and int(rotated_view.get("dealer_seat", -1)) == 1, "T-03k: New hand increments round number and rotates dealer")

	var suit_sort_input: Array[int] = [
		CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE),
		CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.JACK),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.SEVEN),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.ACE)
	]
	var suit_sort_expected: Array[int] = [
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.ACE),
		CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.SEVEN),
		CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.JACK),
		CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN)
	]
	_assert_true(CardDefs.sort_hand_by_suit_and_rank(suit_sort_input) == suit_sort_expected, "T-03l: Hand sorts by suit groups and rank strength within suit")
	var rev_before_passes: int = state.state_revision

	RulesEngine.apply_action(state, 1, {"type": "PASS_BID"})
	RulesEngine.apply_action(state, 2, {"type": "PASS_BID"})
	var third_pass: Dictionary = RulesEngine.apply_action(state, 3, {"type": "PASS_BID"})
	_assert_true(str(third_pass.get("event", "")) == "dealer_forced_opening_bid" and state.current_turn_seat == 0, "T-03b: First three passes force the dealer to open")

	var dealer_pass: Dictionary = RulesEngine.apply_action(state, 0, {"type": "PASS_BID"})
	_assert_true(not bool(dealer_pass.get("ok", false)) and str(dealer_pass.get("error", "")) == "ERR_DEALER_MUST_BID_15", "T-03c: Dealer cannot pass the forced opening bid")
	var forced_bid: Dictionary = RulesEngine.apply_action(state, 0, {"type": "BID", "amount": 15})
	_assert_true(bool(forced_bid.get("ok", false)) and state.current_bid == 15 and state.phase == GameState.Phase.SET_HIDDEN_TRUMP, "T-03d: Dealer is forced to bid exactly 15 and wins the opening auction")
	_assert_true(state.hands[0].size() == 4 and state.stock_deck.size() == 16, "T-03e: Remaining four cards are not dealt before Double/Redouble")
	_assert_true(state.state_revision == rev_before_passes + 4, "T-03f: Three passes and forced bid each increment revision once")
	_assert_true(RulesEngine.MAX_BID == 28, "T-03g: Maximum bid is 28")

	var max_bid_state := GameState.new()
	RulesEngine.start_new_hand(max_bid_state, 0, 991)
	_complete_test_deal_animation(max_bid_state)
	var max_bid_result: Dictionary = RulesEngine.apply_action(max_bid_state, 1, {"type": "BID", "amount": 28})
	_assert_true(bool(max_bid_result.get("ok", false)) and max_bid_state.phase == GameState.Phase.SET_HIDDEN_TRUMP, "T-03h: A bid of 28 ends the auction immediately")

	var pass_after_bid := GameState.new()
	RulesEngine.start_new_hand(pass_after_bid, 0, 992)
	_complete_test_deal_animation(pass_after_bid)
	RulesEngine.apply_action(pass_after_bid, 1, {"type": "BID", "amount": 16})
	RulesEngine.apply_action(pass_after_bid, 2, {"type": "PASS_BID"})
	RulesEngine.apply_action(pass_after_bid, 3, {"type": "PASS_BID"})
	var third_opponent_pass: Dictionary = RulesEngine.apply_action(pass_after_bid, 0, {"type": "PASS_BID"})
	_assert_true(bool(third_opponent_pass.get("ok", false)) and pass_after_bid.phase == GameState.Phase.SET_HIDDEN_TRUMP and pass_after_bid.high_bidder_seat == 1, "T-03i: Three opponents passing ends the auction at the highest bid")

func _test_t12_deal_animation_action_barrier() -> void:
	var state := GameState.new()
	RulesEngine.start_new_hand(state, 0, 20261112)
	var first_card: int = int(state.hands[1][0])
	var premature_bid: Dictionary = RulesEngine.apply_action(state, 1, {"type": "BID", "amount": 15})
	_assert_true(not bool(premature_bid.get("ok", false)) and str(premature_bid.get("error", "")) == "ERR_DEAL_ANIMATION_IN_PROGRESS", "T-12a: Bidding is rejected until the initial four-card deal finishes")
	_assert_true(_complete_test_deal_animation(state), "T-12b: Initial deal completion unlocks bidding")

	state.current_bid = 15
	state.high_bidder_seat = 0
	state.effective_contract_target = 15
	state.phase = GameState.Phase.SET_HIDDEN_TRUMP
	state.current_turn_seat = 0
	RulesEngine.apply_action(state, 0, {"type": "SET_TRUMP", "suit": CardDefs.Suit.SPADES})
	RulesEngine.apply_action(state, 1, {"type": "CALL_DOUBLE", "double": false})
	RulesEngine.apply_action(state, 3, {"type": "CALL_DOUBLE", "double": false})
	var premature_play: Dictionary = RulesEngine.apply_action(state, 1, {"type": "PLAY_CARD", "card": first_card})
	_assert_true(state.deal_animation_pending and not bool(premature_play.get("ok", false)) and str(premature_play.get("error", "")) == "ERR_DEAL_ANIMATION_IN_PROGRESS", "T-12c: Trick play is rejected while the second four-card deal is animating")
	_assert_true(_complete_test_deal_animation(state), "T-12d: Completing the second deal releases trick play")
	var valid_play: Dictionary = RulesEngine.apply_action(state, state.current_turn_seat, {"type": "PLAY_CARD", "card": int(state.hands[state.current_turn_seat][0])})
	_assert_true(bool(valid_play.get("ok", false)), "T-12e: A card can be played once all eight cards have been dealt to every player")


func _test_t04_automatic_trump_revelation_on_void() -> void:
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
	state.hands[1] = [sj]
	state.hands[2] = [c8]
	state.hands[3] = [d8]

	RulesEngine.apply_action(state, 0, {"type": "PLAY_CARD", "card": h7})
	var void_play: Dictionary = RulesEngine.apply_action(state, 1, {"type": "PLAY_CARD", "card": sj})
	RulesEngine.apply_action(state, 2, {"type": "PLAY_CARD", "card": c8})
	var trick_res: Dictionary = RulesEngine.apply_action(state, 3, {"type": "PLAY_CARD", "card": d8})

	_assert_true(bool(void_play.get("ok", false)) and bool(void_play.get("trump_revealed_now", false)), "T-04a: Trump reveals automatically when a player cannot follow suit")
	_assert_true(state.trump_revealed and state.trump_revealed_by_seat == 1, "T-04b: The void player reveals trump immediately")
	_assert_true(int(trick_res.get("winner_seat", -1)) == 1, "T-04c: The revealed trump card can win the current trick")
	_assert_true(not bool(RulesEngine.apply_action(state, 0, {"type": "REQUEST_TRUMP_REVEAL"}).get("ok", false)), "T-04d: Manual trump reveal action is no longer accepted")

	var discard_state := GameState.new()
	discard_state.phase = GameState.Phase.TRICK_PLAY
	discard_state.trump_revealed = true
	discard_state.hidden_trump_suit = CardDefs.Suit.SPADES
	discard_state.current_turn_seat = 1
	var heart_seven: int = CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN)
	var heart_jack: int = CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.JACK)
	var spade_nine: int = CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE)
	var club_seven: int = CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.SEVEN)
	discard_state.current_trick = [{"seat": 0, "card": heart_seven, "trump_active": false}]
	discard_state.hands[1] = [spade_nine, club_seven]
	var off_suit_discard: Dictionary = RulesEngine.apply_action(discard_state, 1, {"type": "PLAY_CARD", "card": club_seven})
	_assert_true(bool(off_suit_discard.get("ok", false)), "T-04e: A void player may discard any card even while holding trump")

	var follow_state := GameState.new()
	follow_state.phase = GameState.Phase.TRICK_PLAY
	follow_state.trump_revealed = true
	follow_state.hidden_trump_suit = CardDefs.Suit.SPADES
	follow_state.current_turn_seat = 1
	follow_state.current_trick = [{"seat": 0, "card": heart_seven, "trump_active": false}]
	follow_state.hands[1] = [heart_jack, spade_nine]
	var follow_result: Dictionary = RulesEngine.apply_action(follow_state, 1, {"type": "PLAY_CARD", "card": spade_nine})
	_assert_true(not bool(follow_result.get("ok", false)) and str(follow_result.get("error", "")) == "ERR_ILLEGAL_CARD_PLAY", "T-04f: A player must follow the lead suit when they have it, even after trump is revealed")

func _test_t05_royal_pair_timing_and_caps() -> void:
	# Bidder's partnership won the previous trick; the Pair holder may announce
	# even if their partner is currently the next trick leader.
	var state := GameState.new()
	state.phase = GameState.Phase.PAIR_DECISION
	state.high_bidder_seat = 0
	state.current_bid = 15
	state.effective_contract_target = 15
	state.hidden_trump_suit = CardDefs.Suit.DIAMONDS
	state.trump_revealed = true
	state.current_turn_seat = 0
	state.trick_leader_seat = 2
	state.trick_index = 1
	state.completed_tricks = [{"trick_index": 0, "winner_team": 0, "winner_seat": 2, "plays": [], "points": 3}]
	var dk: int = CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.KING)
	var dq: int = CardDefs.make_card(CardDefs.Suit.DIAMONDS, CardDefs.Rank.QUEEN)
	state.hands[0] = [dk, dq]
	var pair_low: Dictionary = RulesEngine.apply_action(state, 0, {"type": "DECLARE_PAIR"})
	_assert_true(bool(pair_low.get("ok", false)) and state.effective_contract_target == 15, "T-05a: Declaring-team Pair reduces bid by 4 but never below 15")
	_assert_true(int(pair_low.get("by_seat", -1)) == 0, "T-05b: The player holding both King and Queen announces the Pair")

	# Defender's Pair raises the bid but never above 28.
	var state_high := GameState.new()
	state_high.phase = GameState.Phase.PAIR_DECISION
	state_high.high_bidder_seat = 0
	state_high.current_bid = 26
	state_high.effective_contract_target = 26
	state_high.hidden_trump_suit = CardDefs.Suit.CLUBS
	state_high.trump_revealed = true
	state_high.current_turn_seat = 1
	state_high.trick_leader_seat = 3
	state_high.trick_index = 1
	state_high.completed_tricks = [{"trick_index": 0, "winner_team": 1, "winner_seat": 3, "plays": [], "points": 4}]
	var ck: int = CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.KING)
	var cq: int = CardDefs.make_card(CardDefs.Suit.CLUBS, CardDefs.Rank.QUEEN)
	state_high.hands[1] = [ck, cq]
	var pair_high: Dictionary = RulesEngine.apply_action(state_high, 1, {"type": "DECLARE_PAIR"})
	_assert_true(bool(pair_high.get("ok", false)) and state_high.effective_contract_target == 28, "T-05c: Defending-team Pair adds 4 but never above 28")

	var closed_window := GameState.new()
	closed_window.phase = GameState.Phase.TRICK_PLAY
	closed_window.high_bidder_seat = 0
	closed_window.current_bid = 20
	closed_window.hidden_trump_suit = CardDefs.Suit.CLUBS
	closed_window.trump_revealed = true
	closed_window.current_turn_seat = 1
	closed_window.trick_index = 1
	closed_window.completed_tricks = [{"winner_team": 0}]
	closed_window.current_trick = [{"seat": 1, "card": 0}]
	closed_window.hands[1] = [ck, cq]
	var closed_result: Dictionary = RulesEngine.apply_action(closed_window, 1, {"type": "DECLARE_PAIR"})
	_assert_true(not bool(closed_result.get("ok", false)), "T-05d: Royal Pair cannot be announced after the next trick has started")

	# After seven completed tricks, trick_index is 7 because the eighth trick
	# is next. Passing a Pair decision here must NOT score the hand early.
	var seventh_trick_state := GameState.new()
	seventh_trick_state.phase = GameState.Phase.PAIR_DECISION
	seventh_trick_state.high_bidder_seat = 0
	seventh_trick_state.current_bid = 15
	seventh_trick_state.effective_contract_target = 15
	seventh_trick_state.current_turn_seat = 0
	seventh_trick_state.trick_leader_seat = 2
	seventh_trick_state.trick_index = 7
	for trick_number in range(7):
		seventh_trick_state.completed_tricks.append({"trick_index": trick_number, "winner_team": trick_number % 2, "points": 3})
	var seventh_pass: Dictionary = RulesEngine.apply_action(seventh_trick_state, 0, {"type": "PASS_PAIR"})
	_assert_true(bool(seventh_pass.get("ok", false)) and seventh_trick_state.phase == GameState.Phase.TRICK_PLAY and seventh_trick_state.completed_tricks.size() == 7, "T-05e: Passing Pair after trick seven leaves the eighth trick playable")

	# Once all eight tricks are actually recorded, passing the Pair decision
	# may safely score the completed hand.
	var eighth_trick_state := GameState.new()
	eighth_trick_state.phase = GameState.Phase.PAIR_DECISION
	eighth_trick_state.high_bidder_seat = 0
	eighth_trick_state.current_bid = 15
	eighth_trick_state.effective_contract_target = 15
	eighth_trick_state.current_turn_seat = 0
	eighth_trick_state.trick_leader_seat = 2
	eighth_trick_state.trick_index = 7
	for trick_number in range(8):
		eighth_trick_state.completed_tricks.append({"trick_index": trick_number, "winner_team": trick_number % 2, "points": 3})
	eighth_trick_state.team_card_points = [28, 1]
	eighth_trick_state.team_tricks_won = [4, 4]
	var eighth_pass: Dictionary = RulesEngine.apply_action(eighth_trick_state, 0, {"type": "PASS_PAIR"})
	_assert_true(bool(eighth_pass.get("ok", false)) and eighth_trick_state.phase == GameState.Phase.HAND_SCORING, "T-05f: Pair decision after all eight tricks scores the hand")

func _test_t06_scoring_multipliers_unrevealed_trump_and_match_bounds() -> void:
	var state := GameState.new()
	for trick_number in range(8):
		state.completed_tricks.append({"trick_index": trick_number, "winner_seat": trick_number % 4, "winner_team": trick_number % 2, "points": 0})
	state.high_bidder_seat = 0
	state.current_bid = 28
	state.effective_contract_target = 28
	state.trump_revealed = false # Never revealed
	state.stake_multiplier = GameState.StakeMultiplier.NORMAL
	state.team_card_points = [28, 1]
	state.team_tricks_won = [7, 1]

	# Uploaded scoring rule: bid 28 still has a normal 1-point base stake:
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



func _test_t10_double_before_second_deal_and_tram() -> void:
	# Both defenders decline: the second four are dealt only after decisions.
	var state := GameState.new()
	state.match_seed = 123
	RulesEngine.start_new_hand(state, 0, state.match_seed)
	_complete_test_deal_animation(state)
	var first_batch_hands: Array = [[], [], [], []]
	for seat_index in range(4):
		first_batch_hands[seat_index].assign(state.hands[seat_index])
	var second_batch_stock: Array[int] = []
	second_batch_stock.assign(state.stock_deck)
	state.current_bid = 15
	state.high_bidder_seat = 0
	state.phase = GameState.Phase.SET_HIDDEN_TRUMP
	state.current_turn_seat = 0
	RulesEngine.apply_action(state, 0, {"type": "SET_TRUMP", "suit": CardDefs.Suit.SPADES})
	_assert_true(state.phase == GameState.Phase.DOUBLE_DECISION and state.stock_deck.size() == 16 and state.hands[0].size() == 4, "T-10a: Trump selection opens Double before the second deal")
	RulesEngine.apply_action(state, 1, {"type": "CALL_DOUBLE", "double": false})
	var defender_two: Dictionary = RulesEngine.apply_action(state, 3, {"type": "CALL_DOUBLE", "double": false})
	_assert_true(bool(defender_two.get("ok", false)) and state.phase == GameState.Phase.TRICK_PLAY and state.stock_deck.is_empty() and state.hands[0].size() == 8 and state.deal_animation_pending, "T-10b: Second deal follows both defenders declining Double and locks play until animation ends")
	_complete_test_deal_animation(state)
	var expected_second_hands: Array = [[], [], [], []]
	for seat_index in range(4):
		expected_second_hands[seat_index].assign(first_batch_hands[seat_index])
	var second_deal_order: Array[int] = [1, 2, 3, 0] # dealer=0; start left, clockwise
	var second_cursor: int = 0
	for deal_round in range(4):
		for dealt_seat in second_deal_order:
			expected_second_hands[dealt_seat].append(second_batch_stock[second_cursor])
			second_cursor += 1
	for seat_index in range(4):
		expected_second_hands[seat_index].sort()
	var combined_second_hand: Dictionary = {}
	for seat_index in range(4):
		for dealt_card in state.hands[seat_index]:
			combined_second_hand[int(dealt_card)] = true
	_assert_true(state.hands == expected_second_hands, "T-10i: Second four cards are dealt clockwise from dealer's left")
	_assert_true(combined_second_hand.size() == 32, "T-10j: Both deal batches preserve all 32 unique cards")

	# A called Double and bidder's Redouble also resolve before the second deal.
	var doubled := GameState.new()
	doubled.match_seed = 456
	RulesEngine.start_new_hand(doubled, 0, doubled.match_seed)
	_complete_test_deal_animation(doubled)
	doubled.current_bid = 18
	doubled.high_bidder_seat = 0
	doubled.phase = GameState.Phase.SET_HIDDEN_TRUMP
	doubled.current_turn_seat = 0
	RulesEngine.apply_action(doubled, 0, {"type": "SET_TRUMP", "suit": CardDefs.Suit.HEARTS})
	RulesEngine.apply_action(doubled, 1, {"type": "CALL_DOUBLE", "double": true})
	_assert_true(doubled.phase == GameState.Phase.REDOUBLE_DECISION and doubled.stock_deck.size() == 16, "T-10c: Double decision occurs before the second deal")
	var partner_redouble: Dictionary = RulesEngine.apply_action(doubled, 2, {"type": "CALL_REDOUBLE", "redouble": true})
	_assert_true(bool(partner_redouble.get("ok", false)) and doubled.phase == GameState.Phase.TRICK_PLAY and doubled.stake_multiplier == GameState.StakeMultiplier.REDOUBLED and doubled.hands[0].size() == 8 and doubled.deal_animation_pending, "T-10d: Redouble resolves before second deal and trick play remains locked during animation")
	_complete_test_deal_animation(doubled)

	# TRAM is available only on a middle trick when all remaining cards are sure winners.
	var tram_state := GameState.new()
	tram_state.phase = GameState.Phase.TRICK_PLAY
	tram_state.current_turn_seat = 0
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

	# Reconstruct six completed tricks from public cards. TRAM availability must
	# be provable from this visible history and our own hand, not hidden hands.
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
	_assert_true(RulesEngine.can_call_tram(tram_state, 0), "T-10e: TRAM is available when public history proves every remaining card is guaranteed")
	var tram_result: Dictionary = RulesEngine.apply_action(tram_state, 0, {"type": "TRAM"})
	_assert_true(bool(tram_result.get("ok", false)) and int(tram_result.get("remaining_tricks", 0)) == 2 and tram_state.hands[0].is_empty(), "T-10f: TRAM collects all remaining tricks at once")
	_assert_true(tram_state.team_tricks_won[0] == 8 and int(tram_state.last_hand_summary.get("bidder_points", 0)) >= 0, "T-10g: TRAM awards remaining tricks and their card points to the caller's team")
	_assert_true(tram_state.team_card_points[0] + tram_state.team_card_points[1] == 29, "T-10h: TRAM preserves the 29-point total including the last-trick bonus")
	_assert_true(tram_state.phase == GameState.Phase.HAND_SCORING and bool(tram_state.last_hand_summary.get("contract_succeeded", false)) and int(tram_state.last_hand_summary.get("game_point_delta", 0)) == 1 and tram_state.match_game_points == [1, 0], "T-10k: TRAM completes contract scoring and awards the correct match point")

	var resolved_hand_number: int = tram_state.hand_number
	var resolved_dealer: int = tram_state.dealer_seat
	var resolved_match_points: Array[int] = tram_state.match_game_points.duplicate()
	var next_hand_result: Dictionary = RulesEngine.start_new_hand(tram_state, (resolved_dealer + 1) % 4, tram_state.match_seed)
	var next_hand_has_four_each: bool = true
	for next_seat in range(4):
		next_hand_has_four_each = next_hand_has_four_each and tram_state.hands[next_seat].size() == 4
	_assert_true(bool(next_hand_result.get("ok", false)) and tram_state.hand_number == resolved_hand_number + 1 and tram_state.dealer_seat == (resolved_dealer + 1) % 4 and tram_state.phase == GameState.Phase.BIDDING and tram_state.deal_animation_pending and next_hand_has_four_each and tram_state.stock_deck.size() == 16, "T-10l: Next Hand starts the next clockwise-dealer round and deals its first four cards")
	_assert_true(tram_state.match_game_points == resolved_match_points, "T-10m: Starting the next hand preserves cumulative match points")
	_assert_true(_complete_test_deal_animation(tram_state) and not tram_state.deal_animation_pending, "T-10n: The next hand's initial deal barrier clears after cards are dealt")

func _test_t11_eighth_trick_completion_gate() -> void:
	var state := GameState.new()
	state.phase = GameState.Phase.TRICK_PLAY
	state.high_bidder_seat = 0
	state.current_bid = 15
	state.effective_contract_target = 15
	state.hidden_trump_suit = CardDefs.Suit.DIAMONDS
	state.trump_revealed = false
	state.trick_index = 6
	state.trick_leader_seat = 0
	state.current_turn_seat = 0
	state.team_card_points = [11, 10]
	state.team_tricks_won = [3, 3]
	for trick_number in range(6):
		state.completed_tricks.append({
			"trick_index": trick_number,
			"winner_seat": trick_number % 4,
			"winner_team": trick_number % 2,
			"points": [4, 4, 4, 3, 3, 3][trick_number]
		})

	# Seven completed tricks leave one card with every player.
	state.hands[0] = [CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.JACK), CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.KING)]
	state.hands[1] = [CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.NINE), CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.QUEEN)]
	state.hands[2] = [CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.ACE), CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.EIGHT)]
	state.hands[3] = [CardDefs.make_card(CardDefs.Suit.SPADES, CardDefs.Rank.TEN), CardDefs.make_card(CardDefs.Suit.HEARTS, CardDefs.Rank.SEVEN)]

	for _play in range(4):
		var active_seat: int = state.current_turn_seat
		var first_card: int = int(state.hands[active_seat][0])
		var seventh_result: Dictionary = RulesEngine.apply_action(state, active_seat, {"type": "PLAY_CARD", "card": first_card})
		_assert_true(bool(seventh_result.get("ok", false)), "T-11a: Seventh-trick card is accepted")
		if not bool(seventh_result.get("ok", false)):
			return

	_assert_true(
		state.phase == GameState.Phase.TRICK_PLAY
		and state.completed_tricks.size() == 7
		and state.trick_index == 7
		and state.hands[0].size() == 1
		and state.hands[1].size() == 1
		and state.hands[2].size() == 1
		and state.hands[3].size() == 1,
		"T-11b: Seven tricks do not end the hand; the eighth remains playable"
	)

	for _play in range(4):
		var active_seat: int = state.current_turn_seat
		var last_card: int = int(state.hands[active_seat][0])
		var eighth_result: Dictionary = RulesEngine.apply_action(state, active_seat, {"type": "PLAY_CARD", "card": last_card})
		_assert_true(bool(eighth_result.get("ok", false)), "T-11c: Eighth-trick card is accepted")
		if not bool(eighth_result.get("ok", false)):
			return

	var all_hands_empty: bool = true
	for seat in range(4):
		all_hands_empty = all_hands_empty and state.hands[seat].is_empty()
	_assert_true(
		state.phase in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER]
		and state.completed_tricks.size() == 8
		and state.current_trick.is_empty()
		and all_hands_empty,
		"T-11d: Scoring starts only after eight tricks and all hands are empty"
	)
	_assert_true(
		state.team_card_points[0] + state.team_card_points[1] == 29,
		"T-11e: The eighth trick and last-trick bonus preserve 29 points"
	)


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
	var incomplete_hand_completions: int = 0

	for diff in difficulties:
		var state := GameState.new()
		state.match_seed = 9000 + diff * 100
		state.seat_is_ai = [true, true, true, true]

		for h in range(10):
			RulesEngine.start_new_hand(state, h % 4, state.match_seed + h * 37)
			var steps: int = 0

			while state.phase not in [GameState.Phase.HAND_SCORING, GameState.Phase.MATCH_OVER] and steps < 120:
				if state.deal_animation_pending:
					_complete_test_deal_animation(state) # Headless tests treat the UI animation as completed.

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
				var all_cards_played: bool = true
				for completed_seat in range(4):
					all_cards_played = all_cards_played and state.hands[completed_seat].is_empty()
				if state.completed_tricks.size() != 8 or not state.current_trick.is_empty() or not all_cards_played:
					incomplete_hand_completions += 1
					printerr("INCOMPLETE HAND SCORE | tricks=%d hands=%s current_trick=%s" % [state.completed_tricks.size(), str(state.hands), str(state.current_trick)])
				var sum_pts: int = state.team_card_points[0] + state.team_card_points[1]

				if sum_pts != 29:
					point_conservation_errors += 1
					var recorded_trick_points: int = 0
					for trick_record in state.completed_tricks:
						recorded_trick_points += int(trick_record.get("points", 0))
					print("POINT CONSERVATION FAILURE | difficulty=%s | hand=%d | total=%d | teams=%s | tricks=%d | trick_index=%d | recorded_trick_points=%d | phase=%s | last_summary=%s" % [
						str(diff),
						h,
						sum_pts,
						str(state.team_card_points),
						state.completed_tricks.size(),
						state.trick_index,
						recorded_trick_points,
						str(state.phase),
						str(state.last_hand_summary)
					])

	_assert_true(illegal_actions == 0, "T-09a: 0 illegal actions across 30 hands (Casual, Standard, Master)")
	_assert_true(total_hands_completed == 30 and incomplete_hand_completions == 0, "T-09b: All 30 seeded hands score only after eight completed tricks")
	_assert_true(point_conservation_errors == 0, "T-09c: Every completed hand conserved exactly 29 card+last-trick points")


# PASS 22.8 UI regression notes:
# - Opponent score pills must format seat_card_points[absolute_seat], never team_card_points.
# - For both side seats, Dealer D is upper-left of the avatar and trump ?/suit
#   is upper-right; the two badges must not share coordinates.
