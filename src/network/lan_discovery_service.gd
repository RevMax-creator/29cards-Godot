class_name LanDiscoveryService
extends Node

signal room_discovered(room_info: Dictionary)

const DISCOVERY_PORT: int = 29029
const BROADCAST_INTERVAL_SEC: float = 1.2

var _udp_broadcaster: PacketPeerUDP
var _udp_listener: PacketPeerUDP
var _is_broadcasting: bool = false
var _is_listening: bool = false
var _broadcast_timer: float = 0.0
var _hosted_room_payload: Dictionary = {}

func start_hosting_beacon(room_name: String, session_id: String, game_port: int, occupied_seats: int) -> void:
	stop_all()
	_udp_broadcaster = PacketPeerUDP.new()
	_udp_broadcaster.set_broadcast_enabled(true)
	_udp_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_hosted_room_payload = {
		"magic": "SOVEREIGN_29_V1",
		"room_name": room_name,
		"session_id": session_id,
		"game_port": game_port,
		"occupied_seats": occupied_seats
	}
	_is_broadcasting = true

func start_listening() -> void:
	stop_all()
	_udp_listener = PacketPeerUDP.new()
	var err: Error = _udp_listener.bind(DISCOVERY_PORT)
	if err == OK:
		_is_listening = true

func stop_all() -> void:
	_is_broadcasting = false
	_is_listening = false
	if _udp_broadcaster != null:
		_udp_broadcaster.close()
		_udp_broadcaster = null
	if _udp_listener != null:
		_udp_listener.close()
		_udp_listener = null

func _process(delta: float) -> void:
	if _is_broadcasting and _udp_broadcaster != null:
		_broadcast_timer += delta
		if _broadcast_timer >= BROADCAST_INTERVAL_SEC:
			_broadcast_timer = 0.0
			var pkt: PackedByteArray = JSON.stringify(_hosted_room_payload).to_utf8_buffer()
			_udp_broadcaster.put_packet(pkt)

	if _is_listening and _udp_listener != null:
		while _udp_listener.get_available_packet_count() > 0:
			var sender_ip: String = _udp_listener.get_packet_ip()
			var raw: PackedByteArray = _udp_listener.get_packet()
			var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY and parsed.get("magic", "") == "SOVEREIGN_29_V1":
				parsed["host_ip"] = sender_ip
				room_discovered.emit(parsed)