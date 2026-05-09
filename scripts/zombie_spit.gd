extends Area3D

@export var speed: float = 13.0
@export var damage: int = 6
@export var lifetime: float = 3.5
@export var fall_gravity: float = 6.0

var velocity_vec: Vector3 = Vector3.ZERO
var age: float = 0.0
var consumed: bool = false

@onready var visual: Node3D = $Visual
@onready var glow_light: OmniLight3D = $Visual/Light

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("zombie_spit")

func launch(direction: Vector3) -> void:
	velocity_vec = direction.normalized() * speed + Vector3(0.0, 1.6, 0.0)

func _physics_process(delta: float) -> void:
	if consumed:
		return
	age += delta
	if age >= lifetime:
		queue_free()
		return
	velocity_vec.y -= fall_gravity * delta
	global_position += velocity_vec * delta
	if visual:
		visual.rotate_y(delta * 6.0)
	if global_position.y < 0.05:
		_consume(null)

func _on_body_entered(body: Node) -> void:
	if consumed:
		return
	if body.is_in_group("player") and body.has_method("take_damage") and not body.dead:
		body.take_damage(damage)
		_consume(body)
		return
	if body.is_in_group("zombies"):
		return
	_consume(body)

func _consume(_target: Node) -> void:
	if consumed:
		return
	consumed = true
	monitoring = false
	if glow_light:
		glow_light.light_energy = 4.0
		var t := create_tween()
		t.tween_property(glow_light, "light_energy", 0.0, 0.18)
	queue_free()
