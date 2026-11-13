extends Node

## One owner for music, gameplay SFX and auction voice callouts.
## Gameplay effects are bundled assets; auction numbers use native system TTS when available.

const POOL_SIZE: int = 12
const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"
const BUS_VOICE: StringName = &"Voice"
const BGM_STREAM_PATH: String = "res://assets/audio/card_table_ambient.ogg"
const BGM_VOLUME_DB: float = -17.0
const BGM_LOOP_OFFSET_SEC: float = 1.2

const SFX_PATHS: Dictionary = {
	"deck_shuffle": "res://assets/audio/sfx/deck_shuffle.ogg",
	"card_deal": "res://assets/audio/sfx/card_deal.ogg",
	"card_sort": "res://assets/audio/sfx/card_sort.ogg",
	"card_play": "res://assets/audio/sfx/card_play.ogg",
	"trick_collect": "res://assets/audio/sfx/trick_collect.ogg",
	"turn_alert": "res://assets/audio/sfx/turn_alert.ogg",
	"ui_click": "res://assets/audio/sfx/ui_click.ogg",
	"bid_pass": "res://assets/audio/sfx/bid_pass.ogg",
	"trump_select": "res://assets/audio/sfx/trump_select.ogg",
	"trump_reveal": "res://assets/audio/sfx/trump_reveal.ogg",
	"double": "res://assets/audio/sfx/double.ogg",
	"redouble": "res://assets/audio/sfx/redouble.ogg",
	"pair_declared": "res://assets/audio/sfx/pair_declared.ogg",
	"hand_win": "res://assets/audio/sfx/hand_win.ogg",
	"hand_loss": "res://assets/audio/sfx/hand_loss.ogg",
	"match_win": "res://assets/audio/sfx/match_win.ogg",
	"match_loss": "res://assets/audio/sfx/match_loss.ogg",
	"error": "res://assets/audio/sfx/error.ogg"
}

const BID_VOICE_MIN: int = 15
const BID_VOICE_MAX: int = 28
const VOICE_PATH_FORMAT: String = "res://assets/audio/voice/bid_%d.ogg"
const PASS_VOICE_PATH: String = "res://assets/audio/voice/pass.ogg"
const SEAT_PITCHES: Array[float] = [1.0, 0.99, 1.01, 0.98]

var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _bgm_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _sounds: Dictionary = {}
var _voice_streams: Dictionary = {}
var _voice_queue: Array[Dictionary] = []
var _voice_is_playing: bool = false
var _tts_voice_id: String = ""
var _native_tts_available: bool = false
var _tts_voice_is_explicitly_male: bool = false
var _next_utterance_id: int = 1
var _is_suspended: bool = false
var _is_shutting_down: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_bus(BUS_SFX)
	_ensure_audio_bus(BUS_MUSIC)
	_ensure_audio_bus(BUS_VOICE)
	_resolve_native_tts_voice()
	_load_audio_bank()
	_create_players()
	_start_background_music()

func _ensure_audio_bus(bus_name: StringName) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, "Master")
	AudioServer.set_bus_volume_db(bus_index, 0.0)

func _resolve_native_tts_voice() -> void:
	# Godot exposes voice name/id/language, but not a portable gender field.
	# Prefer an English voice whose advertised name/id clearly identifies a male
	# voice; otherwise respect the OS default English voice instead of guessing.
	var voices: Array = DisplayServer.tts_get_voices()
	var best_english_id: String = ""
	var best_male_id: String = ""
	var best_male_score: int = -1
	for voice_info_variant in voices:
		if not voice_info_variant is Dictionary:
			continue
		var voice_info: Dictionary = voice_info_variant
		var language: String = str(voice_info.get("language", "")).to_lower()
		if not language.begins_with("en"):
			continue
		var voice_id: String = str(voice_info.get("id", ""))
		var voice_name: String = str(voice_info.get("name", ""))
		if best_english_id.is_empty():
			best_english_id = voice_id
		var identity: String = (voice_name + " " + voice_id).to_lower()
		var score: int = 0
		for marker in ["#male", "_male", "-male", "male_", "male-"]:
			if identity.contains(marker):
				score = maxi(score, 100)
		for marker in ["david", "daniel", "guy", "mark", "james", "matthew", "george", "oliver", "ryan", "aaron", "john", "paul", "peter", "liam", "nathan", "thomas", "alex", "fred", "albert", "tom"]:
			if identity.contains(marker):
				score = maxi(score, 50)
		if score > best_male_score:
			best_male_score = score
			best_male_id = voice_id

	if not best_male_id.is_empty() and best_male_score > 0:
		_tts_voice_id = best_male_id
		_tts_voice_is_explicitly_male = true
	elif not best_english_id.is_empty():
		_tts_voice_id = best_english_id
		_tts_voice_is_explicitly_male = false
	else:
		var english_ids: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
		if not english_ids.is_empty():
			_tts_voice_id = str(english_ids[0])
			_tts_voice_is_explicitly_male = false

	_native_tts_available = not _tts_voice_id.is_empty()
	if not _native_tts_available:
		push_warning("No English system TTS voice found. Falling back to bundled bid recordings.")
	elif not _tts_voice_is_explicitly_male:
		push_warning("No explicitly male English TTS voice was exposed by this device. Using its first English voice; select an installed male English voice in system Text-to-Speech settings for a male announcer.")

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
			push_warning("Missing spoken bid clip: %s" % voice_path)
		else:
			_voice_streams[amount] = voice_stream
	var pass_stream := ResourceLoader.load(PASS_VOICE_PATH) as AudioStream
	if pass_stream != null:
		_voice_streams["pass"] = pass_stream

func _create_players() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%02d" % i
		player.bus = BUS_SFX
		player.volume_db = -3.5
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_pool.append(player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "AuctionVoicePlayer"
	_voice_player.bus = BUS_VOICE
	_voice_player.volume_db = -2.0
	_voice_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)

func _start_background_music() -> void:
	var bgm_stream := ResourceLoader.load(BGM_STREAM_PATH) as AudioStreamOggVorbis
	if bgm_stream == null:
		push_warning("Background music could not be loaded: %s" % BGM_STREAM_PATH)
		return

	bgm_stream.loop = true
	bgm_stream.loop_offset = BGM_LOOP_OFFSET_SEC
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BackgroundMusicPlayer"
	_bgm_player.bus = BUS_MUSIC
	_bgm_player.volume_db = BGM_VOLUME_DB
	_bgm_player.stream = bgm_stream
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	_bgm_player.play()

## volume_scale is linear and intended for per-event mix balance.
func play_sfx(sound_name: String, pitch_variance: float = 0.04, volume_scale: float = 1.0) -> void:
	if _is_suspended or _is_shutting_down or _sfx_pool.is_empty():
		return
	var stream: AudioStream = _sounds.get(sound_name) as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.volume_db = -3.5 + linear_to_db(maxf(volume_scale, 0.001))
	player.play()

## Speaks the actual accepted bid, including bids made by AI or remote players.
## Prefer native device TTS for a natural voice and keep bundled clips as fallback.
func play_bid_callout(amount: int, seat: int) -> void:
	if _is_suspended or _is_shutting_down or amount < BID_VOICE_MIN or amount > BID_VOICE_MAX:
		return
	var phrase: String = _bid_phrase(amount)
	if phrase.is_empty():
		return
	if OS.is_debug_build():
		print("[Audio] accepted bid event %d from seat %d; native_tts=%s" % [amount, seat, str(_native_tts_available)])
	if _native_tts_available:
		# Keep the same natural male timbre for all seats; avoid chipmunk-like
		# pitch shifts. Slight rate variation is intentionally not used.
		DisplayServer.tts_speak(phrase + ".", _tts_voice_id, 100, 0.98, 0.92, _next_utterance_id, false)
		_next_utterance_id += 1
		if OS.is_debug_build():
			print("[Audio] TTS accepted bid: %s (seat %d)" % [phrase, seat])
		return
	_enqueue_voice(amount, seat)

func play_pass_callout(seat: int) -> void:
	if _is_suspended or _is_shutting_down:
		return
	if _native_tts_available:
		DisplayServer.tts_speak("Pass.", _tts_voice_id, 100, 0.98, 0.92, _next_utterance_id, false)
		_next_utterance_id += 1
		if OS.is_debug_build():
			print("[Audio] TTS pass (seat %d)" % seat)
		return
	_enqueue_voice("pass", seat)

func _enqueue_voice(voice_key: Variant, seat: int) -> void:
	if _is_suspended or _is_shutting_down or not _voice_streams.has(voice_key):
		return
	var seat_index: int = posmod(seat, SEAT_PITCHES.size())
	_voice_queue.append({
		"stream": _voice_streams[voice_key],
		"pitch": SEAT_PITCHES[seat_index]
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

## Discard transient cues while backgrounded; music resumes from its paused point.
func suspend() -> void:
	if _is_shutting_down or _is_suspended:
		return
	_is_suspended = true
	_voice_queue.clear()
	_voice_is_playing = false
	if _native_tts_available:
		DisplayServer.tts_pause()
	if is_instance_valid(_bgm_player):
		_bgm_player.stream_paused = true
	if is_instance_valid(_voice_player):
		_voice_player.stop()
	for player in _sfx_pool:
		if is_instance_valid(player):
			player.stop()

func resume() -> void:
	if _is_shutting_down or not _is_suspended:
		return
	_is_suspended = false
	if is_instance_valid(_bgm_player):
		_bgm_player.stream_paused = false
	if _native_tts_available:
		DisplayServer.tts_resume()

## Explicit terminal cleanup called before SceneTree.quit() and on tree exit.
func shutdown() -> void:
	_is_shutting_down = true
	_is_suspended = true
	_voice_queue.clear()
	_voice_is_playing = false
	if _native_tts_available:
		DisplayServer.tts_stop()
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
	if is_instance_valid(_voice_player):
		_voice_player.stop()
	for player in _sfx_pool:
		if is_instance_valid(player):
			player.stop()

func _exit_tree() -> void:
	shutdown()
