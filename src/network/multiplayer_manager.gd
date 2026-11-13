extends Node

signal player_view_updated(player_view: Dictionary)
signal action_rejected(error_code: String)
signal host_migration_started(new_host_seat: int)
signal host_migration_completed(new_host_seat: int)
signal seat_connection_changed(seat: int, is_connected_human: bool)

const GAME_PORT: int = 29030
const NON_TRICK_GRACE_SEC: float = 8.0
const AI_THINK_DELAY_SEC: float = 0.55

var is_offline_solo: bool = true
var is_authoritative_host: bool = true
var local_seat: int = 0
var ai_difficulty: int = AIController.Difficulty.STANDARD
var active_host_seat: int = 0
# var ai_difficulty: int = AIController.Difficulty.TACTICAL

# Host-Only Authoritative State
var authoritative_state: GameState = null
var _processed_action_tokens: Dictionary = {} # token -> state_revision
var _seat_to_peer_id: Dictionary = {0: 1}
var _peer_id_to_seat: Dictionary = {1: 0}
var _seat_reconnect_tokens: Dictionary = {}
var _disconnect_grace_timers: Dictionary = {} # seat -> remaining_seconds

# Client-Side Cached State & Migration Shares
var latest_player_view: Dictionary = {}
var _cached_encrypted_envelope: Dictionary = {}
var _cached_my_key_share: Dictionary = {}
var _migration_collected_shares: Array[Dictionary] = []
var _ai_turn_cooldown: float = 0.0

func start_solo_ai_match(difficulty: int, resume_saved: bool = false) -> void:
	is_offline_solo = true
	is_authoritative_host = true
	local_seat = 0
	active_host_seat = 0
	ai_difficulty = difficulty

	if resume_saved and SaveManager.has_valid_solo_save():
		authoritative_state = SaveManager.load_solo_save()
	else:
		authoritative_state = GameState.new()
		authoritative_state.session_id = "SOLO_%d" % Time.get_unix_time_from_system()
		authoritative_state.match_seed = int(Time.get_unix_time_from_system())
		authoritative_state.seat_is_ai = [false, true, true, true]
		var dealer_rng := RandomNumberGenerator.new()
		dealer_rng.seed = authoritative_state.match_seed ^ 0x29A11
		var initial_dealer: int = dealer_rng.randi_range(0, 3)
		RulesEngine.start_new_hand(authoritative_state, initial_dealer, authoritative_state.match_seed)

	_broadcast_state_from_host()

func host_multiplayer_room() -> Error:
	is_offline_solo = false
	is_authoritative_host = true
	local_seat = 0
	active_host_seat = 0

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(GAME_PORT, 4)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_bind_multiplayer_signals()

	authoritative_state = GameState.new()
	authoritative_state.session_id = "MP_%d" % randi()
	authoritative_state.match_seed = int(Time.get_unix_time_from_system())
	authoritative_state.seat_is_ai = [false, true, true, true]
	_seat_to_peer_id = {0: 1}
	_peer_id_to_seat = {1: 0}
	return OK

func join_multiplayer_room(host_ip: String, reconnect_token: String = "") -> Error:
	is_offline_solo = false
	is_authoritative_host = false

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(host_ip, GAME_PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_bind_multiplayer_signals()
	return OK

func submit_local_action(action: Dictionary) -> void:
	var envelope: Dictionary = {
		"session_id": latest_player_view.get("session_id", ""),
		"seat": local_seat,
		"expected_revision": int(latest_player_view.get("state_revision", 0)),
		"action_token": "%d_%d_%d" % [local_seat, Time.get_ticks_usec(), randi()],
		"action": action
	}
	if is_authoritative_host:
		_process_authoritative_action_envelope(envelope)
	else:
		_rpc_submit_action.rpc_id(1, envelope)

func _process(delta: float) -> void:
	if not is_authoritative_host or authoritative_state == null:
		return

	# 1. Tick disconnect grace timers for non-trick phases
	var expired_seats: Array[int] = []
	for seat in _disconnect_grace_timers.keys():
		_disconnect_grace_timers[seat] -= delta
		if _disconnect_grace_timers[seat] <= 0.0:
			expired_seats.append(int(seat))
	for seat in expired_seats:
		_disconnect_grace_timers.erase(seat)
		authoritative_state.seat_is_ai[seat] = true
		_broadcast_state_from_host()

	# 2. Do not let the authoritative AI play ahead of the visual deal.
	# The deal animation can take longer than AI_THINK_DELAY_SEC.
	if authoritative_state.deal_animation_pending:
		_ai_turn_cooldown = 0.0
		return

	# 3. Drive AI turns
	if authoritative_state.phase in [
		GameState.Phase.BIDDING,
		GameState.Phase.SET_HIDDEN_TRUMP,
		GameState.Phase.DOUBLE_DECISION,
		GameState.Phase.REDOUBLE_DECISION,
		GameState.Phase.PAIR_DECISION,
		GameState.Phase.TRICK_PLAY
	]:
		var turn_seat: int = authoritative_state.current_turn_seat
		if authoritative_state.phase == GameState.Phase.REDOUBLE_DECISION:
			var declaring_team: int = GameState.get_team(authoritative_state.high_bidder_seat)
			var has_human_declaring_player: bool = false
			for candidate_seat in range(4):
				if GameState.get_team(candidate_seat) == declaring_team and not authoritative_state.seat_is_ai[candidate_seat] and not _disconnect_grace_timers.has(candidate_seat):
					has_human_declaring_player = true
					break
			if has_human_declaring_player:
				_ai_turn_cooldown = 0.0
				return
			# With no human on the declaring partnership, the high bidder AI
			# makes the Redouble decision using its private trump knowledge.
			turn_seat = authoritative_state.high_bidder_seat
		if authoritative_state.seat_is_ai[turn_seat] and not _disconnect_grace_timers.has(turn_seat):
			_ai_turn_cooldown += delta
			if _ai_turn_cooldown >= AI_THINK_DELAY_SEC:
				_ai_turn_cooldown = 0.0
				var ai_view: Dictionary = authoritative_state.build_player_view(turn_seat)
				ai_view["tram_available"] = RulesEngine.can_call_tram(authoritative_state, turn_seat)
				var ai_action: Dictionary = AIController.choose_action(ai_view, ai_difficulty)
				if ai_action.get("type", "NONE") != "NONE":
					var res: Dictionary = RulesEngine.apply_action(authoritative_state, turn_seat, ai_action)
					if res.get("ok", false):
						_broadcast_state_from_host()

## The table calls this only after its complete clockwise deal queue has
## finished. Only the authoritative host may clear the game-state deal barrier.
func notify_local_deal_animation_completed() -> void:
	if not is_authoritative_host or authoritative_state == null:
		return
	if not authoritative_state.deal_animation_pending:
		return
	var completion: Dictionary = RulesEngine.complete_deal_animation(authoritative_state)
	if not bool(completion.get("ok", false)):
		push_warning("Deal animation completion was rejected: %s" % str(completion))
		return
	_broadcast_state_from_host()


func _process_authoritative_action_envelope(envelope: Dictionary) -> void:
	if authoritative_state == null:
		return

	var token: String = str(envelope.get("action_token", ""))
	if token.is_empty() or _processed_action_tokens.has(token):
		action_rejected.emit("ERR_DUPLICATE_OR_MISSING_TOKEN")
		return

	if str(envelope.get("session_id", "")) != authoritative_state.session_id:
		action_rejected.emit("ERR_SESSION_MISMATCH")
		return

	var seat: int = int(envelope.get("seat", -1))
	var expected_rev: int = int(envelope.get("expected_revision", -1))
	if expected_rev != authoritative_state.state_revision:
		action_rejected.emit("ERR_STALE_REVISION")
		return

	if authoritative_state.seat_is_ai[seat]:
		action_rejected.emit("ERR_SEAT_UNDER_AI_CONTROL")
		return

	var res: Dictionary = RulesEngine.apply_action(authoritative_state, seat, envelope.get("action", {}))
	if not res.get("ok", false):
		action_rejected.emit(str(res.get("error", "ERR_ACTION_REJECTED")))
		return

	_processed_action_tokens[token] = authoritative_state.state_revision
	_broadcast_state_from_host()

func _broadcast_state_from_host() -> void:
	if authoritative_state == null:
		return

	# Persist durable checkpoint automatically
	if is_offline_solo:
		SaveManager.save_solo_state(authoritative_state)
	else:
		SaveManager.save_multiplayer_recovery_state(authoritative_state)

	# Build Split-Key Encrypted Replication bundle for multiplayer peers
	var rep_bundle: Dictionary = {}
	if not is_offline_solo:
		rep_bundle = CryptoStateReplicator.create_replicated_checkpoint(authoritative_state, active_host_seat)

	for seat in range(4):
		var sanitized_view: Dictionary = authoritative_state.build_player_view(seat)
		sanitized_view["tram_available"] = RulesEngine.can_call_tram(authoritative_state, seat)
		if seat == local_seat:
			latest_player_view = sanitized_view
			player_view_updated.emit(latest_player_view)
		elif not is_offline_solo and _seat_to_peer_id.has(seat):
			var peer_id: int = int(_seat_to_peer_id[seat])
			var share_for_seat: Dictionary = rep_bundle["seat_shares"].get(seat, {})
			_rpc_receive_sanitized_view.rpc_id(peer_id, sanitized_view, rep_bundle["envelope"], share_for_seat)

@rpc("any_peer", "reliable")
func _rpc_submit_action(envelope: Dictionary) -> void:
	if not is_authoritative_host:
		return
	var sender_peer: int = multiplayer.get_remote_sender_id()
	var claimed_seat: int = int(envelope.get("seat", -1))
	if _peer_id_to_seat.get(sender_peer, -99) != claimed_seat:
		return
	_process_authoritative_action_envelope(envelope)

@rpc("authority", "reliable")
func _rpc_receive_sanitized_view(view: Dictionary, encrypted_envelope: Dictionary, my_key_share: Dictionary) -> void:
	latest_player_view = view
	_cached_encrypted_envelope = encrypted_envelope
	_cached_my_key_share = my_key_share
	player_view_updated.emit(latest_player_view)

## Handles Player Disconnect -> Grace Timer / Immediate AI Takeover
func handle_player_disconnect(disconnected_seat: int) -> void:
	if not is_authoritative_host or authoritative_state == null:
		return
	seat_connection_changed.emit(disconnected_seat, false)
	if authoritative_state.phase == GameState.Phase.TRICK_PLAY:
		authoritative_state.seat_is_ai[disconnected_seat] = true
		_broadcast_state_from_host()
	else:
		# 8-second grace period during Bidding / Trump Set / Double
		_disconnect_grace_timers[disconnected_seat] = NON_TRICK_GRACE_SEC

## Handles Player Reconnect -> Restores control strictly at the next Safe Point
func handle_player_reconnect(reconnected_seat: int, peer_id: int) -> void:
	if not is_authoritative_host or authoritative_state == null:
		return
	_seat_to_peer_id[reconnected_seat] = peer_id
	_peer_id_to_seat[peer_id] = reconnected_seat
	seat_connection_changed.emit(reconnected_seat, true)

	if _disconnect_grace_timers.has(reconnected_seat):
		_disconnect_grace_timers.erase(reconnected_seat)
		authoritative_state.seat_is_ai[reconnected_seat] = false
	elif authoritative_state.is_safe_point_for_seat(reconnected_seat):
		authoritative_state.seat_is_ai[reconnected_seat] = false
		authoritative_state.seat_pending_human_reclaim[reconnected_seat] = false
	else:
		# Defer human control restoration until current trick completes
		authoritative_state.seat_pending_human_reclaim[reconnected_seat] = true

	_broadcast_state_from_host()

## Deterministic Host Migration Protocol (Lowest Connected Seat ID Elected)
func trigger_host_migration(connected_seats: Array[int], peer_key_shares: Array[Dictionary]) -> bool:
	if connected_seats.is_empty():
		return false
	connected_seats.sort()
	var elected_host_seat: int = connected_seats[0]
	var previous_host_seat: int = active_host_seat
	active_host_seat = elected_host_seat
	host_migration_started.emit(elected_host_seat)

	if local_seat == elected_host_seat:
		var all_shares: Array[Dictionary] = [_cached_my_key_share]
		all_shares.append_array(peer_key_shares)
		var recovered: GameState = CryptoStateReplicator.recover_state_from_shares(_cached_encrypted_envelope, all_shares)
		if recovered == null:
			return false

		is_authoritative_host = true
		authoritative_state = recovered
		# Assign AI takeover to the disconnected former host's seat
		authoritative_state.seat_is_ai[previous_host_seat] = true
		authoritative_state.state_revision += 1
		_broadcast_state_from_host()
		host_migration_completed.emit(elected_host_seat)
		return true

	return true

func _bind_multiplayer_signals() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_disconnected(peer_id: int) -> void:
	if is_authoritative_host and _peer_id_to_seat.has(peer_id):
		var seat: int = int(_peer_id_to_seat[peer_id])
		_peer_id_to_seat.erase(peer_id)
		_seat_to_peer_id.erase(seat)
		handle_player_disconnect(seat)