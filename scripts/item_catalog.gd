extends Node
## Catálogo estático de itens (id → definição). Usado pelo inventário.

const KIND_CONSUMABLE := "consumable"
const KIND_MATERIAL := "material"
const KIND_EQUIPMENT := "equipment"

const ATTACK_SLASH := "slash"
const ATTACK_BOLT := "bolt"
const SLOT_HAND := "hand"
const SLOT_HELMET := "helmet"
const SLOT_CHEST := "chest"
const FIST_RANGE := 46.0
const FIST_ARC_DOT := -0.15
const FIST_COOLDOWN := 0.42

const ITEMS := {
	"potion_hp": {
		"id": "potion_hp",
		"name": "Poção de HP",
		"kind": KIND_CONSUMABLE,
		"max_stack": 20,
		"heal": 35,
		"description": "Restaura 35 de HP.",
	},
	"bread": {
		"id": "bread",
		"name": "Pão",
		"kind": KIND_CONSUMABLE,
		"max_stack": 30,
		"heal": 12,
		"description": "Alimento simples. Restaura 12 de HP.",
	},
	"herb": {
		"id": "herb",
		"name": "Erva",
		"kind": KIND_MATERIAL,
		"max_stack": 50,
		"heal": 0,
		"description": "Ingrediente de poções.",
	},
	"rusty_sword": {
		"id": "rusty_sword",
		"name": "Espada Enferrujada",
		"kind": KIND_EQUIPMENT,
		"max_stack": 1,
		"heal": 0,
		"slot": SLOT_HAND,
		"attack": ATTACK_SLASH,
		"bonus": 2,
		"range": 52.0,
		"cooldown": 0.40,
		"arc_dot": -0.15,
		"description": "Corte em arco à frente (+2 de dano).",
	},
	"wizard_staff": {
		"id": "wizard_staff",
		"name": "Cajado do Mago",
		"kind": KIND_EQUIPMENT,
		"max_stack": 1,
		"heal": 0,
		"slot": SLOT_HAND,
		"attack": ATTACK_BOLT,
		"bonus": 1,
		"range": 175.0,
		"cooldown": 0.65,
		"arc_dot": 0.35,
		"description": "Dispara um projétil mágico de longo alcance (+1 de dano).",
	},
	"iron_helm": {
		"id": "iron_helm",
		"name": "Elmo de Ferro",
		"kind": KIND_EQUIPMENT,
		"max_stack": 1,
		"heal": 0,
		"slot": SLOT_HELMET,
		"defense": 3,
		"description": "Protege a cabeça (+3 de defesa). Arraste até o slot de elmo.",
	},
	"iron_chest": {
		"id": "iron_chest",
		"name": "Peitoral de Ferro",
		"kind": KIND_EQUIPMENT,
		"max_stack": 1,
		"heal": 0,
		"slot": SLOT_CHEST,
		"defense": 5,
		"description": "Blindagem do torso (+5 de defesa). Arraste até o slot de peito.",
	},
}


func has_item(item_id: String) -> bool:
	return ITEMS.has(item_id)


func get_def(item_id: String) -> Dictionary:
	if not ITEMS.has(item_id):
		return {}
	return (ITEMS[item_id] as Dictionary).duplicate(true)


func display_name(item_id: String) -> String:
	var def := get_def(item_id)
	return str(def.get("name", item_id))


func max_stack(item_id: String) -> int:
	var def := get_def(item_id)
	return int(def.get("max_stack", 1))


func is_consumable(item_id: String) -> bool:
	return str(get_def(item_id).get("kind", "")) == KIND_CONSUMABLE


func is_equipment(item_id: String) -> bool:
	return str(get_def(item_id).get("kind", "")) == KIND_EQUIPMENT


func slot_of(item_id: String) -> String:
	return str(get_def(item_id).get("slot", SLOT_HAND))


func armor_bonus(item_id: String) -> int:
	return int(get_def(item_id).get("defense", 0))


func weapon_attack(item_id: String) -> String:
	return str(get_def(item_id).get("attack", ""))


func weapon_bonus(item_id: String) -> int:
	return int(get_def(item_id).get("bonus", 0))


func weapon_range(item_id: String) -> float:
	if item_id.is_empty() or not is_equipment(item_id):
		return FIST_RANGE
	return float(get_def(item_id).get("range", FIST_RANGE))


func weapon_cooldown(item_id: String) -> float:
	if item_id.is_empty() or not is_equipment(item_id):
		return FIST_COOLDOWN
	return float(get_def(item_id).get("cooldown", FIST_COOLDOWN))


func weapon_arc_dot(item_id: String) -> float:
	if item_id.is_empty() or not is_equipment(item_id):
		return FIST_ARC_DOT
	return float(get_def(item_id).get("arc_dot", FIST_ARC_DOT))


func heal_amount(item_id: String) -> int:
	return int(get_def(item_id).get("heal", 0))
