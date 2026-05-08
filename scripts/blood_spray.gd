extends Node3D

const SPRAY_DURATION := 1.05
const GRAVITY := Vector3.DOWN * 4.6
const DRAG := 2.8

var droplets: Array[Dictionary] = []
var age: float = 0.0

func configure(hit_position: Vector3, impulse_direction: Vector3, amount: int = 12) -> void:
	global_position = hit_position
	var forward := impulse_direction.normalized()
	if forward.length_squared() <= 0.01:
		forward = Vector3(randf_range(-0.45, 0.45), 0.25, randf_range(-0.45, 0.45)).normalized()

	for i in amount:
		var droplet := MeshInstance3D.new()
		droplet.name = "BloodDroplet"
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.025, 0.055)
		mesh.height = mesh.radius * randf_range(1.2, 2.3)
		droplet.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(randf_range(0.34, 0.62), 0.0, 0.0, randf_range(0.76, 0.95))
		material.roughness = 0.68
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		droplet.material_override = material
		add_child(droplet)
		droplet.position = Vector3(
			randf_range(-0.045, 0.045),
			randf_range(-0.035, 0.045),
			randf_range(-0.045, 0.045)
		)
		var sideways := Vector3(randf_range(-0.85, 0.85), randf_range(-0.2, 0.95), randf_range(-0.85, 0.85))
		var velocity := forward * randf_range(1.2, 2.4) + sideways * randf_range(0.35, 0.9)
		velocity.y += randf_range(0.15, 0.85)
		droplets.append({
			"node": droplet,
			"material": material,
			"velocity": velocity,
			"spin": Vector3(randf_range(-7.0, 7.0), randf_range(-9.0, 9.0), randf_range(-7.0, 7.0)),
			"life": randf_range(0.62, SPRAY_DURATION),
			"base_scale": Vector3.ONE * randf_range(0.75, 1.35),
		})

func _process(delta: float) -> void:
	age += delta
	for i in range(droplets.size() - 1, -1, -1):
		var particle := droplets[i]
		var droplet := particle["node"] as MeshInstance3D
		if not is_instance_valid(droplet):
			droplets.remove_at(i)
			continue
		var velocity: Vector3 = particle["velocity"]
		velocity += GRAVITY * delta
		velocity = velocity.lerp(Vector3.ZERO, min(delta * DRAG, 0.85))
		droplet.position += velocity * delta
		droplet.rotation += particle["spin"] * delta
		var life: float = particle["life"]
		var progress := clampf(age / life, 0.0, 1.0)
		var material := particle["material"] as StandardMaterial3D
		var color := material.albedo_color
		color.a = pow(1.0 - progress, 1.7)
		material.albedo_color = color
		var stretch := clampf(velocity.length() * 0.35, 0.8, 2.2)
		droplet.scale = particle["base_scale"] * Vector3(0.75, stretch, 0.75) * (1.0 - progress * 0.65)
		particle["velocity"] = velocity
		droplets[i] = particle
	if age >= SPRAY_DURATION or droplets.is_empty():
		queue_free()
