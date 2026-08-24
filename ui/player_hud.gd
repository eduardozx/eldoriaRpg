extends CanvasLayer
## HUD local: HP, ouro e inventário (slots).

const SLOT_SIZE := Vector2(72, 58)

var _data: PlayerData
var _slot_buttons: Array[Button] = []

@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_label: Label = %HpLabel
@onready var level_label: Label = %LevelLabel
@onready var exp_label: Label = %ExpLabel
@onready var damage_label: Label = %DamageLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var gold_label: Label = %GoldLabel
@onready var quest_label: Label = %QuestLabel
@onready var inventory_panel: Control = %InventoryPanel
@onready var slot_grid: GridContainer = %SlotGrid
@onready var slot_hint: Label = %SlotHint
@onready var player_list_panel: PanelContainer = %PlayerListPanel
@onready var player_list_title: Label = %ListTitle
@onready var player_list_rows: VBoxContainer = %ListRows

var _list_refresh_left := 0.0


func _ready() -> void:
	add_to_group("player_hud")
	inventory_panel.visible = false
	_build_slots()
	set_process_unhandled_input(true)
	QuestManager.quest_updated.connect(_on_quest_updated)
	QuestManager.quest_completed.connect(_on_quest_updated)
	_refresh_quest()


func bind_player_data(data: PlayerData) -> void:
	if _data == data:
		_refresh_all()
		return
	if _data:
		if _data.stats_changed.is_connected(_on_stats_changed):
			_data.stats_changed.disconnect(_on_stats_changed)
		if _data.gold_changed.is_connected(_on_gold_changed):
			_data.gold_changed.disconnect(_on_gold_changed)
		if _data.inventory_changed.is_connected(_on_inventory_changed):
			_data.inventory_changed.disconnect(_on_inventory_changed)
		if _data.equipment_changed.is_connected(_refresh_all):
			_data.equipment_changed.disconnect(_refresh_all)
	_data = data
	if _data == null:
		return
	_data.stats_changed.connect(_on_stats_changed)
	_data.gold_changed.connect(_on_gold_changed)
	_data.inventory_changed.connect(_on_inventory_changed)
	_data.equipment_changed.connect(_refresh_all)
	_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("player_list"):
		player_list_panel.visible = not player_list_panel.visible
		if player_list_panel.visible:
			_refresh_player_list()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("toggle_inventory"):
		return
	if NetworkManager.is_chat_blocking_movement():
		return
	inventory_panel.visible = not inventory_panel.visible
	if inventory_panel.visible:
		_refresh_inventory()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not player_list_panel.visible:
		return
	_list_refresh_left -= delta
	if _list_refresh_left <= 0.0:
		_list_refresh_left = 0.5
		_refresh_player_list()


## Lista de jogadores online (Tab): nome, nível e quem é você.
func _refresh_player_list() -> void:
	if player_list_rows == null:
		return
	for child in player_list_rows.get_children():
		child.queue_free()
	var players := get_tree().get_nodes_in_group("player")
	player_list_title.text = "Jogadores online: %d" % players.size()
	for p in players:
		if not (p is Node2D):
			continue
		var shown_name := "?"
		if "display_name" in p and not str(p.display_name).is_empty():
			shown_name = str(p.display_name)
		var level := 1
		if "data" in p and p.data != null:
			level = p.data.level
		var suffix := "  ·  você" if p.is_multiplayer_authority() else ""
		var row := Label.new()
		row.text = "%s  ·  Nv %d%s" % [shown_name, level, suffix]
		player_list_rows.add_child(row)


func _build_slots() -> void:
	for child in slot_grid.get_children():
		child.queue_free()
	_slot_buttons.clear()
	for i in PlayerData.SLOT_COUNT:
		var button := Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.clip_text = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_slot_pressed.bind(i))
		slot_grid.add_child(button)
		_slot_buttons.append(button)


func _on_stats_changed() -> void:
	_refresh_status()


func _on_gold_changed() -> void:
	_refresh_gold()


func _on_inventory_changed() -> void:
	_refresh_inventory()


func _refresh_all() -> void:
	_refresh_status()
	_refresh_gold()
	_refresh_inventory()
	_refresh_quest()


func _on_quest_updated(_quest_id: String = "") -> void:
	_refresh_quest()


func _refresh_quest() -> void:
	if quest_label == null:
		return
	var text := QuestManager.get_active_tracker_text()
	if text.is_empty():
		quest_label.text = "Missão: nenhuma"
	else:
		quest_label.text = "Missão: %s" % text


func _refresh_status() -> void:
	if _data == null:
		return
	hp_bar.max_value = _data.max_hp
	hp_bar.value = _data.hp
	hp_label.text = "HP  %d / %d" % [_data.hp, _data.max_hp]
	level_label.text = "Nível %d" % _data.level
	exp_label.text = "EXP  %d / %d" % [_data.experience, _data.experience_to_next()]
	var weapon := _data.equipped_weapon_id
	damage_label.text = "Dano  %d" % _data.attack_damage(weapon)
	if weapon.is_empty():
		weapon_label.text = "Arma  Punhos"
	else:
		weapon_label.text = "Arma  %s" % ItemCatalog.display_name(weapon)


func _refresh_gold() -> void:
	if _data == null:
		return
	gold_label.text = "Ouro  %d" % _data.gold


func _refresh_inventory() -> void:
	if _data == null:
		return
	for i in _slot_buttons.size():
		var button := _slot_buttons[i]
		var slot := _data.get_slot(i)
		if slot.is_empty():
			button.text = "—"
			button.disabled = true
			button.tooltip_text = "Slot vazio"
			continue
		var item_id := str(slot.get("item_id", ""))
		var qty := int(slot.get("quantity", 0))
		var shown := ItemCatalog.display_name(item_id)
		var equipped := _data.equipped_weapon_id == item_id
		button.text = "%s%s\n×%d" % ["[E] " if equipped else "", shown, qty]
		button.disabled = false
		var def := ItemCatalog.get_def(item_id)
		var extra: String
		if equipped:
			extra = "Equipada. Clique para desequipar."
		elif ItemCatalog.is_equipment(item_id):
			extra = "Clique para equipar."
		elif ItemCatalog.is_consumable(item_id):
			extra = "Clique para usar."
		else:
			extra = "Não é consumível."
		button.tooltip_text = "%s\n%s\n%s" % [shown, str(def.get("description", "")), extra]


func _on_slot_pressed(index: int) -> void:
	if _data == null:
		return
	var slot := _data.get_slot(index)
	if not slot.is_empty() and ItemCatalog.is_equipment(str(slot.get("item_id", ""))):
		var item_id := str(slot.get("item_id", ""))
		if _data.toggle_equip(index):
			if _data.equipped_weapon_id == item_id:
				slot_hint.text = "%s equipada." % ItemCatalog.display_name(item_id)
			else:
				slot_hint.text = "Arma guardada."
			return
		slot_hint.text = "Não foi possível equipar."
		return
	if not _data.use_slot(index):
		slot_hint.text = "Não foi possível usar este item."
		return
	slot_hint.text = "Item usado."
