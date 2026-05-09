extends Area3D

@export var zone_name: String = "torso"

func take_hit(
	amount: int,
	impulse_direction: Vector3 = Vector3.ZERO,
	force: float = 0.0,
	hit_position: Vector3 = Vector3.ZERO,
	has_hit_position: bool = false
) -> void:
	var zombie := get_parent()
	if zombie and zombie.has_method("take_hit"):
		zombie.take_hit(zone_name, amount, impulse_direction, force, Color(1.0, 0.42, 0.35), hit_position, has_hit_position)

func get_hit_zone() -> String:
	return zone_name

func get_zombie() -> Node:
	return get_parent()
