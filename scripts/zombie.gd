extends CharacterBody3D

@export var move_speed: float = 2.6
@export var crawl_speed: float = 1.45
@export var max_health: int = 2
@export var damage: int = 12
@export var attack_cooldown: float = 0.8
@export var hit_flash_energy: float = 2.0

@onready var mesh_root: Node3D = $MeshRoot
@onready var attack_area: Area3D = $AttackArea
@onready var hit_light: OmniLight3D = $MeshRoot/HitLight
@onready var head_mesh: MeshInstance3D = $MeshRoot/Head
@onready var jaw_mesh: MeshInstance3D = $MeshRoot/Jaw
@onready var arm_l_mesh: MeshInstance3D = $MeshRoot/ArmL
@onready var arm_r_mesh: MeshInstance3D = $MeshRoot/ArmR
@onready var shoulder_l_mesh: MeshInstance3D = $MeshRoot/ShoulderL
@onready var shoulder_r_mesh: MeshInstance3D = $MeshRoot/ShoulderR
@onready var leg_l_mesh: MeshInstance3D = $MeshRoot/LegL
@onready var leg_r_mesh: MeshInstance3D = $MeshRoot/LegR
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var arm_l_hitbox: Area3D = $ArmLHitbox
@onready var arm_r_hitbox: Area3D = $ArmRHitbox
@onready var leg_l_hitbox: Area3D = $LegLHitbox
@onready var leg_r_hitbox: Area3D = $LegRHitbox

var network_id: int = -1
var health: int
var target: Node3D
var attack_timer: float = 0.0
var dying: bool = false
var bob_phase: float = 0.0
var remote_position: Vector3
var remote_yaw: float = 0.0
var crawl_mode: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO
var severed_parts: Dictionary = {}
var mesh_rest_y: float = 0.0

signal died(zombie)

func _ready() -> void:
	add_to_group("zombies")
	health = max_health
	bob_phase = randf() * TAU
	remote_position = global_position
	hit_light.light_energy = 0.0
	mesh_rest_y = mesh_root.position.y
	severed_parts = {
		"head": false,
		"arm_l": false,
		"arm_r": false,
		"leg_l": false,
		"leg_r": false,
	}
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
	var active_speed := crawl_speed if crawl_mode else move_speed
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > 0.05:
		var dir := to_target.normalized()
		velocity.x = dir.x * active_speed + knockback_velocity.x
		velocity.z = dir.z * active_speed + knockback_velocity.z
		var look_target := target.global_position
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
	else:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, min(delta * 6.5, 1.0))
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
	bob_phase += delta * (5.0 if crawl_mode else 8.0)
	var bob_height: float = abs(sin(bob_phase)) * (0.04 if crawl_mode else 0.08)
	var crawl_offset: float = -0.38 if crawl_mode else 0.0
	mesh_root.position.y = mesh_rest_y + crawl_offset + bob_height

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
	_flash_hit_light(1.6, Color(1.0, 0.55, 0.32), 0.16)
	var t := create_tween()
	t.tween_property(mesh_root, "scale", Vector3(0.85, 1.15, 0.85), 0.06)
	t.tween_property(mesh_root, "scale", Vector3.ONE, 0.18)

func take_damage(amount: int) -> void:
	take_hit("torso", amount, Vector3.ZERO, 0.0)

func take_hit(zone_name: String, amount: int, impulse_direction: Vector3 = Vector3.ZERO, force: float = 0.0) -> void:
	if dying:
		return
	var applied_damage := amount
	match zone_name:
		"head":
			if randf() < 0.78:
				applied_damage = max_health
			else:
				applied_damage = max(amount, 2)
			if randf() < 0.85:
				_sever_head(impulse_direction, force)
		"arm_l":
			if randf() < 0.68:
				_sever_arm(true, impulse_direction, force)
		"arm_r":
			if randf() < 0.68:
				_sever_arm(false, impulse_direction, force)
		"leg_l":
			if randf() < 0.74:
				_sever_leg(true, impulse_direction, force)
		"leg_r":
			if randf() < 0.74:
				_sever_leg(false, impulse_direction, force)
		_:
			pass
	if impulse_direction.length() > 0.01 and force > 0.0:
		apply_impulse(impulse_direction, force)
	health -= applied_damage
	if health <= 0:
		_die()
	else:
		_flash_hit_light(hit_flash_energy, Color(1.0, 0.42, 0.35), 0.18)
		var t := create_tween()
		t.tween_property(mesh_root, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
		t.tween_property(mesh_root, "scale", Vector3.ONE, 0.12)

func apply_remote_state(pos: Vector3, yaw: float) -> void:
	remote_position = pos
	remote_yaw = yaw

func apply_impulse(direction: Vector3, force: float) -> void:
	if direction.length() <= 0.01:
		return
	knockback_velocity += direction.normalized() * force

func play_remote_death() -> void:
	if dying:
		return
	dying = true
	_flash_hit_light(3.8, Color(1.0, 0.8, 0.45), 0.34)
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
	_disable_all_hitboxes()
	died.emit(self)
	_flash_hit_light(3.8, Color(1.0, 0.8, 0.45), 0.34)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mesh_root, "scale", Vector3(1.5, 0.1, 1.5), 0.45)
	t.tween_property(mesh_root, "rotation", mesh_root.rotation + Vector3(0, PI, 0), 0.45)
	await t.finished
	queue_free()

func _flash_hit_light(energy: float, color: Color, duration: float) -> void:
	hit_light.light_color = color
	hit_light.light_energy = energy
	var t := create_tween()
	t.tween_property(hit_light, "light_energy", 0.0, duration)

func _sever_head(direction: Vector3, force: float) -> void:
	if severed_parts["head"]:
		return
	severed_parts["head"] = true
	head_hitbox.monitoring = false
	_spawn_detached_piece(head_mesh, direction, force + 2.5, 0.9)
	_spawn_detached_piece(jaw_mesh, direction, force + 1.0, 0.6)
	head_mesh.visible = false
	jaw_mesh.visible = false

func _sever_arm(is_left: bool, direction: Vector3, force: float) -> void:
	var key := "arm_l" if is_left else "arm_r"
	if severed_parts[key]:
		return
	severed_parts[key] = true
	var mesh := arm_l_mesh if is_left else arm_r_mesh
	var shoulder := shoulder_l_mesh if is_left else shoulder_r_mesh
	var hitbox := arm_l_hitbox if is_left else arm_r_hitbox
	hitbox.monitoring = false
	_spawn_detached_piece(mesh, direction, force + 1.8, 0.55)
	mesh.visible = false
	shoulder.visible = false

func _sever_leg(is_left: bool, direction: Vector3, force: float) -> void:
	var key := "leg_l" if is_left else "leg_r"
	if severed_parts[key]:
		return
	severed_parts[key] = true
	var mesh := leg_l_mesh if is_left else leg_r_mesh
	var hitbox := leg_l_hitbox if is_left else leg_r_hitbox
	hitbox.monitoring = false
	_spawn_detached_piece(mesh, direction, force + 1.5, 0.7)
	mesh.visible = false
	if not crawl_mode:
		crawl_mode = true
		attack_area.position.y = 0.55

func _spawn_detached_piece(mesh: MeshInstance3D, direction: Vector3, force: float, torque_scale: float) -> void:
	if mesh == null or not mesh.visible:
		return
	var gib := RigidBody3D.new()
	gib.name = "%s_Gib" % mesh.name
	gib.global_transform = mesh.global_transform
	gib.gravity_scale = 1.0
	gib.mass = 0.3
	gib.freeze = true
	gib.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	gib.collision_layer = 16
	gib.collision_mask = 1
	var visual := MeshInstance3D.new()
	visual.mesh = mesh.mesh
	visual.material_override = mesh.material_override
	gib.add_child(visual)
	var shape := CollisionShape3D.new()
	var aabb := mesh.mesh.get_aabb()
	var box := BoxShape3D.new()
	box.size = aabb.size
	shape.shape = box
	gib.add_child(shape)
	get_tree().current_scene.add_child(gib)
	var impulse_dir := direction.normalized() if direction.length() > 0.01 else Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3)).normalized()
	gib.freeze = false
	gib.linear_velocity = impulse_dir * force + Vector3(0.0, 1.8, 0.0)
	gib.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-3.0, 3.0), randf_range(-1.0, 1.0)) * torque_scale

func _disable_all_hitboxes() -> void:
	for hitbox in [head_hitbox, arm_l_hitbox, arm_r_hitbox, leg_l_hitbox, leg_r_hitbox]:
		hitbox.monitoring = false
