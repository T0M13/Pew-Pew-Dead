extends Area3D

const TYPE_HEAL: StringName = &"heal"
const TYPE_MAX_HEALTH: StringName = &"max_health"
const TYPE_SPEED: StringName = &"speed"
const TYPE_DAMAGE: StringName = &"damage"

const TYPES: Array[StringName] = [TYPE_HEAL, TYPE_MAX_HEALTH, TYPE_SPEED, TYPE_DAMAGE]

@onready var body_root: Node3D = $Body
@onready var crystal: MeshInstance3D = $Body/Crystal
@onready var halo: MeshInstance3D = $Body/Halo
@onready var pickup_light: OmniLight3D = $Body/Light

var drop_type: StringName = TYPE_HEAL
var phase: float = 0.0
var consumed: bool = false

signal pickup_consumed(drop)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	phase = randf() * TAU
	_apply_visuals()

func configure(new_type: StringName) -> void:
	drop_type = new_type
	if is_node_ready():
		_apply_visuals()

func _process(delta: float) -> void:
	phase += delta * 2.2
	body_root.position.y = sin(phase) * 0.2
	body_root.rotate_y(delta * 1.6)
	pickup_light.light_energy = 1.6 + sin(phase * 1.7) * 0.4

func _on_body_entered(body_in: Node) -> void:
	if consumed:
		return
	if not body_in.is_in_group("player"):
		return
	if "owning_peer_id" in body_in and "local_peer_id" in body_in:
		if body_in.owning_peer_id != body_in.local_peer_id:
			return
	if not body_in.has_method("apply_pickup"):
		return
	consumed = true
	body_in.apply_pickup(drop_type)
	pickup_consumed.emit(self)
	_play_consume_burst()

func _play_consume_burst() -> void:
	monitoring = false
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(body_root, "scale", Vector3(2.4, 2.4, 2.4), 0.18)
	t.tween_property(pickup_light, "light_energy", 8.0, 0.1)
	t.chain().tween_callback(queue_free)

func _apply_visuals() -> void:
	var color: Color = _color_for_type()
	if crystal and crystal.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = crystal.material_override.duplicate()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.5
		crystal.material_override = mat
	if halo and halo.material_override is StandardMaterial3D:
		var hmat: StandardMaterial3D = halo.material_override.duplicate()
		hmat.albedo_color = Color(color.r, color.g, color.b, 0.55)
		hmat.emission_enabled = true
		hmat.emission = color
		hmat.emission_energy_multiplier = 2.4
		halo.material_override = hmat
	if pickup_light:
		pickup_light.light_color = color

func _color_for_type() -> Color:
	match drop_type:
		TYPE_HEAL:
			return Color(0.95, 0.45, 0.55)
		TYPE_MAX_HEALTH:
			return Color(1.0, 0.78, 0.35)
		TYPE_SPEED:
			return Color(0.4, 0.9, 1.0)
		TYPE_DAMAGE:
			return Color(0.85, 0.5, 1.0)
		_:
			return Color.WHITE

static func random_type() -> StringName:
	return TYPES.pick_random()
