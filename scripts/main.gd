extends Node3D

const DEFAULT_PORT := 7000
const MAX_CONNECTIONS := 4

@onready var hud: CanvasLayer = $HUD
@onready var wave_manager: Node = $WaveManager
@onready var players_root: Node3D = $Players
@onready var zombies_root: Node3D = $Zombies

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var zombie_scene: PackedScene = preload("res://scenes/zombie.tscn")

var session_started: bool = false
var status_text: String = "Choose Solo, Host, or Join to start."
var player_nodes: Dictionary = {}
var player_spawn_map: Dictionary = {}
var zombie_nodes: Dictionary = {}
var next_zombie_id: int = 1
var alive_players: int = 0
var current_wave_number: int = 0
var current_wave_total: int = 0
var total_kills: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	hud.play_solo_requested.connect(start_solo_game)
	hud.host_requested.connect(host_game)
	hud.join_requested.connect(join_game)
	hud.command_submitted.connect(_on_console_command)
	hud.console_visibility_changed.connect(_on_console_visibility_changed)

	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.zombie_killed.connect(_on_zombie_killed)
	wave_manager.all_waves_complete.connect(_on_all_waves_complete)
	wave_manager.zombie_spawned.connect(_on_zombie_spawned)

	hud.set_status(status_text)
	hud.show_menu(true)
	hud.add_console_line("Use ` or F1 to open the debug console.")

func start_solo_game() -> void:
	_prepare_for_new_session()
	_reset_session_state()
	status_text = "Solo run started."
	_start_session()

func host_game(port: int = DEFAULT_PORT) -> void:
	_prepare_for_new_session()
	_reset_session_state()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CONNECTIONS)
	if err != OK:
		hud.set_status("Host failed on UDP %d (error %d)." % [port, err])
		return
	multiplayer.multiplayer_peer = peer
	status_text = "Hosting on UDP %d. Friends join with your IP." % port
	hud.set_status(status_text)
	_start_session()

func join_game(address: String, port: int = DEFAULT_PORT) -> void:
	_prepare_for_new_session()
	_reset_session_state()
	var cleaned := address.strip_edges()
	if cleaned.is_empty():
		cleaned = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(cleaned, port)
	if err != OK:
		hud.set_status("Join failed for %s:%d (error %d)." % [cleaned, port, err])
		return
	multiplayer.multiplayer_peer = peer
	status_text = "Connecting to %s:%d..." % [cleaned, port]
	hud.set_status(status_text)
	hud.show_menu(false)

func _start_session() -> void:
	if session_started:
		return
	session_started = true
	get_tree().paused = false
	hud.reset_for_session()
	hud.show_menu(false)
	hud.set_status(status_text)
	if _is_server_authority():
		_spawn_player_for_peer(_local_peer_id())
	if _is_server_authority():
		alive_players = 1
		wave_manager.start_waves()

func _reset_session_state() -> void:
	get_tree().paused = false
	session_started = false
	status_text = "Choose Solo, Host, or Join to start."
	next_zombie_id = 1
	alive_players = 0
	current_wave_number = 0
	current_wave_total = 0
	total_kills = 0
	player_spawn_map.clear()
	for peer_id in player_nodes.keys():
		var player: Node = player_nodes[peer_id]
		if is_instance_valid(player):
			player.queue_free()
	player_nodes.clear()
	zombie_nodes.clear()
	for child in zombies_root.get_children():
		child.queue_free()
	wave_manager.reset_waves()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _prepare_for_new_session() -> void:
	get_tree().paused = false
	_release_local_menu_control()

func _open_session_menu() -> void:
	_release_local_menu_control()
	if not multiplayer.has_multiplayer_peer():
		get_tree().paused = true
	status_text = "Choose Solo, Host, or Join."
	hud.set_status(status_text)
	hud.show_menu(true)

func _close_session_menu() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	_capture_local_menu_control()

func _spawn_player_for_peer(peer_id: int) -> void:
	if player_nodes.has(peer_id):
		return
	var player = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	player.configure_for_peer(peer_id, _local_peer_id())
	players_root.add_child(player)
	var spawn_index := _get_spawn_index_for_peer(peer_id)
	player.global_position = _get_player_spawn_position(spawn_index)
	player_nodes[peer_id] = player
	if _is_server_authority():
		player.died.connect(_player_died_on_server)
	if peer_id == _local_peer_id():
		player.health_changed.connect(hud.set_health)
		player.died.connect(_on_local_player_died)
		hud.set_health(player.max_health, player.max_health)

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int, spawn_index: int) -> void:
	player_spawn_map[peer_id] = spawn_index
	_spawn_player_for_peer(peer_id)
	if player_nodes.has(peer_id):
		player_nodes[peer_id].global_position = _get_player_spawn_position(spawn_index)

func _despawn_player(peer_id: int) -> void:
	if not player_nodes.has(peer_id):
		return
	var player: Node = player_nodes[peer_id]
	player_nodes.erase(peer_id)
	if is_instance_valid(player):
		player.queue_free()

@rpc("authority", "call_local", "reliable")
func despawn_player(peer_id: int) -> void:
	_despawn_player(peer_id)

func _get_spawn_index_for_peer(peer_id: int) -> int:
	if player_spawn_map.has(peer_id):
		return player_spawn_map[peer_id]
	var used: Array = player_spawn_map.values()
	var count := $PlayerSpawnPoints.get_child_count()
	for idx in range(count):
		if not used.has(idx):
			player_spawn_map[peer_id] = idx
			return idx
	player_spawn_map[peer_id] = used.size() % max(count, 1)
	return player_spawn_map[peer_id]

func _get_player_spawn_position(index: int) -> Vector3:
	var points := $PlayerSpawnPoints.get_children()
	if points.is_empty():
		return Vector3.ZERO
	var point: Marker3D = points[index % points.size()]
	return point.global_position

func _on_peer_connected(peer_id: int) -> void:
	if not _is_server_authority() or not session_started:
		return
	for existing_peer_id in player_nodes.keys():
		var spawn_index := _get_spawn_index_for_peer(existing_peer_id)
		spawn_player.rpc_id(peer_id, existing_peer_id, spawn_index)
	spawn_player.rpc(peer_id, _get_spawn_index_for_peer(peer_id))
	for zombie_id in zombie_nodes.keys():
		var zombie = zombie_nodes[zombie_id]
		if is_instance_valid(zombie):
			spawn_zombie.rpc_id(peer_id, zombie_id, zombie.global_position)
	if current_wave_number > 0:
		sync_wave.rpc_id(peer_id, current_wave_number, current_wave_total)
	sync_kills.rpc_id(peer_id, total_kills)
	alive_players += 1
	status_text = "%d players connected." % alive_players
	hud.set_status(status_text)

func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)
	player_spawn_map.erase(peer_id)
	if _is_server_authority() and session_started:
		alive_players = max(0, alive_players - 1)
		_evaluate_game_over()
	status_text = "Peer %d disconnected." % peer_id
	hud.set_status(status_text)

func _on_connected_to_server() -> void:
	status_text = "Connected. Waiting for host state..."
	hud.set_status(status_text)
	_start_session()

func _on_connection_failed() -> void:
	status_text = "Connection failed."
	hud.show_menu(true)
	hud.set_status(status_text)
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	status_text = "Server disconnected."
	hud.show_menu(true)
	hud.set_status(status_text)
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()

func _on_local_player_died() -> void:
	if not session_started:
		return
	if multiplayer.has_multiplayer_peer():
		hud.show_persistent("YOU DIED - SPECTATING", Color(0.95, 0.35, 0.45))
	else:
		hud.show_lose()
		await get_tree().create_timer(3.0).timeout
		get_tree().reload_current_scene()

func _on_wave_started(wave_index: int, total: int) -> void:
	current_wave_number = wave_index
	current_wave_total = total
	hud.set_wave(wave_index, total)
	if _is_server_authority() and multiplayer.has_multiplayer_peer():
		sync_wave.rpc(wave_index, total)

func _on_zombie_killed(remaining: int) -> void:
	total_kills += 1
	hud.set_kills(total_kills)
	if _is_server_authority() and multiplayer.has_multiplayer_peer():
		sync_kills.rpc(total_kills)

func _on_all_waves_complete() -> void:
	if multiplayer.has_multiplayer_peer():
		show_win_state.rpc()
	else:
		await show_win_state()

func _on_zombie_spawned(zombie: Node) -> void:
	if not _is_server_authority():
		return
	zombie.network_id = next_zombie_id
	zombie_nodes[next_zombie_id] = zombie
	if multiplayer.has_multiplayer_peer():
		spawn_zombie.rpc(next_zombie_id, zombie.global_position)
	next_zombie_id += 1

@rpc("authority", "call_local", "reliable")
func spawn_zombie(zombie_id: int, spawn_position: Vector3) -> void:
	if zombie_nodes.has(zombie_id):
		return
	var zombie = zombie_scene.instantiate()
	zombie.name = "Zombie_%d" % zombie_id
	zombie.network_id = zombie_id
	zombies_root.add_child(zombie)
	zombie.global_position = spawn_position
	zombie_nodes[zombie_id] = zombie

@rpc("authority", "call_local", "reliable")
func despawn_zombie(zombie_id: int) -> void:
	if not zombie_nodes.has(zombie_id):
		return
	var zombie: Node = zombie_nodes[zombie_id]
	zombie_nodes.erase(zombie_id)
	if is_instance_valid(zombie):
		zombie.play_remote_death()

@rpc("authority", "call_remote", "reliable")
func sync_wave(wave_index: int, total: int) -> void:
	hud.set_wave(wave_index, total)

@rpc("authority", "call_remote", "reliable")
func sync_kills(value: int) -> void:
	total_kills = value
	hud.set_kills(total_kills)

@rpc("authority", "call_local", "reliable")
func show_win_state() -> void:
	hud.show_win()
	await get_tree().create_timer(5.0).timeout
	get_tree().reload_current_scene()

@rpc("authority", "call_local", "reliable")
func show_lose_state() -> void:
	hud.show_lose()
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()

@rpc("any_peer", "call_remote", "reliable")
func request_zombie_hit(zombie_id: int, zone_name: String, amount: int, impulse_direction: Vector3 = Vector3.ZERO, force: float = 0.0) -> void:
	if not _is_server_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not player_nodes.has(sender) or not zombie_nodes.has(zombie_id):
		return
	var zombie = zombie_nodes[zombie_id]
	if is_instance_valid(zombie):
		zombie.take_hit(zone_name, amount, impulse_direction, force)

func _physics_process(_delta: float) -> void:
	if _is_server_authority() and multiplayer.has_multiplayer_peer() and not zombie_nodes.is_empty():
		var states: Array = []
		for zombie_id in zombie_nodes.keys():
			var zombie = zombie_nodes[zombie_id]
			if not is_instance_valid(zombie):
				continue
			states.append({
				"id": zombie_id,
				"pos": zombie.global_position,
				"yaw": zombie.rotation.y,
			})
		if not states.is_empty():
			sync_zombie_states.rpc(states)

@rpc("authority", "call_remote", "unreliable")
func sync_zombie_states(states: Array) -> void:
	for entry in states:
		var zombie_id: int = entry.get("id", -1)
		if zombie_nodes.has(zombie_id):
			var zombie = zombie_nodes[zombie_id]
			if is_instance_valid(zombie):
				zombie.apply_remote_state(entry["pos"], entry["yaw"])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		hud.toggle_console()
		return
	if event.is_action_pressed("ui_unpause") or event.is_action_pressed("ui_cancel"):
		if hud.is_console_visible():
			hud.set_console_visible(false)
			return
		if session_started:
			_return_to_main_menu()
		elif hud.is_menu_visible():
			_close_session_menu()
		else:
			_open_session_menu()

func _player_died_on_server() -> void:
	alive_players = 0
	for peer_id in player_nodes.keys():
		var player = player_nodes[peer_id]
		if is_instance_valid(player) and not player.dead:
			alive_players += 1
	_evaluate_game_over()

func _evaluate_game_over() -> void:
	if alive_players > 0:
		return
	if multiplayer.has_multiplayer_peer():
		show_lose_state.rpc()
	else:
		await show_lose_state()

func _is_server_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _local_peer_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1

func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _release_local_menu_control() -> void:
	for peer_id in player_nodes.keys():
		if peer_id != _local_peer_id():
			continue
		var player = player_nodes[peer_id]
		if is_instance_valid(player) and player.has_method("open_menu"):
			player.open_menu()

func _capture_local_menu_control() -> void:
	for peer_id in player_nodes.keys():
		if peer_id != _local_peer_id():
			continue
		var player = player_nodes[peer_id]
		if is_instance_valid(player) and player.has_method("close_menu"):
			player.close_menu()

func _on_console_visibility_changed(visible_state: bool) -> void:
	for peer_id in player_nodes.keys():
		if peer_id != _local_peer_id():
			continue
		var player = player_nodes[peer_id]
		if is_instance_valid(player) and player.has_method("set_input_blocked"):
			player.set_input_blocked(visible_state)

func _on_console_command(command: String) -> void:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return
	match parts[0].to_lower():
		"help":
			hud.add_console_line("Commands: help, clear, restart, menu, killall, wave")
		"clear":
			hud.clear_console()
		"restart":
			_return_to_main_menu()
		"menu":
			_open_session_menu()
		"killall":
			for zombie in zombie_nodes.values():
				if is_instance_valid(zombie):
					zombie.take_hit("head", zombie.max_health, Vector3.UP, 0.0)
			hud.add_console_line("All active zombies removed.")
		"wave":
			hud.add_console_line("Wave %d / kills %d / alive zombies %d" % [current_wave_number, total_kills, zombie_nodes.size()])
		_:
			hud.add_console_line("Unknown command: %s" % command)
