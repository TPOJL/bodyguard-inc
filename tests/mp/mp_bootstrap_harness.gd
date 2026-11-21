extends SceneTree
## Headless Host/Client ENet localhost connection & scripted bot intent smoke test.
## Invoked by `.agent/skills/headless-coop-playtester/scripts/run_coop_smoke.py`.

const NetworkTransport := preload("res://src/core/network_transport.gd")
const VipStateMachine := preload("res://src/vip/vip_state_machine.gd")

var _role: String = "host"
var _port: int = 17777
var _bot_id: int = 1
var _expected_clients: int = 2
var _duration: float = 10.0

var _transport: NetworkTransport = null
var _vip: VipStateMachine = null
var _elapsed: float = 0.0
var _connected_peers: Dictionary = {}
var _intents_count: int = 0
var _client_sent_intents: int = 0


func _init() -> void:
	_parse_args()
	var root_node: Node3D = Node3D.new()
	root_node.name = "MpHarnessRoot"
	get_root().add_child(root_node)

	_transport = NetworkTransport.new()
	_transport.name = "NetworkTransport"
	root_node.add_child(_transport)

	_vip = VipStateMachine.new()
	_vip.name = "VIP"
	root_node.add_child(_vip)

	if _role == "host":
		_transport.peer_connected_safe.connect(_on_host_peer_connected)
		_transport.validated_intent_received.connect(_on_host_intent_received)
		var err: Error = _transport.host_session(_port, 4)
		if err != OK:
			push_error("ERROR: Host failed to bind port %d (code %d)" % [_port, err])
			quit(1)
			return
		print("[host] Listening on 127.0.0.1:%d" % _port)
	else:
		var err: Error = _transport.join_session("127.0.0.1", _port)
		if err != OK:
			push_error("ERROR: Client %d failed to connect (code %d)" % [_bot_id, err])
			quit(1)
			return
		print("[client%d] Connecting to 127.0.0.1:%d" % [_bot_id, _port])


func _process(delta: float) -> bool:
	_elapsed += delta
	if _role == "client" and multiplayer.has_multiplayer_peer():
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			if _client_sent_intents < 3 and _elapsed > float(_client_sent_intents + 1) * 0.5:
				var move_dir: Vector2 = Vector2(1.0, 0.0)
				var grab: bool = (_bot_id == 1)
				var voice_rms: float = 0.55 if _bot_id == 1 else 0.85
				_transport.submit_player_intent.rpc_id(1, move_dir, grab, voice_rms)
				_client_sent_intents += 1
				print("[client%d] Sent scripted intent #%d" % [_bot_id, _client_sent_intents])

	if _elapsed >= _duration:
		return _finish_and_validate()
	return false


func _finish_and_validate() -> bool:
	_transport.close_session()
	if _role == "host":
		if _connected_peers.size() < _expected_clients:
			push_error("ERROR: Expected %d clients, got %d" % [_expected_clients, _connected_peers.size()])
			quit(1)
			return true
		if _intents_count < _expected_clients:
			push_error("ERROR: Expected validated intents from clients, got %d" % _intents_count)
			quit(1)
			return true
		print("[host] PASS: %d clients connected, %d validated intents received" % [_connected_peers.size(), _intents_count])
	else:
		if _client_sent_intents < 3:
			push_error("ERROR: Client %d failed to send scripted intents (%d/3)" % [_bot_id, _client_sent_intents])
			quit(1)
			return true
		print("[client%d] PASS: Sent %d scripted intents cleanly" % [_bot_id, _client_sent_intents])
	quit(0)
	return true


func _on_host_peer_connected(peer_id: int) -> void:
	_connected_peers[peer_id] = true
	print("[host] Peer connected: %d" % peer_id)


func _on_host_intent_received(sender_id: int, _move_dir: Vector2, _grab: bool, voice_rms: float) -> void:
	_intents_count += 1
	if voice_rms > 0.80:
		_vip.apply_damage_authoritative(120.0, true)
	print("[host] Validated intent from peer %d (voice_rms=%.2f, vip_state=%d)" % [sender_id, voice_rms, _vip.state])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--bot-id="):
			_bot_id = int(arg.get_slice("=", 1))
		elif arg.begins_with("--expected-clients="):
			_expected_clients = int(arg.get_slice("=", 1))
		elif arg.begins_with("--duration="):
			_duration = float(arg.get_slice("=", 1))
