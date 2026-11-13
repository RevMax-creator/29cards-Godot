class_name RulesEngine
extends RefCounted

const MIN_BID: int = 15
const MAX_BID: int = 28
const PAIR_DELTA: int = 4
const MATCH_WIN_TARGET: int = 6
const MATCH_LOSS_THRESHOLD: int = -6

## Starts a new hand with a deterministic seed, dealing the first 4 cards to each player.
## When invoked internally by an action handler, increment_revision is set to false
## so apply_action() increments state_revision exactly once.
static func start_new_hand(state: GameState, dealer: int, seed_val: int, increment_revision: bool = true) -> Dictionary:
	state.hand_number += 1
	state.dealer_seat = posmod(dealer, 4)
	state.current_turn_seat = (state.dealer_seat + 1) % 4
	state.phase = GameState.Phase.BIDDING
	state.deal_animation_pending = true

	state.current_bid = 0
	state.high_bidder_seat = -1
	state.passed_seats = [false, false, false, false]
	state.bidding_history.clear()

	state.hidden_trump_suit = CardDefs.Suit.NONE
	state.trump_revealed = false
	state.trump_revealed_on_trick = -1
	state.trump_revealed_by_seat = -1
	state.must_play_trump_this_turn = false

	state.pair_declared_by_team = -1
	state.effective_contract_target = 0
	state.stake_multiplier = GameState.StakeMultiplier.NORMAL
	state.double_decided_by_defenders.clear()

	state.trick_index = 0
	state.trick_leader_seat = (state.dealer_seat + 1) % 4
	state.current_trick.clear()
	state.completed_tricks.clear()
	state.team_card_points = [0, 0]
	state.team_tricks_won = [0, 0]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + state.hand_number * 7919

	var deck: Array[int] = CardDefs.build_full_deck()
	for i in range(deck.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp

	# Deal one card at a time clockwise, beginning with the player to the
	# dealer's left. This matches the table animation and the supplied rules.
	state.hands = [[], [], [], []]
	var deal_order: Array[int] = []
	for offset in range(4):
		deal_order.append(posmod(state.dealer_seat + 1 + offset, 4))
	var deck_cursor: int = 0
	for card_round in range(4):
		for dealt_seat in deal_order:
			var dealt_hand: Array[int] = []
			dealt_hand.assign(state.hands[dealt_seat])
			dealt_hand.append(deck[deck_cursor])
			state.hands[dealt_seat] = dealt_hand
			deck_cursor += 1
	for seat in range(4):
		var sorted_hand: Array[int] = []
		sorted_hand.assign(state.hands[seat])
		sorted_hand.sort()
		state.hands[seat] = sorted_hand

	state.stock_deck.clear()
	for idx in range(16, 32):
		state.stock_deck.append(deck[idx])

	_process_safe_point_reclaims(state)
	if increment_revision:
		state.state_revision += 1
	return {"ok": true, "event": "hand_started", "dealer": state.dealer_seat}

## Master entry point for authoritative action execution.
static func apply_action(state: GameState, seat: int, action: Dictionary) -> Dictionary:
	if seat < 0 or seat > 3:
		return {"ok": false, "error": "ERR_INVALID_SEAT"}

	if state.deal_animation_pending:
		return {"ok": false, "error": "ERR_DEAL_ANIMATION_IN_PROGRESS"}

	var action_type: String = str(action.get("type", ""))
	var result: Dictionary

	match action_type:
		"BID":
			result = _handle_bid(state, seat, int(action.get("amount", 0)))
		"PASS_BID":
			result = _handle_pass_bid(state, seat)
		"SET_TRUMP":
			result = _handle_set_trump(state, seat, int(action.get("suit", CardDefs.Suit.NONE)))
		"CALL_DOUBLE":
			result = _handle_double_call(state, seat, bool(action.get("double", false)))
		"CALL_REDOUBLE":
			result = _handle_redouble_call(state, seat, bool(action.get("redouble", false)))
		"REQUEST_TRUMP_REVEAL":
			result = _handle_request_trump_reveal(state, seat)
		"DECLARE_PAIR":
			result = _handle_declare_pair(state, seat)
		"PASS_PAIR":
			result = _handle_pass_pair(state, seat)
		"PLAY_CARD":
			result = _handle_play_card(state, seat, int(action.get("card", -1)))
		"TRAM":
			result = _handle_tram(state, seat)
		_:
			return {"ok": false, "error": "ERR_UNKNOWN_ACTION_TYPE"}

	if result.get("ok", false):
		_process_safe_point_reclaims(state)
		state.state_revision += 1
	return result

static func _handle_bid(state: GameState, seat: int, amount: int) -> Dictionary:
	if state.phase != GameState.Phase.BIDDING:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}
	if state.passed_seats[seat]:
		return {"ok": false, "error": "ERR_ALREADY_PASSED"}

	var opening_passes: int = 0
	for passed in state.passed_seats:
		if passed:
			opening_passes += 1
	var dealer_forced_open: bool = state.high_bidder_seat == -1 and opening_passes == 3 and seat == state.dealer_seat
	var min_allowed: int = MIN_BID if state.current_bid == 0 else state.current_bid + 1
	if dealer_forced_open and amount != MIN_BID:
		return {"ok": false, "error": "ERR_DEALER_MUST_BID_15"}
	if amount < min_allowed or amount > MAX_BID:
		return {"ok": false, "error": "ERR_INVALID_BID_AMOUNT"}

	state.current_bid = amount
	state.high_bidder_seat = seat
	state.effective_contract_target = amount
	state.bidding_history.append({"seat": seat, "type": "BID", "amount": amount})

	# Check whether all three opponents have already passed.
	var all_opponents_passed: bool = true
	for s in range(4):
		if s != seat and not state.passed_seats[s]:
			all_opponents_passed = false
			break

	# Bidding ends if the maximum bid is reached or no opponent remains.
	if amount == MAX_BID or all_opponents_passed:
		for s in range(4):
			if s != seat:
				state.passed_seats[s] = true

		state.phase = GameState.Phase.SET_HIDDEN_TRUMP
		state.current_turn_seat = state.high_bidder_seat

		return {
			"ok": true,
			"event": "bidding_won",
			"winner": seat,
			"bid": amount
		}

	_advance_bidding_turn(state)

	return {"ok": true, "event": "bid_placed", "seat": seat, "amount": amount}

static func _handle_pass_bid(state: GameState, seat: int) -> Dictionary:
	if state.phase != GameState.Phase.BIDDING:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}
	if state.passed_seats[seat]:
		return {"ok": false, "error": "ERR_ALREADY_PASSED"}

	var pass_count_before: int = 0
	for passed in state.passed_seats:
		if passed:
			pass_count_before += 1
	if state.high_bidder_seat == -1 and pass_count_before == 3 and seat == state.dealer_seat:
		return {"ok": false, "error": "ERR_DEALER_MUST_BID_15"}

	state.passed_seats[seat] = true
	state.bidding_history.append({"seat": seat, "type": "PASS"})

	var pass_count: int = 0
	for passed in state.passed_seats:
		if passed:
			pass_count += 1

	# The first three players pass: the dealer must open at exactly 15.
	if pass_count == 3 and state.high_bidder_seat == -1:
		state.current_turn_seat = state.dealer_seat
		return {"ok": true, "event": "dealer_forced_opening_bid", "dealer": state.dealer_seat, "minimum_bid": MIN_BID}

	# After a bid exists, three opponents passing ends the auction.
	if pass_count == 3 and state.high_bidder_seat != -1:
		state.phase = GameState.Phase.SET_HIDDEN_TRUMP
		state.current_turn_seat = state.high_bidder_seat
		return {"ok": true, "event": "bidding_won", "winner": state.high_bidder_seat, "bid": state.current_bid}

	_advance_bidding_turn(state)
	return {"ok": true, "event": "bid_passed", "seat": seat}

static func _advance_bidding_turn(state: GameState) -> void:
	for step in range(1, 5):
		var candidate: int = (state.current_turn_seat + step) % 4
		if not state.passed_seats[candidate]:
			state.current_turn_seat = candidate
			return

static func _handle_set_trump(state: GameState, seat: int, suit: int) -> Dictionary:
	if state.phase != GameState.Phase.SET_HIDDEN_TRUMP:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if seat != state.high_bidder_seat:
		return {"ok": false, "error": "ERR_NOT_HIGH_BIDDER"}
	if suit < CardDefs.Suit.SPADES or suit > CardDefs.Suit.DIAMONDS:
		return {"ok": false, "error": "ERR_INVALID_TRUMP_SUIT"}

	state.hidden_trump_suit = suit
	# Defenders decide Double before the remaining four cards are dealt.
	state.phase = GameState.Phase.DOUBLE_DECISION
	state.double_decided_by_defenders.clear()
	state.current_turn_seat = _first_defender_after_bidder(state.high_bidder_seat)
	return {"ok": true, "event": "trump_set_awaiting_double"}

static func _deal_second_batch(state: GameState) -> bool:
	# Existing saves from the previous UI already contain 8 cards during Double.
	# Do not deal a second batch twice when resuming one of those matches.
	var already_dealt: bool = true
	for seat in range(4):
		if state.hands[seat].size() != 8:
			already_dealt = false
			break
	if not already_dealt:
		if state.stock_deck.size() != 16:
			return false
		# The second four are also dealt one-by-one clockwise from dealer's left.
		var deal_order: Array[int] = []
		for offset in range(4):
			deal_order.append(posmod(state.dealer_seat + 1 + offset, 4))
		var stock_cursor: int = 0
		for card_round in range(4):
			for dealt_seat in deal_order:
				var hand_ref: Array[int] = []
				hand_ref.assign(state.hands[dealt_seat])
				hand_ref.append(state.stock_deck[stock_cursor])
				state.hands[dealt_seat] = hand_ref
				stock_cursor += 1
		for seat in range(4):
			var sorted_hand: Array[int] = []
			sorted_hand.assign(state.hands[seat])
			sorted_hand.sort()
			state.hands[seat] = sorted_hand
	state.stock_deck.clear()
	# Newly distributed second-batch cards must finish their clockwise UI deal
	# before any trick-play action or AI turn can be accepted.
	state.deal_animation_pending = not already_dealt
	if bool(state.rule_config.get("auto_redeal_invalid_hands", false)) and _is_invalid_full_deal(state):
		var same_dealer: int = state.dealer_seat
		start_new_hand(state, same_dealer, state.match_seed + 307, false)
		return true
	_begin_trick_play(state)
	return true

## Called only by the authoritative host after the visual deal queue has
## delivered every card to all four seats. RulesEngine actions remain locked
## until this barrier is cleared.
static func complete_deal_animation(state: GameState) -> Dictionary:
	if not state.deal_animation_pending:
		return {"ok": false, "error": "ERR_NO_PENDING_DEAL"}

	var expected_hand_size: int = 0
	if state.phase == GameState.Phase.BIDDING:
		expected_hand_size = 4
	elif state.phase == GameState.Phase.TRICK_PLAY:
		expected_hand_size = 8
	else:
		return {"ok": false, "error": "ERR_DEAL_PHASE_INVALID"}

	for seat in range(4):
		if state.hands[seat].size() != expected_hand_size:
			return {"ok": false, "error": "ERR_DEAL_INCOMPLETE", "seat": seat, "expected": expected_hand_size, "actual": state.hands[seat].size()}

	state.deal_animation_pending = false
	state.state_revision += 1
	return {"ok": true, "event": "deal_animation_completed", "cards_per_player": expected_hand_size}


static func _is_invalid_full_deal(state: GameState) -> bool:
	for s in range(4):
		var h: Array[int] = state.hands[s]
		var pts: int = 0
		var jacks: int = 0
		var suit_counts: Array[int] = [0, 0, 0, 0]
		for card_id in h:
			pts += CardDefs.get_points(card_id)
			if CardDefs.get_rank(card_id) == CardDefs.Rank.JACK:
				jacks += 1
			suit_counts[CardDefs.get_suit(card_id)] += 1
		if pts == 0 or jacks == 4 or suit_counts.has(8):
			return true
	return false

static func _first_defender_after_bidder(bidder: int) -> int:
	return (bidder + 1) % 4

static func _second_defender_after_bidder(bidder: int) -> int:
	return (bidder + 3) % 4

static func _handle_double_call(state: GameState, seat: int, call_double: bool) -> Dictionary:
	if state.phase != GameState.Phase.DOUBLE_DECISION:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}
	if GameState.get_team(seat) == GameState.get_team(state.high_bidder_seat):
		return {"ok": false, "error": "ERR_BIDDING_TEAM_CANNOT_DOUBLE"}

	state.double_decided_by_defenders[seat] = call_double
	if call_double:
		state.stake_multiplier = GameState.StakeMultiplier.DOUBLED
		state.phase = GameState.Phase.REDOUBLE_DECISION
		state.current_turn_seat = state.high_bidder_seat
		return {"ok": true, "event": "contract_doubled", "by_seat": seat}

	var second_def: int = _second_defender_after_bidder(state.high_bidder_seat)
	if not state.double_decided_by_defenders.has(second_def):
		state.current_turn_seat = second_def
		return {"ok": true, "event": "defender_passed_double", "seat": seat}

	if not _deal_second_batch(state):
		return {"ok": false, "error": "ERR_SECOND_DEAL_STOCK_INVALID"}
	return {"ok": true, "event": "defenders_declined_double_second_deal_complete"}

static func _handle_redouble_call(state: GameState, seat: int, call_redouble: bool) -> Dictionary:
	if state.phase != GameState.Phase.REDOUBLE_DECISION:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if GameState.get_team(seat) != GameState.get_team(state.high_bidder_seat):
		return {"ok": false, "error": "ERR_ONLY_DECLARING_TEAM_CAN_REDOUBLE"}

	if call_redouble:
		state.stake_multiplier = GameState.StakeMultiplier.REDOUBLED

	if not _deal_second_batch(state):
		return {"ok": false, "error": "ERR_SECOND_DEAL_STOCK_INVALID"}
	return {"ok": true, "event": "redouble_resolved_second_deal_complete", "by_seat": seat, "redoubled": call_redouble}

static func _begin_trick_play(state: GameState) -> void:
	state.phase = GameState.Phase.TRICK_PLAY
	state.trick_index = 0
	state.trick_leader_seat = (state.dealer_seat + 1) % 4
	state.current_turn_seat = state.trick_leader_seat
	state.current_trick.clear()
	state.must_play_trump_this_turn = false

static func _handle_request_trump_reveal(_state: GameState, _seat: int) -> Dictionary:
	return {"ok": false, "error": "ERR_TRUMP_REVEALS_AUTOMATICALLY"}

static func _find_pair_holder(state: GameState, winning_team: int) -> int:
	if winning_team < 0 or not state.trump_revealed or state.pair_declared_by_team != -1:
		return -1
	var king_trump: int = CardDefs.make_card(state.hidden_trump_suit, CardDefs.Rank.KING)
	var queen_trump: int = CardDefs.make_card(state.hidden_trump_suit, CardDefs.Rank.QUEEN)
	for seat in range(4):
		if GameState.get_team(seat) == winning_team and state.hands[seat].has(king_trump) and state.hands[seat].has(queen_trump):
			return seat
	return -1

static func can_declare_pair(state: GameState, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if state.phase != GameState.Phase.PAIR_DECISION or state.current_turn_seat != seat:
		return false
	var king_trump: int = CardDefs.make_card(state.hidden_trump_suit, CardDefs.Rank.KING)
	var queen_trump: int = CardDefs.make_card(state.hidden_trump_suit, CardDefs.Rank.QUEEN)
	return state.hands[seat].has(king_trump) and state.hands[seat].has(queen_trump)

static func _handle_declare_pair(state: GameState, seat: int) -> Dictionary:
	if not can_declare_pair(state, seat):
		return {"ok": false, "error": "ERR_PAIR_NOT_AVAILABLE"}
	var declaring_team: int = GameState.get_team(seat)
	var bidding_team: int = GameState.get_team(state.high_bidder_seat)
	state.pair_declared_by_team = declaring_team
	if declaring_team == bidding_team:
		state.effective_contract_target = maxi(MIN_BID, state.current_bid - PAIR_DELTA)
	else:
		state.effective_contract_target = mini(MAX_BID, state.current_bid + PAIR_DELTA)
	if state.completed_tricks.size() >= 8:
		_score_completed_hand(state)
		return {
			"ok": true,
			"event": "pair_declared_hand_scored",
			"by_seat": seat,
			"team": declaring_team,
			"effective_contract_target": state.effective_contract_target,
			"summary": state.last_hand_summary
		}
	state.phase = GameState.Phase.TRICK_PLAY
	state.current_turn_seat = state.trick_leader_seat
	return {
		"ok": true,
		"event": "pair_declared",
		"by_seat": seat,
		"team": declaring_team,
		"effective_contract_target": state.effective_contract_target
	}

static func _handle_pass_pair(state: GameState, seat: int) -> Dictionary:
	if state.phase != GameState.Phase.PAIR_DECISION or state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_PAIR_DECISION_NOT_ACTIVE"}
	if state.completed_tricks.size() >= 8:
		_score_completed_hand(state)
		return {"ok": true, "event": "pair_declined_hand_scored", "by_seat": seat, "summary": state.last_hand_summary}
	state.phase = GameState.Phase.TRICK_PLAY
	state.current_turn_seat = state.trick_leader_seat
	return {"ok": true, "event": "pair_declined", "by_seat": seat}

static func get_legal_cards(state: GameState, seat: int) -> Array[int]:
	if state.phase != GameState.Phase.TRICK_PLAY or state.current_turn_seat != seat:
		return []
	var hand: Array[int] = []
	for raw_card in state.hands[seat]:
		hand.append(int(raw_card))
	if state.current_trick.is_empty():
		return hand.duplicate()

	var led_suit: int = CardDefs.get_suit(int(state.current_trick[0]["card"]))
	var same_suit_cards: Array[int] = []
	for c in hand:
		if CardDefs.get_suit(c) == led_suit:
			same_suit_cards.append(c)

	if not same_suit_cards.is_empty():
		return same_suit_cards

	# A player void in the lead suit may discard any card; trump has already been opened automatically.
	return hand.duplicate()

static func _handle_play_card(state: GameState, seat: int, card_id: int) -> Dictionary:
	if state.phase != GameState.Phase.TRICK_PLAY:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}
	if not state.hands[seat].has(card_id):
		return {"ok": false, "error": "ERR_CARD_NOT_IN_HAND"}

	var trump_revealed_now: bool = false
	if not state.current_trick.is_empty():
		var led_suit: int = CardDefs.get_suit(int(state.current_trick[0]["card"]))
		if not _player_has_suit(state.hands[seat], led_suit) and not state.trump_revealed:
			state.trump_revealed = true
			state.trump_revealed_on_trick = state.trick_index
			state.trump_revealed_by_seat = seat
			trump_revealed_now = true
			# Re-evaluate any trump-suit cards already present in this trick now
			# that the trump suit has been revealed.
			for i in range(state.current_trick.size()):
				var prior_card: int = int(state.current_trick[i]["card"])
				if CardDefs.get_suit(prior_card) == state.hidden_trump_suit:
					state.current_trick[i]["trump_active"] = true

	var legal_cards: Array[int] = get_legal_cards(state, seat)
	if not legal_cards.has(card_id):
		return {"ok": false, "error": "ERR_ILLEGAL_CARD_PLAY"}

	state.hands[seat].erase(card_id)
	state.must_play_trump_this_turn = false
	state.current_trick.append({
		"seat": seat,
		"card": card_id,
		"trump_active": state.trump_revealed
	})

	if state.current_trick.size() < 4:
		state.current_turn_seat = (seat + 1) % 4
		return {"ok": true, "event": "card_played", "seat": seat, "card": card_id, "trump_revealed_now": trump_revealed_now}

	# Resolve completed 4-card trick
	var led_suit: int = CardDefs.get_suit(int(state.current_trick[0]["card"]))
	var winning_entry: Dictionary = state.current_trick[0]
	var trick_points: int = CardDefs.get_points(int(winning_entry["card"]))

	for i in range(1, 4):
		var entry: Dictionary = state.current_trick[i]
		var c_id: int = int(entry["card"])
		trick_points += CardDefs.get_points(c_id)
		var challenger_effective_trump: int = state.hidden_trump_suit if bool(entry["trump_active"]) else CardDefs.Suit.NONE
		var best_effective_trump: int = state.hidden_trump_suit if bool(winning_entry["trump_active"]) else CardDefs.Suit.NONE

		if _trick_entry_beats(c_id, challenger_effective_trump, int(winning_entry["card"]), best_effective_trump, led_suit):
			winning_entry = entry

	var winner_seat: int = int(winning_entry["seat"])
	var winner_team: int = GameState.get_team(winner_seat)

	# Award +1 Last-Trick bonus point on the 8th trick (index 7)
	if state.trick_index == 7:
		trick_points += 1

	state.team_card_points[winner_team] += trick_points
	state.team_tricks_won[winner_team] += 1

	state.completed_tricks.append({
		"trick_index": state.trick_index,
		"plays": state.current_trick.duplicate(true),
		"winner_seat": winner_seat,
		"winner_team": winner_team,
		"points": trick_points
	})
	state.current_trick.clear()

	# The index is zero-based. After the seventh completed trick the
	# next index is 7, which represents the eighth trick, not hand completion.
	var completed_trick_count: int = state.completed_tricks.size()
	if completed_trick_count < 8:
		state.trick_index = completed_trick_count
	state.trick_leader_seat = winner_seat

	# Royal Pair can be announced immediately after any trick won by its
	# holder's partnership, including the final trick before hand scoring.
	var pair_holder: int = _find_pair_holder(state, winner_team)
	if pair_holder >= 0:
		state.phase = GameState.Phase.PAIR_DECISION
		state.current_turn_seat = pair_holder
		return {
			"ok": true,
			"event": "trick_completed_pair_decision",
			"winner_seat": winner_seat,
			"pair_holder_seat": pair_holder,
			"points": trick_points,
			"trump_revealed_now": trump_revealed_now
		}

	if completed_trick_count < 8:
		state.phase = GameState.Phase.TRICK_PLAY
		state.current_turn_seat = winner_seat
		return {
			"ok": true,
			"event": "trick_completed",
			"winner_seat": winner_seat,
			"points": trick_points,
			"trump_revealed_now": trump_revealed_now
		}

	_score_completed_hand(state)
	return {
		"ok": true,
		"event": "hand_completed",
		"summary": state.last_hand_summary
	}

static func _trick_entry_beats(challenger_card: int, challenger_trump: int, best_card: int, best_trump: int, led_suit: int) -> bool:
	var c_suit: int = CardDefs.get_suit(challenger_card)
	var b_suit: int = CardDefs.get_suit(best_card)
	var c_rank: int = CardDefs.get_rank(challenger_card)
	var b_rank: int = CardDefs.get_rank(best_card)

	var c_is_trump: bool = (challenger_trump != CardDefs.Suit.NONE) and (c_suit == challenger_trump)
	var b_is_trump: bool = (best_trump != CardDefs.Suit.NONE) and (b_suit == best_trump)

	if c_is_trump and not b_is_trump:
		return true
	if not c_is_trump and b_is_trump:
		return false
	if c_is_trump and b_is_trump:
		return c_rank > b_rank

	if c_suit == led_suit and b_suit != led_suit:
		return true
	if c_suit == b_suit:
		return c_rank > b_rank
	return false

static func can_call_tram(state: GameState, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if state.phase != GameState.Phase.TRICK_PLAY or state.current_turn_seat != seat or state.trick_leader_seat != seat:
		return false
	if not state.current_trick.is_empty() or state.trick_index <= 0 or state.trick_index >= 7:
		return false
	if not state.stock_deck.is_empty() or state.hidden_trump_suit == CardDefs.Suit.NONE:
		return false
	# Before automatic reveal, only the high bidder knows the chosen trump suit.
	if not state.trump_revealed and seat != state.high_bidder_seat:
		return false

	var hand: Array[int] = []
	hand.assign(state.hands[seat])
	if hand.is_empty() or hand.size() != 8 - state.trick_index:
		return false
	for other_seat in range(4):
		if state.hands[other_seat].size() != hand.size():
			return false

	# Prove TRAM from the caller's hand and public card history only.
	# Do not inspect opponents' private hands to decide whether to show the button.
	var own_cards: Dictionary = {}
	for card_id in hand:
		own_cards[card_id] = true

	var played_cards: Dictionary = {}
	for trick_record in state.completed_tricks:
		var plays: Array = trick_record.get("plays", [])
		for play in plays:
			played_cards[int(play.get("card", -1))] = true
	for play in state.current_trick:
		played_cards[int(play.get("card", -1))] = true

	if played_cards.size() != state.trick_index * 4:
		return false

	var unknown_cards: Array[int] = []
	for card_id in CardDefs.build_full_deck():
		if not own_cards.has(card_id) and not played_cards.has(card_id):
			unknown_cards.append(card_id)

	# At a valid trick boundary, the only unseen cards are the other three hands.
	if unknown_cards.size() != hand.size() * 3:
		return false

	var every_card_is_trump: bool = true
	for card_id in hand:
		var suit: int = CardDefs.get_suit(card_id)
		var rank: int = CardDefs.get_rank(card_id)
		if suit != state.hidden_trump_suit:
			every_card_is_trump = false

		# Every possible unseen card in the same suit must be lower.
		for unknown_card in unknown_cards:
			if CardDefs.get_suit(unknown_card) == suit and CardDefs.get_rank(unknown_card) > rank:
				return false

	if not every_card_is_trump:
		# With a mixed-suit hand, TRAM is safe only when every remaining trump
		# card is either in our hand or already visible in the completed tricks.
		for unknown_card in unknown_cards:
			if CardDefs.get_suit(unknown_card) == state.hidden_trump_suit:
				return false
	return true

static func _handle_tram(state: GameState, seat: int) -> Dictionary:
	if not can_call_tram(state, seat):
		return {"ok": false, "error": "ERR_TRAM_NOT_AVAILABLE"}

	var winner_team: int = GameState.get_team(seat)
	var remaining_tricks: int = 8 - state.trick_index
	var points_awarded: int = 0

	# Resolve each remaining trick authoritatively. The exact card order is not
	# material because can_call_tram() proves every card in the caller's hand wins.
	for trick_number in range(state.trick_index, 8):
		var plays: Array[Dictionary] = []
		var trick_points: int = 0
		for player_seat in range(4):
			var player_hand: Array[int] = []
			player_hand.assign(state.hands[player_seat])
			var card_id: int = int(player_hand.pop_back())
			state.hands[player_seat] = player_hand
			trick_points += CardDefs.get_points(card_id)
			plays.append({
				"seat": player_seat,
				"card": card_id,
				"trump_active": state.trump_revealed
			})
		if trick_number == 7:
			trick_points += 1
		points_awarded += trick_points
		state.completed_tricks.append({
			"trick_index": trick_number,
			"plays": plays,
			"winner_seat": seat,
			"winner_team": winner_team,
			"points": trick_points,
			"tram": true
		})

	state.team_card_points[winner_team] += points_awarded
	state.team_tricks_won[winner_team] += remaining_tricks
	state.trick_index = 7
	state.trick_leader_seat = seat
	state.current_turn_seat = seat
	_score_completed_hand(state)
	return {
		"ok": true,
		"event": "tram_completed",
		"winner_seat": seat,
		"remaining_tricks": remaining_tricks,
		"points": points_awarded,
		"summary": state.last_hand_summary
	}

static func _score_completed_hand(state: GameState) -> void:
	# Never resolve a hand while one of its eight tricks or any player's cards
	# remain. TRAM also satisfies this gate after recording all remaining tricks.
	if state.completed_tricks.size() != 8:
		push_error("Refusing to score hand: exactly eight completed tricks are required.")
		return
	if not state.current_trick.is_empty():
		push_error("Refusing to score hand: a trick is still in progress.")
		return
	for seat in range(4):
		if not state.hands[seat].is_empty():
			push_error("Refusing to score hand: seat %d still has cards." % seat)
			return
	if state.team_card_points[0] + state.team_card_points[1] != 29:
		push_error("Refusing to score hand: card and last-trick points must total 29.")
		return

	var bidding_team: int = GameState.get_team(state.high_bidder_seat)
	var target: int = state.current_bid

	# Pair decisions are only offered after the holder's partnership wins a trick.
	var require_trick_for_pair: bool = bool(state.rule_config.get("pair_requires_trick_win", true))
	if state.pair_declared_by_team != -1:
		if not require_trick_for_pair or state.team_tricks_won[state.pair_declared_by_team] > 0:
			target = state.effective_contract_target

	var bidder_points: int = state.team_card_points[bidding_team]

	# A hidden trump suit does not by itself cause a contract forfeit.
	var forfeit_unrevealed: bool = bool(state.rule_config.get("forfeit_if_trump_unrevealed", false))
	var contract_succeeded: bool = (bidder_points >= target)
	if forfeit_unrevealed and not state.trump_revealed:
		contract_succeeded = false

	# Standard base stake is one game point, multiplied by Double/Redouble.
	var double_high_bids: bool = bool(state.rule_config.get("high_bid_double_stake", false))
	var base_stake: int = 2 if (double_high_bids and state.current_bid >= 28) else 1
	var game_point_delta: int = base_stake * state.stake_multiplier
	if not contract_succeeded:
		game_point_delta = -game_point_delta

	state.match_game_points[bidding_team] += game_point_delta

	state.last_hand_summary = {
		"hand_number": state.hand_number,
		"bidding_team": bidding_team,
		"high_bidder_seat": state.high_bidder_seat,
		"original_bid": state.current_bid,
		"final_target": target,
		"bidder_points": bidder_points,
		"defender_points": state.team_card_points[1 - bidding_team],
		"pair_declared_by_team": state.pair_declared_by_team,
		"pair_applied": (state.pair_declared_by_team != -1 and target == state.effective_contract_target),
		"trump_revealed": state.trump_revealed,
		"stake_multiplier": state.stake_multiplier,
		"contract_succeeded": contract_succeeded,
		"game_point_delta": game_point_delta,
		"match_game_points": state.match_game_points.duplicate()
	}

	if state.match_game_points[bidding_team] >= MATCH_WIN_TARGET:
		state.winning_team = bidding_team
		state.phase = GameState.Phase.MATCH_OVER
	elif state.match_game_points[bidding_team] <= MATCH_LOSS_THRESHOLD:
		state.winning_team = 1 - bidding_team
		state.phase = GameState.Phase.MATCH_OVER
	else:
		state.phase = GameState.Phase.HAND_SCORING

static func _player_has_suit(hand: Array, suit: int) -> bool:
	# GameState.hands is an Array of untyped nested Arrays. Accept Array here
	# and normalize each card ID before passing it into CardDefs.
	for raw_card in hand:
		if CardDefs.get_suit(int(raw_card)) == suit:
			return true
	return false

static func _process_safe_point_reclaims(state: GameState) -> void:
	for seat in range(4):
		if state.seat_pending_human_reclaim[seat] and state.is_safe_point_for_seat(seat):
			state.seat_is_ai[seat] = false
			state.seat_pending_human_reclaim[seat] = false
