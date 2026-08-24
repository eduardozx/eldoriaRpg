class_name CharacterCreator
extends Control
## Pequena tela de customização do personagem, exibida após o login.

signal confirmed(appearance: Dictionary)
signal cancelled

const SKIN_TONES: Array[Color] = [
	Color("f6dcc4"), Color("eec39a"), Color("cf9668"),
	Color("a9713f"), Color("7c4e28"), Color("54331c"),
]
const HAIR_COLORS: Array[Color] = [
	Color("241b12"), Color("4c2f1b"), Color("7a4a22"),
	Color("c08a3e"), Color("ded6c2"), Color("a83a30"),
	Color("494956"),
]
const SHIRT_COLORS: Array[Color] = [
	Color("52a0dc"), Color("4f9d55"), Color("c94f43"),
	Color("d99a3c"), Color("8b5fc0"), Color("3aa1a1"),
	Color("c96a9b"), Color("565666"),
]
const PANTS_COLORS: Array[Color] = [
	Color("33415f"), Color("5a4632"), Color("37503a"),
	Color("6e3350"), Color("444450"), Color("7a3b2e"),
]
const HAIR_STYLES: PackedStringArray = ["Careca", "Curto", "Longo", "Capuz"]

@onready var preview_sprite: AnimatedSprite2D = %PreviewSprite
@onready var preview_name: Label = %PreviewName
@onready var skin_row: HBoxContainer = %SkinRow
@onready var hair_row: HBoxContainer = %HairRow
@onready var style_option: OptionButton = %StyleOption
@onready var shirt_row: HBoxContainer = %ShirtRow
@onready var pants_row: HBoxContainer = %PantsRow
@onready var random_button: Button = %RandomButton
@onready var back_button: Button = %BackButton
@onready var confirm_button: Button = %ConfirmButton
@onready var status_label: Label = %StatusLabel

var _selection: Dictionary = {}
var _rows: Array[Dictionary] = []


func _ready() -> void:
	_build_swatch_row(skin_row, "skin", SKIN_TONES)
	_build_swatch_row(hair_row, "hair", HAIR_COLORS)
	_build_swatch_row(shirt_row, "shirt", SHIRT_COLORS)
	_build_swatch_row(pants_row, "pants", PANTS_COLORS)
	for style_name in HAIR_STYLES:
		style_option.add_item(style_name)
	style_option.item_selected.connect(_on_style_selected)
	random_button.pressed.connect(_apply_random)
	back_button.pressed.connect(_go_back)
	confirm_button.pressed.connect(_confirm)


func _input(event: InputEvent) -> void:
	if visible and confirm_button != null and not confirm_button.disabled \
			and event.is_action_pressed("ui_cancel"):
		accept_event()
		cancelled.emit()


func open(player_name: String = "") -> void:
	visible = true
	set_busy(false)
	status_label.text = ""
	preview_name.text = player_name
	_selection = PlayerSpriteFrames.normalize({})
	_sync_controls()
	_refresh_preview()
	confirm_button.grab_focus()


func set_status(text_value: String) -> void:
	status_label.text = text_value


func set_busy(busy: bool) -> void:
	confirm_button.disabled = busy
	back_button.disabled = busy
	random_button.disabled = busy


func _build_swatch_row(row: HBoxContainer, key: String, colors: Array[Color]) -> void:
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for color in colors:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(26, 26)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "#" + color.to_html(false)
		_style_swatch(button, color)
		button.toggled.connect(_on_color_toggled.bind(key, color))
		row.add_child(button)
		buttons.append(button)
	_rows.append({"key": key, "colors": colors, "buttons": buttons})


func _style_swatch(button: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(5)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.05, 0.06, 0.09, 0.85)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color(1, 1, 1, 0.45)
	var picked := normal.duplicate() as StyleBoxFlat
	picked.bg_color = color.lightened(0.12)
	picked.border_color = Color(1, 1, 1, 0.95)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", picked)
	button.add_theme_stylebox_override("hover_pressed", picked)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _sync_controls() -> void:
	for row in _rows:
		var index := _selected_index(row.colors, str(row.key))
		var buttons: Array = row.buttons
		for i in buttons.size():
			(buttons[i] as Button).set_pressed_no_signal(i == index)
	style_option.select(clampi(int(_selection.get("hair_style", 1)), 0, HAIR_STYLES.size() - 1))


func _selected_index(colors: Array[Color], key: String) -> int:
	var chosen: Variant = _selection.get(key)
	if chosen is Color:
		for i in colors.size():
			if colors[i].is_equal_approx(chosen):
				return i
	return 0


func _refresh_preview() -> void:
	preview_sprite.sprite_frames = PlayerSpriteFrames.build(_selection)
	preview_sprite.play("idle_%s" % PlayerSpriteFrames.DIR_NAMES[2])


func _on_color_toggled(pressed: bool, key: String, color: Color) -> void:
	if not pressed:
		return
	_selection[key] = color
	_refresh_preview()


func _on_style_selected(index: int) -> void:
	_selection["hair_style"] = index
	_refresh_preview()


func _apply_random() -> void:
	_selection["skin"] = SKIN_TONES.pick_random()
	_selection["hair"] = HAIR_COLORS.pick_random()
	_selection["shirt"] = SHIRT_COLORS.pick_random()
	_selection["pants"] = PANTS_COLORS.pick_random()
	_selection["hair_style"] = randi() % PlayerSpriteFrames.HAIR_STYLE_COUNT
	_sync_controls()
	_refresh_preview()


func _confirm() -> void:
	confirmed.emit(PlayerSpriteFrames.normalize(_selection))


func _go_back() -> void:
	cancelled.emit()
