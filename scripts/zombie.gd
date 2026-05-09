extends CharacterBody3D

@export var move_speed: float = 2.6
@export var crawl_speed: float = 1.45
@export var max_health: int = 2
@export var damage: int = 12
@export var attack_cooldown: float = 0.8
@export var hit_flash_energy: float = 2.0
@export var gib_lifetime: float = 2.5
@export var attack_windup: float = 0.45
@export var attack_telegraph_color: Color = Color(1.0, 0.55, 0.32)
@export var variant: StringName = &"walker"
@export var spit_scene: PackedScene = preload("res://scenes/zombie_spit.tscn")
@export var spit_cooldown: float = 1.9
@export var spit_min_range: float = 4.0
@export var spit_max_range: float = 16.0
@export var spit_preferred_range: float = 7.5

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
var slow_timer: float = 0.0
var poison_timer: float = 0.0
var poison_tick_timer: float = 0.0
var attack_state: int = 0
var windup_timer: float = 0.0
var windup_target: Node = null
var windup_tween: Tween
var spit_timer: float = 0.0
var mesh_base_colors: Dictionary[StandardMaterial3D, Color] = {}
var hit_flash_tween: Tween

signal died(zombie)

func apply_wave_scaling(wave_index: int) -> void:
	var tier: int = max(0, (wave_index - 1) / 3)
	var multiplier: float = 1.0 + minf(float(tier), 6.0) * 0.05
	match variant:
		&"runner":
			max_health = 1 + tier / 2
			move_speed = 5.6 * multiplier
			crawl_speed = 2.6 * multiplier
		&"spitter":
			max_health = 2 + tier
			move_speed = 1.9 * multiplier
			crawl_speed = 1.0 * multiplier
		_:
			max_health = 2 + tier
			move_speed = 2.6 * multiplier
			crawl_speed = 1.45 * multiplier
	health = max_health

func _ready() -> void:
	add_to_group("zombies")
	_apply_variant_config()
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
	_prepare_hit_flash_materials()
	_select_target()

func _apply_variant_config() -> void:
	match variant:
		&"runner":
			move_speed = 5.6
			max_health = 1
			damage = 8
			attack_cooldown = 0.55
			attack_windup = 0.32
			mesh_root.scale = Vector3(0.85, 0.85, 0.85)
			_tint_meshes(Color(0.95, 0.45, 0.4), Color(0.65, 0.32, 0.3))
		&"spitter":
			move_speed = 1.9
			max_health = 2
			damage = 6
			attack_cooldown = 1.0
			attack_windup = 0.55
			mesh_root.scale = Vector3(1.05, 1.05, 1.05)
			_tint_meshes(Color(0.78, 0.55, 1.0), Color(0.45, 0.3, 0.62))
		_:
			pass

func _tint_meshes(skin: Color, dark: Color) -> void:
	for child in mesh_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		var mat := mi.material_override
		if not (mat is StandardMaterial3D):
			continue
		var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		var name_lower := mi.name.to_lower()
		if name_lower.contains("eye") or name_lower.contains("pupil"):
			mi.material_override = dup
			continue
		if dup.albedo_color.r < 0.55 and dup.albedo_color.g < 0.75:
			dup.albedo_color = dark
		else:
			dup.albedo_color = skin
		mi.material_override = dup

func _physics_process(delta: float) -> void:
	if dying:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_apply_remote_state(delta)
		return
	_update_status_effects(delta)
	_select_target()
	if target == null:
		return
	var active_speed := crawl_speed if crawl_mode else move_speed
	if slow_timer > 0.0:
		active_speed *= 0.52
	var to_target := target.global_position - global_position
	var dist := Vector2(to_target.x, to_target.z).length()
	to_target.y = 0.0
	var move_intent: Vector3 = Vector3.ZERO
	if to_target.length() > 0.05:
		var dir := to_target.normalized()
		match variant:
			&"spitter":
				if dist > spit_preferred_range + 0.5:
					move_intent = dir * active_speed
				elif dist < spit_preferred_range - 1.5:
					move_intent = -dir * active_speed * 0.6
			_:
				move_intent = dir * active_speed
		var look_target := target.global_position
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
	velocity.x = move_intent.x + knockback_velocity.x
	velocity.z = move_intent.z + knockback_velocity.z
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, min(delta * 6.5, 1.0))
	_animate_bob(delta)
	_update_attack_state(delta)
	if variant == &"spitter":
		_update_spit_attack(delta, dist)

func _update_attack_state(delta: float) -> void:
	match attack_state:
		0:
			attack_timer = max(0.0, attack_timer - delta)
			if attack_timer <= 0.0:
				var victim := _find_attack_target()
				if victim != null:
					_begin_windup(victim)
		1:
			windup_timer -= delta
			if windup_target == null or not is_instance_valid(windup_target) or windup_target.dead:
				_cancel_windup()
				return
			if windup_timer <= 0.0:
				_resolve_attack()
		2:
			attack_timer = max(0.0, attack_timer - delta)
			if attack_timer <= 0.0:
				attack_state = 0

func _find_attack_target() -> Node:
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage") and not body.dead:
			return body
	return null

func _begin_windup(victim: Node) -> void:
	attack_state = 1
	windup_timer = attack_windup
	windup_target = victim
	if windup_tween:
		windup_tween.kill()
	hit_light.light_color = attack_telegraph_color
	hit_light.light_energy = 0.0
	windup_tween = create_tween()
	windup_tween.tween_property(hit_light, "light_energy", 2.4, attack_windup * 0.85)
	var pop := create_tween()
	pop.tween_property(mesh_root, "scale", Vector3(0.92, 1.12, 0.92), attack_windup * 0.6)
	pop.tween_property(mesh_root, "scale", Vector3(1.18, 0.86, 1.18), attack_windup * 0.4)

func _cancel_windup() -> void:
	if windup_tween:
		windup_tween.kill()
	hit_light.light_energy = 0.0
	mesh_root.scale = Vector3.ONE
	windup_target = null
	attack_state = 2
	attack_timer = attack_cooldown * 0.5

func _resolve_attack() -> void:
	var still_in_range := false
	if windup_target != null and is_instance_valid(windup_target) and not windup_target.dead:
		for body in attack_area.get_overlapping_bodies():
			if body == windup_target:
				still_in_range = true
				break
	if still_in_range:
		windup_target.take_damage(damage)
		_lunge()
	else:
		_lunge_whiff()
	windup_target = null
	attack_state = 2
	attack_timer = attack_cooldown

func _update_spit_attack(delta: float, dist: float) -> void:
	spit_timer = max(0.0, spit_timer - delta)
	if target == null or not is_instance_valid(target) or target.dead:
		return
	if dist < spit_min_range or dist > spit_max_range:
		return
	if spit_timer > 0.0:
		return
	_fire_spit()
	spit_timer = spit_cooldown

func _fire_spit() -> void:
	if spit_scene == null or target == null:
		return
	var spit = spit_scene.instantiate()
	get_tree().current_scene.add_child(spit)
	var origin: Vector3 = global_position + Vector3(0.0, 1.55, 0.0)
	var aim: Vector3 = target.global_position + Vector3(0.0, 0.85, 0.0)
	var dir: Vector3 = (aim - origin).normalized()
	spit.global_position = origin
	if spit.has_method("launch"):
		spit.launch(dir)
	hit_light.light_color = Color(0.6, 1.0, 0.4)
	hit_light.light_energy = 1.8
	var t := create_tween()
	t.tween_property(hit_light, "light_energy", 0.0, 0.25)

func _lunge_whiff() -> void:
	hit_light.light_energy = 0.0
	var t := create_tween()
	t.tween_property(mesh_root, "scale", Vector3(1.05, 0.95, 1.05), 0.08)
	t.tween_property(mesh_root, "scale", Vector3.ONE, 0.18)

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

func take_damage(
	amount: int,
	hit_direction: Vector3 = Vector3.ZERO,
	hit_color: Color = Color.WHITE,
	hit_effect: StringName = &"",
	charge: float = 0.0
) -> void:
	if dying:
		return
	take_hit("torso", amount, hit_direction, 0.0, hit_color, hit_effect, charge)

func take_hit(
	zone_name: String,
	amount: int,
	impulse_direction: Vector3 = Vector3.ZERO,
	force: float = 0.0,
	hit_color: Color = Color(1.0, 0.42, 0.35),
	hit_effect: StringName = &"",
	charge: float = 0.0
) -> void:
	if dying:
		return
	if hit_effect != &"":
		_apply_hit_effect(impulse_direction, hit_effect, charge)
	_flash_hit(hit_color)
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
			if randf() < 0.35:
				_sever_random_part(impulse_direction, force)
	if impulse_direction.length() > 0.01 and force > 0.0:
		apply_impulse(impulse_direction, force)
	health -= applied_damage
	if health <= 0:
		_die()
	else:
		_flash_hit_light(hit_flash_energy, hit_color, 0.18)
		var t := create_tween()
		t.tween_property(mesh_root, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
		t.tween_property(mesh_root, "scale", Vector3.ONE, 0.12)

func _apply_hit_effect(hit_direction: Vector3, hit_effect: StringName, charge: float) -> void:
	match hit_effect:
		&"frost":
			slow_timer = max(slow_timer, 0.9 + charge * 0.7)
		&"venom":
			poison_timer = max(poison_timer, 1.4 + charge * 0.8)
			poison_tick_timer = min(poison_tick_timer, 0.35)
		&"knockback":
			apply_impulse(hit_direction, 2.8 + charge * 4.0)

func _update_status_effects(delta: float) -> void:
	slow_timer = max(0.0, slow_timer - delta)
	if poison_timer <= 0.0:
		return
	poison_timer = max(0.0, poison_timer - delta)
	poison_tick_timer -= delta
	if poison_tick_timer <= 0.0:
		poison_tick_timer = 0.7
		_apply_poison_tick()

func _apply_poison_tick() -> void:
	if dying:
		return
	health -= 1
	_flash_hit_light(0.9, Color(0.5, 1.0, 0.25), 0.18)
	if health <= 0:
		_die()

func _prepare_hit_flash_materials() -> void:
	for child in mesh_root.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var material := mesh_instance.material_override as StandardMaterial3D
			if material:
				var duplicate := material.duplicate() as StandardMaterial3D
				mesh_instance.material_override = duplicate
				mesh_base_colors[duplicate] = duplicate.albedo_color

func _flash_hit(hit_color: Color) -> void:
	if hit_flash_tween:
		hit_flash_tween.kill()
	for material in mesh_base_colors:
		material.albedo_color = hit_color.lerp(Color.WHITE, 0.35)
		material.emission_enabled = true
		material.emission = hit_color
		material.emission_energy_multiplier = 1.8
	hit_flash_tween = create_tween()
	hit_flash_tween.tween_interval(0.08)
	hit_flash_tween.tween_callback(_restore_hit_flash_materials)

func _restore_hit_flash_materials() -> void:
	for material in mesh_base_colors:
		material.albedo_color = mesh_base_colors[material]
		material.emission_enabled = false

func get_zone_for_point(world_point: Vector3) -> String:
	var entries: Array = [
		["head", head_hitbox, 0.7],
		["arm_l", arm_l_hitbox, 0.7],
		["arm_r", arm_r_hitbox, 0.7],
		["leg_l", leg_l_hitbox, 0.65],
		["leg_r", leg_r_hitbox, 0.65],
	]
	var best_zone: String = "torso"
	var best_score: float = INF
	for e in entries:
		var hb: Area3D = e[1]
		if hb == null or not hb.monitoring:
			continue
		var center: Vector3 = _zone_center(hb)
		var dist: float = center.distance_to(world_point)
		var threshold: float = e[2]
		if dist < threshold and dist < best_score:
			best_score = dist
			best_zone = e[0]
	return best_zone

func _zone_center(hitbox: Area3D) -> Vector3:
	if hitbox.get_child_count() > 0:
		var shape := hitbox.get_child(0)
		if shape is Node3D:
			return (shape as Node3D).global_position
	return hitbox.global_position

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
	_explode_into_gibs()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mesh_root, "scale", Vector3(1.5, 0.1, 1.5), 0.45)
	t.tween_property(mesh_root, "rotation", mesh_root.rotation + Vector3(0, PI, 0), 0.45)
	await t.finished
	queue_free()

func _explode_into_gibs() -> void:
	var dir := Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	if dir.length() < 0.05:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	if not severed_parts["head"]:
		_sever_head(dir + Vector3(0.0, 0.6, 0.0), 4.0)
	if not severed_parts["arm_l"]:
		_sever_arm(true, Vector3(-1.0, 0.5, randf_range(-0.4, 0.4)).normalized(), 3.2)
	if not severed_parts["arm_r"]:
		_sever_arm(false, Vector3(1.0, 0.5, randf_range(-0.4, 0.4)).normalized(), 3.2)
	if not severed_parts["leg_l"]:
		_sever_leg(true, Vector3(-0.6, 0.5, randf_range(-0.4, 0.4)).normalized(), 2.8)
	if not severed_parts["leg_r"]:
		_sever_leg(false, Vector3(0.6, 0.5, randf_range(-0.4, 0.4)).normalized(), 2.8)
	var torso: MeshInstance3D = $MeshRoot/Body
	if torso and torso.visible:
		_spawn_detached_piece(torso, dir + Vector3(0.0, 0.4, 0.0), 3.0, 0.6)
		torso.visible = false

func _sever_random_part(direction: Vector3, force: float) -> void:
	var keys: Array[String] = []
	for key in severed_parts.keys():
		if not severed_parts[key]:
			keys.append(String(key))
	if keys.is_empty():
		return
	var pick: String = keys.pick_random()
	match pick:
		"head":
			_sever_head(direction, force + 1.0)
		"arm_l":
			_sever_arm(true, direction, force)
		"arm_r":
			_sever_arm(false, direction, force)
		"leg_l":
			_sever_leg(true, direction, force)
		"leg_r":
			_sever_leg(false, direction, force)

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
	var aabb: AABB = mesh.mesh.get_aabb()
	var box_size := Vector3(maxf(aabb.size.x, 0.18), maxf(aabb.size.y, 0.18), maxf(aabb.size.z, 0.18))
	var spawn_origin: Vector3 = mesh.global_position + Vector3(0.0, 0.05, 0.0)
	var spawn_basis: Basis = mesh.global_transform.basis.orthonormalized()
	var gib := RigidBody3D.new()
	gib.name = "%s_Gib" % mesh.name
	gib.gravity_scale = 1.0
	gib.mass = 0.4
	gib.linear_damp = 0.5
	gib.angular_damp = 0.6
	gib.collision_layer = 16
	gib.collision_mask = 1
	gib.continuous_cd = true
	var visual := MeshInstance3D.new()
	visual.mesh = mesh.mesh
	visual.material_override = mesh.material_override
	gib.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	gib.add_child(shape)
	get_tree().current_scene.add_child(gib)
	gib.global_transform = Transform3D(spawn_basis, spawn_origin)
	var impulse_dir: Vector3
	if direction.length() > 0.01:
		impulse_dir = (direction.normalized() + Vector3.UP * 0.35).normalized()
	else:
		impulse_dir = Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)).normalized()
	var launch_speed: float = clampf(force + 2.0, 3.5, 8.5)
	gib.linear_velocity = impulse_dir * launch_speed + Vector3(0.0, 2.6, 0.0)
	gib.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-3.0, 3.0), randf_range(-1.0, 1.0)) * (torque_scale + 1.6)
	var lifetime_timer := Timer.new()
	lifetime_timer.wait_time = gib_lifetime
	lifetime_timer.one_shot = true
	lifetime_timer.autostart = true
	gib.add_child(lifetime_timer)
	lifetime_timer.timeout.connect(gib.queue_free)

func _disable_all_hitboxes() -> void:
	for hitbox in [head_hitbox, arm_l_hitbox, arm_r_hitbox, leg_l_hitbox, leg_r_hitbox]:
		hitbox.monitoring = false
