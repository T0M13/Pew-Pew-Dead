extends CanvasLayer

@onready var health_label: Label = $Margin/VBox/Health
@onready var wave_label: Label = $Margin/VBox/Wave
@onready var kills_label: Label = $Margin/VBox/Kills
@onready var center_label: Label = $CenterMessage

var kills: int = 0

func _ready() -> void:
	center_label.text = ""
	center_label.modulate.a = 0.0

func set_health(value: int, max_value: int) -> void:
	health_label.text = "HP %d / %d" % [value, max_value]

func set_wave(wave: int, total: int) -> void:
	wave_label.text = "Wave %d  (%d zombies)" % [wave, total]
	flash_message("WAVE %d" % wave, 1.6)

func register_kill(_remaining: int) -> void:
	kills += 1
	kills_label.text = "Kills %d" % kills

func flash_message(msg: String, duration: float) -> void:
	center_label.text = msg
	center_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(center_label, "modulate:a", 0.0, 0.6)

func show_persistent(msg: String, color: Color) -> void:
	center_label.text = msg
	center_label.modulate = Color(color.r, color.g, color.b, 1)

func show_win() -> void:
	show_persistent("YOU SURVIVED", Color(0.4, 0.85, 0.5))

func show_lose() -> void:
	show_persistent("YOU DIED", Color(0.95, 0.35, 0.45))
