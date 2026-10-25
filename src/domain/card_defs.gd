class_name CardDefs
extends RefCounted

enum Suit {
	NONE = -1,
	SPADES = 0,
	HEARTS = 1,
	CLUBS = 2,
	DIAMONDS = 3
}

## Ordered from lowest trick-taking power (0) to highest trick-taking power (7)
enum Rank {
	SEVEN = 0,
	EIGHT = 1,
	QUEEN = 2,
	KING = 3,
	TEN = 4,
	ACE = 5,
	NINE = 6,
	JACK = 7
}

const SUIT_NAMES: Dictionary = {
	Suit.SPADES: "Spades",
	Suit.HEARTS: "Hearts",
	Suit.CLUBS: "Clubs",
	Suit.DIAMONDS: "Diamonds"
}

const SUIT_SYMBOLS: Dictionary = {
	Suit.SPADES: "♠",
	Suit.HEARTS: "♥",
	Suit.CLUBS: "♣",
	Suit.DIAMONDS: "♦"
}

const RANK_LABELS: Dictionary = {
	Rank.SEVEN: "7",
	Rank.EIGHT: "8",
	Rank.QUEEN: "Q",
	Rank.KING: "K",
	Rank.TEN: "10",
	Rank.ACE: "A",
	Rank.NINE: "9",
	Rank.JACK: "J"
}

const CARD_POINTS: Dictionary = {
	Rank.JACK: 3,
	Rank.NINE: 2,
	Rank.ACE: 1,
	Rank.TEN: 1,
	Rank.KING: 0,
	Rank.QUEEN: 0,
	Rank.EIGHT: 0,
	Rank.SEVEN: 0
}

## Compact integer encoding: card_id = suit * 8 + rank (0..31)
static func make_card(suit: int, rank: int) -> int:
	assert(suit >= Suit.SPADES and suit <= Suit.DIAMONDS, "Invalid suit")
	assert(rank >= Rank.SEVEN and rank <= Rank.JACK, "Invalid rank")
	return suit * 8 + rank

static func get_suit(card_id: int) -> int:
	return int(card_id / 8)

static func get_rank(card_id: int) -> int:
	return card_id % 8

static func get_points(card_id: int) -> int:
	return CARD_POINTS.get(get_rank(card_id), 0)

static func format_card(card_id: int) -> String:
	if card_id < 0 or card_id > 31:
		return "??"
	return "%s%s" % [RANK_LABELS[get_rank(card_id)], SUIT_SYMBOLS[get_suit(card_id)]]

static func build_full_deck() -> Array[int]:
	var deck: Array[int] = []
	for s in range(4):
		for r in range(8):
			deck.append(make_card(s, r))
	return deck

## Evaluates whether challenger_card beats current_best_card given led_suit and active_trump
static func beats(challenger_card: int, current_best_card: int, led_suit: int, active_trump: int) -> bool:
	var c_suit: int = get_suit(challenger_card)
	var b_suit: int = get_suit(current_best_card)
	var c_rank: int = get_rank(challenger_card)
	var b_rank: int = get_rank(current_best_card)

	var c_is_trump: bool = (active_trump != Suit.NONE) and (c_suit == active_trump)
	var b_is_trump: bool = (active_trump != Suit.NONE) and (b_suit == active_trump)

	if c_is_trump and not b_is_trump:
		return true
	if not c_is_trump and b_is_trump:
		return false
	if c_is_trump and b_is_trump:
		return c_rank > b_rank

	# Neither is active trump
	if c_suit == led_suit and b_suit != led_suit:
		return true
	if c_suit == b_suit:
		return c_rank > b_rank
	return false