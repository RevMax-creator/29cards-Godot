class_name ProceduralAudio
extends RefCounted

## Pass 22.11 compatibility shim.
## Gameplay audio is now shipped as authored project assets under
## res://assets/audio/sfx/ and res://assets/audio/voice/ so cues have consistent
## timbre, can be mixed independently, and do not need to be synthesized at boot.
## AudioManager loads that bank directly; this legacy method intentionally
## returns an empty dictionary and is retained only for older references.
static func generate_sfx() -> Dictionary:
	return {}
