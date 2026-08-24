extends Area2D
## Zona lógica (spawn, vila, caça). Detecta jogadores na collision_layer 1.

@export var zone_id: String = "safe"
@export var zone_title: String = "Zona"


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
	if body.has_method("enter_zone"):
		body.enter_zone(zone_id, zone_title)


func _on_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	if body.has_method("exit_zone"):
		body.exit_zone(zone_id)


func _is_player(body: Node2D) -> bool:
	return body is CharacterBody2D and body.has_method("enter_zone")
