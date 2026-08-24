extends Button
## Slot de equipamento (mão / elmo / peito): alvo do drag-and-drop.
## Clicar desequipa; receber item do inventário equipa.

const ItemCatalogRes := preload("res://scripts/item_catalog.gd")

var slot_name := ""
var hud: Node = null


func setup(p_slot: String, p_hud: Node) -> void:
	slot_name = p_slot
	hud = p_hud
	match slot_name:
		"hand":
			text = "Arma"
		"helmet":
			text = "Elmo"
		"chest":
			text = "Peito"


func _get_drag_data(_at: Vector2) -> Variant:
	if hud == null or hud._data == null:
		return null
	var item_id: String = hud.equipped_id_for(slot_name)
	if item_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = "🗡 " + ItemCatalog.display_name(item_id)
	set_drag_preview(preview)
	return {"type": "equip_slot", "slot": slot_name, "item_id": item_id}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or data.get("type", "") != "inv_item":
		return false
	var item_id := str(data.get("item_id", ""))
	if not ItemCatalog.is_equipment(item_id):
		return false
	return ItemCatalog.slot_of(item_id) == slot_name


func _drop_data(_at: Vector2, data: Variant) -> void:
	if hud == null:
		return
	var index := int(data.get("index", -1))
	if index >= 0:
		hud.equip_via_drop(slot_name, index)
