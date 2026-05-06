extends CharacterBody3D

@export var move_speed: float = 2.6
@export var max_health: int = 2
@export var damage: int = 12
@export var attack_cooldown: float = 0.8

@onready var mesh_root: Node3D = $MeshRoot
@onready var attack_area: Area3D = $AttackArea

var network_id: int = -1
var health: int
var target: Node3D
var attack_timer: float = 0.0
var dying: bool = false
var bob_phase: float = 0.0
var remote_position: Vector3
var remote_yaw: float = 0.0

signal died(zombie)

func _ready() -> void:
	add_to_group("zombies")
	health = max_health
	bob_phase = randf() * TAU
	remote_position = global_position
	_select_target()

func _physics_process(delta: float) -> void:
	if dying:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_apply_remote_state(delta)
		return
	_select_target()
	if target == null:
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > 0.05:
		var dir := to_target.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		var look_target := target.global_position
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()
	_animate_bob(delta)
	attack_timer -= delta
	if attack_timer <= 0.0:
		for body in attack_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage") and not body.dead:
				body.take_damage(damage)
				attack_timer = attack_cooldown
				_lunge()
				break

func _apply_remote_state(delta: float) -> void:
	global_position = global_position.lerp(remote_position, min(14.0 * delta, 1.0))
	rotation.y = lerp_angle(rotation.y, remote_yaw, min(14.0 * delta, 1.0))
	_animate_bob(delta)

func _animate_bob(delta: float) -> void:
	bob_phase += delta * 8.0
	mesh_root.position.y = abs(sin(bob_phase)) * 0.08

func _select_target() -> void:
	var best_distance := INF
	target = null
	for player in get_tree().get_nodes_in_group("player"):
		if player.dead:
			continue
		var dist: float = player.global_position.distance_to(global_position)
		if dist < best_distance:
			best_distance = dist
			target = player

func _lunge() -> void:
	var t := create_tween()
	t.tween_property(mesh_root, "scale", Vector3(0.85, 1.15, 0.85), 0.06)
	t.tween_property(mesh_root, "scale", Vector3.ONE, 0.18)

func take_damage(amount: int) -> void:
	if dying:
		return
	health -= amount
	if health <= 0:
		_die()
	else:
		var t := create_tween()
		t.tween_property(mesh_root, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
		t.tween_property(mesh_root, "scale", Vector3.ONE, 0.12)

func apply_remote_state(pos: Vector3, yaw: float) -> void:
	remote_position = pos
	remote_yaw = yaw

func play_remote_death() -> void:
	if dying:
		return
	dying = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mesh_root, "scale", Vector3(1.5, 0.1, 1.5), 0.45)
	t.tween_property(mesh_root, "rotation", mesh_root.rotation + Vector3(0, PI, 0), 0.45)
	await t.finished
	queue_free()

func _die() -> void:
	dying = true
	set_collision_layer_value(3, false)
	set_collision_mask_value(2, false)
	died.emit(self)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mesh_root, "scale", Vector3(1.5, 0.1, 1.5), 0.45)
	t.tween_property(mesh_root, "rotation", mesh_root.rotation + Vector3(0, PI, 0), 0.45)
	await t.finished
	queue_free()
