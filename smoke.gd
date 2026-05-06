extends SceneTree

var frames := 0

func _initialize() -> void:
	var ps := load("res://scenes/main.tscn")
	if ps == null:
		print("FAIL load main")
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	current_scene = inst
	print("Main scene started")

func _process(_delta: float) -> bool:
	frames += 1
	if frames >= 120:
		print("Survived ", frames, " frames OK")
		quit(0)
		return true
	return false
