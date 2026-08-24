extends Button
## Slot do inventário: arrasta itens para os slots de equipamento.
## Recebe de volta payloads de equipamento para desequipar.

var slot_index := -1
var hud: Node = null


func _get_drag_data(_at: Vector2) -> Variant:
	if hud == null or hud._data == null or slot_index < 0:
		return null
	var slot: Dictionary = hud._data.get_slot(slot_index)
	if slot.is_empty():
		return null
	var item_id := str(slot.get("item_id", ""))
	var preview := Label.new()
	preview.text = "· " + ItemCatalog.display_name(item_id)
	set_drag_preview(preview)
	return {"type": "inv_item", "index": slot_index, "item_id": item_id}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == "equip_slot"


func _drop_data(_at: Vector2, data: Variant) -> void:
	if hud != null:
		hud.unequip_via_drop(str(data.get("slot", "")))
