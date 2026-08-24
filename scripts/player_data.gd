class_name PlayerData
extends Node
## Status, ouro e inventário do jogador (um componente por instância).

signal stats_changed
signal gold_changed
signal inventory_changed
signal equipment_changed

const SLOT_COUNT := 16

@export var level: int = 1:
	set(value):
		level = maxi(value, 1)
		stats_changed.emit()

@export var experience: int = 0

@export var hp: int = 100:
	set(value):
		hp = clampi(value, 0, maxi(max_hp, 1))
		stats_changed.emit()

@export var max_hp: int = 100:
	set(value):
		max_hp = maxi(value, 1)
		hp = mini(hp, max_hp)
		stats_changed.emit()

@export var base_damage: int = 8
@export var gold: int = 0

## Cada slot: {"item_id": String, "quantity": int} ou vazio {}.
var slots: Array[Dictionary] = []

## Item de equipamento em uso ("", = punhos). O item continua no inventário.
var equipped_weapon_id: String = "":
	set(value):
		equipped_weapon_id = value
		equipment_changed.emit()


func _ready() -> void:
	_ensure_slots()
	if _is_empty_inventory() and gold == 0 and level == 1 and experience == 0:
		_give_starter_kit()
	stats_changed.emit()
	gold_changed.emit()
	inventory_changed.emit()


func experience_to_next() -> int:
	return maxi(level, 1) * 100


func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount
	var leveled := false
	while experience >= experience_to_next():
		experience -= experience_to_next()
		level += 1
		max_hp += 10
		hp = max_hp
		base_damage += 2
		leveled = true
	if leveled:
		hp = mini(hp, max_hp)
	stats_changed.emit()


func set_hp(value: int) -> void:
	hp = value


func heal(amount: int) -> int:
	if amount <= 0 or hp >= max_hp:
		return 0
	var before := hp
	hp = hp + amount
	return hp - before


func take_damage(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var before := hp
	hp = hp - amount
	return before - hp


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit()


func remove_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit()
	return true


func can_afford(amount: int) -> bool:
	return amount <= 0 or gold >= amount


func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index]


func add_item(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0 or not ItemCatalog.has_item(item_id):
		return quantity
	_ensure_slots()
	var remaining := quantity
	var stack_limit := ItemCatalog.max_stack(item_id)

	for i in slots.size():
		if remaining <= 0:
			break
		var slot := slots[i]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var current := int(slot.get("quantity", 0))
		var space := stack_limit - current
		if space <= 0:
			continue
		var moved := mini(space, remaining)
		slot["quantity"] = current + moved
		slots[i] = slot
		remaining -= moved

	for i in slots.size():
		if remaining <= 0:
			break
		if not slots[i].is_empty():
			continue
		var moved := mini(stack_limit, remaining)
		slots[i] = {"item_id": item_id, "quantity": moved}
		remaining -= moved

	inventory_changed.emit()
	return remaining


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true
	if count_item(item_id) < quantity:
		return false
	var remaining := quantity
	for i in slots.size():
		if remaining <= 0:
			break
		var slot := slots[i]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var current := int(slot.get("quantity", 0))
		var take := mini(current, remaining)
		current -= take
		remaining -= take
		if current <= 0:
			slots[i] = {}
		else:
			slot["quantity"] = current
			slots[i] = slot
	inventory_changed.emit()
	return true


func count_item(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("quantity", 0))
	return total
func use_slot(index: int) -> bool:
	var slot := get_slot(index)
	if slot.is_empty():
		return false
	var item_id := str(slot.get("item_id", ""))
	if not ItemCatalog.is_consumable(item_id):
		return false
	var heal_value := ItemCatalog.heal_amount(item_id)
	if heal_value > 0 and hp >= max_hp:
		return false
	if not remove_item_from_slot(index, 1):
		return false
	if heal_value > 0:
		heal(heal_value)
	return true


func toggle_equip(index: int) -> bool:
	var slot := get_slot(index)
	if slot.is_empty():
		return false
	var item_id := str(slot.get("item_id", ""))
	if not ItemCatalog.is_equipment(item_id):
		return false
	if equipped_weapon_id == item_id:
		equipped_weapon_id = ""
		return true
	if count_item(item_id) <= 0:
		return false
	equipped_weapon_id = item_id
	return true


func attack_damage(equipped_item_id: String = "") -> int:
	return maxi(base_damage, 0) + ItemCatalog.weapon_bonus(equipped_item_id)


func to_snapshot() -> Dictionary:
	_ensure_slots()
	return {
		"level": level,
		"experience": experience,
		"max_hp": max_hp,
		"base_damage": base_damage,
		"gold": gold,
		"equipped_weapon_id": equipped_weapon_id,
		"inventory": slots.duplicate(true),
	}


func apply_snapshot(snapshot: Dictionary) -> void:
	level = int(snapshot.get("level", 1))
	experience = int(snapshot.get("experience", 0))
	max_hp = int(snapshot.get("max_hp", 100))
	base_damage = int(snapshot.get("base_damage", 8))
	gold = int(snapshot.get("gold", 0))

	slots.clear()
	var inventory: Variant = snapshot.get("inventory", [])
	if inventory is Array:
		for entry in inventory:
			if entry is Dictionary and not entry.is_empty():
				slots.append({
					"item_id": str(entry.get("item_id", "")),
					"quantity": int(entry.get("quantity", 1)),
				})
			else:
				slots.append({})
	_ensure_slots()

	equipped_weapon_id = str(snapshot.get("equipped_weapon_id", ""))
	hp = max_hp
	stats_changed.emit()
	gold_changed.emit()
	inventory_changed.emit()


func remove_item_from_slot(index: int, quantity: int = 1) -> bool:
	if quantity <= 0 or index < 0 or index >= slots.size():
		return false
	var slot := slots[index]
	if slot.is_empty():
		return false
	var current := int(slot.get("quantity", 0))
	if current < quantity:
		return false
	current -= quantity
	if current <= 0:
		slots[index] = {}
	else:
		slot["quantity"] = current
		slots[index] = slot
	inventory_changed.emit()
	return true


func _ensure_slots() -> void:
	while slots.size() < SLOT_COUNT:
		slots.append({})
	if slots.size() > SLOT_COUNT:
		slots.resize(SLOT_COUNT)


func _is_empty_inventory() -> bool:
	for slot in slots:
		if not slot.is_empty():
			return false
	return true


func _give_starter_kit() -> void:
	add_gold(50)
	add_item("potion_hp", 3)
	add_item("bread", 5)
	add_item("herb", 2)
	add_item("rusty_sword", 1)
	add_item("wizard_staff", 1)
