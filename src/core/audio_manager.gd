extends Node

## One owner for music, gameplay SFX and auction voice callouts.
## All announcements use natural, high-fidelity male announcer voice assets.

const POOL_SIZE: int = 12
const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"
const BUS_VOICE: StringName = &"Voice"
const BGM_STREAM_PATH: String = "res://assets/audio/music/background_music.ogg"
const BGM_VOLUME_DB: float = -14.5
const BGM_LOOP_OFFSET_SEC: float = 0.0

const SFX_PATHS: Dictionary = {
	"shuffle": "res://assets/audio/sfx/shuffle.ogg",
	"card_deal": "res://assets/audio/sfx/card_slide_1.ogg",
	"card_slide_1": "res://assets/audio/sfx/card_slide_1.ogg",
	"card_slide_2": "res://assets/audio/sfx/card_slide_2.ogg",
	"card_slide_3": "res://assets/audio/sfx/card_slide_3.ogg",
	"card_slide_4": "res://assets/audio/sfx/card_slide_4.ogg",
	"card_slide_5": "res://assets/audio/sfx/card_slide_5.ogg",
	"card_slide_6": "res://assets/audio/sfx/card_slide_6.ogg",
	"card_slide_7": "res://assets/audio/sfx/card_slide_7.ogg",
	"card_slide_8": "res://assets/audio/sfx/card_slide_8.ogg",
	"card_place_2": "res://assets/audio/sfx/card_place_2.ogg",
	"card_place_3": "res://assets/audio/sfx/card_place_3.ogg",
	"card_place_4": "res://assets/audio/sfx/card_place_4.ogg",
	"card_sort": "res://assets/audio/sfx/card_sort.ogg",
	"card_place": "res://assets/audio/sfx/card_place.ogg",
	"trick_collect": "res://assets/audio/sfx/trick_collect.ogg",
	"turn_alert": "res://assets/audio/sfx/turn_alert.ogg",
	"ui_click": "res://assets/audio/sfx/ui_click.ogg",
	"bid_pass": "res://assets/audio/sfx/bid_pass.ogg",
	"trump_select": "res://assets/audio/sfx/trump_select.ogg",
	"trump_reveal": "res://assets/audio/sfx/trump_reveal.ogg",
	"pair_declared": "res://assets/audio/sfx/pair_declared.ogg",
	"hand_win": "res://assets/audio/sfx/hand_win.ogg",
	"hand_loss": "res://assets/audio/sfx/hand_loss.ogg",
	"match_win": "res://assets/audio/sfx/match_win.ogg",
	"match_loss": "res://assets/audio/sfx/match_loss.ogg",
	"error": "res://assets/audio/sfx/error.ogg",
	"card_invalid_drop": "res://assets/audio/sfx/card_invalid_drop.ogg"
}

const SFX_ALIASES: Dictionary = {
	"deck_shuffle": "shuffle",
	"card_play": "card_place",
	"card_place_1": "card_place"
}

const DEAL_SFX_VARIANTS: Array[String] = [
	"card_slide_1", "card_slide_2", "card_slide_3", "card_slide_4",
	"card_slide_5", "card_slide_6", "card_slide_7", "card_slide_8"
]

const PLAY_CARD_SFX_VARIANTS: Array[String] = [
	"card_slide_1", "card_slide_2", "card_slide_3", "card_slide_4",
	"card_slide_5", "card_slide_6", "card_slide_7", "card_slide_8",
	"card_place", "card_place_2", "card_place_3", "card_place_4"
]

const BID_VOICE_MIN: int = 15
const BID_VOICE_MAX: int = 28
const VOICE_PATH_FORMAT: String = "res://assets/audio/voice/bid_%d.ogg"
const PASS_VOICE_PATH: String = "res://assets/audio/voice/pass.ogg"
const HOLD_VOICE_PATH: String = "res://assets/audio/voice/hold.ogg"
const DOUBLE_VOICE_PATH: String = "res://assets/audio/voice/double.ogg"
const QUADRUPLE_VOICE_PATH: String = "res://assets/audio/voice/quadruple.ogg"

var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _deal_player: AudioStreamPlayer
var _bgm_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _sounds: Dictionary = {}
var _voice_streams: Dictionary = {}
var _voice_queue: Array[Dictionary] = []
var _voice_is_playing: bool = false
var _is_suspended: bool = false
var _is_shutting_down: bool = false
var _last_variant_key: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_bus(BUS_SFX)
	_ensure_audio_bus(BUS_MUSIC)
	_ensure_audio_bus(BUS_VOICE)
	_load_audio_bank()
	_create_players()

func _ensure_audio_bus(bus_name: StringName) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, "Master")
	AudioServer.set_bus_volume_db(bus_index, 0.0)

func _bid_phrase(amount: int) -> String:
	var names: Dictionary = {
		15: "Fifteen", 16: "Sixteen", 17: "Seventeen", 18: "Eighteen",
		19: "Nineteen", 20: "Twenty", 21: "Twenty one", 22: "Twenty two",
		23: "Twenty three", 24: "Twenty four", 25: "Twenty five",
		26: "Twenty six", 27: "Twenty seven", 28: "Twenty eight"
	}
	return str(names.get(amount, ""))

func _load_audio_bank() -> void:
	_sounds.clear()
	for sound_name in SFX_PATHS.keys():
		var path: String = str(SFX_PATHS[sound_name])
		var stream := ResourceLoader.load(path) as AudioStream
		if stream == null:
			push_warning("Missing gameplay sound '%s': %s" % [str(sound_name), path])
		else:
			_sounds[str(sound_name)] = stream

	_voice_streams.clear()
	for amount in range(BID_VOICE_MIN, BID_VOICE_MAX + 1):
		var voice_path: String = VOICE_PATH_FORMAT % amount
		var voice_stream := ResourceLoader.load(voice_path) as AudioStream
		if voice_stream == null:
			push_error("Missing spoken bid clip: %s" % voice_path)
		else:
			_voice_streams[amount] = voice_stream
	var pass_stream := ResourceLoader.load(PASS_VOICE_PATH) as AudioStream
	if pass_stream != null:
		_voice_streams["pass"] = pass_stream
	else:
		push_error("Missing spoken pass clip: %s" % PASS_VOICE_PATH)
	var extra_voices: Dictionary = {
		"hold": HOLD_VOICE_PATH,
		"double": DOUBLE_VOICE_PATH,
		"quadruple": QUADRUPLE_VOICE_PATH
	}
	for extra_key in extra_voices.keys():
		var extra_path: String = str(extra_voices[extra_key])
		var extra_stream := ResourceLoader.load(extra_path) as AudioStream
		if extra_stream != null:
			_voice_streams[extra_key] = extra_stream
		else:
			push_error("Missing spoken callout clip: %s" % extra_path)

func _create_players() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%02d" % i
		player.bus = BUS_SFX
		player.volume_db = -3.5
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_pool.append(player)

	_deal_player = AudioStreamPlayer.new()
	_deal_player.name = "DealAudioPlayer"
	_deal_player.bus = BUS_SFX
	_deal_player.volume_db = -4.5
	_deal_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_deal_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "AuctionVoicePlayer"
	_voice_player.bus = BUS_VOICE
	_voice_player.volume_db = -2.0
	_voice_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)

	var bgm_stream := ResourceLoader.load(BGM_STREAM_PATH) as AudioStreamOggVorbis
	if bgm_stream != null:
		bgm_stream.loop = true
		bgm_stream.loop_offset = BGM_LOOP_OFFSET_SEC
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "BackgroundMusicPlayer"
		_bgm_player.bus = BUS_MUSIC
		_bgm_player.volume_db = BGM_VOLUME_DB
		_bgm_player.stream = bgm_stream
		_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_bgm_player)
	else:
		push_warning("Background music could not be loaded: %s" % BGM_STREAM_PATH)

## Starts background music once when entering gameplay. Idempotent: never restarts if already playing.
func start_gameplay_music() -> void:
	if _is_suspended or _is_shutting_down:
		return
	if is_instance_valid(_bgm_player):
		if not _bgm_player.playing:
			_bgm_player.play()

## Stops background music cleanly when leaving gameplay.
func stop_gameplay_music() -> void:
	if is_instance_valid(_bgm_player) and _bgm_player.playing:
		_bgm_player.stop()

## Legacy compatibility alias.
func _start_background_music() -> void:
	start_gameplay_music()

func _pick_random_variant_stream(variant_keys: Array[String], fallback_key: String, channel_tag: String) -> AudioStream:
	var loaded: Array[String] = []
	for key in variant_keys:
		if _sounds.has(key):
			loaded.append(key)
	if loaded.is_empty():
		return _sounds.get(fallback_key) as AudioStream
	var last_key: String = str(_last_variant_key.get(channel_tag, ""))
	var candidates: Array[String] = loaded
	if loaded.size() > 1 and loaded.has(last_key):
		candidates = loaded.filter(func(k: String) -> bool: return k != last_key)
	var chosen_key: String = candidates[randi() % candidates.size()]
	_last_variant_key[channel_tag] = chosen_key
	return _sounds.get(chosen_key) as AudioStream

func get_sfx_length(sound_name: String) -> float:
	var resolved_name: String = str(SFX_ALIASES.get(sound_name, sound_name))
	var stream: AudioStream = _sounds.get(resolved_name) as AudioStream
	return stream.get_length() if stream != null else 0.0

## volume_scale is linear and intended for per-event mix balance.
func play_sfx(sound_name: String, pitch_variance: float = 0.04, volume_scale: float = 1.0) -> void:
	if _is_suspended or _is_shutting_down or _sfx_pool.is_empty():
		return
	var resolved_name: String = str(SFX_ALIASES.get(sound_name, sound_name))
	if resolved_name == "card_deal":
		play_deal_sfx(volume_scale, pitch_variance)
		return
	var stream: AudioStream = (
		_pick_random_variant_stream(PLAY_CARD_SFX_VARIANTS, "card_place", "card_place")
		if resolved_name == "card_place"
		else _sounds.get(resolved_name) as AudioStream
	)
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.volume_db = -3.5 + linear_to_db(maxf(volume_scale, 0.001))
	player.play()

## Dedicated single-channel player for sequential card-by-card dealing so
## individual card deal slides remain crisp and never pile up or overlap.
func play_deal_sfx(volume_scale: float = 0.55, pitch_variance: float = 0.03) -> void:
	if _is_suspended or _is_shutting_down or not is_instance_valid(_deal_player):
		return
	var stream: AudioStream = _pick_random_variant_stream(DEAL_SFX_VARIANTS, "card_deal", "card_deal")
	if stream == null:
		return
	if _deal_player.playing:
		_deal_player.stop()
	_deal_player.stream = stream
	_deal_player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	_deal_player.volume_db = -4.5 + linear_to_db(maxf(volume_scale, 0.001))
	_deal_player.play()

## Speaks the actual accepted bid, using the authoritative natural male announcer recordings.
func play_bid_callout(amount: int, seat: int) -> void:
	if _is_suspended or _is_shutting_down or amount < BID_VOICE_MIN or amount > BID_VOICE_MAX:
		return
	if OS.is_debug_build():
		print("[Audio] accepted bid event %d from seat %d" % [amount, seat])
	_enqueue_voice(amount)

## Speaks pass callout using the authoritative natural male announcer recording.
func play_pass_callout(seat: int) -> void:
	if _is_suspended or _is_shutting_down:
		return
	if OS.is_debug_build():
		print("[Audio] pass event from seat %d" % seat)
	_enqueue_voice("pass")

## Speaks hold callout when declining Double/Redouble using the same announcer voice.
func play_hold_callout(seat: int = -1) -> void:
	if _is_suspended or _is_shutting_down:
		return
	if OS.is_debug_build():
		print("[Audio] hold event from seat %d" % seat)
	_enqueue_voice("hold")

## Speaks double callout using the same announcer voice.
func play_double_callout(seat: int = -1) -> void:
	if _is_suspended or _is_shutting_down:
		return
	if OS.is_debug_build():
		print("[Audio] double event from seat %d" % seat)
	_enqueue_voice("double")

## Speaks quadruple (redouble) callout using the same announcer voice.
func play_quadruple_callout(seat: int = -1) -> void:
	if _is_suspended or _is_shutting_down:
		return
	if OS.is_debug_build():
		print("[Audio] quadruple event from seat %d" % seat)
	_enqueue_voice("quadruple")

func _enqueue_voice(voice_key: Variant) -> void:
	if _is_suspended or _is_shutting_down or not _voice_streams.has(voice_key):
		push_error("Cannot play voice cue: asset not found for key '%s'" % str(voice_key))
		return
	_voice_queue.append({
		"stream": _voice_streams[voice_key],
		"pitch": 1.0
	})
	_play_next_voice()

func _play_next_voice() -> void:
	if _voice_is_playing or _is_suspended or _is_shutting_down or _voice_queue.is_empty():
		return
	if not is_instance_valid(_voice_player):
		return
	var item: Dictionary = _voice_queue.pop_front()
	_voice_player.stream = item.get("stream") as AudioStream
	_voice_player.pitch_scale = float(item.get("pitch", 1.0))
	_voice_is_playing = true
	_voice_player.play()

func _on_voice_finished() -> void:
	_voice_is_playing = false
	_play_next_voice()

## Returns true while a bid/pass voice announcement is actively playing or queued.
func is_voice_playing() -> bool:
	return _voice_is_playing or not _voice_queue.is_empty() or (is_instance_valid(_voice_player) and _voice_player.playing)

## Discard transient cues while backgrounded; music resumes from its paused point.
func suspend() -> void:
	if _is_shutting_down or _is_suspended:
		return
	_is_suspended = true
	_voice_queue.clear()
	_voice_is_playing = false
	if is_instance_valid(_bgm_player):
		_bgm_player.stream_paused = true
	if is_instance_valid(_voice_player):
		_voice_player.stop()
	if is_instance_valid(_deal_player):
		_deal_player.stop()
	for player in _sfx_pool:
		if is_instance_valid(player):
			player.stop()

func resume() -> void:
	if _is_shutting_down or not _is_suspended:
		return
	_is_suspended = false
	if is_instance_valid(_bgm_player):
		_bgm_player.stream_paused = false

## Explicit terminal cleanup called before SceneTree.quit() and on tree exit.
func shutdown() -> void:
	_is_shutting_down = true
	_is_suspended = true
	_voice_queue.clear()
	_voice_is_playing = false
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
		_bgm_player.stream = null
	if is_instance_valid(_voice_player):
		_voice_player.stop()
		_voice_player.stream = null
	if is_instance_valid(_deal_player):
		_deal_player.stop()
		_deal_player.stream = null
	for player in _sfx_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null

func _exit_tree() -> void:
	shutdown()
