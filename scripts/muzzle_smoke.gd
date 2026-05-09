extends Node3D

@onready var puffs: Array[MeshInstance3D] = [$Puff1, $Puff2, $Puff3]
@onready var rings: Array[MeshInstance3D] = [$Ring1, $Ring2]

func play(direction: Vector3, charge_level: float) -> void:
	var forward := direction.normalized()
	if forward.length_squared() == 0.0:
		forward = Vector3.FORWARD
	var exhaust := (-forward + Vector3.UP * 0.55).normalized()
	var tangent := forward.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var bitangent := tangent.cross(forward).normalized()
	var tween := create_tween()
	tween.set_parallel(true)
	for i in puffs.size():
		var puff := puffs[i]
		puff.position = Vector3.ZERO
		puff.scale = Vector3.ONE * 0.08
		var angle := TAU * float(i) / float(puffs.size())
		var spread := tangent * cos(angle) * 0.18 + bitangent * sin(angle) * 0.18
		tween.tween_property(puff, "position", exhaust * (0.22 + charge_level * 0.2) + spread, 0.24)
		tween.tween_property(puff, "scale", Vector3.ONE * (0.38 + charge_level * 0.28), 0.24)
	for i in rings.size():
		var ring := rings[i]
		ring.visible = charge_level > 0.25
		ring.position = exhaust * (0.08 + float(i) * 0.12)
		ring.scale = Vector3.ONE * 0.1
		tween.tween_property(ring, "position", exhaust * (0.44 + float(i) * 0.18 + charge_level * 0.2), 0.28)
		tween.tween_property(ring, "scale", Vector3.ONE * (0.5 + charge_level * 0.35), 0.28)
	tween.chain().tween_callback(queue_free)
