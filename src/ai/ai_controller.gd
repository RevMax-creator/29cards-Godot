class_name AIController
extends RefCounted

enum Difficulty {
	CASUAL = 0,
	STANDARD = 1,
	MASTER = 2
}

## Computes the next authoritative action for an AI seat or generates a hint for a human player.
## Operates strictly on the sanitized player_view to guarantee zero hidden-information cheating.
static func choose_action(player_view: Dictionary, difficulty: int = Difficulty.STANDARD) -> Dictionary:
	var phase: int = int(player_view["phase"])
	var my_hand: Array[int] = []
	my_hand.assign(player_view["my_hand"])

	match phase:
		GameState.Phase.BIDDING:
			return _decide_bid(player_view, my_hand, difficulty)
		GameState.Phase.SET_HIDDEN_TRUMP:
			return _decide_trump_suit(my_hand)
		GameState.Phase.DOUBLE_DECISION:
			return _decide_double(player_view, my_hand, difficulty)
		GameState.Phase.REDOUBLE_DECISION:
			return _decide_redouble(player_view, my_hand)
		GameState.Phase.TRICK_PLAY:
			return _decide_trick_action(player_view, my_hand, difficulty)
		_:
			return {"type": "NONE"}

static func _decide_bid(view: Dictionary, hand: Array[int], difficulty: int) -> Dictionary:
	var current_bid: int = int(view["current_bid"])
	var high_bidder: int = int(view["high_bidder_seat"])
	var my_seat: int = int(view["viewer_seat"])

	var partner_holds_bid: bool = (high_bidder == GameState.get_partner(my_seat))
	var best_suit_eval: Dictionary = _evaluate_four_card_hand(hand)
	var estimated_ceiling: int = int(best_suit_eval["max_bid"])

	if difficulty == Difficulty.CASUAL:
		estimated_ceiling = mini(estimated_ceiling, 18)

	if partner_holds_bid and estimated_ceiling <= current_bid + 2:
		return {"type": "PASS_BID"}

	var next_bid: int = RulesEngine.MIN_BID if current_bid == 0 else current_bid + 1
	if next_bid <= estimated_ceiling and next_bid <= RulesEngine.MAX_BID:
		return {"type": "BID", "amount": next_bid}

	return {"type": "PASS_BID"}

static func _evaluate_four_card_hand(hand: Array[int]) -> Dictionary:
	var suit_scores: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var suit_counts: Array[int] = [0, 0, 0, 0]
	var total_high_points: int = 0

	for c in hand:
		var s: int = CardDefs.get_suit(c)
		var r: int = CardDefs.get_rank(c)
		suit_counts[s] += 1
		total_high_points += CardDefs.get_points(c)
		if r == CardDefs.Rank.JACK:
			suit_scores[s] += 4.5
		elif r == CardDefs.Rank.NINE:
			suit_scores[s] += 3.0
		elif r == CardDefs.Rank.ACE or r == CardDefs.Rank.TEN:
			suit_scores[s] += 1.5
		else:
			suit_scores[s] += 0.6

	var best_suit: int = 0
	var best_score: float = -1.0
	for s in range(4):
		var score: float = suit_scores[s] + float(suit_counts[s]) * 1.4
		if score > best_score:
			best_score = score
			best_suit = s

	var max_bid: int = 14
	if best_score >= 11.5:
		max_bid = 21
	elif best_score >= 9.5:
		max_bid = 19
	elif best_score >= 7.5:
		max_bid = 17
	elif best_score >= 6.0 and total_high_points >= 4:
		max_bid = 16

	return {"best_suit": best_suit, "max_bid": max_bid}

static func _decide_trump_suit(hand: Array[int]) -> Dictionary:
	var eval_res: Dictionary = _evaluate_four_card_hand(hand)
	return {"type": "SET_TRUMP", "suit": int(eval_res["best_suit"])}

static func _decide_double(view: Dictionary, hand: Array[int], difficulty: int) -> Dictionary:
	if difficulty == Difficulty.CASUAL:
		return {"type": "CALL_DOUBLE", "double": false}
	var jacks: int = 0
	var nines: int = 0
	for c in hand:
		var r: int = CardDefs.get_rank(c)
		if r == CardDefs.Rank.JACK:
			jacks += 1
		elif r == CardDefs.Rank.NINE:
			nines += 1
	var current_bid: int = int(view["current_bid"])
	var should_double: bool = (jacks >= 2 and nines >= 2) or (current_bid >= 21 and jacks >= 2)
	return {"type": "CALL_DOUBLE", "double": should_double}

static func _decide_redouble(view: Dictionary, hand: Array[int]) -> Dictionary:
	var trump_suit: int = int(view["visible_trump_suit"])
	var trump_count: int = 0
	var has_trump_jack: bool = false
	for c in hand:
		if CardDefs.get_suit(c) == trump_suit:
			trump_count += 1
			if CardDefs.get_rank(c) == CardDefs.Rank.JACK:
				has_trump_jack = true
	return {"type": "CALL_REDOUBLE", "redouble": (trump_count >= 5 and has_trump_jack)}

static func _decide_trick_action(view: Dictionary, hand: Array[int], difficulty: int) -> Dictionary:
	var my_seat: int = int(view["viewer_seat"])
	var trump_revealed: bool = bool(view["trump_revealed"])
	var visible_trump: int = int(view["visible_trump_suit"])
	var current_trick: Array = view["current_trick"]

	# 1. Check if we hold Pair (K + Q of revealed trump) and haven't declared it yet
	if trump_revealed and int(view["pair_declared_by_team"]) == -1 and visible_trump != CardDefs.Suit.NONE:
		var k_card: int = CardDefs.make_card(visible_trump, CardDefs.Rank.KING)
		var q_card: int = CardDefs.make_card(visible_trump, CardDefs.Rank.QUEEN)
		if hand.has(k_card) and hand.has(q_card):
			return {"type": "DECLARE_PAIR"}

	# 2. Check if void in led suit while trump is unrevealed
	if not current_trick.is_empty() and not trump_revealed:
		var led_suit: int = CardDefs.get_suit(int(current_trick[0]["card"]))
		var has_led: bool = false
		for c in hand:
			if CardDefs.get_suit(c) == led_suit:
				has_led = true
				break
		if not has_led:
			var trick_pts: int = 0
			for entry in current_trick:
				trick_pts += CardDefs.get_points(int(entry["card"]))
			var current_winner_seat: int = _get_current_trick_winner_from_view(current_trick, visible_trump, trump_revealed)
			var partner_winning: bool = (current_winner_seat == GameState.get_partner(my_seat))
			if not partner_winning and (trick_pts >= 2 or hand.size() <= 5):
				return {"type": "REQUEST_TRUMP_REVEAL"}

	# 3. Compute legal cards from player_view
	var legal_cards: Array[int] = _get_legal_cards_from_view(view, hand)
	if legal_cards.size() == 1:
		return {"type": "PLAY_CARD", "card": legal_cards[0]}

	if difficulty == Difficulty.MASTER:
		var best_ismcts_card: int = _run_determinized_rollouts(view, legal_cards, 24)
		return {"type": "PLAY_CARD", "card": best_ismcts_card}

	var chosen_card: int = _select_standard_card(view, legal_cards, difficulty)
	return {"type": "PLAY_CARD", "card": chosen_card}

static func _get_legal_cards_from_view(view: Dictionary, hand: Array[int]) -> Array[int]:
	var current_trick: Array = view["current_trick"]
	if current_trick.is_empty():
		return hand.duplicate()

	var led_suit: int = CardDefs.get_suit(int(current_trick[0]["card"]))
	var follow_cards: Array[int] = []
	for c in hand:
		if CardDefs.get_suit(c) == led_suit:
			follow_cards.append(c)
	if not follow_cards.is_empty():
		return follow_cards

	if bool(view["must_play_trump_this_turn"]) and bool(view["trump_revealed"]):
		var trump_suit: int = int(view["visible_trump_suit"])
		var trumps: Array[int] = []
		for c in hand:
			if CardDefs.get_suit(c) == trump_suit:
				trumps.append(c)
		if not trumps.is_empty():
			return trumps

	return hand.duplicate()

static func _select_standard_card(view: Dictionary, legal_cards: Array[int], difficulty: int) -> int:
	var my_seat: int = int(view["viewer_seat"])
	var current_trick: Array = view["current_trick"]
	var trump_revealed: bool = bool(view["trump_revealed"])
	var trump_suit: int = int(view["visible_trump_suit"]) if trump_revealed else CardDefs.Suit.NONE

	if current_trick.is_empty():
		for c in legal_cards:
			if CardDefs.get_rank(c) == CardDefs.Rank.JACK and CardDefs.get_suit(c) != trump_suit:
				return c
		var sorted: Array[int] = legal_cards.duplicate()
		sorted.sort_custom(func(a: int, b: int) -> bool:
			return CardDefs.get_points(a) < CardDefs.get_points(b)
		)
		return sorted[0]

	var led_suit: int = CardDefs.get_suit(int(current_trick[0]["card"]))
	var winning_seat: int = _get_current_trick_winner_from_view(current_trick, trump_suit, trump_revealed)
	var winning_card: int = _get_current_winning_card_from_view(current_trick, trump_suit, trump_revealed)
	var partner_is_winning: bool = (winning_seat == GameState.get_partner(my_seat))

	if partner_is_winning and (current_trick.size() == 3 or difficulty == Difficulty.STANDARD):
		var fattening: Array[int] = legal_cards.duplicate()
		fattening.sort_custom(func(a: int, b: int) -> bool:
			if CardDefs.get_points(a) != CardDefs.get_points(b):
				return CardDefs.get_points(a) > CardDefs.get_points(b)
			return CardDefs.get_rank(a) < CardDefs.get_rank(b)
		)
		for c in fattening:
			if not CardDefs.beats(c, winning_card, led_suit, trump_suit):
				return c

	var winning_candidates: Array[int] = []
	for c in legal_cards:
		if CardDefs.beats(c, winning_card, led_suit, trump_suit):
			winning_candidates.append(c)

	if not winning_candidates.is_empty():
		winning_candidates.sort_custom(func(a: int, b: int) -> bool:
			return CardDefs.get_rank(a) < CardDefs.get_rank(b)
		)
		return winning_candidates[0]

	var discards: Array[int] = legal_cards.duplicate()
	discards.sort_custom(func(a: int, b: int) -> bool:
		if CardDefs.get_points(a) != CardDefs.get_points(b):
			return CardDefs.get_points(a) < CardDefs.get_points(b)
		return CardDefs.get_rank(a) < CardDefs.get_rank(b)
	)
	return discards[0]

static func _run_determinized_rollouts(view: Dictionary, legal_cards: Array[int], num_rollouts: int) -> int:
	var scores: Dictionary = {}
	for c in legal_cards:
		scores[c] = 0.0

	var my_seat: int = int(view["viewer_seat"])
	var my_team: int = GameState.get_team(my_seat)

	for i in range(num_rollouts):
		var candidate_card: int = legal_cards[i % legal_cards.size()]
		var sim_state: GameState = _sample_determinized_state(view, i * 97 + 13)
		RulesEngine.apply_action(sim_state, my_seat, {"type": "PLAY_CARD", "card": candidate_card})

		var steps: int = 0
		while sim_state.phase == GameState.Phase.TRICK_PLAY and steps < 8:
			var turn_s: int = sim_state.current_turn_seat
			var turn_view: Dictionary = sim_state.build_player_view(turn_s)
			var turn_legal: Array[int] = RulesEngine.get_legal_cards(sim_state, turn_s)
			if turn_legal.is_empty():
				break
			var next_c: int = _select_standard_card(turn_view, turn_legal, Difficulty.STANDARD)
			RulesEngine.apply_action(sim_state, turn_s, {"type": "PLAY_CARD", "card": next_c})
			steps += 1

		var my_pts: float = float(sim_state.team_card_points[my_team])
		var opp_pts: float = float(sim_state.team_card_points[1 - my_team])
		scores[candidate_card] += (my_pts - opp_pts)

	var best_card: int = legal_cards[0]
	var best_val: float = -99999.0
	for c in legal_cards:
		if scores[c] > best_val:
			best_val = scores[c]
			best_card = c
	return best_card

static func _sample_determinized_state(view: Dictionary, seed_offset: int) -> GameState:
	var s := GameState.new()
	s.phase = GameState.Phase.TRICK_PLAY
	s.dealer_seat = int(view["dealer_seat"])
	s.current_turn_seat = int(view["current_turn_seat"])
	s.high_bidder_seat = int(view["high_bidder_seat"])
	s.current_bid = int(view["current_bid"])
	s.effective_contract_target = int(view["effective_contract_target"])
	s.trump_revealed = bool(view["trump_revealed"])
	s.must_play_trump_this_turn = bool(view["must_play_trump_this_turn"])
	s.trick_index = int(view["trick_index"])
	s.trick_leader_seat = int(view["trick_leader_seat"])
	s.current_trick.assign(view["current_trick"].duplicate(true))
	s.team_card_points.assign(view["team_card_points"].duplicate())
	s.team_tricks_won.assign(view["team_tricks_won"].duplicate())

	var viewer_seat: int = int(view["viewer_seat"])
	var known_cards: Dictionary = {}
	for c in view["my_hand"]:
		known_cards[int(c)] = true
	for entry in s.current_trick:
		known_cards[int(entry["card"])] = true

	var unknown_pool: Array[int] = []
	for c in CardDefs.build_full_deck():
		if not known_cards.has(c):
			unknown_pool.append(c)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_offset + s.trick_index * 31
	for i in range(unknown_pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = unknown_pool[i]
		unknown_pool[i] = unknown_pool[j]
		unknown_pool[j] = tmp

	# Sample hidden trump without bias when unknown to viewer:
	# picking the suit of a randomly drawn unseen card weights suits naturally by how few cards the viewer holds in that suit.
	var vis_trump: int = int(view["visible_trump_suit"])
	if vis_trump != CardDefs.Suit.NONE:
		s.hidden_trump_suit = vis_trump
	elif not unknown_pool.is_empty():
		s.hidden_trump_suit = CardDefs.get_suit(unknown_pool[0])
	else:
		s.hidden_trump_suit = rng.randi_range(0, 3)

	var hand_counts: Array = view["hand_counts"]
	var pool_cursor: int = 0
	s.hands = [[], [], [], []]
	for seat in range(4):
		if seat == viewer_seat:
			var my_h: Array[int] = []
			my_h.assign(view["my_hand"])
			s.hands[seat] = my_h
		else:
			var count: int = int(hand_counts[seat])
			var opp_h: Array[int] = []
			for k in range(count):
				if pool_cursor < unknown_pool.size():
					opp_h.append(unknown_pool[pool_cursor])
					pool_cursor += 1
			s.hands[seat] = opp_h
	return s

static func _get_current_trick_winner_from_view(trick: Array, trump_suit: int, trump_revealed: bool) -> int:
	var led_suit: int = CardDefs.get_suit(int(trick[0]["card"]))
	var best_entry: Dictionary = trick[0]
	var active_trump: int = trump_suit if trump_revealed else CardDefs.Suit.NONE
	for i in range(1, trick.size()):
		var entry: Dictionary = trick[i]
		if CardDefs.beats(int(entry["card"]), int(best_entry["card"]), led_suit, active_trump):
			best_entry = entry
	return int(best_entry["seat"])

static func _get_current_winning_card_from_view(trick: Array, trump_suit: int, trump_revealed: bool) -> int:
	var led_suit: int = CardDefs.get_suit(int(trick[0]["card"]))
	var best_card: int = int(trick[0]["card"])
	var active_trump: int = trump_suit if trump_revealed else CardDefs.Suit.NONE
	for i in range(1, trick.size()):
		var c: int = int(trick[i]["card"])
		if CardDefs.beats(c, best_card, led_suit, active_trump):
			best_card = c
	return best_card