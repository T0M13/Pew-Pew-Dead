extends Node

@export var zombie_scene: PackedScene
@export var spawn_points: Array[NodePath] = []
@export var waves: Array[int] = [5, 10, 15]
@export var spawn_interval: float = 0.7
@export var wave_break: float = 3.0

var current_wave: int = 0
var alive_count: int = 0
var spawned_count: int = 0
var to_spawn: int = 0
var spawning: bool = false

signal wave_started(wave_index: int, total: int)
signal zombie_killed(remaining: int)
signal all_waves_complete

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	_start_next_wave()

func _start_next_wave() -> void:
	if current_wave >= waves.size():
		all_waves_complete.emit()
		return
	to_spawn = waves[current_wave]
	spawned_count = 0
	alive_count = 0
	wave_started.emit(current_wave + 1, to_spawn)
	spawning = true
	while spawned_count < to_spawn:
		_spawn_one()
		await get_tree().create_timer(spawn_interval).timeout
	spawning = false
	if alive_count <= 0:
		_advance_wave()

func _spawn_one() -> void:
	if zombie_scene == null or spawn_points.is_empty():
		return
	var sp_path: NodePath = spawn_points.pick_random()
	var sp := get_node_or_null(sp_path)
	if sp == null:
		return
	var z = zombie_scene.instantiate()
	get_tree().current_scene.add_child(z)
	z.global_position = sp.global_position
	z.died.connect(_on_zombie_died)
	spawned_count += 1
	alive_count += 1

func _on_zombie_died(_z) -> void:
	alive_count -= 1
	zombie_killed.emit(alive_count)
	if alive_count <= 0 and not spawning:
		_advance_wave()

func _advance_wave() -> void:
	current_wave += 1
	await get_tree().create_timer(wave_break).timeout
	_start_next_wave()
