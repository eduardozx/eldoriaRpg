extends CanvasLayer

const MAX_LOG_LINES := 80

var _lines: PackedStringArray = []

@onready var log_label: RichTextLabel = %Log
@onready var input_field: LineEdit = %Input
@onready var send_button: Button = %SendButton


func _ready() -> void:
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	input_field.text_submitted.connect(_on_text_submitted)
	input_field.focus_entered.connect(_on_focus_entered)
	input_field.focus_exited.connect(_on_focus_exited)
	send_button.pressed.connect(_on_send_pressed)
	NetworkManager.chat_message_received.connect(_on_chat_message_received)
	_append_system("Chat pronto. Enter para escrever, Esc para voltar ao jogo.")


func _exit_tree() -> void:
	NetworkManager.chat_input_active = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat_focus") and not input_field.has_focus():
		input_field.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and input_field.has_focus():
		input_field.release_focus()
		get_viewport().set_input_as_handled()


func _on_focus_entered() -> void:
	NetworkManager.chat_input_active = true


func _on_focus_exited() -> void:
	NetworkManager.chat_input_active = false


func _on_send_pressed() -> void:
	_submit(input_field.text)


func _on_text_submitted(text: String) -> void:
	_submit(text)


func _submit(text: String) -> void:
	NetworkManager.send_chat(text)
	input_field.clear()
	# Adia a liberação para o Enter atual terminar de propagar. Se liberar aqui,
	# _unhandled_input recebe o mesmo evento e torna a focar o campo, bloqueando WASD.
	input_field.call_deferred("release_focus")


func _on_chat_message_received(player_name: String, message: String) -> void:
	_append_line("[b]%s[/b]: %s" % [_escape_bbcode(player_name), _escape_bbcode(message)])


func _append_system(text: String) -> void:
	_append_line("[i][color=#9aa3ad]%s[/color][/i]" % _escape_bbcode(text))


func _append_line(bbcode: String) -> void:
	_lines.append(bbcode)
	while _lines.size() > MAX_LOG_LINES:
		_lines.remove_at(0)
	log_label.clear()
	log_label.append_text("\n".join(_lines) + "\n")


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
