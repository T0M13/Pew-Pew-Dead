extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://scenes/player.tscn",
		"res://scenes/projectile.tscn",
		"res://scenes/projectile_impact.tscn",
		"res://scenes/drop.tscn",
		"res://scenes/zombie_spit.tscn",
		"res://scenes/muzzle_smoke.tscn",
		"res://scenes/zombie.tscn",
		"res://scenes/hud.tscn",
		"res://scenes/main.tscn",
	]
	var failed := false
	for p in paths:
		var ps := load(p)
		if ps == null:
			print("FAIL load: ", p)
			failed = true
			continue
		var inst = ps.instantiate()
		if inst == null:
			print("FAIL instantiate: ", p)
			failed = true
			continue
		print("OK ", p, " => ", inst.get_class(), "/", inst.name)
		inst.queue_free()
	if failed:
		print("VALIDATION FAILED")
		quit(1)
	else:
		print("VALIDATION OK")
		quit(0)
