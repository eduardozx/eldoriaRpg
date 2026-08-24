extends Node
## Catálogo e progresso de missões do jogador local.

signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String)
signal dialog_changed(is_open: bool)

const QUEST_HUNT_3 := "hunt_3_monsters"

const QUESTS := {
	QUEST_HUNT_3: {
		"id": QUEST_HUNT_3,
		"title": "Caçada Inicial",
		"npc_name": "Ancião Torren",
		"intro": "Os campos ao leste estão infestados. Derrote 3 monstros e volte aqui.",
		"objective": "Derrote 3 Monstros",
		"objective_type": "kill_monster",
		"target": 3,
		"reward_exp": 45,
		"reward_gold": 30,
		"complete_text": "Excelente trabalho. Tome estas moedas e a bênção da vila.",
		"done_text": "Obrigado pela ajuda. A vila dorme mais segura.",
	},
}

## quest_id -> { "status": String, "progress": int }
## status: inactive | active | ready | completed
var _entries: Dictionary = {}
var dialog_open: bool = false


func _ready() -> void:
	for quest_id in QUESTS.keys():
		_entries[quest_id] = {"status": "inactive", "progress": 0}


func get_def(quest_id: String) -> Dictionary:
	if not QUESTS.has(quest_id):
		return {}
	return (QUESTS[quest_id] as Dictionary).duplicate(true)


func get_status(quest_id: String) -> String:
	return str(_entries.get(quest_id, {}).get("status", "inactive"))


func get_progress(quest_id: String) -> int:
	return int(_entries.get(quest_id, {}).get("progress", 0))


func get_target(quest_id: String) -> int:
	return int(get_def(quest_id).get("target", 0))


func is_blocking_input() -> bool:
	return dialog_open


func set_dialog_open(open: bool) -> void:
	if dialog_open == open:
		return
	dialog_open = open
	dialog_changed.emit(open)


func accept_quest(quest_id: String) -> bool:
	if not QUESTS.has(quest_id):
		return false
	var entry: Dictionary = _entries[quest_id]
	if str(entry.get("status", "")) != "inactive":
		return false
	entry["status"] = "active"
	entry["progress"] = 0
	_entries[quest_id] = entry
	quest_updated.emit(quest_id)
	return true


func report_monster_kill() -> void:
	for quest_id in QUESTS.keys():
		var def: Dictionary = QUESTS[quest_id]
		if str(def.get("objective_type", "")) != "kill_monster":
			continue
		var entry: Dictionary = _entries[quest_id]
		if str(entry.get("status", "")) != "active":
			continue
		var target := int(def.get("target", 1))
		var progress := mini(int(entry.get("progress", 0)) + 1, target)
		entry["progress"] = progress
		if progress >= target:
			entry["status"] = "ready"
		_entries[quest_id] = entry
		quest_updated.emit(quest_id)


func turn_in_quest(quest_id: String, player_data: PlayerData) -> bool:
	if player_data == null or not QUESTS.has(quest_id):
		return false
	var entry: Dictionary = _entries[quest_id]
	if str(entry.get("status", "")) != "ready":
		return false
	var def: Dictionary = QUESTS[quest_id]
	player_data.add_experience(int(def.get("reward_exp", 0)))
	player_data.add_gold(int(def.get("reward_gold", 0)))
	entry["status"] = "completed"
	_entries[quest_id] = entry
	quest_updated.emit(quest_id)
	quest_completed.emit(quest_id)
	return true


func get_active_tracker_text() -> String:
	for quest_id in QUESTS.keys():
		var status := get_status(quest_id)
		if status != "active" and status != "ready":
			continue
		var def := get_def(quest_id)
		var progress := get_progress(quest_id)
		var target := int(def.get("target", 0))
		if status == "ready":
			return "%s — pronto para entregar" % str(def.get("title", quest_id))
		return "%s  %d/%d" % [str(def.get("objective", "")), progress, target]
	return ""


func reset_all() -> void:
	for quest_id in QUESTS.keys():
		_entries[quest_id] = {"status": "inactive", "progress": 0}
		quest_updated.emit(quest_id)
	set_dialog_open(false)
