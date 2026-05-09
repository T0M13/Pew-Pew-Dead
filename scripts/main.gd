extends Node3D

const DEFAULT_PORT := 7000
const MAX_CONNECTIONS := 4

@onready var hud: CanvasLayer = $HUD
@onready var wave_manager: Node = $WaveManager
@onready var players_root: Node3D = $Players
@onready var zombies_root: Node3D = $Zombies

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var zombie_scene: PackedScene = preload("res://scenes/zombie.tscn")
var drop_scene: PackedScene = preload("res://scenes/drop.tscn")

const DROP_TYPES: Array[StringName] = [&"heal", &"max_health", &"speed", &"damage"]

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
var drop_nodes: Dictionary = {}
var next_drop_id: int = 1
var card_phase_active: bool = false
var card_phase_wave: int = 0
var pending_card_offers: Dictionary = {}
var pending_card_picks: Dictionary = {}
var local_card_offer: Array = []

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
	wave_manager.drop_requested.connect(_on_drop_requested)
	wave_manager.card_phase_requested.connect(_on_card_phase_requested)
	hud.card_picked.connect(_on_local_card_picked)

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
	next_drop_id = 1
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
	for did in drop_nodes.keys():
		var d: Node = drop_nodes[did]
		if is_instance_valid(d):
			d.queue_free()
	drop_nodes.clear()
	card_phase_active = false
	pending_card_offers.clear()
	pending_card_picks.clear()
	local_card_offer.clear()
	if hud:
		hud.hide_card_picker()
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
		player.stamina_changed.connect(hud.set_stamina)
		player.weapon_changed.connect(hud.set_weapon)
		player.died.connect(_on_local_player_died)
		hud.set_health(player.max_health, player.max_health)
		hud.set_stamina(player.stamina_max, player.stamina_max)
		hud.set_weapon(player.current_weapon, player.WEAPON_NAMES[player.current_weapon])

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
			spawn_zombie.rpc_id(peer_id, zombie_id, zombie.global_position, zombie.variant)
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
	if wave_index >= 5 and wave_index % 5 == 0:
		hud.flash_message("BOSS INCOMING", 2.4)
		hud.add_console_line("Boss wave %d." % wave_index)
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
	zombie.died.connect(_on_zombie_died_for_lifesteal)
	if multiplayer.has_multiplayer_peer():
		spawn_zombie.rpc(next_zombie_id, zombie.global_position, zombie.variant)
	next_zombie_id += 1

func _on_zombie_died_for_lifesteal(zombie: Node) -> void:
	if not _is_server_authority() or not is_instance_valid(zombie):
		return
	var pos: Vector3 = zombie.global_position
	for peer_id in player_nodes.keys():
		var p: Node = player_nodes[peer_id]
		if not is_instance_valid(p) or p.dead:
			continue
		if p.lifesteal_per_kill <= 0:
			continue
		if pos.distance_to(p.global_position) > 12.0:
			continue
		if peer_id == _local_peer_id():
			p.apply_lifesteal_tick()
		else:
			grant_lifesteal.rpc_id(peer_id)

@rpc("authority", "call_remote", "reliable")
func grant_lifesteal() -> void:
	var p: Node = player_nodes.get(_local_peer_id(), null)
	if p and p.has_method("apply_lifesteal_tick"):
		p.apply_lifesteal_tick()

@rpc("authority", "call_local", "reliable")
func spawn_zombie(zombie_id: int, spawn_position: Vector3, zombie_variant: StringName = &"walker") -> void:
	if zombie_nodes.has(zombie_id):
		return
	var zombie = zombie_scene.instantiate()
	zombie.name = "Zombie_%d" % zombie_id
	zombie.network_id = zombie_id
	zombie.variant = zombie_variant
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

func _on_card_phase_requested(wave_index: int) -> void:
	if not _is_server_authority():
		return
	card_phase_active = true
	card_phase_wave = wave_index
	pending_card_offers.clear()
	pending_card_picks.clear()
	await get_tree().create_timer(0.9).timeout
	if not card_phase_active:
		return
	for peer_id in player_nodes.keys():
		var offer: Array = CardLibrary.random_offer(3)
		pending_card_offers[peer_id] = offer
		if peer_id == _local_peer_id():
			local_card_offer = offer
			_show_local_cards(offer, wave_index)
		else:
			present_cards.rpc_id(peer_id, offer, wave_index)
	if pending_card_offers.is_empty():
		_finish_card_phase()

func _show_local_cards(offer: Array, wave_index: int) -> void:
	if hud == null:
		return
	hud.show_card_picker(offer, wave_index)
	_release_local_menu_control()

func _on_local_card_picked(card_id: StringName) -> void:
	if not card_phase_active:
		return
	var local_id: int = _local_peer_id()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		submit_card_pick.rpc_id(1, card_id)
		hud.mark_card_picker_waiting("Picked. Waiting for the squad...")
		return
	_record_card_pick(local_id, card_id)

@rpc("authority", "call_remote", "reliable")
func present_cards(offer: Array, wave_index: int) -> void:
	local_card_offer = offer
	_show_local_cards(offer, wave_index)

@rpc("any_peer", "call_remote", "reliable")
func submit_card_pick(card_id: StringName) -> void:
	if not _is_server_authority():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_record_card_pick(sender, card_id)

func _record_card_pick(peer_id: int, card_id: StringName) -> void:
	if not card_phase_active:
		return
	if not pending_card_offers.has(peer_id):
		return
	if pending_card_picks.has(peer_id):
		return
	var offer: Array = pending_card_offers[peer_id]
	if not offer.has(card_id):
		return
	pending_card_picks[peer_id] = card_id
	_apply_card_to_peer(peer_id, card_id)
	hud.add_console_line("Peer %d picked %s." % [peer_id, card_id])
	var remaining: int = pending_card_offers.size() - pending_card_picks.size()
	if remaining > 0:
		if peer_id == _local_peer_id():
			hud.mark_card_picker_waiting("Picked. Waiting for %d more..." % remaining)
		return
	_finish_card_phase()

func _apply_card_to_peer(peer_id: int, card_id: StringName) -> void:
	var player: Node = player_nodes.get(peer_id, null)
	if player == null or not is_instance_valid(player):
		return
	if peer_id == _local_peer_id():
		if player.has_method("apply_card"):
			player.apply_card(card_id)
	else:
		apply_card_remote.rpc_id(peer_id, card_id)

@rpc("authority", "call_remote", "reliable")
func apply_card_remote(card_id: StringName) -> void:
	var player: Node = player_nodes.get(_local_peer_id(), null)
	if player and player.has_method("apply_card"):
		player.apply_card(card_id)

func _finish_card_phase() -> void:
	card_phase_active = false
	pending_card_offers.clear()
	pending_card_picks.clear()
	local_card_offer.clear()
	hud.hide_card_picker()
	_capture_local_menu_control()
	if multiplayer.has_multiplayer_peer():
		end_card_phase.rpc()
	wave_manager.resolve_card_phase()

@rpc("authority", "call_remote", "reliable")
func end_card_phase() -> void:
	hud.hide_card_picker()
	_capture_local_menu_control()

func _on_drop_requested(_wave_index: int) -> void:
	if not _is_server_authority():
		return
	var pos: Vector3 = _pick_drop_position()
	var drop_type: StringName = DROP_TYPES.pick_random()
	var drop_id: int = next_drop_id
	next_drop_id += 1
	if multiplayer.has_multiplayer_peer():
		spawn_drop.rpc(drop_id, pos, drop_type)
	else:
		spawn_drop(drop_id, pos, drop_type)
	hud.flash_message(_drop_announce(drop_type), 1.4)
	hud.add_console_line("Drop spawned: %s" % drop_type)

func _pick_drop_position() -> Vector3:
	var obstacle_keepout: Array = [
		Vector3(6, 0, 5), Vector3(-7, 0, -4),
		Vector3(5, 0, -8), Vector3(-8, 0, 7),
		Vector3(0, 0, 12),
	]
	for _attempt in range(8):
		var x: float = randf_range(-13.0, 13.0)
		var z: float = randf_range(-13.0, 13.0)
		var p := Vector3(x, 0.55, z)
		var ok := true
		for c in obstacle_keepout:
			if Vector2(p.x - c.x, p.z - c.z).length() < 2.6:
				ok = false
				break
		if ok:
			return p
	return Vector3(randf_range(-10.0, 10.0), 0.55, randf_range(-10.0, 10.0))

func _drop_announce(drop_type: StringName) -> String:
	match drop_type:
		&"heal": return "DROP: HEAL PACK"
		&"max_health": return "DROP: VITALITY +"
		&"speed": return "DROP: SPEED +"
		&"damage": return "DROP: DAMAGE +"
		_: return "DROP"

@rpc("authority", "call_local", "reliable")
func spawn_drop(drop_id: int, pos: Vector3, drop_type: StringName) -> void:
	if drop_nodes.has(drop_id):
		return
	var drop = drop_scene.instantiate()
	drop.name = "Drop_%d" % drop_id
	drop.set_meta("drop_id", drop_id)
	add_child(drop)
	drop.global_position = pos
	drop.configure(drop_type)
	drop.pickup_consumed.connect(_on_drop_consumed)
	drop_nodes[drop_id] = drop

@rpc("authority", "call_local", "reliable")
func despawn_drop(drop_id: int) -> void:
	if not drop_nodes.has(drop_id):
		return
	var d: Node = drop_nodes[drop_id]
	drop_nodes.erase(drop_id)
	if is_instance_valid(d):
		d.queue_free()

func _on_drop_consumed(drop: Node) -> void:
	if not is_instance_valid(drop) or not drop.has_meta("drop_id"):
		return
	var drop_id: int = drop.get_meta("drop_id")
	if not multiplayer.has_multiplayer_peer():
		drop_nodes.erase(drop_id)
		return
	if multiplayer.is_server():
		despawn_drop.rpc(drop_id)
	else:
		request_drop_despawn.rpc_id(1, drop_id)

@rpc("any_peer", "call_remote", "reliable")
func request_drop_despawn(drop_id: int) -> void:
	if not multiplayer.is_server():
		return
	if drop_nodes.has(drop_id):
		despawn_drop.rpc(drop_id)

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
			hud.add_console_line("Commands: help, clear, restart, menu, killall, wave, drop [type]")
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
		"drop":
			if not _is_server_authority():
				hud.add_console_line("Only the host can spawn drops.")
				return
			var requested_type: StringName = DROP_TYPES.pick_random()
			if parts.size() >= 2:
				var raw := String(parts[1]).to_lower()
				if DROP_TYPES.has(StringName(raw)):
					requested_type = StringName(raw)
				else:
					hud.add_console_line("Unknown drop type. Use: heal, max_health, speed, damage")
					return
			var pos: Vector3 = _pick_drop_position()
			var drop_id: int = next_drop_id
			next_drop_id += 1
			if multiplayer.has_multiplayer_peer():
				spawn_drop.rpc(drop_id, pos, requested_type)
			else:
				spawn_drop(drop_id, pos, requested_type)
			hud.add_console_line("Spawned %s drop." % requested_type)
		_:
			hud.add_console_line("Unknown command: %s" % command)
