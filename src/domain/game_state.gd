class_name GameState
extends RefCounted

enum Phase {
	WAITING_FOR_PLAYERS = 0,
	DEAL_FIRST_FOUR = 1,
	BIDDING = 2,
	SET_HIDDEN_TRUMP = 3,
	DEAL_SECOND_FOUR = 4,
	DOUBLE_DECISION = 5,
	REDOUBLE_DECISION = 6,
	TRICK_PLAY = 7,
	HAND_SCORING = 8,
	MATCH_OVER = 9,
	PAIR_DECISION = 10
}

enum StakeMultiplier {
	NORMAL = 1,
	DOUBLED = 2,
	REDOUBLED = 4
}

## Standard ruleset flags derived from the supplied 29 rules reference.
var rule_config: Dictionary = {
	"clamp_pair_target": true,
	"pair_requires_trick_win": true,
	"forfeit_if_trump_unrevealed": false,
	"auto_redeal_invalid_hands": false,
	"high_bid_double_stake": false
}

var session_id: String = ""
var state_revision: int = 0
var match_seed: int = 0
var hand_number: int = 0
var phase: int = Phase.WAITING_FOR_PLAYERS

# True while the currently dealt batch is still being animated by the host UI.
# No player (including AI) may act until the host completes this visual barrier.
var deal_animation_pending: bool = false

# Seating & Partnerships: Team 0 = Seats [0, 2], Team 1 = Seats [1, 3]
var dealer_seat: int = 0
var current_turn_seat: int = 0
var seat_is_ai: Array[bool] = [false, true, true, true]
var seat_pending_human_reclaim: Array[bool] = [false, false, false, false]

# Deck & Private Hands (Strictly Host-Only)
var stock_deck: Array[int] = []
var hands: Array = [[], [], [], []] # Array of 4 Array[int]

# Bidding State
var current_bid: int = 0
var high_bidder_seat: int = -1
var passed_seats: Array[bool] = [false, false, false, false]
var bidding_history: Array[Dictionary] = []

# Trump State (Concealed suit model)
var hidden_trump_suit: int = CardDefs.Suit.NONE
var trump_revealed: bool = false
var trump_revealed_on_trick: int = -1
var trump_revealed_by_seat: int = -1
var must_play_trump_this_turn: bool = false

# Pair (Marriage) State
var pair_declared_by_team: int = -1 # -1 = None, 0 = Team 0, 1 = Team 1
var effective_contract_target: int = 0

# Double / Redouble State
var stake_multiplier: int = StakeMultiplier.NORMAL
var double_decided_by_defenders: Dictionary = {} # seat_id -> bool

# Trick Play State
var trick_index: int = 0 # 0..7
var trick_leader_seat: int = 0
var current_trick: Array[Dictionary] = [] # [{ "seat": int, "card": int, "trump_active": bool }]
var completed_tricks: Array[Dictionary] = []
var team_card_points: Array[int] = [0, 0]
var team_tricks_won: Array[int] = [0, 0]

# Match Score State (+6 Wins, -6 Loses)
var match_game_points: Array[int] = [0, 0]
var winning_team: int = -1
var last_hand_summary: Dictionary = {}

static func get_team(seat: int) -> int:
	return seat % 2

static func get_partner(seat: int) -> int:
	return (seat + 2) % 4

## Determines whether human control can safely replace AI control without rolling back actions.
func is_safe_point_for_seat(seat: int) -> bool:
	if phase in [Phase.HAND_SCORING, Phase.MATCH_OVER, Phase.WAITING_FOR_PLAYERS]:
		return true
	if phase == Phase.TRICK_PLAY and current_trick.is_empty():
		return true
	if phase == Phase.PAIR_DECISION:
		return true
	if current_turn_seat != seat and phase in [
		Phase.BIDDING,
		Phase.SET_HIDDEN_TRUMP,
		Phase.DOUBLE_DECISION,
		Phase.REDOUBLE_DECISION
	]:
		return true
	return false

## Produces a strictly sanitized state projection for a specific seat.
## NEVER includes other players' hands, stock_deck, or unrevealed hidden_trump_suit for non-bidders.
func build_player_view(viewer_seat: int) -> Dictionary:
	var hand_counts: Array[int] = [
		hands[0].size(),
		hands[1].size(),
		hands[2].size(),
		hands[3].size()
	]
	var visible_trump: int = CardDefs.Suit.NONE
	if trump_revealed or (viewer_seat == high_bidder_seat and hidden_trump_suit != CardDefs.Suit.NONE):
		visible_trump = hidden_trump_suit
	var last_trick_winner_team: int = -1
	var seat_card_points: Array[int] = [0, 0, 0, 0]
	if not completed_tricks.is_empty():
		var last_completed: Dictionary = completed_tricks[completed_tricks.size() - 1]
		last_trick_winner_team = int(last_completed.get("winner_team", -1))

	for trick_record in completed_tricks:
		var winner_seat: int = int(trick_record.get("winner_seat", -1))
		if winner_seat >= 0 and winner_seat < 4:
			seat_card_points[winner_seat] += int(trick_record.get("points", 0))

	return {
		"session_id": session_id,
		"state_revision": state_revision,
		"hand_number": hand_number,
		"phase": phase,
		"deal_animation_pending": deal_animation_pending,
		"dealer_seat": dealer_seat,
		"current_turn_seat": current_turn_seat,
		"viewer_seat": viewer_seat,
		"my_hand": hands[viewer_seat].duplicate(),
		"hand_counts": hand_counts,
		"seat_is_ai": seat_is_ai.duplicate(),
		"seat_pending_human_reclaim": seat_pending_human_reclaim.duplicate(),
		"current_bid": current_bid,
		"high_bidder_seat": high_bidder_seat,
		"passed_seats": passed_seats.duplicate(),
		"bidding_history": bidding_history.duplicate(true),
		"trump_revealed": trump_revealed,
		"trump_selected": hidden_trump_suit != CardDefs.Suit.NONE,
		"visible_trump_suit": visible_trump,
		"must_play_trump_this_turn": must_play_trump_this_turn if viewer_seat == current_turn_seat else false,
		"pair_declared_by_team": pair_declared_by_team,
		"effective_contract_target": effective_contract_target,
		"stake_multiplier": stake_multiplier,
		"trick_index": trick_index,
		"trick_leader_seat": trick_leader_seat,
		"current_trick": current_trick.duplicate(true),
		"completed_tricks": completed_tricks.duplicate(true),
		"completed_tricks_count": completed_tricks.size(),
		"last_trick_winner_team": last_trick_winner_team,
		"pair_declaration_window_open": phase == Phase.PAIR_DECISION and pair_declared_by_team == -1,
		"team_card_points": team_card_points.duplicate(),
		"seat_card_points": seat_card_points,
		"team_tricks_won": team_tricks_won.duplicate(),
		"match_game_points": match_game_points.duplicate(),
		"winning_team": winning_team,
		"last_hand_summary": last_hand_summary.duplicate(true)
	}

func to_authoritative_dict() -> Dictionary:
	return {
		"rule_config": rule_config.duplicate(),
		"session_id": session_id,
		"state_revision": state_revision,
		"match_seed": match_seed,
		"hand_number": hand_number,
		"phase": phase,
		"deal_animation_pending": deal_animation_pending,
		"dealer_seat": dealer_seat,
		"current_turn_seat": current_turn_seat,
		"seat_is_ai": seat_is_ai.duplicate(),
		"seat_pending_human_reclaim": seat_pending_human_reclaim.duplicate(),
		"stock_deck": stock_deck.duplicate(),
		"hands": hands.duplicate(true),
		"current_bid": current_bid,
		"high_bidder_seat": high_bidder_seat,
		"passed_seats": passed_seats.duplicate(),
		"bidding_history": bidding_history.duplicate(true),
		"hidden_trump_suit": hidden_trump_suit,
		"trump_revealed": trump_revealed,
		"trump_revealed_on_trick": trump_revealed_on_trick,
		"trump_revealed_by_seat": trump_revealed_by_seat,
		"must_play_trump_this_turn": must_play_trump_this_turn,
		"pair_declared_by_team": pair_declared_by_team,
		"effective_contract_target": effective_contract_target,
		"stake_multiplier": stake_multiplier,
		"double_decided_by_defenders": double_decided_by_defenders.duplicate(),
		"trick_index": trick_index,
		"trick_leader_seat": trick_leader_seat,
		"current_trick": current_trick.duplicate(true),
		"completed_tricks": completed_tricks.duplicate(true),
		"team_card_points": team_card_points.duplicate(),
		"team_tricks_won": team_tricks_won.duplicate(),
		"match_game_points": match_game_points.duplicate(),
		"winning_team": winning_team,
		"last_hand_summary": last_hand_summary.duplicate(true)
	}

static func from_authoritative_dict(data: Dictionary) -> GameState:
	var s := GameState.new()
	if data.has("rule_config") and typeof(data["rule_config"]) == TYPE_DICTIONARY:
		for k in data["rule_config"].keys():
			s.rule_config[k] = data["rule_config"][k]
	# The uploaded rules are the standard ruleset. Do not let older M1 saves
	# silently restore the superseded unbounded Pair calculation.
	s.rule_config["clamp_pair_target"] = true
	s.rule_config["pair_requires_trick_win"] = true

	s.session_id = str(data.get("session_id", ""))
	s.state_revision = int(data.get("state_revision", 0))
	s.match_seed = int(data.get("match_seed", 0))
	s.hand_number = int(data.get("hand_number", 0))
	s.phase = int(data.get("phase", Phase.WAITING_FOR_PLAYERS))
	# Older saves predate this flag and already represent completed visible deals.
	s.deal_animation_pending = bool(data.get("deal_animation_pending", false))
	s.dealer_seat = int(data.get("dealer_seat", 0))
	s.current_turn_seat = int(data.get("current_turn_seat", 0))

	s.seat_is_ai.assign(data.get("seat_is_ai", [false, true, true, true]))
	s.seat_pending_human_reclaim.assign(data.get("seat_pending_human_reclaim", [false, false, false, false]))
	s.stock_deck.assign(data.get("stock_deck", []))

	var raw_hands: Array = data.get("hands", [[], [], [], []])
	s.hands = [[], [], [], []]
	for i in range(4):
		var h: Array[int] = []
		h.assign(raw_hands[i])
		s.hands[i] = h

	s.current_bid = int(data.get("current_bid", 0))
	if s.phase not in [Phase.HAND_SCORING, Phase.MATCH_OVER] and s.current_bid > 28:
		s.current_bid = 28
	s.high_bidder_seat = int(data.get("high_bidder_seat", -1))
	s.passed_seats.assign(data.get("passed_seats", [false, false, false, false]))
	s.bidding_history.assign(data.get("bidding_history", []))
	s.hidden_trump_suit = int(data.get("hidden_trump_suit", CardDefs.Suit.NONE))
	s.trump_revealed = bool(data.get("trump_revealed", false))
	s.trump_revealed_on_trick = int(data.get("trump_revealed_on_trick", -1))
	s.trump_revealed_by_seat = int(data.get("trump_revealed_by_seat", -1))
	s.must_play_trump_this_turn = bool(data.get("must_play_trump_this_turn", false))
	s.pair_declared_by_team = int(data.get("pair_declared_by_team", -1))
	s.effective_contract_target = int(data.get("effective_contract_target", 0))
	s.stake_multiplier = int(data.get("stake_multiplier", StakeMultiplier.NORMAL))
	s.double_decided_by_defenders = data.get("double_decided_by_defenders", {}).duplicate()
	s.trick_index = int(data.get("trick_index", 0))
	s.trick_leader_seat = int(data.get("trick_leader_seat", 0))
	s.current_trick.assign(data.get("current_trick", []))
	s.completed_tricks.assign(data.get("completed_tricks", []))
	s.team_card_points.assign(data.get("team_card_points", [0, 0]))
	s.team_tricks_won.assign(data.get("team_tricks_won", [0, 0]))
	s.match_game_points.assign(data.get("match_game_points", [0, 0]))
	s.winning_team = int(data.get("winning_team", -1))
	s.last_hand_summary = data.get("last_hand_summary", {}).duplicate(true)
	if s.pair_declared_by_team != -1 and s.high_bidder_seat >= 0:
		var bidding_team: int = get_team(s.high_bidder_seat)
		if s.pair_declared_by_team == bidding_team:
			s.effective_contract_target = maxi(15, s.current_bid - 4)
		else:
			s.effective_contract_target = mini(28, s.current_bid + 4)
	return s