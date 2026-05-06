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

var health: int
var mouse_captured: bool = false
var dead: bool = false

signal health_changed(value: int, max_value: int)
signal died

func _ready() -> void:
	add_to_group("player")
	health = max_health
	muzzle_flash.visible = false
	_capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if dead:
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

func _shoot() -> void:
	muzzle_flash.visible = true
	var hide_tween := create_tween()
	hide_tween.tween_interval(0.05)
	hide_tween.tween_callback(func(): muzzle_flash.visible = false)
	var orig := gun.position
	var recoil_tween := create_tween()
	recoil_tween.tween_property(gun, "position", orig + Vector3(0, 0.01, 0.08), 0.04)
	recoil_tween.tween_property(gun, "position", orig, 0.12)
	if shoot_ray.is_colliding():
		var col := shoot_ray.get_collider()
		if col and col.has_method("take_damage"):
			col.take_damage(1)

func take_damage(amount: int) -> void:
	if dead:
		return
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		dead = true
		died.emit()

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true

func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false
