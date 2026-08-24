extends Area2D
## Arena PVP: liga `can_pvp` no Player enquanto o corpo estiver dentro da área.

const ZONE_ID := "pvp"
const ZONE_TITLE := "Área PVP"


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	if "can_pvp" in body:
		body.can_pvp = true
	if body.has_method("enter_zone"):
		body.enter_zone(ZONE_ID, ZONE_TITLE)


func _on_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	if "can_pvp" in body:
		body.can_pvp = false
	if body.has_method("exit_zone"):
		body.exit_zone(ZONE_ID)


func _is_player(body: Node2D) -> bool:
	return body is CharacterBody2D
