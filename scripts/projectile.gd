extends CharacterBody3D

@export var speed: float = 34.0
@export var damage: int = 1
@export var lifetime: float = 1.8
@export var impact_scene: PackedScene

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var core_mesh: MeshInstance3D = $VisualRoot/CoreMesh
@onready var aura_mesh: MeshInstance3D = $VisualRoot/AuraMesh
@onready var billboard_glow: MeshInstance3D = $VisualRoot/BillboardGlow
@onready var comet_tail: MeshInstance3D = $VisualRoot/CometTail
@onready var ribbon_trail: MeshInstance3D = $RibbonTrail
@onready var solar_shape: MeshInstance3D = $VisualRoot/ElementShapes/SolarOrb
@onready var frost_shape: MeshInstance3D = $VisualRoot/ElementShapes/FrostShard
@onready var venom_shape: MeshInstance3D = $VisualRoot/ElementShapes/VenomDrop
@onready var knockback_shape: MeshInstance3D = $VisualRoot/ElementShapes/KnockbackPulse
@onready var orbit_sparks: Array[MeshInstance3D] = [
	$VisualRoot/OrbitSparks/Spark1,
	$VisualRoot/OrbitSparks/Spark2,
	$VisualRoot/OrbitSparks/Spark3,
	$VisualRoot/OrbitSparks/Spark4,
]

var direction: Vector3 = Vector3.FORWARD
var age: float = 0.0
var charge_level: float = 0.0
var projectile_color: Color = Color(1.0, 0.78, 0.12, 1.0)
var hit_effect: StringName = &"solar"
var bounces_remaining: int = 1
var pierces_remaining: int = 0
var wobble_phase: float = randf() * TAU
var hit_targets: Array[Object] = []
var base_visual_scale: float = 1.0
var ribbon_mesh := ImmediateMesh.new()
var trail_points: Array[Vector3] = []
var camera: Camera3D

func _ready() -> void:
	ribbon_trail.mesh = ribbon_mesh
	ribbon_trail.top_level = true
	camera = get_viewport().get_camera_3d()
	_apply_collision_size()
	_apply_projectile_style()

func configure(shot_color: Color, effect: StringName, charge: float) -> void:
	projectile_color = shot_color
	hit_effect = effect
	charge_level = clamp(charge, 0.0, 1.0)
	damage = 1 + int(charge_level >= 0.75)
	speed = 34.0 - charge_level * 5.0
	lifetime = 1.8 + charge_level * 0.6
	bounces_remaining = 1 + int(charge_level >= 0.75)
	pierces_remaining = int(charge_level >= 0.5)
	base_visual_scale = 1.0 + charge_level * 0.75
	_apply_collision_size()
	_apply_projectile_style()

func _apply_collision_size() -> void:
	if not is_node_ready():
		return
	var sphere := collision_shape.shape as SphereShape3D
	if sphere:
		sphere.radius = 0.12 + charge_level * 0.04

func launch(start_position: Vector3, shot_direction: Vector3) -> void:
	direction = shot_direction.normalized()
	if direction.length_squared() == 0.0:
		direction = Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), start_position)

func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	_update_visuals(delta)
	_update_ribbon_trail()
	var travel_direction := _get_travel_direction()
	global_transform = Transform3D(Basis.looking_at(travel_direction, Vector3.UP), global_position)
	var collision := move_and_collide(travel_direction * speed * delta)
	if collision == null:
		return
	var collider := collision.get_collider()
	var hit_position := collision.get_position()
	var hit_normal := collision.get_normal()
	var damage_target := _get_damage_target(collider)
	if damage_target and not hit_targets.has(damage_target):
		_damage_target(damage_target)
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
		direction = travel_direction.bounce(hit_normal).normalized()
		speed *= 0.82
		_spawn_impact(hit_position, hit_normal)
		return
	_spawn_impact(hit_position, hit_normal)
	queue_free()

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

func _damage_target(target: Object) -> void:
	if target.has_method("take_damage"):
		target.take_damage(damage, direction, projectile_color, hit_effect, charge_level)
	elif target.has_method("take_hit"):
		target.take_hit("torso", damage, direction, 0.0, projectile_color, hit_effect, charge_level)

func _update_visuals(delta: float) -> void:
	var distance_scale := 1.0
	if camera:
		var distance := global_position.distance_to(camera.global_position)
		distance_scale = clamp(distance / 14.0, 0.8, 1.45)
	var pulse := 1.0 + sin(age * 22.0) * 0.08
	visual_root.scale = Vector3.ONE * base_visual_scale * distance_scale * pulse
	visual_root.rotate_z(delta * (12.0 + charge_level * 8.0))
	if camera:
		billboard_glow.look_at(camera.global_position, Vector3.UP)
	comet_tail.scale.z = 1.0 + charge_level * 1.2 + sin(age * 18.0) * 0.18
	billboard_glow.scale = Vector3.ONE * (1.0 + charge_level * 0.8 + sin(age * 14.0) * 0.08)
	for i in orbit_sparks.size():
		var angle := age * (8.0 + charge_level * 4.0) + TAU * float(i) / float(orbit_sparks.size())
		var radius := 0.18 + charge_level * 0.1
		var spark := orbit_sparks[i]
		spark.position = Vector3(cos(angle) * radius, sin(angle * 1.35) * radius * 0.45, sin(angle) * radius)
		spark.scale = Vector3.ONE * (0.75 + sin(age * 20.0 + angle) * 0.18)

func _update_ribbon_trail() -> void:
	ribbon_trail.global_transform = Transform3D.IDENTITY
	trail_points.push_front(global_position)
	if trail_points.size() > 7:
		trail_points.resize(7)
	ribbon_mesh.clear_surfaces()
	if trail_points.size() < 2:
		return
	var width := 0.16 + charge_level * 0.12
	ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in trail_points.size() - 1:
		var head := trail_points[i]
		var tail := trail_points[i + 1]
		var segment_direction := (head - tail).normalized()
		var side := segment_direction.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = segment_direction.cross(Vector3.RIGHT)
		side = side.normalized() * width * (1.0 - float(i) / float(trail_points.size()))
		var fade := 1.0 - float(i) / float(trail_points.size() - 1)
		var color := projectile_color
		color.a = 0.55 * fade
		ribbon_mesh.surface_set_color(color)
		ribbon_mesh.surface_add_vertex(head + side)
		ribbon_mesh.surface_add_vertex(tail + side * 0.55)
		ribbon_mesh.surface_add_vertex(tail - side * 0.55)
		ribbon_mesh.surface_add_vertex(head + side)
		ribbon_mesh.surface_add_vertex(tail - side * 0.55)
		ribbon_mesh.surface_add_vertex(head - side)
	ribbon_mesh.surface_end()

func _get_travel_direction() -> Vector3:
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(direction).normalized()
	var wobble_strength := 0.025 + charge_level * 0.035
	var wobble := right * sin(age * 18.0 + wobble_phase) + up * cos(age * 13.0 + wobble_phase)
	return (direction + wobble * wobble_strength).normalized()

func _apply_projectile_style() -> void:
	if not is_node_ready():
		return
	var hot_core := Color.WHITE.lerp(projectile_color, 0.18)
	_set_material(core_mesh, hot_core, hot_core, 6.0 + charge_level * 3.0)
	_set_material(aura_mesh, projectile_color.lightened(0.15), projectile_color, 2.8 + charge_level * 2.0)
	_set_material(billboard_glow, Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.38), projectile_color, 2.5)
	var trail_color := projectile_color.darkened(0.15)
	_set_material(comet_tail, trail_color, projectile_color, 2.2 + charge_level * 1.6)
	_set_material(ribbon_trail, Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.5), projectile_color, 1.7)
	for spark in orbit_sparks:
		_set_material(spark, hot_core, projectile_color, 4.5)
	_show_element_shape()
	comet_tail.scale.z = 1.0 + charge_level * 1.25

func _set_material(mesh_instance: MeshInstance3D, albedo: Color, emission: Color, energy: float) -> void:
	var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = albedo
	material.emission = emission
	material.emission_energy_multiplier = energy
	mesh_instance.material_override = material

func _show_element_shape() -> void:
	solar_shape.visible = hit_effect == &"solar"
	frost_shape.visible = hit_effect == &"frost"
	venom_shape.visible = hit_effect == &"venom"
	knockback_shape.visible = hit_effect == &"knockback"
	var active_shape := solar_shape
	match hit_effect:
		&"frost":
			active_shape = frost_shape
		&"venom":
			active_shape = venom_shape
		&"knockback":
			active_shape = knockback_shape
	_set_material(active_shape, Color.WHITE.lerp(projectile_color, 0.28), projectile_color, 5.5 + charge_level * 2.0)

func _spawn_impact(hit_position: Vector3, hit_normal: Vector3) -> void:
	if impact_scene == null:
		return
	var impact := impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = hit_position + hit_normal * 0.03
	impact.play(projectile_color, hit_normal, charge_level)
