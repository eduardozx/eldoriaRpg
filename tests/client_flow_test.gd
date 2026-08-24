extends Node
## Carrega o worker fora da cena atual para sobreviver à troca de cena (mundo).

const Worker := preload("res://tests/client_flow_worker.gd")


func _ready() -> void:
	var worker: Node = Worker.new()
	get_tree().root.add_child.call_deferred(worker)
