extends Node3D

@onready var flash: MeshInstance3D = $Flash
@onready var sparks: Array[MeshInstance3D] = [$Spark1, $Spark2, $Spark3, $Spark4]

func play(impact_color: Color, impact_normal: Vector3, charge_level: float) -> void:
	var material := flash.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = impact_color
	material.emission = impact_color
	material.emission_energy_multiplier = 4.0 + charge_level * 2.0
	flash.material_override = material
	flash.scale = Vector3.ONE * (0.35 + charge_level * 0.45)
	var tangent := impact_normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var bitangent := tangent.cross(impact_normal).normalized()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * (0.9 + charge_level * 0.8), 0.16)
	for i in sparks.size():
		var spark := sparks[i]
		var spark_material := material.duplicate() as StandardMaterial3D
		spark.material_override = spark_material
		spark.position = Vector3.ZERO
		spark.scale = Vector3.ONE * (0.12 + charge_level * 0.08)
		var angle := TAU * float(i) / float(sparks.size())
		var spark_direction := (impact_normal * 0.4 + tangent * cos(angle) + bitangent * sin(angle)).normalized()
		tween.tween_property(spark, "position", spark_direction * (0.45 + charge_level * 0.35), 0.16)
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.16)
	tween.chain().tween_callback(queue_free)
