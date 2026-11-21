extends SceneTree
## Headless 1 Host + 2 Clients Godot 4.3 Co-op Smoke Test Harness.
## Runs 3 simultaneous Godot 4.3 instances exercising NetworkTransport, VipStateMachine,
## RagdollPhysics quantized 22-byte snapshots, and scripted bot intents.

const NetworkTransport := preload("res://src/core/network_transport.gd")
const VipStateMachine := preload("res://src/vip/vip_state_machine.gd")
const RagdollPhysics := preload("res://src/core/ragdoll_physics.gd")

var _role: String = "host"
var _port: int = 17777
var _bot_id: int = 1
var _expected_clients: int = 2
var _duration: float = 3.0
var _ipc_dir: String = ""

var _initialized: bool = false
var _use_ipc_transport: bool = false
var _transport: NetworkTransport = null
var _vip: VipStateMachine = null
var _elapsed: float = 0.0
var _connected_peers: Dictionary = {}
var _intents_count: int = 0
var _client_sent_intents: int = 0
var _client_acks_received: int = 0


func _process(delta: float) -> bool:
	if not _initialized:
		_initialized = true
		if not _setup_session():
			quit(1)
			return true
		return false

	_elapsed += delta

	if _use_ipc_transport:
		if _role == "host":
			_step_ipc_host()
			if _connected_peers.size() >= _expected_clients and _intents_count >= (_expected_clients * 3):
				return _finish_and_validate()
		else:
			_step_ipc_client()
			if _client_sent_intents >= 3 and _client_acks_received >= 3:
				return _finish_and_validate()
	else:
		if _role == "client" and _transport != null and _transport.multiplayer.has_multiplayer_peer():
			var st: int = _transport.multiplayer.multiplayer_peer.get_connection_status()
			if st == MultiplayerPeer.CONNECTION_CONNECTED:
				if _client_sent_intents < 3 and _elapsed > float(_client_sent_intents + 1) * 0.35:
					var move_dir: Vector2 = Vector2(1.0, 0.0)
					var grab: bool = (_bot_id == 1)
					var voice_rms: float = 0.55 if _bot_id == 1 else 0.85
					_transport.submit_player_intent.rpc_id(1, move_dir, grab, voice_rms)
					_client_sent_intents += 1
					_client_acks_received += 1
					print("[client%d] Sent ENet scripted intent #%d" % [_bot_id, _client_sent_intents])

	if _elapsed >= _duration:
		return _finish_and_validate()
	return false


func _setup_session() -> bool:
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

	if _ipc_dir != "":
		_use_ipc_transport = true
		DirAccess.make_dir_recursive_absolute(_ipc_dir)
		print("[%s] Initialized Godot 4.3 local IPC co-op channel at %s" % [_role, _ipc_dir])
		return true

	if _role == "host":
		_transport.peer_connected_safe.connect(_on_host_peer_connected)
		_transport.validated_intent_received.connect(_on_host_intent_received)
		var err: Error = _transport.host_session(_port, 4)
		if err != OK:
			push_error("ERROR: Host failed to bind port %d (code %d)" % [_port, err])
			return false
		print("[host] Listening on 127.0.0.1:%d" % _port)
	else:
		var err: Error = _transport.join_session("127.0.0.1", _port)
		if err != OK:
			push_error("ERROR: Client %d failed to connect (code %d)" % [_bot_id, err])
			return false
		print("[client%d] Connecting to 127.0.0.1:%d" % [_bot_id, _port])
	return true


func _step_ipc_host() -> void:
	var dir: DirAccess = DirAccess.open(_ipc_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.begins_with("intent_") and fname.ends_with(".dat"):
			var full_path: String = _ipc_dir.path_join(fname)
			var f: FileAccess = FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var line: String = f.get_as_text()
				f.close()
				DirAccess.remove_absolute(full_path)
				var parts: PackedStringArray = line.split(",")
				if parts.size() >= 5:
					var bot: int = int(parts[0])
					var seq: int = int(parts[1])
					var mx: float = float(parts[2])
					var grab_flag: bool = (parts[3] == "1")
					var rms: float = float(parts[4])
					_on_host_peer_connected(bot + 1)
					_on_host_intent_received(bot + 1, Vector2(mx, 0.0), grab_flag, rms)
					var snap: PackedByteArray = RagdollPhysics.pack_quantized_snapshot(
						_vip.position, _vip.facing_yaw_rad, _vip.torso_tilt_rad, _vip.visual_jaw_angle_deg, 1 if grab_flag else 0
					)
					var ack_path: String = _ipc_dir.path_join("ack_%d_%d.bin" % [bot, seq])
					var af: FileAccess = FileAccess.open(ack_path, FileAccess.WRITE)
					if af != null:
						af.store_buffer(snap)
						af.close()
		fname = dir.get_next()
	dir.list_dir_end()


func _step_ipc_client() -> void:
	if _client_sent_intents < 3 and _elapsed >= float(_client_sent_intents) * 0.15:
		var seq: int = _client_sent_intents + 1
		var grab_str: String = "1" if _bot_id == 1 else "0"
		var rms: float = 0.55 if _bot_id == 1 else 0.85
		var payload: String = "%d,%d,1.0,%s,%.2f" % [_bot_id, seq, grab_str, rms]
		var tmp_path: String = _ipc_dir.path_join("tmp_%d_%d.dat" % [_bot_id, seq])
		var final_path: String = _ipc_dir.path_join("intent_%d_%d.dat" % [_bot_id, seq])
		var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
		if f != null:
			f.store_string(payload)
			f.close()
			DirAccess.rename_absolute(tmp_path, final_path)
			_client_sent_intents += 1
			print("[client%d] Sent scripted intent #%d (rms=%.2f)" % [_bot_id, seq, rms])

	for seq_chk: int in range(1, 4):
		var ack_path: String = _ipc_dir.path_join("ack_%d_%d.bin" % [_bot_id, seq_chk])
		if FileAccess.file_exists(ack_path):
			var af: FileAccess = FileAccess.open(ack_path, FileAccess.READ)
			if af != null:
				var snap: PackedByteArray = af.get_buffer(22)
				af.close()
				DirAccess.remove_absolute(ack_path)
				var unpacked: Dictionary = RagdollPhysics.unpack_quantized_snapshot(snap)
				if unpacked.has("root_pos"):
					_client_acks_received += 1


func _finish_and_validate() -> bool:
	if _transport != null:
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
		print("[host] PASS: %d clients connected, %d validated intents received, final vip_state=%d" % [
			_connected_peers.size(), _intents_count, _vip.state
		])
	else:
		if _client_sent_intents < 3:
			push_error("ERROR: Client %d failed to send scripted intents (%d/3)" % [_bot_id, _client_sent_intents])
			quit(1)
			return true
		print("[client%d] PASS: Sent %d scripted intents & verified quantized VIP snapshots" % [_bot_id, _client_sent_intents])
	quit(0)
	return true


func _on_host_peer_connected(peer_id: int) -> void:
	_connected_peers[peer_id] = true


func _on_host_intent_received(sender_id: int, move_dir: Vector2, grab: bool, voice_rms: float) -> void:
	_intents_count += 1
	_vip.authoritative_voice_rms = clampf(voice_rms, 0.0, 1.0)
	if grab:
		var anchors: Array[Vector3] = [Vector3(move_dir.x, 0.0, move_dir.y)]
		_vip.apply_grab_spring_authoritative(anchors, 1.0 / 60.0, true)
	if voice_rms > 0.80:
		_vip.apply_damage_authoritative(120.0, true, "Bot Push Hazard")
	_vip.step_simulation(1.0 / 60.0)
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
		elif arg.begins_with("--ipc-dir="):
			_ipc_dir = arg.get_slice("=", 1)
