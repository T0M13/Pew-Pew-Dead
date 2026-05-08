extends CharacterBody3D

const HIT_FLASH_COLOR := Color(1.0, 0.24, 0.08, 1.0)
const PELLET_COLOR := Color(0.08, 0.065, 0.045, 1.0)
const RED_EXHAUST_COLOR := Color(1.0, 0.12, 0.05, 0.7)
const DARK_SMOKE_COLOR := Color(0.16, 0.15, 0.14, 0.5)
const WHITE_SMOKE_COLOR := Color(0.92, 0.9, 0.84, 0.0)

@export var speed: float = 42.0
@export var damage: int = 1
@export var lifetime: float = 1.4
@export var impact_scene: PackedScene

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var core_mesh: MeshInstance3D = $VisualRoot/CoreMesh
@onready var tracer_mesh: MeshInstance3D = $VisualRoot/TracerMesh
@onready var smoke_rings: Array[MeshInstance3D] = [
	$VisualRoot/SmokeRings/Ring1,
	$VisualRoot/SmokeRings/Ring2,
	$VisualRoot/SmokeRings/Ring3,
]
@onready var trail_sparks: Array[MeshInstance3D] = [
	$VisualRoot/TrailSparks/Spark1,
	$VisualRoot/TrailSparks/Spark2,
	$VisualRoot/TrailSparks/Spark3,
	$VisualRoot/TrailSparks/Spark4,
]
@onready var smoke_trail: MeshInstance3D = $SmokeTrail

var direction: Vector3 = Vector3.FORWARD
var age: float = 0.0
var charge_level: float = 0.0
var bounces_remaining: int = 1
var pierces_remaining: int = 0
var hit_targets: Array[Object] = []
var base_visual_scale: float = 1.0
var shot_variation: float = 1.0
var trail_spin_speed: float = 0.0
var trail_phase: float = 0.0
var trail_mesh := ImmediateMesh.new()
var trail_samples: Array[Dictionary] = []
var camera: Camera3D

func _ready() -> void:
	smoke_trail.mesh = trail_mesh
	smoke_trail.top_level = true
	camera = get_viewport().get_camera_3d()
	_apply_collision_size()
	_apply_projectile_style()

func configure(charge: float) -> void:
	charge_level = clamp(charge, 0.0, 1.0)
	damage = 1 + int(charge_level >= 0.75)
	shot_variation = randf_range(0.88, 1.14)
	trail_spin_speed = randf_range(8.0, 13.0) * (-1.0 if randf() < 0.5 else 1.0)
	trail_phase = randf() * TAU
	speed = (42.0 - charge_level * 6.0) * randf_range(0.96, 1.04)
	lifetime = 1.4 + charge_level * 0.45
	bounces_remaining = 1 + int(charge_level >= 0.75)
	pierces_remaining = int(charge_level >= 0.5)
	base_visual_scale = (1.0 + charge_level * 0.45) * shot_variation
	_apply_collision_size()
	_apply_projectile_style()

func _apply_collision_size() -> void:
	if not is_node_ready():
		return
	var sphere := collision_shape.shape as SphereShape3D
	if sphere:
		sphere.radius = 0.1 + charge_level * 0.035

func launch(start_position: Vector3, shot_direction: Vector3) -> void:
	direction = shot_direction.normalized()
	if direction.length_squared() == 0.0:
		direction = Vector3.FORWARD
	global_position = start_position
	_orient_to_direction()

func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	_orient_to_direction()
	_update_visuals(delta)
	_update_smoke_trail(delta)
	var collision := move_and_collide(direction * speed * delta)
	if collision == null:
		return
	var collider := collision.get_collider()
	var hit_position := collision.get_position()
	var hit_normal := collision.get_normal()
	var damage_target := _get_damage_target(collider)
	if damage_target and not hit_targets.has(damage_target):
		_damage_target(damage_target, collider, hit_position)
		_spawn_impact(hit_position, hit_normal)
		if pierces_remaining > 0:
			pierces_remaining -= 1
			hit_targets.append(damage_target)
			if damage_target is CollisionObject3D:
				add_collision_exception_with(damage_target)
			global_position += direction * 0.28
			return
		queue_free()
		return
	if bounces_remaining > 0:
		bounces_remaining -= 1
		direction = direction.bounce(hit_normal).normalized()
		_orient_to_direction()
		speed *= 0.82
		_spawn_impact(hit_position, hit_normal)
		return
	_spawn_impact(hit_position, hit_normal)
	queue_free()

func _orient_to_direction() -> void:
	var up := Vector3.UP
	if abs(direction.dot(up)) > 0.98:
		up = Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(direction, up), global_position)

func _get_damage_target(collider: Object) -> Object:
	if collider == null:
		return null
	if collider.has_method("get_zombie"):
		var zombie = collider.get_zombie()
		if zombie:
			return zombie
	if collider.has_method("take_damage") or collider.has_method("take_hit"):
		return collider
	return null

func _damage_target(target: Object, collider: Object, hit_position: Vector3) -> void:
	var zone_name := "torso"
	if collider and collider.has_method("get_hit_zone"):
		zone_name = collider.get_hit_zone()
	elif target.has_method("get_hit_zone_at_position"):
		zone_name = target.get_hit_zone_at_position(hit_position)
	if target.has_method("take_hit"):
		target.take_hit(zone_name, damage, direction, charge_level * 3.0, HIT_FLASH_COLOR, hit_position, true)
	elif target.has_method("take_damage"):
		target.take_damage(damage, direction, HIT_FLASH_COLOR, charge_level, hit_position, true)

func _update_visuals(delta: float) -> void:
	var distance_scale := 1.0
	if camera:
		var distance := global_position.distance_to(camera.global_position)
		distance_scale = clamp(distance / 15.0, 0.9, 1.35)
	var pulse := 1.0 + sin(age * 28.0) * 0.06
	visual_root.scale = Vector3.ONE * base_visual_scale * distance_scale * pulse
	visual_root.rotate_z(delta * (18.0 + charge_level * 8.0))
	tracer_mesh.scale.z = (1.2 + charge_level * 1.45 + sin(age * 20.0) * 0.08) * shot_variation
	for i in trail_sparks.size():
		var spark := trail_sparks[i]
		var drift := float(i) * 0.09 + age * 0.35
		spark.position = Vector3(
			sin(age * 24.0 + float(i)) * 0.035,
			cos(age * 19.0 + float(i) * 1.7) * 0.035,
			0.18 + drift
		)
		spark.scale = Vector3.ONE * (0.65 + sin(age * 22.0 + float(i)) * 0.2)
	_update_smoke_rings()

func _update_smoke_rings() -> void:
	for i in smoke_rings.size():
		var ring := smoke_rings[i]
		ring.visible = charge_level >= 0.35
		if not ring.visible:
			continue
		var offset := 0.32 + float(i) * 0.22 + fmod(age * 1.5, 0.24)
		var spread := 0.35 + charge_level * 0.55 + float(i) * 0.16
		ring.position = Vector3(0.0, 0.0, offset)
		ring.scale = Vector3.ONE * spread

func _update_smoke_trail(delta: float) -> void:
	smoke_trail.global_transform = Transform3D.IDENTITY
	for i in trail_samples.size():
		var sample := trail_samples[i]
		sample["age"] += delta
		trail_samples[i] = sample
	trail_samples.push_front({
		"position": global_position,
		"age": 0.0,
	})
	while trail_samples.size() > 14 or (trail_samples.size() > 0 and trail_samples[trail_samples.size() - 1]["age"] > 0.42):
		trail_samples.pop_back()
	trail_mesh.clear_surfaces()
	if trail_samples.size() < 2:
		return
	var base_width := (0.08 + charge_level * 0.06) * shot_variation
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in trail_samples.size() - 1:
		var head_sample := trail_samples[i]
		var tail_sample := trail_samples[i + 1]
		var head_age: float = head_sample["age"]
		var tail_age: float = tail_sample["age"]
		var head: Vector3 = head_sample["position"]
		var tail: Vector3 = tail_sample["position"]
		var segment_direction: Vector3 = (head - tail).normalized()
		var side: Vector3 = segment_direction.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = segment_direction.cross(Vector3.RIGHT)
		side = side.normalized()
		var up: Vector3 = side.cross(segment_direction).normalized()
		var spin_head := trail_phase + age * trail_spin_speed + head_age * (12.0 + charge_level * 20.0)
		var spin_tail := trail_phase + age * trail_spin_speed + tail_age * (12.0 + charge_level * 20.0)
		var corkscrew_strength := 0.08 + charge_level * 0.26
		var head_wave: float = sin(age * 15.0 + float(i) * 1.4) * head_age * 0.34
		var tail_wave: float = sin(age * 15.0 + float(i + 1) * 1.4) * tail_age * 0.34
		var head_spin_offset := (side * cos(spin_head) + up * sin(spin_head)) * head_age * corkscrew_strength
		var tail_spin_offset := (side * cos(spin_tail) + up * sin(spin_tail)) * tail_age * corkscrew_strength
		head += side * head_wave + up * cos(age * 11.0 + float(i)) * head_age * 0.24
		tail += side * tail_wave + up * cos(age * 11.0 + float(i + 1)) * tail_age * 0.24
		head += head_spin_offset
		tail += tail_spin_offset
		var head_width: float = base_width * (1.0 + head_age * (3.0 + charge_level * 2.0))
		var tail_width: float = base_width * (1.0 + tail_age * (4.5 + charge_level * 3.0))
		var fade: float = clampf(1.0 - tail_age / 0.42, 0.0, 1.0)
		var smoke_mix := clampf(tail_age / 0.42, 0.0, 1.0)
		var color: Color
		if tail_age < 0.08:
			color = RED_EXHAUST_COLOR.lerp(DARK_SMOKE_COLOR, tail_age / 0.08)
		else:
			color = DARK_SMOKE_COLOR.lerp(WHITE_SMOKE_COLOR, smoke_mix)
		color.a *= fade * fade
		trail_mesh.surface_set_color(color)
		trail_mesh.surface_add_vertex(head + side * head_width)
		trail_mesh.surface_add_vertex(tail + side * tail_width)
		trail_mesh.surface_add_vertex(tail - side * tail_width)
		trail_mesh.surface_add_vertex(head + side * head_width)
		trail_mesh.surface_add_vertex(tail - side * tail_width)
		trail_mesh.surface_add_vertex(head - side * head_width)
	trail_mesh.surface_end()

func _apply_projectile_style() -> void:
	if not is_node_ready():
		return
	_set_material(core_mesh, PELLET_COLOR, Color(0.2, 0.16, 0.08, 1.0), 0.25)
	_set_material(tracer_mesh, RED_EXHAUST_COLOR, HIT_FLASH_COLOR, 1.4)
	_set_material(smoke_trail, DARK_SMOKE_COLOR, Color(0.55, 0.5, 0.45, 1.0), 0.15)
	for spark in trail_sparks:
		_set_material(spark, Color(0.95, 0.24, 0.08, 1.0), HIT_FLASH_COLOR, 3.0)
	for ring in smoke_rings:
		_set_material(ring, DARK_SMOKE_COLOR.lerp(WHITE_SMOKE_COLOR, 0.45), Color(0.55, 0.5, 0.45, 1.0), 0.12)

func _set_material(mesh_instance: MeshInstance3D, albedo: Color, emission: Color, energy: float) -> void:
	var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = albedo
	material.emission = emission
	material.emission_energy_multiplier = energy
	mesh_instance.material_override = material

func _spawn_impact(hit_position: Vector3, hit_normal: Vector3) -> void:
	if impact_scene == null:
		return
	var impact := impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = hit_position + hit_normal * 0.03
	impact.play(HIT_FLASH_COLOR, hit_normal, charge_level)
