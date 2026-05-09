extends Control

@onready var center: CenterContainer = $Center
@onready var heading: Label = $Center/VBox/Heading
@onready var subheading: Label = $Center/VBox/Subheading
@onready var card_row: HBoxContainer = $Center/VBox/Cards
@onready var status: Label = $Center/VBox/Status

const INPUT_GRACE: float = 0.4

var current_offer: Array = []
var picked: bool = false
var grace_timer: float = 0.0

signal card_picked(card_id: StringName)

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)

func _process(delta: float) -> void:
	if grace_timer > 0.0:
		grace_timer = max(0.0, grace_timer - delta)

func show_offer(card_ids: Array, wave_index: int) -> void:
	current_offer = card_ids.duplicate()
	picked = false
	grace_timer = INPUT_GRACE
	heading.text = "WAVE %d CLEARED" % wave_index
	subheading.text = "Pick one card. Press 1 / 2 / 3 or click."
	status.text = ""
	_clear_cards()
	for i in current_offer.size():
		var card_data: Dictionary = CardLibrary.get_card(current_offer[i])
		if card_data.is_empty():
			continue
		var card_node := _build_card_panel(card_data, i)
		card_row.add_child(card_node)
	visible = true
	set_process(true)

func show_waiting(message: String) -> void:
	subheading.text = ""
	status.text = message
	for child in card_row.get_children():
		if child is Button:
			child.disabled = true

func hide_picker() -> void:
	visible = false
	current_offer.clear()
	grace_timer = 0.0
	set_process(false)
	_clear_cards()

func _clear_cards() -> void:
	for child in card_row.get_children():
		child.queue_free()

func _build_card_panel(card_data: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 320)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	btn.theme_type_variation = "CardButton"
	var color: Color = card_data.get("color", Color.WHITE)
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(color.r * 0.18, color.g * 0.18, color.b * 0.22, 0.92)
	sb_normal.border_color = color
	sb_normal.border_width_left = 4
	sb_normal.border_width_right = 4
	sb_normal.border_width_top = 4
	sb_normal.border_width_bottom = 4
	sb_normal.corner_radius_top_left = 12
	sb_normal.corner_radius_top_right = 12
	sb_normal.corner_radius_bottom_left = 12
	sb_normal.corner_radius_bottom_right = 12
	var sb_hover := sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(color.r * 0.32, color.g * 0.32, color.b * 0.36, 0.95)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", sb_hover)
	btn.add_theme_stylebox_override("disabled", sb_normal)
	btn.text = "%d. %s\n\n%s\n\n[%s]" % [
		index + 1,
		card_data.get("name", "?"),
		card_data.get("desc", ""),
		_rarity_label(card_data.get("rarity", 0)),
	]
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.pressed.connect(_on_card_pressed.bind(index))
	return btn

func _rarity_label(rarity: int) -> String:
	match rarity:
		1: return "RARE"
		2: return "LEGENDARY"
		_: return "COMMON"

func _on_card_pressed(index: int) -> void:
	_pick_index(index)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or picked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _pick_index(0)
			KEY_2: _pick_index(1)
			KEY_3: _pick_index(2)

func _pick_index(index: int) -> void:
	if picked or index < 0 or index >= current_offer.size():
		return
	if grace_timer > 0.0:
		return
	picked = true
	for child in card_row.get_children():
		if child is Button:
			child.disabled = true
	var pick_id: StringName = current_offer[index]
	status.text = "Picked %s. Waiting..." % CardLibrary.get_card(pick_id).get("name", "?")
	card_picked.emit(pick_id)
