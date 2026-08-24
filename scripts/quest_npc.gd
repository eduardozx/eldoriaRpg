extends Node2D
## NPC de missão na Vila. Area2D detecta proximidade; tecla E abre o diálogo.

@export var quest_id: String = "hunt_3_monsters"
@export var npc_display_name: String = "Ancião Torren"

@onready var prompt_label: Label = %PromptLabel
@onready var name_label: Label = %NameLabel
@onready var interact_area: Area2D = %InteractArea

var _local_player: Node = null


func _ready() -> void:
	add_to_group("quest_npc")
	name_label.text = npc_display_name
	prompt_label.visible = false
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if _local_player == null:
		return
	if not event.is_action_pressed("interact"):
		return
	if NetworkManager.is_chat_blocking_movement():
		return
	if QuestManager.dialog_open:
		return
	var dialog := get_tree().get_first_node_in_group("quest_dialog")
	if dialog and dialog.has_method("open_for_npc"):
		dialog.open_for_npc(self, _local_player)
		get_viewport().set_input_as_handled()


func get_quest_id() -> String:
	return quest_id


func get_npc_name() -> String:
	return npc_display_name


func _on_body_entered(body: Node2D) -> void:
	if not _is_local_player(body):
		return
	_local_player = body
	prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body != _local_player:
		return
	_local_player = null
	prompt_label.visible = false
	var dialog := get_tree().get_first_node_in_group("quest_dialog")
	if dialog and dialog.has_method("close_if_npc") and dialog.visible:
		dialog.close_if_npc(self)


func _is_local_player(body: Node2D) -> bool:
	return body.is_in_group("player") and body.has_method("is_multiplayer_authority") and body.is_multiplayer_authority()
