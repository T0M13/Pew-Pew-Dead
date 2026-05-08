extends Node3D

@onready var smoke: Array[MeshInstance3D] = [$Smoke1, $Smoke2, $Smoke3]
@onready var sparks: Array[MeshInstance3D] = [$Spark1, $Spark2, $Spark3, $Spark4]

func play(impact_color: Color, impact_normal: Vector3, charge_level: float) -> void:
	var tangent := impact_normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var bitangent := tangent.cross(impact_normal).normalized()
	var tween := create_tween()
	tween.set_parallel(true)
	for i in smoke.size():
		var puff := smoke[i]
		var material := puff.material_override.duplicate() as StandardMaterial3D
		material.albedo_color = Color(0.68, 0.64, 0.58, 0.42)
		puff.material_override = material
		puff.position = Vector3.ZERO
		puff.scale = Vector3.ONE * (0.08 + charge_level * 0.04)
		var angle := TAU * float(i) / float(smoke.size())
		var puff_direction := (impact_normal * 0.5 + tangent * cos(angle) * 0.35 + bitangent * sin(angle) * 0.35).normalized()
		tween.tween_property(puff, "position", puff_direction * (0.32 + charge_level * 0.28), 0.28)
		tween.tween_property(puff, "scale", Vector3.ONE * (0.45 + charge_level * 0.35), 0.28)
	for i in sparks.size():
		var spark := sparks[i]
		var spark_material := spark.material_override.duplicate() as StandardMaterial3D
		spark_material.albedo_color = impact_color
		spark_material.emission = impact_color
		spark.material_override = spark_material
		spark.position = Vector3.ZERO
		spark.scale = Vector3.ONE * (0.08 + charge_level * 0.05)
		var angle := TAU * float(i) / float(sparks.size())
		var spark_direction := (impact_normal * 0.25 + tangent * cos(angle) + bitangent * sin(angle)).normalized()
		tween.tween_property(spark, "position", spark_direction * (0.48 + charge_level * 0.32), 0.14)
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.16)
	tween.chain().tween_callback(queue_free)
