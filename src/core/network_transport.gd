class_name NetworkTransport
extends Node
## P2P Transport Abstraction (ENet localhost for headless tests, SteamP2P for production).

enum TransportMode {
	ENET_LOCALHOST,
	STEAM_P2P,
}

signal peer_connected_safe(peer_id: int)
signal peer_disconnected_safe(peer_id: int)
signal validated_intent_received(sender_id: int, move_dir: Vector2, grab: bool, voice_rms: float)

var active_mode: TransportMode = TransportMode.ENET_LOCALHOST


func host_session(port: int = 17777, max_clients: int = 3) -> Error:
	if active_mode == TransportMode.ENET_LOCALHOST:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var err: Error = peer.create_server(port, max_clients)
		if err != OK:
			return err
		multiplayer.multiplayer_peer = peer
		_bind_signals()
		return OK
	push_error("SteamP2P transport requires SteamMultiplayerPeer plugin at runtime.")
	return ERR_UNAVAILABLE


func join_session(address: String = "127.0.0.1", port: int = 17777) -> Error:
	if active_mode == TransportMode.ENET_LOCALHOST:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var err: Error = peer.create_client(address, port)
		if err != OK:
			return err
		multiplayer.multiplayer_peer = peer
		_bind_signals()
		return OK
	push_error("SteamP2P transport requires SteamMultiplayerPeer plugin at runtime.")
	return ERR_UNAVAILABLE


func close_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


@rpc("any_peer", "unreliable_ordered")
func submit_player_intent(move_dir: Vector2, grab_pressed: bool, voice_rms: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var safe_dir: Vector2 = move_dir.limit_length(1.0) if move_dir.is_finite() else Vector2.ZERO
	var safe_rms: float = clampf(voice_rms, 0.0, 1.0) if is_finite(voice_rms) else 0.0
	validated_intent_received.emit(sender_id, safe_dir, grab_pressed, safe_rms)


func _bind_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	peer_connected_safe.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_disconnected_safe.emit(peer_id)
