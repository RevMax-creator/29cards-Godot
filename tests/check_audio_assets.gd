extends SceneTree

func _init() -> void:
	print("=== AUDIO ASSETS DECODE & INTEGRITY TEST ===")
	var sfx_paths: Dictionary = {
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
	var failed: int = 0
	for key in sfx_paths.keys():
		var path: String = sfx_paths[key]
		var stream := load(path) as AudioStream
		if stream == null:
			printerr("[FAIL] Could not load SFX: ", key, " at ", path)
			failed += 1
		else:
			print("[PASS] SFX: %s (length: %.3fs)" % [key, stream.get_length()])

	# Check voice files 15 to 28
	for bid in range(15, 29):
		var path := "res://assets/audio/voice/bid_%d.ogg" % bid
		var stream := load(path) as AudioStream
		if stream == null:
			printerr("[FAIL] Could not load voice: bid_", bid, " at ", path)
			failed += 1
		else:
			print("[PASS] Voice bid_%d (length: %.3fs)" % [bid, stream.get_length()])

	var pass_path := "res://assets/audio/voice/pass.ogg"
	var pass_stream := load(pass_path) as AudioStream
	if pass_stream == null:
		printerr("[FAIL] Could not load pass voice")
		failed += 1
	else:
		print("[PASS] Voice pass (length: %.3fs)" % pass_stream.get_length())

	for extra_voice in ["hold", "double", "quadruple"]:
		var extra_path := "res://assets/audio/voice/%s.ogg" % extra_voice
		var extra_stream := load(extra_path) as AudioStream
		if extra_stream == null:
			printerr("[FAIL] Could not load voice: ", extra_voice, " at ", extra_path)
			failed += 1
		else:
			print("[PASS] Voice %s (length: %.3fs)" % [extra_voice, extra_stream.get_length()])

	var bgm_path := "res://assets/audio/music/background_music.ogg"
	var bgm_stream := load(bgm_path) as AudioStream
	if bgm_stream == null:
		printerr("[FAIL] Could not load BGM ambient")
		failed += 1
	else:
		print("[PASS] BGM ambient (length: %.3fs)" % bgm_stream.get_length())

	print("==========================================")
	print("Audio decode integrity result: ", "ALL PASSED" if failed == 0 else "%d FAILED" % failed)
	quit(0 if failed == 0 else 1)
