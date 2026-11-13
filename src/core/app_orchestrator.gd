extends Node

## Root application lifecycle orchestrator (Autoload: AppOrchestrator).
## Ensures Android backgrounding, focus loss, or OS termination flushes durable state.

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			AudioManager.suspend()
			_flush_active_session_checkpoint()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			AudioManager.resume()
		NOTIFICATION_WM_CLOSE_REQUEST:
			AudioManager.shutdown()
			_flush_active_session_checkpoint()
			get_tree().quit()

func _flush_active_session_checkpoint() -> void:
	if MultiplayerManager == null or MultiplayerManager.authoritative_state == null:
		return
	if MultiplayerManager.is_offline_solo:
		SaveManager.save_solo_state(MultiplayerManager.authoritative_state)
	elif MultiplayerManager.is_authoritative_host:
		SaveManager.save_multiplayer_recovery_state(MultiplayerManager.authoritative_state)
