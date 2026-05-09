extends CharacterBody3D

@export var move_speed: float = 7.6
@export var sprint_multiplier: float = 1.7
@export var sprint_acceleration: float = 48.0
@export var ground_friction: float = 9.0
@export var air_acceleration: float = 36.0
@export var air_speed_cap: float = 14.0
@export var air_strafe_wishspeed: float = 13.0
@export var slide_initial_speed: float = 15.5
@export var slide_duration: float = 0.8
@export var slide_camera_drop: float = 0.34
@export var coyote_time_window: float = 0.14
@export var jump_buffer_window: float = 0.14
@export var jump_velocity: float = 6.2
@export var mouse_sensitivity: float = 0.0025
@export var max_health: int = 100
@export var sprint_fov: float = 86.0
@export var melee_range: float = 2.6
@export var melee_angle_dot: float = 0.45
@export var melee_cooldown: float = 0.45
@export var melee_force: float = 8.0
@export var bunnyhop_speed_boost: float = 1.025
@export var stamina_max: float = 100.0
@export var stamina_per_jump: float = 18.0
@export var stamina_regen: float = 22.0
@export var stamina_regen_delay: float = 0.25
@export var stamina_min_to_jump: float = 14.0
@export var projectile_scene: PackedScene
@export var max_charge_time: float = 0.9
@export var pickup_heal_amount: int = 35
@export var pickup_max_health_step: int = 20
@export var pickup_speed_step: float = 0.55
@export var pickup_damage_step: int = 1

var damage_bonus: int = 0

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var muzzle_flash: MeshInstance3D = $Head/Camera3D/Gun/MuzzleFlash
@onready var muzzle_light: OmniLight3D = $Head/Camera3D/Gun/MuzzleLight
@onready var gun: Node3D = $Head/Camera3D/Gun
@onready var avatar_root: Node3D = $AvatarRoot
@onready var head_mesh: MeshInstance3D = $Head/HeadMesh

const PROJECTILE_ELEMENTS := [
	{"name": &"solar", "color": Color(1.0, 0.78, 0.12, 1.0)},
	{"name": &"frost", "color": Color(0.2, 0.82, 1.0, 1.0)},
	{"name": &"venom", "color": Color(0.35, 1.0, 0.26, 1.0)},
	{"name": &"knockback", "color": Color(1.0, 0.32, 0.78, 1.0)},
]

var health: int
var mouse_captured: bool = false
var dead: bool = false
var owning_peer_id: int = 1
var local_peer_id: int = 1
var remote_position: Vector3
var remote_yaw: float = 0.0
var remote_pitch: float = 0.0
var base_fov: float = 0.0
var head_default_y: float = 0.0
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var slide_timer: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO
var sprinting: bool = false
var melee_timer: float = 0.0
var input_blocked: bool = false
var gun_rest_position: Vector3 = Vector3.ZERO
var recoil_tween: Tween
var muzzle_tween: Tween
var camera_kick_tween: Tween
var was_on_floor: bool = false
var charging_shot: bool = false
var charge_time: float = 0.0
var projectile_index: int = 0
var stamina: float = 0.0
var stamina_regen_timer: float = 0.0

signal health_changed(value: int, max_value: int)
signal stamina_changed(value: float, max_value: float)
signal died

func _ready() -> void:
	add_to_group("player")
	health = max_health
	stamina = stamina_max
	muzzle_flash.material_override = muzzle_flash.material_override.duplicate()
	muzzle_flash.visible = false
	muzzle_light.light_energy = 0.0
	remote_position = global_position
	base_fov = camera.fov
	head_default_y = head.position.y
	gun_rest_position = gun.position
	_update_local_visual_mode()
	if _is_locally_controlled():
		_capture_mouse()

func configure_for_peer(peer_id: int, current_local_peer_id: int) -> void:
	owning_peer_id = peer_id
	local_peer_id = current_local_peer_id
	if is_inside_tree():
		_update_local_visual_mode()
		if _is_locally_controlled() and not dead and not input_blocked:
			_capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if dead or not _is_locally_controlled() or input_blocked:
		return
	if event is InputEventMouseMotion and mouse_captured:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo and _is_slide_key(event):
		if _can_start_slide():
			_start_slide()
	elif event.is_action_pressed("slide"):
		if _can_start_slide():
			_start_slide()
	elif event.is_action_pressed("melee"):
		_try_melee_attack()
	elif event.is_action_pressed("shoot"):
		if not mouse_captured:
			_capture_mouse()
		else:
			_start_charging_shot()
	elif event.is_action_released("shoot") and charging_shot:
		_shoot(charge_time / max_charge_time)
	elif event.is_action_pressed("ui_unpause"):
		_release_mouse()

func _physics_process(delta: float) -> void:
	melee_timer = max(0.0, melee_timer - delta)
	if dead:
		return
	if _is_locally_controlled():
		if charging_shot:
			_update_charge(delta)
		_run_local_movement(delta)
		if multiplayer.has_multiplayer_peer():
			sync_player_state.rpc(global_position, head.rotation.y, camera.rotation.x, velocity)
	else:
		_apply_remote_movement(delta)

func _run_local_movement(delta: float) -> void:
	if input_blocked:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 2.0 * delta)
		move_and_slide()
		_restore_view(delta)
		return

	if Input.is_action_pressed("jump"):
		jump_buffer_timer = jump_buffer_window
	else:
		jump_buffer_timer = max(0.0, jump_buffer_timer - delta)

	var on_floor := is_on_floor()
	if on_floor:
		coyote_timer = coyote_time_window
	else:
		coyote_timer = max(0.0, coyote_timer - delta)

	if not on_floor:
		velocity.y -= 20.0 * delta
	_tick_stamina(delta)
	var jumped_this_frame := false
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and stamina >= stamina_min_to_jump:
		velocity.y = jump_velocity
		if was_on_floor:
			velocity.x *= bunnyhop_speed_boost
			velocity.z *= bunnyhop_speed_boost
		stamina = maxf(0.0, stamina - stamina_per_jump)
		stamina_regen_timer = stamina_regen_delay
		stamina_changed.emit(stamina, stamina_max)
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jumped_this_frame = true

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -head.global_transform.basis.z
	var right := head.global_transform.basis.x
	var direction := (right * input_dir.x - forward * input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	slide_timer = max(0.0, slide_timer - delta)
	if slide_timer > 0.0:
		var slide_alpha := slide_timer / slide_duration
		var slide_speed := lerpf(move_speed * 1.05, slide_initial_speed, slide_alpha)
		velocity.x = slide_direction.x * slide_speed
		velocity.z = slide_direction.z * slide_speed
		sprinting = false
	else:
		sprinting = on_floor and Input.is_action_pressed("sprint") and direction.length() > 0.0
		var target_speed := move_speed * (sprint_multiplier if sprinting else 1.0)
		var horiz_velocity := Vector3(velocity.x, 0.0, velocity.z)
		if on_floor and not jumped_this_frame:
			horiz_velocity = horiz_velocity.move_toward(Vector3.ZERO, ground_friction * delta)
		var use_air_branch: bool = not on_floor or jumped_this_frame
		if direction.length() > 0.0:
			if not use_air_branch:
				horiz_velocity = horiz_velocity.move_toward(direction * target_speed, sprint_acceleration * delta)
			else:
				var projected: float = horiz_velocity.dot(direction)
				var wishspeed: float = air_strafe_wishspeed
				var add_speed: float = minf(wishspeed - projected, air_acceleration * delta)
				if add_speed > 0.0:
					horiz_velocity += direction * add_speed
				var horiz_speed: float = horiz_velocity.length()
				if horiz_speed > air_speed_cap:
					horiz_velocity = horiz_velocity.normalized() * air_speed_cap
		else:
			if on_floor:
				horiz_velocity = horiz_velocity.move_toward(Vector3.ZERO, ground_friction * delta)
		velocity.x = horiz_velocity.x
		velocity.z = horiz_velocity.z

	move_and_slide()
	if slide_timer > 0.0:
		_process_slide_collisions()
	_update_view_juice(delta)
	was_on_floor = is_on_floor()

func _tick_stamina(delta: float) -> void:
	if stamina_regen_timer > 0.0:
		stamina_regen_timer = max(0.0, stamina_regen_timer - delta)
		return
	if stamina >= stamina_max:
		return
	var prev := stamina
	stamina = minf(stamina_max, stamina + stamina_regen * delta)
	if not is_equal_approx(prev, stamina):
		stamina_changed.emit(stamina, stamina_max)

func _apply_remote_movement(delta: float) -> void:
	global_position = global_position.lerp(remote_position, min(12.0 * delta, 1.0))
	rotation.y = lerp_angle(rotation.y, remote_yaw, min(12.0 * delta, 1.0))
	head.rotation.y = rotation.y
	camera.rotation.x = lerp(camera.rotation.x, remote_pitch, min(14.0 * delta, 1.0))

func _start_charging_shot() -> void:
	charging_shot = true
	charge_time = 0.0
	muzzle_flash.visible = true

func _update_charge(delta: float) -> void:
	charge_time = min(charge_time + delta, max_charge_time)
	var charge_level := charge_time / max_charge_time
	var pulse := 1.0 + charge_level * 1.1 + sin(Time.get_ticks_msec() * 0.025) * 0.08
	muzzle_flash.scale = Vector3.ONE * pulse

func _shoot(charge_level: float) -> void:
	charging_shot = false
	charge_level = clamp(charge_level, 0.0, 1.0)
	var element = PROJECTILE_ELEMENTS[projectile_index % PROJECTILE_ELEMENTS.size()]
	projectile_index += 1
	var shot_color: Color = element.color
	var shot_effect: StringName = element.name
	_play_shot_feedback(shot_color, charge_level)
	if projectile_scene == null:
		push_warning("Player cannot shoot because no projectile scene is assigned.")
		return
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.configure(shot_color, shot_effect, charge_level, damage_bonus)
	projectile.launch(muzzle_flash.global_position, -camera.global_transform.basis.z.normalized())

func _try_melee_attack() -> void:
	if melee_timer > 0.0:
		return
	melee_timer = melee_cooldown
	_play_melee_feedback()
	var best_target: Node = null
	var best_zone := "torso"
	var best_distance: float = INF
	var forward: Vector3 = -head.global_transform.basis.z.normalized()
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(zombie) or zombie.dying:
			continue
		var to_target: Vector3 = zombie.global_position - global_position
		var distance: float = to_target.length()
		if distance > melee_range or distance <= 0.01:
			continue
		var dot := forward.dot(to_target.normalized())
		if dot < melee_angle_dot:
			continue
		if distance < best_distance:
			best_distance = distance
			best_target = zombie
			best_zone = "torso"
	if best_target == null:
		return
	_apply_zombie_hit(best_target, best_zone, 1, forward, melee_force)

func _extract_hit_data(collider: Object) -> Dictionary:
	if collider == null:
		return {}
	if collider.has_method("get_zombie") and collider.has_method("get_hit_zone"):
		var zombie = collider.get_zombie()
		if zombie:
			return {"zombie": zombie, "zone": collider.get_hit_zone(), "amount": 1}
	if collider.is_in_group("zombies"):
		return {"zombie": collider, "zone": "torso", "amount": 1}
	if collider.has_method("take_hit"):
		return {"zombie": collider.get_parent(), "zone": "torso", "amount": 1}
	return {}

func _apply_zombie_hit(zombie: Node, zone_name: String, amount: int, impulse_direction: Vector3, force: float) -> void:
	if zombie == null:
		return
	if not multiplayer.has_multiplayer_peer():
		zombie.take_hit(zone_name, amount, impulse_direction, force)
	elif multiplayer.is_server():
		zombie.take_hit(zone_name, amount, impulse_direction, force)
	else:
		var root := get_tree().current_scene
		if root and root.has_method("request_zombie_hit"):
			root.request_zombie_hit.rpc_id(1, zombie.network_id, zone_name, amount, impulse_direction, force)

func _process_slide_collisions() -> void:
	for idx in range(get_slide_collision_count()):
		var collision := get_slide_collision(idx)
		if collision == null:
			continue
		var collider := collision.get_collider()
		if collider and collider.is_in_group("zombies"):
			var direction := Vector3(velocity.x, 0.0, velocity.z).normalized()
			if direction.length() <= 0.01:
				direction = -head.global_transform.basis.z
			_apply_zombie_hit(collider, "torso", 1, direction, melee_force + 2.5)

func _play_shot_feedback(shot_color: Color, charge_level: float) -> void:
	if recoil_tween:
		recoil_tween.kill()
	if muzzle_tween:
		muzzle_tween.kill()
	if camera_kick_tween:
		camera_kick_tween.kill()
	gun.position = gun_rest_position
	_set_muzzle_color(shot_color)
	muzzle_flash.visible = true
	muzzle_flash.scale = Vector3.ONE * (1.0 + charge_level * 1.2)
	muzzle_light.light_color = shot_color
	muzzle_light.light_energy = 2.6 + charge_level * 2.2
	muzzle_tween = create_tween()
	muzzle_tween.tween_interval(0.05)
	muzzle_tween.tween_callback(func():
		muzzle_flash.visible = false
		muzzle_flash.scale = Vector3.ONE
		muzzle_light.light_energy = 0.0
	)
	var recoil := Vector3(0, 0.014 + charge_level * 0.02, 0.1 + charge_level * 0.12)
	recoil_tween = create_tween()
	recoil_tween.tween_property(gun, "position", gun_rest_position + recoil, 0.035)
	recoil_tween.tween_property(gun, "position", gun_rest_position, 0.12)
	var orig_x := camera.rotation.x
	camera_kick_tween = create_tween()
	camera_kick_tween.tween_property(camera, "rotation:x", orig_x + 0.018 + charge_level * 0.018, 0.025)
	camera_kick_tween.tween_property(camera, "rotation:x", orig_x, 0.11)

func _set_muzzle_color(shot_color: Color) -> void:
	var material := muzzle_flash.material_override as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = shot_color
	material.emission = shot_color
	material.emission_energy_multiplier = 4.0

func _play_melee_feedback() -> void:
	if recoil_tween:
		recoil_tween.kill()
	gun.position = gun_rest_position
	recoil_tween = create_tween()
	recoil_tween.tween_property(gun, "rotation_degrees:z", -14.0, 0.06)
	recoil_tween.tween_property(gun, "rotation_degrees:z", 0.0, 0.12)

func apply_pickup(drop_type: StringName) -> void:
	if dead:
		return
	match drop_type:
		&"heal":
			health = min(max_health, health + pickup_heal_amount)
			health_changed.emit(health, max_health)
		&"max_health":
			max_health += pickup_max_health_step
			health = min(max_health, health + pickup_max_health_step)
			health_changed.emit(health, max_health)
		&"speed":
			move_speed += pickup_speed_step
			air_speed_cap += pickup_speed_step * sprint_multiplier
			air_strafe_wishspeed += pickup_speed_step * sprint_multiplier
		&"damage":
			damage_bonus += pickup_damage_step
	_play_pickup_feedback(drop_type)

func _play_pickup_feedback(drop_type: StringName) -> void:
	var color: Color
	match drop_type:
		&"heal": color = Color(0.95, 0.45, 0.55)
		&"max_health": color = Color(1.0, 0.78, 0.35)
		&"speed": color = Color(0.4, 0.9, 1.0)
		&"damage": color = Color(0.85, 0.5, 1.0)
		_: color = Color.WHITE
	if camera_kick_tween:
		camera_kick_tween.kill()
	var orig_x := camera.rotation.x
	camera_kick_tween = create_tween()
	camera_kick_tween.tween_property(camera, "rotation:x", orig_x - 0.05, 0.06)
	camera_kick_tween.tween_property(camera, "rotation:x", orig_x, 0.18)
	muzzle_light.light_color = color
	muzzle_light.light_energy = 4.5
	var pulse := create_tween()
	pulse.tween_property(muzzle_light, "light_energy", 0.0, 0.35)

func take_damage(amount: int) -> void:
	if dead:
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_apply_damage(amount)
			sync_health.rpc(health, dead)
	else:
		_apply_damage(amount)

func _apply_damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0 and not dead:
		dead = true
		_release_mouse()
		died.emit()

@rpc("authority", "call_remote", "reliable")
func sync_health(value: int, is_dead: bool) -> void:
	health = value
	dead = is_dead
	health_changed.emit(health, max_health)
	if dead:
		_release_mouse()
		died.emit()

@rpc("any_peer", "call_remote", "unreliable")
func sync_player_state(pos: Vector3, yaw: float, pitch: float, new_velocity: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != owning_peer_id:
		return
	remote_position = pos
	remote_yaw = yaw
	remote_pitch = pitch
	velocity = new_velocity

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true

func _release_mouse() -> void:
	if _is_locally_controlled():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false

func open_menu() -> void:
	_release_mouse()
	set_input_blocked(true)
	camera.fov = base_fov
	head.position.y = head_default_y

func close_menu() -> void:
	set_input_blocked(false)
	if _is_locally_controlled() and not dead:
		_capture_mouse()

func set_input_blocked(value: bool) -> void:
	input_blocked = value
	if value:
		_release_mouse()
	elif _is_locally_controlled() and not dead:
		_capture_mouse()

func _is_locally_controlled() -> bool:
	return owning_peer_id == local_peer_id

func _update_local_visual_mode() -> void:
	var local := _is_locally_controlled()
	camera.current = local
	gun.visible = local
	avatar_root.visible = not local
	head_mesh.visible = not local

func _can_start_slide() -> bool:
	if slide_timer > 0.0 or not is_on_floor():
		return false
	var planar_velocity := Vector2(velocity.x, velocity.z)
	return planar_velocity.length() > move_speed * 0.75

func _start_slide() -> void:
	var move_flat := Vector3(velocity.x, 0.0, velocity.z)
	if move_flat.length() <= 0.01:
		move_flat = -head.global_transform.basis.z
		move_flat.y = 0.0
	slide_direction = move_flat.normalized()
	var speed_ratio: float = clampf(move_flat.length() / (move_speed * sprint_multiplier), 0.75, 1.25)
	slide_timer = slide_duration * speed_ratio
	sprinting = false

func _update_view_juice(delta: float) -> void:
	var target_fov := sprint_fov if sprinting else base_fov
	if slide_timer > 0.0:
		target_fov += 5.0
	camera.fov = lerpf(camera.fov, target_fov, min(delta * 9.0, 1.0))
	var target_head_y := head_default_y - slide_camera_drop if slide_timer > 0.0 else head_default_y
	head.position.y = lerpf(head.position.y, target_head_y, min(delta * 12.0, 1.0))

func _restore_view(delta: float) -> void:
	camera.fov = lerpf(camera.fov, base_fov, min(delta * 10.0, 1.0))
	head.position.y = lerpf(head.position.y, head_default_y, min(delta * 10.0, 1.0))

func _is_slide_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_CTRL or event.physical_keycode == KEY_CTRL or event.keycode == KEY_C or event.physical_keycode == KEY_C
