extends CanvasLayer

@onready var health_label: Label = $Margin/VBox/Health
@onready var wave_label: Label = $Margin/VBox/Wave
@onready var kills_label: Label = $Margin/VBox/Kills
@onready var center_label: Label = $CenterMessage
@onready var menu_panel: PanelContainer = $MenuPanel
@onready var join_ip: LineEdit = $MenuPanel/Margin/VBox/JoinIP
@onready var status_label: Label = $MenuPanel/Margin/VBox/Status
@onready var perf_label: Label = $PerfPanel/Margin/VBox/Perf
@onready var peer_label: Label = $PerfPanel/Margin/VBox/Peer
@onready var console_panel: PanelContainer = $ConsolePanel
@onready var console_log: RichTextLabel = $ConsolePanel/Margin/VBox/Log
@onready var console_input: LineEdit = $ConsolePanel/Margin/VBox/Command

var kills: int = 0
var last_frame_ms: float = 0.0

signal play_solo_requested
signal host_requested
signal join_requested(address: String)
signal command_submitted(command: String)
signal console_visibility_changed(visible_state: bool)

func _ready() -> void:
	center_label.text = ""
	center_label.modulate.a = 0.0
	console_panel.visible = false
	console_log.clear()
	add_console_line("Console ready. Type 'help' for commands.")
	_update_perf_labels()

func _process(delta: float) -> void:
	last_frame_ms = delta * 1000.0
	_update_perf_labels()

func reset_for_session() -> void:
	kills = 0
	kills_label.text = "Kills 0"
	center_label.text = ""
	center_label.modulate.a = 0.0
	add_console_line("Session reset.")

func set_health(value: int, max_value: int) -> void:
	health_label.text = "HP %d / %d" % [value, max_value]

func set_wave(wave: int, total: int) -> void:
	wave_label.text = "Wave %d  (%d zombies)" % [wave, total]
	flash_message("WAVE %d" % wave, 1.6)
	add_console_line("Wave %d started with %d zombies." % [wave, total])

func register_kill(_remaining: int) -> void:
	kills += 1
	kills_label.text = "Kills %d" % kills

func set_kills(value: int) -> void:
	kills = value
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
	add_console_line("Run complete: survived all waves.")

func show_lose() -> void:
	show_persistent("TEAM WIPED", Color(0.95, 0.35, 0.45))
	add_console_line("Run failed: team wiped.")

func show_menu(visible_state: bool) -> void:
	menu_panel.visible = visible_state

func is_menu_visible() -> bool:
	return menu_panel.visible

func set_status(message: String) -> void:
	status_label.text = message
	peer_label.text = message
	add_console_line(message)

func toggle_console() -> void:
	set_console_visible(not console_panel.visible)

func set_console_visible(visible_state: bool) -> void:
	console_panel.visible = visible_state
	if visible_state:
		console_input.grab_focus()
	else:
		console_input.release_focus()
	console_visibility_changed.emit(visible_state)

func is_console_visible() -> bool:
	return console_panel.visible

func add_console_line(message: String) -> void:
	console_log.append_text("%s\n" % message)
	console_log.scroll_to_line(console_log.get_line_count())

func clear_console() -> void:
	console_log.clear()

func _update_perf_labels() -> void:
	var fps := Engine.get_frames_per_second()
	perf_label.text = "FPS %d\nMS %.2f" % [fps, last_frame_ms]

func _on_solo_pressed() -> void:
	play_solo_requested.emit()

func _on_host_pressed() -> void:
	host_requested.emit()

func _on_join_pressed() -> void:
	join_requested.emit(join_ip.text)

func _on_command_text_submitted(new_text: String) -> void:
	var trimmed := new_text.strip_edges()
	if trimmed.is_empty():
		console_input.text = ""
		return
	add_console_line("> %s" % trimmed)
	command_submitted.emit(trimmed)
	console_input.text = ""
