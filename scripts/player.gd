extends CharacterBody3D

@export var move_speed: float = 6.0
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0025
@export var max_health: int = 100

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var shoot_ray: RayCast3D = $Head/Camera3D/ShootRay
@onready var muzzle_flash: MeshInstance3D = $Head/Camera3D/Gun/MuzzleFlash
@onready var gun: Node3D = $Head/Camera3D/Gun
@onready var avatar_root: Node3D = $AvatarRoot
@onready var head_mesh: MeshInstance3D = $Head/HeadMesh

var health: int
var mouse_captured: bool = false
var dead: bool = false
var owning_peer_id: int = 1
var local_peer_id: int = 1
var remote_position: Vector3
var remote_yaw: float = 0.0
var remote_pitch: float = 0.0

signal health_changed(value: int, max_value: int)
signal died

func _ready() -> void:
	add_to_group("player")
	health = max_health
	muzzle_flash.visible = false
	remote_position = global_position
	_update_local_visual_mode()
	if _is_locally_controlled():
		_capture_mouse()

func configure_for_peer(peer_id: int, current_local_peer_id: int) -> void:
	owning_peer_id = peer_id
	local_peer_id = current_local_peer_id
	if is_inside_tree():
		_update_local_visual_mode()
		if _is_locally_controlled() and not dead:
			_capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if dead or not _is_locally_controlled():
		return
	if event is InputEventMouseMotion and mouse_captured:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -1.4, 1.4)
	elif event.is_action_pressed("shoot"):
		if not mouse_captured:
			_capture_mouse()
		else:
			_shoot()
	elif event.is_action_pressed("ui_unpause"):
		_release_mouse()

func _physics_process(delta: float) -> void:
	if dead:
		return
	if _is_locally_controlled():
		_run_local_movement(delta)
		if multiplayer.has_multiplayer_peer():
			sync_player_state.rpc(global_position, head.rotation.y, camera.rotation.x, velocity)
	else:
		_apply_remote_movement(delta)

func _run_local_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction.length() > 0.0:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
	move_and_slide()

func _apply_remote_movement(delta: float) -> void:
	global_position = global_position.lerp(remote_position, min(12.0 * delta, 1.0))
	rotation.y = lerp_angle(rotation.y, remote_yaw, min(12.0 * delta, 1.0))
	head.rotation.y = rotation.y
	camera.rotation.x = lerp(camera.rotation.x, remote_pitch, min(14.0 * delta, 1.0))

func _shoot() -> void:
	_play_shot_feedback()
	if shoot_ray.is_colliding():
		var col := shoot_ray.get_collider()
		if col and col.has_method("take_damage") and not multiplayer.has_multiplayer_peer():
			col.take_damage(1)
		elif col and col.is_in_group("zombies"):
			if multiplayer.is_server():
				col.take_damage(1)
			else:
				var root := get_tree().current_scene
				if root and root.has_method("request_zombie_hit"):
					root.request_zombie_hit.rpc_id(1, col.network_id, 1)

func _play_shot_feedback() -> void:
	muzzle_flash.visible = true
	var hide_tween := create_tween()
	hide_tween.tween_interval(0.05)
	hide_tween.tween_callback(func(): muzzle_flash.visible = false)
	var orig := gun.position
	var recoil_tween := create_tween()
	recoil_tween.tween_property(gun, "position", orig + Vector3(0, 0.01, 0.08), 0.04)
	recoil_tween.tween_property(gun, "position", orig, 0.12)

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

func close_menu() -> void:
	if _is_locally_controlled() and not dead:
		_capture_mouse()

func _is_locally_controlled() -> bool:
	return owning_peer_id == local_peer_id

func _update_local_visual_mode() -> void:
	var local := _is_locally_controlled()
	camera.current = local
	shoot_ray.enabled = local
	gun.visible = local
	avatar_root.visible = not local
	head_mesh.visible = not local
