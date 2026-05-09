extends Node

@export var zombie_scene: PackedScene
@export var spawn_points: Array[NodePath] = []
@export var spawn_parent_path: NodePath = NodePath("../Zombies")
@export var base_wave_size: int = 5
@export var wave_size_growth: int = 3
@export var spawn_interval: float = 0.7
@export var spawn_interval_min: float = 0.22
@export var spawn_interval_decay: float = 0.04
@export var wave_break: float = 3.0
@export var drop_chance_per_wave: float = 0.55
@export var drop_chance_growth: float = 0.06
@export var drop_chance_max: float = 0.95

var current_wave: int = 0
var alive_count: int = 0
var spawned_count: int = 0
var to_spawn: int = 0
var spawning: bool = false
var running: bool = false

signal wave_started(wave_index: int, total: int)
signal zombie_killed(remaining: int)
signal zombie_spawned(zombie)
signal all_waves_complete
signal drop_requested(wave_index: int)
signal card_phase_requested(wave_index: int)
signal card_phase_done

func start_waves() -> void:
	if running:
		return
	running = true
	await get_tree().create_timer(1.0).timeout
	if running:
		_start_next_wave()

func reset_waves() -> void:
	current_wave = 0
	alive_count = 0
	spawned_count = 0
	to_spawn = 0
	spawning = false
	running = false

func _start_next_wave() -> void:
	if not running:
		return
	var wave_index: int = current_wave + 1
	to_spawn = base_wave_size + wave_size_growth * (wave_index - 1)
	spawned_count = 0
	alive_count = 0
	wave_started.emit(wave_index, to_spawn)
	spawning = true
	var boss_wave: bool = wave_index >= 5 and wave_index % 5 == 0
	if boss_wave:
		_spawn_boss(wave_index)
	var interval: float = maxf(spawn_interval_min, spawn_interval - spawn_interval_decay * float(wave_index - 1))
	while running and spawned_count < to_spawn:
		_spawn_one(wave_index)
		await get_tree().create_timer(interval).timeout
	spawning = false
	if running and alive_count <= 0:
		_advance_wave()

func _spawn_one(wave_index: int = 1) -> void:
	if zombie_scene == null or spawn_points.is_empty():
		return
	var sp_path: NodePath = spawn_points.pick_random()
	var sp := get_node_or_null(sp_path)
	var parent := get_node_or_null(spawn_parent_path)
	if sp == null or parent == null:
		return
	var z = zombie_scene.instantiate()
	z.variant = _pick_variant(wave_index)
	parent.add_child(z)
	z.global_position = sp.global_position
	z.died.connect(_on_zombie_died)
	if z.has_method("apply_wave_scaling"):
		z.apply_wave_scaling(wave_index)
	spawned_count += 1
	alive_count += 1
	zombie_spawned.emit(z)

func _pick_variant(wave_index: int) -> StringName:
	if wave_index <= 1:
		return &"walker"
	var roll: float = randf()
	if wave_index == 2:
		if roll < 0.18:
			return &"runner"
		return &"walker"
	if wave_index == 3:
		if roll < 0.28:
			return &"runner"
		if roll < 0.36:
			return &"spitter"
		return &"walker"
	# wave 4+: progressive mix, capped
	var brute_chance: float = clampf(0.04 + 0.025 * float(wave_index - 4), 0.0, 0.18)
	var exploder_chance: float = clampf(0.05 + 0.025 * float(wave_index - 4), 0.0, 0.20)
	var spitter_chance: float = clampf(0.10 + 0.03 * float(wave_index - 4), 0.10, 0.26)
	var runner_chance: float = clampf(0.22 + 0.03 * float(wave_index - 4), 0.22, 0.40)
	var c1: float = brute_chance
	var c2: float = c1 + exploder_chance
	var c3: float = c2 + spitter_chance
	var c4: float = c3 + runner_chance
	if roll < c1:
		return &"brute"
	if roll < c2:
		return &"exploder"
	if roll < c3:
		return &"spitter"
	if roll < c4:
		return &"runner"
	return &"walker"

func _spawn_boss(wave_index: int) -> void:
	if zombie_scene == null or spawn_points.is_empty():
		return
	var sp_path: NodePath = spawn_points.pick_random()
	var sp := get_node_or_null(sp_path)
	var parent := get_node_or_null(spawn_parent_path)
	if sp == null or parent == null:
		return
	var z = zombie_scene.instantiate()
	z.variant = &"boss"
	parent.add_child(z)
	z.global_position = sp.global_position
	z.died.connect(_on_zombie_died)
	if z.has_method("apply_wave_scaling"):
		z.apply_wave_scaling(wave_index)
	alive_count += 1
	zombie_spawned.emit(z)

func _on_zombie_died(zombie) -> void:
	alive_count -= 1
	zombie_killed.emit(alive_count)
	var root := get_parent()
	if root.has_method("despawn_zombie") and zombie.network_id > 0:
		root.despawn_zombie.rpc(zombie.network_id)
	if alive_count <= 0 and not spawning:
		_advance_wave()

func _advance_wave() -> void:
	current_wave += 1
	var chance: float = minf(drop_chance_max, drop_chance_per_wave + drop_chance_growth * float(current_wave - 1))
	if randf() < chance:
		drop_requested.emit(current_wave)
	card_phase_requested.emit(current_wave)
	await card_phase_done
	if not running:
		return
	await get_tree().create_timer(wave_break).timeout
	_start_next_wave()

func resolve_card_phase() -> void:
	card_phase_done.emit()
