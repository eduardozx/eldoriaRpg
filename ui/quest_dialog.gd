extends CanvasLayer
## Janela de diálogo de missão (aceitar / progresso / entregar).

@onready var panel: PanelContainer = %Panel
@onready var npc_label: Label = %NpcLabel
@onready var title_label: Label = %TitleLabel
@onready var body_label: RichTextLabel = %BodyLabel
@onready var progress_label: Label = %ProgressLabel
@onready var primary_button: Button = %PrimaryButton
@onready var close_button: Button = %CloseButton

var _npc: Node = null
var _player: Node = null
var _quest_id: String = ""


func _ready() -> void:
	add_to_group("quest_dialog")
	visible = false
	primary_button.pressed.connect(_on_primary_pressed)
	close_button.pressed.connect(close)
	QuestManager.quest_updated.connect(_on_quest_updated)
	set_process_unhandled_input(true)


func open_for_npc(npc: Node, player: Node) -> void:
	_npc = npc
	_player = player
	_quest_id = str(npc.get_quest_id()) if npc.has_method("get_quest_id") else ""
	visible = true
	QuestManager.set_dialog_open(true)
	_refresh()


func close_if_npc(npc: Node) -> void:
	if npc == _npc:
		close()


func close() -> void:
	visible = false
	_npc = null
	_player = null
	QuestManager.set_dialog_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _on_quest_updated(quest_id: String) -> void:
	if visible and quest_id == _quest_id:
		_refresh()


func _refresh() -> void:
	var def := QuestManager.get_def(_quest_id)
	if def.is_empty():
		close()
		return
	var status := QuestManager.get_status(_quest_id)
	var npc_name := str(def.get("npc_name", "NPC"))
	if _npc and _npc.has_method("get_npc_name"):
		npc_name = _npc.get_npc_name()
	npc_label.text = npc_name
	title_label.text = str(def.get("title", "Missão"))
	var progress := QuestManager.get_progress(_quest_id)
	var target := int(def.get("target", 0))

	match status:
		"inactive":
			body_label.text = str(def.get("intro", ""))
			progress_label.text = "Objetivo: %s" % str(def.get("objective", ""))
			primary_button.text = "Aceitar missão"
			primary_button.disabled = false
			primary_button.visible = true
		"active":
			body_label.text = str(def.get("intro", ""))
			progress_label.text = "Progresso: %d / %d" % [progress, target]
			primary_button.visible = false
		"ready":
			body_label.text = "Você cumpriu o objetivo. Entregue a missão para receber a recompensa."
			progress_label.text = "Progresso: %d / %d  (completo)" % [progress, target]
			primary_button.text = "Entregar (+%d EXP, +%d ouro)" % [
				int(def.get("reward_exp", 0)),
				int(def.get("reward_gold", 0)),
			]
			primary_button.disabled = false
			primary_button.visible = true
		"completed":
			body_label.text = str(def.get("done_text", def.get("complete_text", "")))
			progress_label.text = "Missão concluída"
			primary_button.visible = false
		_:
			primary_button.visible = false


func _on_primary_pressed() -> void:
	var status := QuestManager.get_status(_quest_id)
	if status == "inactive":
		QuestManager.accept_quest(_quest_id)
		_refresh()
		return
	if status == "ready":
		var data: PlayerData = null
		if _player != null and "data" in _player:
			data = _player.data as PlayerData
		if QuestManager.turn_in_quest(_quest_id, data):
			body_label.text = str(QuestManager.get_def(_quest_id).get("complete_text", ""))
			_refresh()
