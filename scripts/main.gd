extends Node3D

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var wave_manager: Node = $WaveManager

func _ready() -> void:
	player.health_changed.connect(hud.set_health)
	player.died.connect(_on_player_died)
	hud.set_health(player.max_health, player.max_health)
	wave_manager.wave_started.connect(hud.set_wave)
	wave_manager.zombie_killed.connect(hud.register_kill)
	wave_manager.all_waves_complete.connect(_on_win)

func _on_player_died() -> void:
	hud.show_lose()
	player.set_physics_process(false)
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()

func _on_win() -> void:
	hud.show_win()
	await get_tree().create_timer(5.0).timeout
	get_tree().reload_current_scene()
