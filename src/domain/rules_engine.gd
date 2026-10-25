class_name RulesEngine
extends RefCounted

const MIN_BID: int = 15
const MAX_BID: int = 29
const PAIR_DELTA: int = 4
const MATCH_WIN_TARGET: int = 6
const MATCH_LOSS_THRESHOLD: int = -6

## Starts a new hand with a deterministic seed, dealing the first 4 cards to each player.
## When invoked internally by an action handler (such as all-pass redeal), increment_revision is set to false
## so apply_action() increments state_revision exactly once.
static func start_new_hand(state: GameState, dealer: int, seed_val: int, increment_revision: bool = true) -> Dictionary:
	state.hand_number += 1
	state.dealer_seat = posmod(dealer, 4)
	state.current_turn_seat = (state.dealer_seat + 1) % 4
	state.phase = GameState.Phase.BIDDING

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

	state.hands = [[], [], [], []]
	for seat in range(4):
		var first_four: Array[int] = []
		for c_idx in range(4):
			first_four.append(deck[seat * 4 + c_idx])
		first_four.sort()
		state.hands[seat] = first_four

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
		"PLAY_CARD":
			result = _handle_play_card(state, seat, int(action.get("card", -1)))
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

	var min_allowed: int = MIN_BID if state.current_bid == 0 else state.current_bid + 1
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

	state.passed_seats[seat] = true
	state.bidding_history.append({"seat": seat, "type": "PASS"})

	var pass_count: int = 0
	for p in state.passed_seats:
		if p:
			pass_count += 1

	# Approved All-Pass Rule: all 4 players pass with no opening bid -> rotate dealer clockwise and redeal
	if pass_count == 4 and state.high_bidder_seat == -1:
		var next_dealer: int = (state.dealer_seat + 1) % 4
		start_new_hand(state, next_dealer, state.match_seed + 101, false)
		return {"ok": true, "event": "all_pass_redeal", "new_dealer": next_dealer}

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

	# Deal second batch of 4 cards per player (completing 8 cards per player)
	for s in range(4):
		var hand_ref: Array[int] = state.hands[s]
		for c_idx in range(4):
			hand_ref.append(state.stock_deck[s * 4 + c_idx])
		hand_ref.sort()
	state.stock_deck.clear()

	# Provisional Decision #6: Do NOT automatically cancel deals unless explicitly enabled in rule_config
	if bool(state.rule_config.get("auto_redeal_invalid_hands", false)) and _is_invalid_full_deal(state):
		var same_dealer: int = state.dealer_seat
		start_new_hand(state, same_dealer, state.match_seed + 307, false)
		return {"ok": true, "event": "invalid_deal_auto_redeal"}

	state.phase = GameState.Phase.DOUBLE_DECISION
	state.double_decided_by_defenders.clear()
	state.current_turn_seat = _first_defender_after_bidder(state.high_bidder_seat)
	return {"ok": true, "event": "trump_set_and_second_deal_complete"}

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

	_begin_trick_play(state)
	return {"ok": true, "event": "trick_play_started"}

static func _handle_redouble_call(state: GameState, seat: int, call_redouble: bool) -> Dictionary:
	if state.phase != GameState.Phase.REDOUBLE_DECISION:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if seat != state.high_bidder_seat:
		return {"ok": false, "error": "ERR_ONLY_BIDDER_DECIDES_REDOUBLE"}

	if call_redouble:
		state.stake_multiplier = GameState.StakeMultiplier.REDOUBLED

	_begin_trick_play(state)
	return {"ok": true, "event": "redouble_resolved", "redoubled": call_redouble}

static func _begin_trick_play(state: GameState) -> void:
	state.phase = GameState.Phase.TRICK_PLAY
	state.trick_index = 0
	state.trick_leader_seat = (state.dealer_seat + 1) % 4
	state.current_turn_seat = state.trick_leader_seat
	state.current_trick.clear()
	state.must_play_trump_this_turn = false

static func _handle_request_trump_reveal(state: GameState, seat: int) -> Dictionary:
	if state.phase != GameState.Phase.TRICK_PLAY:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}
	if state.trump_revealed:
		return {"ok": false, "error": "ERR_TRUMP_ALREADY_REVEALED"}
	if state.current_trick.is_empty():
		return {"ok": false, "error": "ERR_CANNOT_REVEAL_ON_TRICK_LEAD"}

	var led_suit: int = CardDefs.get_suit(int(state.current_trick[0]["card"]))
	if _player_has_suit(state.hands[seat], led_suit):
		return {"ok": false, "error": "ERR_MUST_FOLLOW_LED_SUIT"}

	state.trump_revealed = true
	state.trump_revealed_on_trick = state.trick_index
	state.trump_revealed_by_seat = seat
	# Provisional Decision #3: Once a player requests revelation, they must play trump on that trick if they hold it
	state.must_play_trump_this_turn = _player_has_suit(state.hands[seat], state.hidden_trump_suit)

	return {
		"ok": true,
		"event": "trump_revealed",
		"trump_suit": state.hidden_trump_suit,
		"by_seat": seat,
		"must_play_trump": state.must_play_trump_this_turn
	}

static func _handle_declare_pair(state: GameState, seat: int) -> Dictionary:
	if state.phase != GameState.Phase.TRICK_PLAY:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}
	if not state.trump_revealed:
		return {"ok": false, "error": "ERR_TRUMP_NOT_REVEALED"}
	if state.pair_declared_by_team != -1:
		return {"ok": false, "error": "ERR_PAIR_ALREADY_DECLARED"}

	# Provisional Decision #4: One player must hold both K and Q of trump still in hand
	var king_trump: int = CardDefs.make_card(state.hidden_trump_suit, CardDefs.Rank.KING)
	var queen_trump: int = CardDefs.make_card(state.hidden_trump_suit, CardDefs.Rank.QUEEN)
	var hand: Array[int] = []
	for raw_card in state.hands[seat]:
		hand.append(int(raw_card))
	if not (hand.has(king_trump) and hand.has(queen_trump)):
		return {"ok": false, "error": "ERR_DOES_NOT_HOLD_TRUMP_PAIR"}

	var declaring_team: int = GameState.get_team(seat)
	var bidding_team: int = GameState.get_team(state.high_bidder_seat)
	state.pair_declared_by_team = declaring_team

	# Provisional Decision #1: Exact arithmetic without clamping (unless clamp_pair_target is explicitly enabled)
	var clamp_enabled: bool = bool(state.rule_config.get("clamp_pair_target", false))
	if declaring_team == bidding_team:
		var raw_low: int = state.current_bid - PAIR_DELTA
		state.effective_contract_target = maxi(MIN_BID, raw_low) if clamp_enabled else raw_low
	else:
		var raw_high: int = state.current_bid + PAIR_DELTA
		var ceiling_val: int = 29 if state.current_bid == 29 else 28
		state.effective_contract_target = mini(ceiling_val, raw_high) if clamp_enabled else raw_high

	return {
		"ok": true,
		"event": "pair_declared",
		"by_seat": seat,
		"team": declaring_team,
		"effective_contract_target": state.effective_contract_target
	}

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

	# Void in led suit: if player just requested trump revelation and holds trump, must play trump
	if state.must_play_trump_this_turn and state.trump_revealed:
		var trump_cards: Array[int] = []
		for c in hand:
			if CardDefs.get_suit(c) == state.hidden_trump_suit:
				trump_cards.append(c)
		if not trump_cards.is_empty():
			return trump_cards

	return hand.duplicate()

static func _handle_play_card(state: GameState, seat: int, card_id: int) -> Dictionary:
	if state.phase != GameState.Phase.TRICK_PLAY:
		return {"ok": false, "error": "ERR_WRONG_PHASE"}
	if state.current_turn_seat != seat:
		return {"ok": false, "error": "ERR_OUT_OF_TURN"}

	var legal_cards: Array[int] = get_legal_cards(state, seat)
	if not legal_cards.has(card_id):
		return {"ok": false, "error": "ERR_ILLEGAL_CARD_PLAY"}

	state.hands[seat].erase(card_id)
	# Provisional Decision #3: Record whether trump was revealed at the moment this card was played.
	# Cards of hidden_trump_suit played before revelation have trump_active = false (zero cutting power).
	state.current_trick.append({
		"seat": seat,
		"card": card_id,
		"trump_active": state.trump_revealed
	})
	state.must_play_trump_this_turn = false

	if state.current_trick.size() < 4:
		state.current_turn_seat = (seat + 1) % 4
		return {"ok": true, "event": "card_played", "seat": seat, "card": card_id}

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

	if state.trick_index < 7:
		state.trick_index += 1
		state.trick_leader_seat = winner_seat
		state.current_turn_seat = winner_seat
		return {
			"ok": true,
			"event": "trick_completed",
			"winner_seat": winner_seat,
			"points": trick_points
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

static func _score_completed_hand(state: GameState) -> void:
	var bidding_team: int = GameState.get_team(state.high_bidder_seat)
	var target: int = state.current_bid

	# Provisional Decision #4: Pair adjustment counts only if declaring partnership won >= 1 trick
	var require_trick_for_pair: bool = bool(state.rule_config.get("pair_requires_trick_win", true))
	if state.pair_declared_by_team != -1:
		if not require_trick_for_pair or state.team_tricks_won[state.pair_declared_by_team] > 0:
			target = state.effective_contract_target

	var bidder_points: int = state.team_card_points[bidding_team]

	# Provisional Decision #5: Score normally even if trump was never revealed
	var forfeit_unrevealed: bool = bool(state.rule_config.get("forfeit_if_trump_unrevealed", false))
	var contract_succeeded: bool = (bidder_points >= target)
	if forfeit_unrevealed and not state.trump_revealed:
		contract_succeeded = false

	# No special 28/29 double base stake unless explicitly configured
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
		"pair_applied": (target != state.current_bid),
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

static func _player_has_suit(hand: Array[int], suit: int) -> bool:
	for c in hand:
		if CardDefs.get_suit(c) == suit:
			return true
	return false

static func _process_safe_point_reclaims(state: GameState) -> void:
	for seat in range(4):
		if state.seat_pending_human_reclaim[seat] and state.is_safe_point_for_seat(seat):
			state.seat_is_ai[seat] = false
			state.seat_pending_human_reclaim[seat] = false
